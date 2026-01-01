package com.github.festeh.bro.vad

interface VadEngine {
    fun start(config: VadConfig)
    fun stop()
    fun process(audioData: ShortArray): VadResult
    fun isRunning(): Boolean
}
