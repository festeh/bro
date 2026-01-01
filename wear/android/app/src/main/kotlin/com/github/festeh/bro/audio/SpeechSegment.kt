package com.github.festeh.bro.audio

import java.util.UUID

data class SpeechSegment(
    val id: UUID,
    val startTime: Long,
    val endTime: Long,
    val sampleRate: Int = 16000,
    val data: ShortArray,
    val opusData: ByteArray? = null
) {
    val durationMs: Long get() = endTime - startTime

    fun toPcmBytes(): ByteArray {
        val bytes = ByteArray(data.size * 2)
        for (i in data.indices) {
            bytes[i * 2] = (data[i].toInt() and 0xFF).toByte()
            bytes[i * 2 + 1] = (data[i].toInt() shr 8 and 0xFF).toByte()
        }
        return bytes
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SpeechSegment) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}
