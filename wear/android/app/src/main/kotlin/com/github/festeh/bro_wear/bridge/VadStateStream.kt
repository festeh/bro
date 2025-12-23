package com.github.festeh.bro_wear.bridge

import android.os.Handler
import android.os.Looper
import com.github.festeh.bro_wear.vad.VadResult
import io.flutter.plugin.common.EventChannel

class VadStateStream : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun emit(result: VadResult) {
        mainHandler.post {
            eventSink?.success(mapOf(
                "status" to if (result.isSpeech) "speech" else "silence",
                "probability" to result.probability,
                "timestamp" to result.timestamp
            ))
        }
    }

    fun emitStatus(status: String) {
        mainHandler.post {
            eventSink?.success(mapOf(
                "status" to status,
                "timestamp" to System.currentTimeMillis()
            ))
        }
    }

    fun emitError(code: String, message: String) {
        mainHandler.post {
            eventSink?.error(code, message, null)
        }
    }

    fun isAttached(): Boolean = eventSink != null
}
