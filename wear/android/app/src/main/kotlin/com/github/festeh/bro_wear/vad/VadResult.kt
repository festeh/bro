package com.github.festeh.bro_wear.vad

data class VadResult(
    val isSpeech: Boolean,
    val probability: Float? = null,
    val timestamp: Long = System.currentTimeMillis()
)
