package com.github.festeh.bro_wear.service

import com.github.festeh.bro_wear.util.L
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService

class PingListenerService : WearableListenerService() {
    companion object {
        private const val TAG = "PingListenerService"
        private const val PING_PATH = "/bro/ping"
        private const val PONG_PATH = "/bro/pong"

        var onPingReceived: (() -> Unit)? = null
    }

    override fun onMessageReceived(event: MessageEvent) {
        L.d(TAG, "Message received: ${event.path} from ${event.sourceNodeId}")

        if (event.path == PING_PATH) {
            L.d(TAG, "Ping received! Sending pong back")

            // Send pong response
            Wearable.getMessageClient(this)
                .sendMessage(event.sourceNodeId, PONG_PATH, ByteArray(0))
                .addOnSuccessListener {
                    L.d(TAG, "Pong sent successfully")
                }
                .addOnFailureListener { e ->
                    L.d(TAG, "Failed to send pong: ${e.message}")
                }

            // Notify Flutter side
            onPingReceived?.invoke()
        }
    }
}
