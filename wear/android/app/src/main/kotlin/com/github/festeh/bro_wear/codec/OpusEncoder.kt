package com.github.festeh.bro_wear.codec

import com.score.rahasak.utils.OpusEncoder as RahasakOpusEncoder
import java.io.ByteArrayOutputStream

/**
 * Wrapper for Opus encoding optimized for voice on WearOS.
 * Encodes PCM 16-bit mono audio at 16kHz to Opus.
 */
class OpusEncoder {
    private var encoder: RahasakOpusEncoder? = null
    private var initialized = false

    // 20ms frame at 16kHz = 320 samples
    private val frameSamples = 320
    private val sampleRate = 16000
    private val channels = 1

    // Output buffer - Opus frame max is ~1275 bytes, but voice at 24kbps is much smaller
    private val encodeBuffer = ByteArray(1275)

    fun init() {
        if (initialized) return

        encoder = RahasakOpusEncoder()
        encoder?.init(sampleRate, channels, RahasakOpusEncoder.OPUS_APPLICATION_VOIP)

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
        if (!initialized || encoder == null) {
            throw IllegalStateException("OpusEncoder not initialized. Call init() first.")
        }

        val output = ByteArrayOutputStream()
        var offset = 0

        while (offset + frameSamples <= pcmSamples.size) {
            val frame = pcmSamples.copyOfRange(offset, offset + frameSamples)
            val encodedBytes = encoder!!.encode(frame, frameSamples, encodeBuffer)

            if (encodedBytes > 0) {
                // Write frame length (2 bytes, little-endian) then frame data
                output.write(encodedBytes and 0xFF)
                output.write((encodedBytes shr 8) and 0xFF)
                output.write(encodeBuffer, 0, encodedBytes)
            }

            offset += frameSamples
        }

        // Handle remaining samples (pad with zeros if needed)
        if (offset < pcmSamples.size) {
            val remaining = pcmSamples.size - offset
            val frame = ShortArray(frameSamples)
            System.arraycopy(pcmSamples, offset, frame, 0, remaining)
            // Rest is already zero-padded

            val encodedBytes = encoder!!.encode(frame, frameSamples, encodeBuffer)
            if (encodedBytes > 0) {
                output.write(encodedBytes and 0xFF)
                output.write((encodedBytes shr 8) and 0xFF)
                output.write(encodeBuffer, 0, encodedBytes)
            }
        }

        return output.toByteArray()
    }

    fun release() {
        if (initialized) {
            encoder?.close()
            encoder = null
            initialized = false
        }
    }
}
