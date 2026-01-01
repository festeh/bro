package com.github.festeh.bro.codec

import android.util.Log
import com.theeasiestway.opus.Constants
import com.theeasiestway.opus.Opus
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Singleton Opus decoder.
 * MUST be singleton because native lib uses a global codec instance.
 */
object OpusDecoder {
    private const val TAG = "OpusDecoder"

    private var opus: Opus? = null
    private var initialized = false

    // 20ms frame at 16kHz = 320 samples
    private val frameSize = Constants.FrameSize._320()
    private val sampleRate = Constants.SampleRate._16000()

    @Synchronized
    fun init() {
        if (initialized) return

        opus = Opus()
        val result = opus!!.decoderInit(sampleRate, Constants.Channels.mono())

        if (result < 0) {
            throw IllegalStateException("Failed to initialize Opus decoder: $result")
        }

        initialized = true
        Log.d(TAG, "Opus decoder initialized")
    }

    /**
     * Decode raw Opus frames (with 2-byte length prefix) to PCM.
     * This is the format produced by the watch encoder.
     *
     * @param rawOpusData Raw Opus frames with 2-byte little-endian length prefix
     * @return ShortArray of PCM 16-bit mono samples at 16kHz
     */
    @Synchronized
    fun decodeRawFrames(rawOpusData: ByteArray): ShortArray {
        if (!initialized || opus == null) {
            throw IllegalStateException("OpusDecoder not initialized. Call init() first.")
        }

        val output = mutableListOf<Short>()
        val buffer = ByteBuffer.wrap(rawOpusData).order(ByteOrder.LITTLE_ENDIAN)
        var frameCount = 0

        while (buffer.remaining() >= 2) {
            val frameLength = buffer.short.toInt() and 0xFFFF

            if (frameLength == 0) {
                Log.w(TAG, "Zero-length frame at position ${buffer.position()}")
                continue
            }

            if (buffer.remaining() < frameLength) {
                Log.w(TAG, "Truncated frame: expected $frameLength bytes, only ${buffer.remaining()} remaining")
                break
            }

            val frame = ByteArray(frameLength)
            buffer.get(frame)

            // Decode this frame - returns ByteArray, convert to shorts
            val pcmBytes = opus!!.decode(frame, frameSize, 0)
            if (pcmBytes != null && pcmBytes.isNotEmpty()) {
                val shorts = bytesToShorts(pcmBytes)
                output.addAll(shorts.toList())
                frameCount++
            } else {
                Log.w(TAG, "Failed to decode frame $frameCount (${frameLength} bytes)")
            }
        }

        Log.d(TAG, "Decoded $frameCount frames to ${output.size} PCM samples")
        return output.toShortArray()
    }

    /**
     * Decode a single Opus frame to PCM.
     *
     * @param opusFrame Single Opus frame (without length prefix)
     * @return ShortArray of PCM samples, or null if decoding failed
     */
    @Synchronized
    fun decodeFrame(opusFrame: ByteArray): ShortArray? {
        if (!initialized || opus == null) {
            throw IllegalStateException("OpusDecoder not initialized. Call init() first.")
        }

        val pcmBytes = opus!!.decode(opusFrame, frameSize, 0) ?: return null
        return bytesToShorts(pcmBytes)
    }

    /**
     * Convert PCM ByteArray (little-endian) to ShortArray.
     */
    private fun bytesToShorts(bytes: ByteArray): ShortArray {
        val shorts = ShortArray(bytes.size / 2)
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        for (i in shorts.indices) {
            shorts[i] = buffer.short
        }
        return shorts
    }

    /**
     * Convert PCM ShortArray to ByteArray (for AudioTrack).
     */
    fun pcmToBytes(pcm: ShortArray): ByteArray {
        val bytes = ByteArray(pcm.size * 2)
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        for (sample in pcm) {
            buffer.putShort(sample)
        }
        return bytes
    }

    // Note: We don't release the decoder since it's a singleton
    // and the native lib uses a global codec anyway
}
