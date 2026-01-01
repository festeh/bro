package com.github.festeh.bro.bridge

import android.os.Handler
import android.os.Looper
import com.github.festeh.bro.service.PingListenerService
import com.github.festeh.bro.util.L
import io.flutter.plugin.common.EventChannel

class PingStream : EventChannel.StreamHandler {
    companion object {
        private const val TAG = "PingStream"
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        L.d(TAG, "init - setting up service callback")
        PingListenerService.onPingReceived = { emitPing() }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        L.d(TAG, "onListen")
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        L.d(TAG, "onCancel")
        eventSink = null
    }

    private fun emitPing() {
        val timestamp = System.currentTimeMillis()
        mainHandler.post {
            L.d(TAG, "Emitting ping event with timestamp: $timestamp")
            eventSink?.success(timestamp)
        }
    }

    fun dispose() {
        L.d(TAG, "dispose")
        PingListenerService.onPingReceived = null
        eventSink = null
    }
}
