package com.github.festeh.bro.vad

/**
 * VAD status states that are communicated to Flutter.
 * Values must match the Dart enum in vad_state.dart.
 */
enum class VadStatus(val value: String) {
    IDLE("idle"),
    LISTENING("listening"),
    SPEECH("speech"),
    SILENCE("silence"),
    ERROR("error");
}
