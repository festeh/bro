package com.github.festeh.bro.chat

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName

data class ChatMessage(
    val id: String,
    val role: String,
    val content: String,
    val timestamp: Long = System.currentTimeMillis()
) {
    companion object {
        private val gson = Gson()

        fun fromJson(json: String): ChatMessage = gson.fromJson(json, ChatMessage::class.java)
    }

    fun toJson(): String = gson.toJson(this)

    fun toMap(): Map<String, Any> = mapOf(
        "id" to id,
        "role" to role,
        "content" to content,
        "timestamp" to timestamp
    )
}

data class WebSocketMessage(
    val type: String,
    val content: String? = null,
    val message: String? = null,
    @SerializedName("message_id")
    val messageId: String? = null,
    val messages: List<Map<String, Any>>? = null
) {
    companion object {
        private val gson = Gson()

        fun fromJson(json: String): WebSocketMessage = gson.fromJson(json, WebSocketMessage::class.java)

        fun message(content: String): String = gson.toJson(mapOf("type" to "message", "content" to content))
        fun ping(): String = gson.toJson(mapOf("type" to "ping"))
    }
}
