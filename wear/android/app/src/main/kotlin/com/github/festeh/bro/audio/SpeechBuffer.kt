package com.github.festeh.bro.audio

import java.util.UUID

class SpeechBuffer(
    private val sampleRate: Int,
    private val maxDurationMs: Int
) {
    private val maxSamples = (sampleRate * maxDurationMs) / 1000
    private var buffer = mutableListOf<Short>()
    private var startTime: Long = 0

    val size: Int get() = buffer.size
    val durationMs: Int get() = (buffer.size * 1000) / sampleRate

    @Synchronized
    fun start(preRoll: ShortArray, preRollMs: Int) {
        buffer = preRoll.toMutableList()
        startTime = System.currentTimeMillis() - preRollMs
    }

    @Synchronized
    fun append(samples: ShortArray): Boolean {
        val remaining = maxSamples - buffer.size
        if (remaining <= 0) return false

        val toAdd = minOf(samples.size, remaining)
        for (i in 0 until toAdd) {
            buffer.add(samples[i])
        }

        return buffer.size < maxSamples
    }

    @Synchronized
    fun isMaxDurationReached(): Boolean = buffer.size >= maxSamples

    @Synchronized
    fun toSegment(): SpeechSegment {
        return SpeechSegment(
            id = UUID.randomUUID(),
            startTime = startTime,
            endTime = System.currentTimeMillis(),
            sampleRate = sampleRate,
            data = buffer.toShortArray()
        )
    }

    @Synchronized
    fun clear() {
        buffer.clear()
        startTime = 0
    }
}
