package com.github.festeh.bro_wear.vad

interface VadEngine {
    fun start(config: VadConfig)
    fun stop()
    fun process(audioData: ShortArray): VadResult
    fun isRunning(): Boolean
}
