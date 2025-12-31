package com.github.festeh.bro_wear.bridge

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.github.festeh.bro_wear.util.L
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.EventChannel

class PingStream(private val context: Context) : EventChannel.StreamHandler, MessageClient.OnMessageReceivedListener {
    companion object {
        private const val TAG = "PingStream"
        private const val PING_PATH = "/bro/ping"
        private const val PONG_PATH = "/bro/pong"
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        L.d(TAG, "init - registering message listener")
        Wearable.getMessageClient(context).addListener(this)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        L.d(TAG, "onListen")
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        L.d(TAG, "onCancel")
        eventSink = null
    }

    override fun onMessageReceived(event: MessageEvent) {
        L.d(TAG, "Message received: ${event.path} from ${event.sourceNodeId}")
        if (event.path == PING_PATH) {
            L.d(TAG, "Ping received! Sending pong and emitting to Flutter")

            // Send pong response immediately
            sendPong(event.sourceNodeId)

            // Emit timestamp to Flutter
            emitPing()
        }
    }

    private fun sendPong(nodeId: String) {
        Wearable.getMessageClient(context)
            .sendMessage(nodeId, PONG_PATH, ByteArray(0))
            .addOnSuccessListener {
                L.d(TAG, "Pong sent successfully to $nodeId")
            }
            .addOnFailureListener { e ->
                L.d(TAG, "Failed to send pong: ${e.message}")
            }
    }

    private fun emitPing() {
        val timestamp = System.currentTimeMillis()
        mainHandler.post {
            L.d(TAG, "Emitting ping event with timestamp: $timestamp")
            eventSink?.success(timestamp)
        }
    }

    fun dispose() {
        L.d(TAG, "dispose - removing message listener")
        Wearable.getMessageClient(context).removeListener(this)
        eventSink = null
    }
}
