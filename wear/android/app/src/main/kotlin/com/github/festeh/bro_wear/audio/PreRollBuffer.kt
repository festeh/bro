package com.github.festeh.bro_wear.audio

class PreRollBuffer(
    private val sampleRate: Int,
    private val preRollMs: Int
) {
    private val capacitySamples = (sampleRate * preRollMs) / 1000
    private val buffer = ShortArray(capacitySamples)
    private var writeIndex = 0
    private var isFull = false

    @Synchronized
    fun write(samples: ShortArray) {
        for (sample in samples) {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacitySamples
            if (writeIndex == 0) isFull = true
        }
    }

    @Synchronized
    fun flush(): ShortArray {
        val size = if (isFull) capacitySamples else writeIndex
        val result = ShortArray(size)

        if (isFull) {
            val firstPart = capacitySamples - writeIndex
            System.arraycopy(buffer, writeIndex, result, 0, firstPart)
            System.arraycopy(buffer, 0, result, firstPart, writeIndex)
        } else {
            System.arraycopy(buffer, 0, result, 0, size)
        }

        return result
    }

    @Synchronized
    fun clear() {
        writeIndex = 0
        isFull = false
    }
}
