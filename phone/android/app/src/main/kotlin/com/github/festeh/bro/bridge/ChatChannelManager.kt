package com.github.festeh.bro.bridge

import android.util.Log
import com.github.festeh.bro.service.AiChatService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class ChatChannelManager(
    private val messenger: BinaryMessenger
) {
    companion object {
        private const val TAG = "ChatChannelManager"
        private const val METHOD_CHANNEL = "com.github.festeh.bro/chat"
        private const val EVENT_CHANNEL = "com.github.festeh.bro/chat_events"
    }

    private val eventStream = ChatEventStream()
    private val commandHandler = ChatCommandHandler()

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    fun setup() {
        Log.d(TAG, "setup")

        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(commandHandler)
        }

        eventChannel = EventChannel(messenger, EVENT_CHANNEL).apply {
            setStreamHandler(eventStream)
        }
    }

    fun setChatService(service: AiChatService?) {
        Log.d(TAG, "setChatService: ${service != null}")
        commandHandler.setChatService(service)
        service?.setEventStream(eventStream)
    }

    fun dispose() {
        Log.d(TAG, "dispose")
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
    }
}
