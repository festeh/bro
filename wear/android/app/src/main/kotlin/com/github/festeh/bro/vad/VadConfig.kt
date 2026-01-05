package com.github.festeh.bro.vad

data class VadConfig(
    val preRollMs: Int = 500,
    val silenceTimeoutMs: Int = 1000,  // 1 second silence to end segment
    val triggerThreshold: Int = 13,    // M: require 13 speech frames in window to trigger
    val triggerWindow: Int = 15,       // N: sliding window size (300ms at 20ms/frame)
    val maxSpeechMs: Int = 60_000,
    val sampleRate: Int = 16000,
    val frameSize: Int = 320           // 20ms frames
)
