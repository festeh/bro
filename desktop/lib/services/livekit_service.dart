import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';

import '../constants/livekit_constants.dart';
import 'token_service.dart';

final _log = Logger('LiveKitService');

enum ConnectionStatus { disconnected, connecting, connected, error }

enum SttProvider { deepgram, elevenlabs }

enum LlmModel { glm47, mimoV2, minimax, kimiK2, deepseekV31 }

enum AgentMode { chat, transcribe }

class TranscriptionEvent {
  final String segmentId;
  final String text;
  final bool isFinal;
  final String participantId;

  TranscriptionEvent({
    required this.segmentId,
    required this.text,
    required this.isFinal,
    required this.participantId,
  });
}

/// Immediate LLM text event (arrives before TTS-synced transcription)
class ImmediateTextEvent {
  final String segmentId;
  final String text;
  final String participantId;

  ImmediateTextEvent({
    required this.segmentId,
    required this.text,
    required this.participantId,
  });
}

/// Session notification event types
enum SessionNotificationType { sessionWarning, sessionTimeout, sessionReady }

/// Session notification from agent
class SessionNotificationEvent {
  final SessionNotificationType type;
  final String sessionId;
  final Map<String, dynamic> payload;
  final String participantId;

  SessionNotificationEvent({
    required this.type,
    required this.sessionId,
    required this.payload,
    required this.participantId,
  });

  int? get remainingSeconds =>
      type == SessionNotificationType.sessionWarning
          ? payload['remaining_seconds'] as int?
          : null;

  String? get reason =>
      type == SessionNotificationType.sessionTimeout
          ? payload['reason'] as String?
          : null;

  double? get idleDuration =>
      type == SessionNotificationType.sessionTimeout
          ? (payload['idle_duration'] as num?)?.toDouble()
          : null;
}

class LiveKitService {
  static const String _wsUrl = 'ws://localhost:7880';
  static const String _roomName = 'voice-recorder';
  static const String _identity = 'desktop-user';

  final TokenService _tokenService;
  Room? _room;
  LocalAudioTrack? _audioTrack;
  SttProvider _sttProvider = SttProvider.deepgram;
  LlmModel _llmModel = LlmModel.deepseekV31;
  AgentMode _agentMode = AgentMode.chat;
  bool _ttsEnabled = true;

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _audioTrackIdController = StreamController<String?>.broadcast();
  final _transcriptionController =
      StreamController<TranscriptionEvent>.broadcast();
  final _immediateTextController =
      StreamController<ImmediateTextEvent>.broadcast();
  final _sessionNotificationController =
      StreamController<SessionNotificationEvent>.broadcast();

  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;
  Stream<String?> get audioTrackId => _audioTrackIdController.stream;
  Stream<TranscriptionEvent> get transcriptionStream =>
      _transcriptionController.stream;
  Stream<ImmediateTextEvent> get immediateTextStream =>
      _immediateTextController.stream;
  Stream<SessionNotificationEvent> get sessionNotificationStream =>
      _sessionNotificationController.stream;

  String? get currentAudioTrackId => _audioTrack?.sid;
  String get roomName => _roomName;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isMicrophoneEnabled => _audioTrack != null;
  SttProvider get sttProvider => _sttProvider;
  LlmModel get llmModel => _llmModel;
  AgentMode get agentMode => _agentMode;
  bool get ttsEnabled => _ttsEnabled;

  LiveKitService({TokenService? tokenService})
    : _tokenService = tokenService ?? TokenService();

  Future<void> connect() async {
    if (_room != null) return;

    _connectionStatusController.add(ConnectionStatus.connecting);

    try {
      final token = _tokenService.generateRoomToken(
        roomName: _roomName,
        identity: _identity,
      );

      _room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(
            audioBitrate: 24000, // Speech quality
          ),
        ),
      );

      _room!.addListener(_onRoomEvent);

      await _room!.connect(_wsUrl, token);

      // Register transcription handlers
      _room!.registerTextStreamHandler(
        LiveKitTopics.transcription,
        _onTranscription,
      );
      _room!.registerTextStreamHandler(
        LiveKitTopics.llmStream,
        _onImmediateText,
      );
      _room!.registerTextStreamHandler(
        LiveKitTopics.vadStatus,
        _onSessionNotification,
      );

      // Set initial STT provider in metadata
      _updateMetadata();

