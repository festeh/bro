package com.github.festeh.bro.chat

import android.util.Log
import kotlinx.coroutines.*
import okhttp3.*
import java.util.concurrent.TimeUnit

enum class ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    RECONNECTING
}

class WebSocketClient(
    private val onMessage: (WebSocketMessage) -> Unit,
    private val onStateChange: (ConnectionState) -> Unit
) {
    companion object {
        private const val TAG = "WebSocketClient"
        private const val PING_INTERVAL_MS = 30_000L
        private const val MAX_RECONNECT_ATTEMPTS = 5
        private val RECONNECT_DELAYS = listOf(1000L, 2000L, 4000L, 8000L, 16000L)
    }

    private val client = OkHttpClient.Builder()
        .pingInterval(30, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    private var webSocket: WebSocket? = null
    private var serverUrl: String? = null
    private var reconnectAttempts = 0
    private var state = ConnectionState.DISCONNECTED

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var pingJob: Job? = null

    fun connect(url: String) {
        Log.d(TAG, "connect: $url")
        serverUrl = url
        reconnectAttempts = 0
        doConnect()
    }

    private fun doConnect() {
        val url = serverUrl ?: return
        updateState(if (reconnectAttempts > 0) ConnectionState.RECONNECTING else ConnectionState.CONNECTING)

        val request = Request.Builder()
            .url(url)
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "onOpen")
                reconnectAttempts = 0
                updateState(ConnectionState.CONNECTED)
                startPingLoop()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.d(TAG, "onMessage: $text")
                try {
                    val message = WebSocketMessage.fromJson(text)
                    onMessage(message)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to parse message", e)
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "onClosing: $code $reason")
                webSocket.close(1000, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "onClosed: $code $reason")
                stopPingLoop()
                updateState(ConnectionState.DISCONNECTED)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "onFailure", t)
                stopPingLoop()
                updateState(ConnectionState.DISCONNECTED)
                scheduleReconnect()
            }
        })
    }

    fun disconnect() {
        Log.d(TAG, "disconnect")
        serverUrl = null
        reconnectAttempts = MAX_RECONNECT_ATTEMPTS // Prevent reconnection
        stopPingLoop()
        webSocket?.close(1000, "User disconnect")
        webSocket = null
        updateState(ConnectionState.DISCONNECTED)
    }

    fun send(message: String): Boolean {
        val ws = webSocket ?: return false
        if (state != ConnectionState.CONNECTED) return false
        return ws.send(message)
    }

    fun sendMessage(content: String): Boolean {
        return send(WebSocketMessage.message(content))
    }

    private fun updateState(newState: ConnectionState) {
        if (state != newState) {
            state = newState
            onStateChange(newState)
        }
    }

    private fun startPingLoop() {
        stopPingLoop()
        pingJob = scope.launch {
            while (isActive) {
                delay(PING_INTERVAL_MS)
                send(WebSocketMessage.ping())
            }
        }
    }

    private fun stopPingLoop() {
        pingJob?.cancel()
        pingJob = null
    }

    private fun scheduleReconnect() {
        if (serverUrl == null) return
        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            Log.d(TAG, "Max reconnect attempts reached")
            return
        }

        val delay = RECONNECT_DELAYS.getOrElse(reconnectAttempts) { RECONNECT_DELAYS.last() }
        reconnectAttempts++

        Log.d(TAG, "Scheduling reconnect in ${delay}ms (attempt $reconnectAttempts)")

        scope.launch {
            delay(delay)
            if (serverUrl != null) {
                doConnect()
            }
        }
    }

    fun getState(): ConnectionState = state
}
