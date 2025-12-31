package com.github.festeh.bro.bridge

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

class PingHandler(private val context: Context) : MessageClient.OnMessageReceivedListener {
    companion object {
        private const val TAG = "PingHandler"
        private const val PING_PATH = "/bro/ping"
        private const val PONG_PATH = "/bro/pong"
        private const val PING_TIMEOUT_MS = 5000L
    }

    private var pongCallback: ((Boolean) -> Unit)? = null

    init {
        Wearable.getMessageClient(context).addListener(this)
    }

    override fun onMessageReceived(event: MessageEvent) {
        Log.d(TAG, "Message received: ${event.path}")
        if (event.path == PONG_PATH) {
            Log.d(TAG, "Pong received from ${event.sourceNodeId}")
            pongCallback?.invoke(true)
            pongCallback = null
        }
    }

    suspend fun pingWatch(): Boolean {
        return withTimeoutOrNull(PING_TIMEOUT_MS) {
            try {
                val nodes = Wearable.getNodeClient(context)
                    .connectedNodes
                    .await()

                if (nodes.isEmpty()) {
                    Log.d(TAG, "No connected nodes found")
                    return@withTimeoutOrNull false
                }

                val node = nodes.first()
                Log.d(TAG, "Sending ping to ${node.id}")

                // Wait for pong response
                val gotPong = suspendCancellableCoroutine { continuation ->
                    pongCallback = { success ->
                        if (continuation.isActive) {
                            continuation.resume(success)
                        }
                    }

                    // Send ping message
                    Wearable.getMessageClient(context)
                        .sendMessage(node.id, PING_PATH, ByteArray(0))
                        .addOnSuccessListener {
                            Log.d(TAG, "Ping sent successfully")
                        }
                        .addOnFailureListener { e ->
                            Log.e(TAG, "Failed to send ping", e)
                            if (continuation.isActive) {
                                continuation.resume(false)
                            }
                        }
                }

                gotPong
            } catch (e: Exception) {
                Log.e(TAG, "Error during ping", e)
                false
            }
        } ?: false
    }

    fun dispose() {
        Wearable.getMessageClient(context).removeListener(this)
        pongCallback = null
    }
}
