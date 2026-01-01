package com.github.festeh.bro.vad

import com.konovalov.vad.webrtc.Vad
import com.konovalov.vad.webrtc.VadWebRTC
import com.konovalov.vad.webrtc.config.FrameSize
import com.konovalov.vad.webrtc.config.Mode
import com.konovalov.vad.webrtc.config.SampleRate

class WebRtcVadEngine : VadEngine {
    private var vad: VadWebRTC? = null
    private var running = false

    override fun start(config: VadConfig) {
        val sampleRate = when (config.sampleRate) {
            8000 -> SampleRate.SAMPLE_RATE_8K
            16000 -> SampleRate.SAMPLE_RATE_16K
            32000 -> SampleRate.SAMPLE_RATE_32K
            48000 -> SampleRate.SAMPLE_RATE_48K
            else -> SampleRate.SAMPLE_RATE_16K
        }

        val frameSize = when (config.frameSize) {
            80 -> FrameSize.FRAME_SIZE_80
            160 -> FrameSize.FRAME_SIZE_160
            240 -> FrameSize.FRAME_SIZE_240
            320 -> FrameSize.FRAME_SIZE_320
            480 -> FrameSize.FRAME_SIZE_480
            640 -> FrameSize.FRAME_SIZE_640
            else -> FrameSize.FRAME_SIZE_320
        }

        vad = Vad.builder()
            .setSampleRate(sampleRate)
            .setFrameSize(frameSize)
            .setMode(Mode.VERY_AGGRESSIVE)  // Strictest - rejects more noise
            .build()

        running = true
    }

    override fun stop() {
        running = false
        vad?.close()
        vad = null
    }

    override fun process(audioData: ShortArray): VadResult {
        val isSpeech = vad?.isSpeech(audioData) ?: false
        return VadResult(isSpeech = isSpeech)
    }

    override fun isRunning(): Boolean = running
}
