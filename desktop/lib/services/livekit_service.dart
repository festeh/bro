import 'dart:async';
import 'dart:convert';

import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';

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

  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;
  Stream<String?> get audioTrackId => _audioTrackIdController.stream;
  Stream<TranscriptionEvent> get transcriptionStream =>
      _transcriptionController.stream;

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

      // Register transcription handler
      _room!.registerTextStreamHandler('lk.transcription', _onTranscription);

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
    _room?.unregisterTextStreamHandler('lk.transcription');
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
      final isFinal = info?.attributes['lk.transcription_final'] == 'true';
      final segmentId = info?.attributes['lk.segment_id'] ?? info?.id ?? '';

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
  }
}
