package com.github.festeh.bro.vad

data class VadResult(
    val isSpeech: Boolean,
    val probability: Float? = null,
    val timestamp: Long = System.currentTimeMillis()
)
