package com.github.festeh.bro_wear.sync

import android.content.Context
import android.util.Log
import com.github.festeh.bro_wear.audio.SpeechSegment
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

/**
 * Sends encoded speech segments to the paired phone via Wear DataLayer API.
 */
class SpeechDataSender(private val context: Context) {

    companion object {
        private const val TAG = "SpeechDataSender"
        private const val PATH_PREFIX = "/bro/speech/"
        private const val KEY_AUDIO = "audio"
        private const val KEY_TIMESTAMP = "timestamp"
        private const val KEY_START_TIME = "startTime"
        private const val KEY_END_TIME = "endTime"
        private const val KEY_DURATION_MS = "durationMs"
        private const val KEY_SAMPLE_RATE = "sampleRate"
    }

    private val dataClient by lazy { Wearable.getDataClient(context) }

    /**
     * Send a speech segment to the phone.
     * The segment must have opusData set (encoded audio).
     *
     * @param segment The speech segment with encoded Opus data
     * @return true if sent successfully, false otherwise
     */
    suspend fun send(segment: SpeechSegment): Boolean {
        val opusData = segment.opusData
        if (opusData == null) {
            Log.e(TAG, "Cannot send segment ${segment.id}: no Opus data")
            return false
        }

        return try {
            val asset = Asset.createFromBytes(opusData)
            val path = "$PATH_PREFIX${segment.id}"

            val request = PutDataMapRequest.create(path).apply {
                dataMap.putAsset(KEY_AUDIO, asset)
                dataMap.putLong(KEY_TIMESTAMP, System.currentTimeMillis())
                dataMap.putLong(KEY_START_TIME, segment.startTime)
                dataMap.putLong(KEY_END_TIME, segment.endTime)
                dataMap.putLong(KEY_DURATION_MS, segment.durationMs)
                dataMap.putInt(KEY_SAMPLE_RATE, segment.sampleRate)
            }.asPutDataRequest()
            // Not using setUrgent() - passive batch mode is battery-friendly

            val result = dataClient.putDataItem(request).await()
            Log.d(TAG, "Sent segment ${segment.id}, uri: ${result.uri}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send segment ${segment.id}", e)
            false
        }
    }
}
