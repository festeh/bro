package com.github.festeh.bro.sync

import android.util.Log
import com.github.festeh.bro.codec.OpusDecoder
import com.github.festeh.bro.storage.SegmentDatabase
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.util.UUID
import kotlin.math.abs

/**
 * Receives speech segments from the watch via Wear DataLayer API.
 * Saves raw Opus data to SQLite and deletes the DataItem to free quota.
 */
class SpeechDataReceiver : WearableListenerService() {

    companion object {
        private const val TAG = "SpeechDataReceiver"
        private const val PATH_PREFIX = "/bro/speech/"
        private const val KEY_AUDIO = "audio"
        private const val KEY_START_TIME = "startTime"
        private const val KEY_DURATION_MS = "durationMs"
    }

    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)

    private val database by lazy { SegmentDatabase(this) }
    private val dataClient: DataClient by lazy { Wearable.getDataClient(this) }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        Log.d(TAG, "onDataChanged: ${dataEvents.count} events")

        dataEvents.forEach { event ->
            if (event.type == DataEvent.TYPE_CHANGED) {
                val uri = event.dataItem.uri
                val path = uri.path ?: return@forEach

                if (path.startsWith(PATH_PREFIX)) {
                    processSegment(event)
                }
            }
        }
    }

    private fun processSegment(event: DataEvent) {
        val uri = event.dataItem.uri
        val path = uri.path ?: return

        // Extract segment ID from path
        val segmentIdStr = path.removePrefix(PATH_PREFIX)
        val segmentId = try {
            UUID.fromString(segmentIdStr)
        } catch (e: Exception) {
            Log.e(TAG, "Invalid segment ID: $segmentIdStr")
            return
        }

        // Dedup check - skip if already processed
        if (database.exists(segmentId)) {
            Log.d(TAG, "Skipping already-processed segment $segmentId")
            // Still delete the DataItem to free quota
            serviceScope.launch {
                try {
                    dataClient.deleteDataItems(uri).await()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to delete duplicate DataItem", e)
                }
            }
            return
        }

        val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
        val asset = dataMap.getAsset(KEY_AUDIO)
        val startTime = dataMap.getLong(KEY_START_TIME)
        val durationMs = dataMap.getLong(KEY_DURATION_MS)

        if (asset == null) {
            Log.e(TAG, "No audio asset in segment $segmentId")
            return
        }

        Log.d(TAG, "Processing segment $segmentId (${durationMs}ms)")

        serviceScope.launch {
            try {
                // Get the asset data
                val fd = dataClient.getFdForAsset(asset).await()
                if (fd == null) {
                    Log.e(TAG, "Failed to get file descriptor for segment $segmentId")
                    return@launch
                }

                val rawOpusData = fd.inputStream.use { it.readBytes() }
                Log.d(TAG, "Received ${rawOpusData.size} bytes for segment $segmentId")

                // Decode to PCM for waveform extraction
                OpusDecoder.init()  // Ensure initialized (idempotent)
                val pcmData = OpusDecoder.decodeRawFrames(rawOpusData)
                Log.d(TAG, "Decoded to ${pcmData.size} PCM samples")

                // Extract waveform for visualization
                val waveform = extractWaveform(pcmData, 50)
                Log.d(TAG, "Extracted waveform: ${waveform.size} samples")

                // Save raw Opus to database
                val saved = database.insert(segmentId, startTime, durationMs, waveform, rawOpusData)

                if (saved) {
                    Log.d(TAG, "Saved segment $segmentId to database")

                    // Delete DataItem to free quota
                    dataClient.deleteDataItems(uri).await()
                    Log.d(TAG, "Deleted DataItem for segment $segmentId")
                } else {
                    Log.e(TAG, "Failed to save segment $segmentId (possible duplicate)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to process segment $segmentId", e)
            }
        }
    }

    /**
     * Extract waveform amplitudes from PCM data.
     * Returns normalized values (0.0 to 1.0) for visualization.
     * Uses peak amplitude per bucket for better visual representation.
     */
    private fun extractWaveform(pcmData: ShortArray, numSamples: Int): DoubleArray {
        if (pcmData.isEmpty()) return DoubleArray(0)

        val samplesPerBucket = pcmData.size / numSamples
        if (samplesPerBucket == 0) {
            // Less samples than buckets - just normalize what we have
            return pcmData.map { abs(it.toDouble()) / Short.MAX_VALUE }.toDoubleArray()
        }

        val waveform = DoubleArray(numSamples)
        for (i in 0 until numSamples) {
            val start = i * samplesPerBucket
            val end = minOf(start + samplesPerBucket, pcmData.size)

            // Find peak amplitude in this bucket
            var peak = 0.0
            for (j in start until end) {
                val sample = abs(pcmData[j].toDouble()) / Short.MAX_VALUE
                if (sample > peak) peak = sample
            }
            waveform[i] = peak
        }

        return waveform
    }

    override fun onDestroy() {
        serviceJob.cancel()
        super.onDestroy()
    }
}
