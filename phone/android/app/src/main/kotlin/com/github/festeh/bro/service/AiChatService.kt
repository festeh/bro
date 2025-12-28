package com.github.festeh.bro.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.github.festeh.bro.MainActivity
import com.github.festeh.bro.R
import com.github.festeh.bro.bridge.ChatEventStream
import com.github.festeh.bro.chat.ChatMessage
import com.github.festeh.bro.chat.ConnectionState
import com.github.festeh.bro.chat.WebSocketClient
import com.github.festeh.bro.chat.WebSocketMessage
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue

class AiChatService : Service() {

    companion object {
        private const val TAG = "AiChatService"
        private const val CHANNEL_ID = "bro_ai_chat"
        private const val NOTIFICATION_ID = 2
    }

    private val binder = LocalBinder()
    private var eventStream: ChatEventStream? = null

    private lateinit var wsClient: WebSocketClient
    private val messageQueue = ConcurrentLinkedQueue<String>()
    private val chatHistory = mutableListOf<ChatMessage>()
    private var currentStreamingContent = StringBuilder()
    private var isStreaming = false

    inner class LocalBinder : Binder() {
        fun getService(): AiChatService = this@AiChatService
    }

    override fun onCreate() {
        Log.d(TAG, "onCreate")
        super.onCreate()
        createNotificationChannel()

        wsClient = WebSocketClient(
            onMessage = { handleMessage(it) },
            onStateChange = { handleStateChange(it) }
        )
    }

    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "onBind")
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand")
        startForegroundService()
        return START_STICKY
    }

    fun setEventStream(stream: ChatEventStream?) {
        eventStream = stream
    }

    fun connect(serverUrl: String, threadId: String) {
        Log.d(TAG, "connect: $serverUrl, thread: $threadId")
        val fullUrl = "$serverUrl/ws/$threadId"
        wsClient.connect(fullUrl)
    }

    fun disconnect() {
        Log.d(TAG, "disconnect")
        wsClient.disconnect()
    }

    fun sendMessage(content: String): Boolean {
        Log.d(TAG, "sendMessage: $content")

        // Add user message to history
        val userMessage = ChatMessage(
            id = UUID.randomUUID().toString(),
            role = "user",
            content = content
        )
        chatHistory.add(userMessage)
        eventStream?.emitMessage(userMessage)

        // Send via WebSocket
        val sent = wsClient.sendMessage(content)
        if (!sent) {
            // Queue for later if not connected
            messageQueue.add(content)
        }
        return sent
    }

    fun getHistory(): List<Map<String, Any>> {
        return chatHistory.map { it.toMap() }
    }

    fun getConnectionState(): String {
        return wsClient.getState().name.lowercase()
    }

    private fun handleMessage(message: WebSocketMessage) {
        Log.d(TAG, "handleMessage: ${message.type}")

        when (message.type) {
            "history" -> {
                // Load history from server
                chatHistory.clear()
                message.messages?.forEach { msgMap ->
                    val msg = ChatMessage(
                        id = UUID.randomUUID().toString(),
                        role = msgMap["role"] as? String ?: "unknown",
                        content = msgMap["content"] as? String ?: ""
                    )
                    chatHistory.add(msg)
                }
                eventStream?.emitHistory(chatHistory)
            }

            "chunk" -> {
                if (!isStreaming) {
                    isStreaming = true
                    currentStreamingContent.clear()
                }
                message.content?.let {
                    currentStreamingContent.append(it)
                    eventStream?.emitChunk(it)
                }
            }

            "done" -> {
                if (isStreaming) {
                    val aiMessage = ChatMessage(
                        id = message.messageId ?: UUID.randomUUID().toString(),
                        role = "assistant",
                        content = currentStreamingContent.toString()
                    )
                    chatHistory.add(aiMessage)
                    eventStream?.emitMessage(aiMessage)
                    isStreaming = false
                    currentStreamingContent.clear()
                }
            }

            "error" -> {
                eventStream?.emitError("SERVER_ERROR", message.message ?: "Unknown error")
                isStreaming = false
                currentStreamingContent.clear()
            }

            "pong" -> {
                // Heartbeat response, no action needed
            }
        }
    }

    private fun handleStateChange(state: ConnectionState) {
        Log.d(TAG, "handleStateChange: $state")
        eventStream?.emitConnectionState(state.name.lowercase())

        // Send queued messages when connected
        if (state == ConnectionState.CONNECTED) {
            while (messageQueue.isNotEmpty()) {
                val msg = messageQueue.poll()
                if (msg != null) {
                    wsClient.sendMessage(msg)
                }
            }
        }
    }

    private fun startForegroundService() {
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "AI Chat",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "AI chat connection service"
            setShowBadge(false)
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Bro AI")
            .setContentText("Chat connected")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        wsClient.disconnect()
        super.onDestroy()
    }
}
