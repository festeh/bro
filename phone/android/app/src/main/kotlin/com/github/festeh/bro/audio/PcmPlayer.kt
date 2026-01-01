package com.github.festeh.bro.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Simple PCM audio player using AudioTrack.
 * Bypasses MediaPlayer/ExoPlayer for direct control over audio playback.
 */
class PcmPlayer(
    private val sampleRate: Int = 16000,
    private val channelConfig: Int = AudioFormat.CHANNEL_OUT_MONO,
    private val audioFormat: Int = AudioFormat.ENCODING_PCM_16BIT
) {
    companion object {
        private const val TAG = "PcmPlayer"
    }

    private var audioTrack: AudioTrack? = null
    private var isPlaying = false

    /**
     * Play PCM audio data.
     *
     * @param pcmData PCM 16-bit samples as ByteArray (little-endian)
     */
    suspend fun play(pcmData: ByteArray) = withContext(Dispatchers.IO) {
        stop()

        val bufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat)

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(audioFormat)
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelConfig)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(bufferSize, pcmData.size))
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()

        audioTrack?.let { track ->
            track.write(pcmData, 0, pcmData.size)
            track.play()
            isPlaying = true
            Log.d(TAG, "Playing ${pcmData.size} bytes of PCM audio")

            // Wait for playback to complete
            val durationMs = (pcmData.size / 2) * 1000L / sampleRate
            Log.d(TAG, "Expected duration: ${durationMs}ms")
        }
    }

    /**
     * Play PCM audio data from ShortArray.
     */
    suspend fun play(pcmData: ShortArray) = withContext(Dispatchers.IO) {
        stop()

        val bufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufferSizeInShorts = bufferSize / 2

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(audioFormat)
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelConfig)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(bufferSize, pcmData.size * 2))
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()

        audioTrack?.let { track ->
            track.write(pcmData, 0, pcmData.size)
            track.play()
            isPlaying = true

            val durationMs = pcmData.size * 1000L / sampleRate
            Log.d(TAG, "Playing ${pcmData.size} samples (${durationMs}ms)")
        }
    }

    fun pause() {
        audioTrack?.pause()
        isPlaying = false
    }

    fun resume() {
        audioTrack?.play()
        isPlaying = true
    }

    fun stop() {
        audioTrack?.let { track ->
            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                track.stop()
            }
            track.release()
        }
        audioTrack = null
        isPlaying = false
    }

    fun isPlaying(): Boolean = isPlaying

    /**
     * Get current playback position in milliseconds.
     */
    fun getPositionMs(): Long {
        val track = audioTrack ?: return 0
        val framePosition = track.playbackHeadPosition
        return framePosition * 1000L / sampleRate
    }

    fun release() {
        stop()
    }
}
