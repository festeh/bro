package com.github.festeh.bro.bridge

import android.os.Handler
import android.os.Looper
import com.github.festeh.bro.chat.ChatMessage
import io.flutter.plugin.common.EventChannel

class ChatEventStream : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun emitMessage(message: ChatMessage) {
        mainHandler.post {
            eventSink?.success(mapOf(
                "type" to "message",
                "data" to message.toMap()
            ))
        }
    }

    fun emitChunk(content: String) {
        mainHandler.post {
            eventSink?.success(mapOf(
                "type" to "chunk",
                "content" to content
            ))
        }
    }

    fun emitHistory(messages: List<ChatMessage>) {
        mainHandler.post {
            eventSink?.success(mapOf(
                "type" to "history",
                "messages" to messages.map { it.toMap() }
            ))
        }
    }

    fun emitConnectionState(state: String) {
        mainHandler.post {
            eventSink?.success(mapOf(
                "type" to "connection",
                "state" to state
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
