package com.github.festeh.bro.bridge

import android.util.Log
import com.github.festeh.bro.service.AiChatService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ChatCommandHandler : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "ChatCommandHandler"
    }

    private var chatService: AiChatService? = null

    fun setChatService(service: AiChatService?) {
        Log.d(TAG, "setChatService: ${service != null}")
        chatService = service
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")

        when (call.method) {
            "connect" -> {
                val serverUrl = call.argument<String>("serverUrl")
                val threadId = call.argument<String>("threadId")

                if (serverUrl == null || threadId == null) {
                    result.error("INVALID_ARG", "serverUrl and threadId are required", null)
                    return
                }

                chatService?.connect(serverUrl, threadId)
                result.success(true)
            }

            "disconnect" -> {
                chatService?.disconnect()
                result.success(true)
            }

            "sendMessage" -> {
                val content = call.argument<String>("content")
                if (content == null) {
                    result.error("INVALID_ARG", "content is required", null)
                    return
                }

                val sent = chatService?.sendMessage(content) ?: false
                result.success(sent)
            }

            "getHistory" -> {
                val history = chatService?.getHistory() ?: emptyList()
                result.success(history)
            }

            "getConnectionState" -> {
                val state = chatService?.getConnectionState() ?: "disconnected"
                result.success(state)
            }

            else -> result.notImplemented()
        }
    }
}
