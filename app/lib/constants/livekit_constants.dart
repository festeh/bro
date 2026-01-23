/// LiveKit text stream topics
class LiveKitTopics {
  static const transcription = 'lk.transcription'; // Synced with TTS
  static const llmStream = 'lk.llm_stream'; // Immediate LLM output
  static const vadStatus = 'lk.vad_status'; // VAD gating notifications
}

/// LiveKit transcription attributes
class LiveKitAttributes {
  static const segmentId = 'lk.segment_id';
  static const transcriptionFinal = 'lk.transcription_final';
}
