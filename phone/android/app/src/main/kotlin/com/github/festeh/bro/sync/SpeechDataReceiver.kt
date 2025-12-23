package com.github.festeh.bro.sync

import android.util.Log
import com.github.festeh.bro.storage.SpeechStorage
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

/**
 * Receives speech segments from the watch via Wear DataLayer API.
 * Saves them to local storage and deletes the DataItem to free quota.
 */
class SpeechDataReceiver : WearableListenerService() {

    companion object {
        private const val TAG = "SpeechDataReceiver"
        private const val PATH_PREFIX = "/bro/speech/"
        private const val KEY_AUDIO = "audio"
        private const val KEY_START_TIME = "startTime"
        private const val KEY_END_TIME = "endTime"
    }

    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)

    private val storage by lazy { SpeechStorage(this) }
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

        val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
        val asset = dataMap.getAsset(KEY_AUDIO)
        val startTime = dataMap.getLong(KEY_START_TIME)
        val endTime = dataMap.getLong(KEY_END_TIME)

        if (asset == null) {
            Log.e(TAG, "No audio asset in segment $segmentId")
            return
        }

        Log.d(TAG, "Processing segment $segmentId (${endTime - startTime}ms)")

        serviceScope.launch {
            try {
                // Get the asset data
                val fd = dataClient.getFdForAsset(asset).await()
                if (fd == null) {
                    Log.e(TAG, "Failed to get file descriptor for segment $segmentId")
                    return@launch
                }

                val opusData = fd.inputStream.use { it.readBytes() }
                Log.d(TAG, "Received ${opusData.size} bytes for segment $segmentId")

                // Save to storage
                val file = storage.save(segmentId, opusData, startTime, endTime)
                if (file != null) {
                    Log.d(TAG, "Saved segment $segmentId to ${file.name}")

                    // Delete DataItem to free quota
                    dataClient.deleteDataItems(uri).await()
                    Log.d(TAG, "Deleted DataItem for segment $segmentId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to process segment $segmentId", e)
            }
        }
    }

    override fun onDestroy() {
        serviceJob.cancel()
        super.onDestroy()
    }
}
