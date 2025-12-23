package com.github.festeh.bro_wear.vad

data class VadConfig(
    val preRollMs: Int = 500,
    val silenceTimeoutMs: Int = 300,
    val minSpeechMs: Int = 1000,
    val maxSpeechMs: Int = 60_000,
    val sampleRate: Int = 16000,
    val frameSize: Int = 320
)
