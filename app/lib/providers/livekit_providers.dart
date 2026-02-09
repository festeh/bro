import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/livekit_service.dart';
import 'settings_provider.dart';

/// Connection status stream from LiveKitService.
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  return ref.watch(liveKitServiceProvider).connectionStatus;
});

/// Whether an agent is connected to the room.
final agentConnectedProvider = StreamProvider<bool>((ref) {
  return ref.watch(liveKitServiceProvider).agentConnectedStream;
});

/// Speech transcription events (user and agent).
final transcriptionProvider = StreamProvider<TranscriptionEvent>((ref) {
  return ref.watch(liveKitServiceProvider).transcriptionStream;
});

/// Immediate LLM text events (agent responses before TTS).
final immediateTextProvider = StreamProvider<ImmediateTextEvent>((ref) {
  return ref.watch(liveKitServiceProvider).immediateTextStream;
});

/// Session lifecycle notifications (ready, warning, timeout).
final sessionNotificationProvider =
    StreamProvider<SessionNotificationEvent>((ref) {
  return ref.watch(liveKitServiceProvider).sessionNotificationStream;
});

/// Active audio track ID (non-null when mic is publishing).
final audioTrackIdProvider = StreamProvider<String?>((ref) {
  return ref.watch(liveKitServiceProvider).audioTrackId;
});