      _connectionStatusController.add(ConnectionStatus.connected);
    } catch (e) {
      _connectionStatusController.add(ConnectionStatus.error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await disableMicrophone();
    _room?.unregisterTextStreamHandler(LiveKitTopics.transcription);
    _room?.unregisterTextStreamHandler(LiveKitTopics.llmStream);
    _room?.unregisterTextStreamHandler(LiveKitTopics.vadStatus);
    await _room?.disconnect();
    _room?.removeListener(_onRoomEvent);
    _room = null;
    _connectionStatusController.add(ConnectionStatus.disconnected);
  }

  /// Change STT provider - agent will restart with new provider
  void setSttProvider(SttProvider provider) {
    _sttProvider = provider;
    _updateMetadata();
    _log.info('STT provider changed to: ${provider.name}');
  }

  /// Change LLM model
  void setLlmModel(LlmModel model) {
    _llmModel = model;
    _updateMetadata();
    _log.info('LLM model changed to: ${model.name}');
  }

  /// Change agent mode - affects whether LLM/TTS are used
  void setAgentMode(AgentMode mode) {
    _agentMode = mode;
    _updateMetadata();
    _log.info('Agent mode changed to: ${mode.name}');
  }

  /// Enable/disable TTS (voice responses)
  void setTtsEnabled(bool enabled) {
    _ttsEnabled = enabled;
    _updateMetadata();
    _log.info('TTS enabled: $enabled');
  }

  void _updateMetadata() {
    final metadata = jsonEncode({
      'stt_provider': _sttProvider.name,
      'llm_model': _llmModel.name,
      'agent_mode': _agentMode.name,
      'tts_enabled': _ttsEnabled,
    });
    _room?.localParticipant?.setMetadata(metadata);
  }

  void _onTranscription(TextStreamReader reader, String participantId) async {
    try {
      final text = await reader.readAll();
      final info = reader.info;
      final isFinal =
          info?.attributes[LiveKitAttributes.transcriptionFinal] == 'true';
      final segmentId =
          info?.attributes[LiveKitAttributes.segmentId] ?? info?.id ?? '';

      _log.fine('Transcription from $participantId: $text (final: $isFinal)');

      _transcriptionController.add(
        TranscriptionEvent(
          segmentId: segmentId,
          text: text,
          isFinal: isFinal,
          participantId: participantId,
        ),
      );
    } catch (e) {
      _log.warning('Error processing transcription: $e');
    }
  }

  void _onImmediateText(TextStreamReader reader, String participantId) {
    final info = reader.info;
    final segmentId =
        info?.attributes[LiveKitAttributes.segmentId] ?? info?.id ?? '';

    reader.listen(
      (chunk) {
        try {
          final text = utf8.decode(chunk.content.toList());
          _log.fine('Chunk from $participantId: "$text"');

          _immediateTextController.add(
            ImmediateTextEvent(
              segmentId: segmentId,
              text: text,
              participantId: participantId,
            ),
          );
        } catch (e) {
          _log.warning('Error decoding chunk: $e');
        }
      },
      onError: (e) => _log.warning('Error in immediate text stream: $e'),
    );
  }

  void _onSessionNotification(TextStreamReader reader, String participantId) async {
    try {
      final text = await reader.readAll();
      final json = jsonDecode(text) as Map<String, dynamic>;

      final typeStr = json['type'] as String?;
      if (typeStr == null) return;

      SessionNotificationType? type;
      switch (typeStr) {
        case 'session_warning':
          type = SessionNotificationType.sessionWarning;
          break;
        case 'session_timeout':
          type = SessionNotificationType.sessionTimeout;
          break;
        case 'session_ready':
          type = SessionNotificationType.sessionReady;
          break;
        default:
          _log.warning('Unknown session notification type: $typeStr');
          return;
      }

      final sessionId = json['session_id'] as String? ?? '';
      final payload = Map<String, dynamic>.from(json)
        ..remove('type')
        ..remove('session_id');

      _log.info('Session notification: $typeStr session=$sessionId payload=$payload');

      _sessionNotificationController.add(
        SessionNotificationEvent(
          type: type,
          sessionId: sessionId,
          payload: payload,
          participantId: participantId,
        ),
      );
    } catch (e) {
      _log.warning('Error processing session notification: $e');
    }
  }

  Future<String?> enableMicrophone() async {
    if (_room == null || !isConnected) {
      throw Exception('Not connected to room');
    }

    if (_audioTrack != null) {
      return _audioTrack!.sid;
    }

    await _room!.localParticipant?.setMicrophoneEnabled(true);

    // Get the audio track after enabling
    final publications = _room!.localParticipant?.audioTrackPublications;
    if (publications != null && publications.isNotEmpty) {
      _audioTrack = publications.first.track;
      _audioTrackIdController.add(_audioTrack?.sid);
      return _audioTrack?.sid;
    }

    return null;
  }

  Future<void> disableMicrophone() async {
    if (_room == null) return;

    await _room!.localParticipant?.setMicrophoneEnabled(false);
    _audioTrack = null;
    _audioTrackIdController.add(null);
  }

  void _onRoomEvent() {
    // Handle room events if needed
  }

  void dispose() {
    disconnect();
    _connectionStatusController.close();
    _audioTrackIdController.close();
    _transcriptionController.close();
    _immediateTextController.close();
    _sessionNotificationController.close();
  }
}
