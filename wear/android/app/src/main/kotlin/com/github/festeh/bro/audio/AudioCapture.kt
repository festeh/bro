package com.github.festeh.bro.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import com.github.festeh.bro.vad.VadConfig

class AudioCapture(
    private val config: VadConfig,
    private val onAudioFrame: (ShortArray) -> Unit
) {
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    @Volatile private var isRecording = false

    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        val bufferSize = AudioRecord.getMinBufferSize(config.sampleRate, channelConfig, audioFormat)
        if (bufferSize == AudioRecord.ERROR_BAD_VALUE || bufferSize == AudioRecord.ERROR) {
            return false
        }

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            config.sampleRate,
            channelConfig,
            audioFormat,
            bufferSize * 2
        )

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            audioRecord?.release()
            audioRecord = null
            return false
        }

        isRecording = true
        audioRecord?.startRecording()

        recordingThread = Thread {
            val frameBuffer = ShortArray(config.frameSize)
            while (isRecording) {
                val read = audioRecord?.read(frameBuffer, 0, config.frameSize) ?: 0
                if (read > 0) {
                    onAudioFrame(frameBuffer.copyOf(read))
                }
            }
        }.apply {
            priority = Thread.MAX_PRIORITY
            start()
        }

        return true
    }

    fun stop() {
        isRecording = false
        recordingThread?.join(1000)
        recordingThread = null

        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
    }

    fun isRunning(): Boolean = isRecording
}
