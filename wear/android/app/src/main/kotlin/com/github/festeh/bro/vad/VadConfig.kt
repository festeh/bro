package com.github.festeh.bro.vad

data class VadConfig(
    val preRollMs: Int = 500,
    val silenceTimeoutMs: Int = 1000,  // 1 second silence to end segment
    val minSpeechMs: Int = 1000,
    val maxSpeechMs: Int = 60_000,
    val sampleRate: Int = 16000,
    val frameSize: Int = 320
)
