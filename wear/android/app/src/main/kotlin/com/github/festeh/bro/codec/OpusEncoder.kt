package com.github.festeh.bro.codec

import com.theeasiestway.opus.Constants
import com.theeasiestway.opus.Opus
import java.io.ByteArrayOutputStream

/**
 * Wrapper for Opus encoding optimized for voice on WearOS.
 * Encodes PCM 16-bit mono audio at 16kHz to Opus.
 *
 * Uses theeasiestway/android-opus-codec library.
 */
class OpusEncoder {
    private var opus: Opus? = null
    private var initialized = false

    // 20ms frame at 16kHz = 320 samples
    private val frameSize = Constants.FrameSize._320()

    fun init() {
        if (initialized) return

        opus = Opus()
        val result = opus!!.encoderInit(
            Constants.SampleRate._16000(),
            Constants.Channels.mono(),
            Constants.Application.voip()
        )

        if (result < 0) {
            throw IllegalStateException("Failed to initialize Opus encoder: $result")
        }

        // Balance quality vs CPU (0-10, default 10)
        opus!!.encoderSetComplexity(Constants.Complexity.instance(5))

        initialized = true
    }

    /**
     * Encode PCM samples to Opus.
     * Input: ShortArray of PCM 16-bit mono samples at 16kHz
     * Output: ByteArray of Opus-encoded frames concatenated together
     *
     * Note: Each Opus frame is prefixed with its length (2 bytes, little-endian)
     * for proper decoding later.
     */
    fun encode(pcmSamples: ShortArray): ByteArray {
        if (!initialized || opus == null) {
            throw IllegalStateException("OpusEncoder not initialized. Call init() first.")
        }

        val output = ByteArrayOutputStream()
        var offset = 0
        val frameSamples = frameSize.v

        while (offset + frameSamples <= pcmSamples.size) {
            val frame = pcmSamples.copyOfRange(offset, offset + frameSamples)

            // Encode returns ShortArray, convert to ByteArray
            val encodedShorts = opus!!.encode(frame, frameSize)
            if (encodedShorts != null && encodedShorts.isNotEmpty()) {
                val encodedBytes = opus!!.convert(encodedShorts)
                if (encodedBytes != null) {
                    // Write frame length (2 bytes, little-endian) then frame data
                    output.write(encodedBytes.size and 0xFF)
                    output.write((encodedBytes.size shr 8) and 0xFF)
                    output.write(encodedBytes)
                }
            }

            offset += frameSamples
        }

        // Handle remaining samples (pad with zeros if needed)
        if (offset < pcmSamples.size) {
            val remaining = pcmSamples.size - offset
            val frame = ShortArray(frameSamples)
            System.arraycopy(pcmSamples, offset, frame, 0, remaining)
            // Rest is already zero-padded

            val encodedShorts = opus!!.encode(frame, frameSize)
            if (encodedShorts != null && encodedShorts.isNotEmpty()) {
                val encodedBytes = opus!!.convert(encodedShorts)
                if (encodedBytes != null) {
                    output.write(encodedBytes.size and 0xFF)
                    output.write((encodedBytes.size shr 8) and 0xFF)
                    output.write(encodedBytes)
                }
            }
        }

        return output.toByteArray()
    }

    fun release() {
        if (initialized) {
            opus?.encoderRelease()
            opus = null
            initialized = false
        }
    }
}
