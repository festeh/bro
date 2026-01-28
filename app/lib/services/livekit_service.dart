import 'dart:async';
import 'dart:convert';

import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../constants/livekit_constants.dart';
import '../models/models_config.dart';
import 'token_service.dart';

final _log = Logger('LiveKitService');

enum ConnectionStatus { disconnected, connecting, connected, error }

enum SttProvider { deepgram, elevenlabs }

enum AgentMode { chat, transcribe }

/// LLM provider for TaskAgent (task management)
enum TaskAgentProvider { chutes, groq, openrouter, gemini }

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
  final String? model;
  final String? intent;
  final String? responseType;

  ImmediateTextEvent({
    required this.segmentId,
    required this.text,
    required this.participantId,
    this.model,
    this.intent,
    this.responseType,
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
  static const String _defaultWsUrl = 'ws://localhost:7880';
  static const String _defaultIdentity = 'desktop-user';

  final String _wsUrl;
  final String _identity;
  late final String _roomName;

  final TokenService _tokenService;
  Room? _room;
  LocalAudioTrack? _audioTrack;
  SttProvider _sttProvider = SttProvider.deepgram;
  late Model _llmModel;
  AgentMode _agentMode = AgentMode.chat;
  bool _ttsEnabled = true;
  TaskAgentProvider _taskAgentProvider = TaskAgentProvider.groq;
  Set<String> _excludedAgents = {};

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _audioTrackIdController = StreamController<String?>.broadcast();
  final _transcriptionController =
      StreamController<TranscriptionEvent>.broadcast();
  final _immediateTextController =
      StreamController<ImmediateTextEvent>.broadcast();
  final _sessionNotificationController =
      StreamController<SessionNotificationEvent>.broadcast();
  final _agentConnectedController = StreamController<bool>.broadcast();
  bool _isAgentConnected = false;

  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;
  Stream<String?> get audioTrackId => _audioTrackIdController.stream;
  Stream<TranscriptionEvent> get transcriptionStream =>
      _transcriptionController.stream;
  Stream<ImmediateTextEvent> get immediateTextStream =>
      _immediateTextController.stream;
  Stream<SessionNotificationEvent> get sessionNotificationStream =>
      _sessionNotificationController.stream;
  Stream<bool> get agentConnectedStream => _agentConnectedController.stream;
  bool get isAgentConnected => _isAgentConnected;

  String? get currentAudioTrackId => _audioTrack?.sid;
  String get roomName => _roomName;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isVoiceSessionActive => _audioTrack != null;
  SttProvider get sttProvider => _sttProvider;
  Model get llmModel => _llmModel;
  AgentMode get agentMode => _agentMode;
  bool get ttsEnabled => _ttsEnabled;
  TaskAgentProvider get taskAgentProvider => _taskAgentProvider;
  Set<String> get excludedAgents => _excludedAgents;

  LiveKitService({
    TokenService? tokenService,
    String? wsUrl,
    String? identity,
  })  : _tokenService = tokenService ?? TokenService(),
        _wsUrl = wsUrl ?? _defaultWsUrl,
        _identity = identity ?? _defaultIdentity,
        _roomName = 'bro-${const Uuid().v4().substring(0, 8)}' {
    _llmModel = ModelsConfig.instance.defaultLlm;
    _log.info('Created session with room: $_roomName, url: $_wsUrl, identity: $_identity');
  }

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

      // Listen for participant events to track agent presence
      _room!.events.on<ParticipantConnectedEvent>((event) {
        if (event.participant.identity.contains('agent')) {
          _log.info('Agent connected: ${event.participant.identity}');
          _isAgentConnected = true;
          _agentConnectedController.add(true);
        }
      });
      _room!.events.on<ParticipantDisconnectedEvent>((event) {
        if (event.participant.identity.contains('agent')) {
          _log.info('Agent disconnected: ${event.participant.identity}');
          _isAgentConnected = false;
          _agentConnectedController.add(false);
        }
      });

      await _room!.connect(_wsUrl, token);

      // Check if agent is already in the room
      for (final participant in _room!.remoteParticipants.values) {
        if (participant.identity.contains('agent')) {
          _log.info('Agent already in room: ${participant.identity}');
          _isAgentConnected = true;
          _agentConnectedController.add(true);
          break;
        }
      }

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
    await stopVoiceSession();
    _room?.unregisterTextStreamHandler(LiveKitTopics.transcription);
    _room?.unregisterTextStreamHandler(LiveKitTopics.llmStream);
    _room?.unregisterTextStreamHandler(LiveKitTopics.vadStatus);
    await _room?.disconnect();
    _room?.removeListener(_onRoomEvent);
    _room = null;
    _isAgentConnected = false;
    _agentConnectedController.add(false);
    _connectionStatusController.add(ConnectionStatus.disconnected);
  }

  /// Change STT provider - agent will restart with new provider
  void setSttProvider(SttProvider provider) {
    _sttProvider = provider;
    _updateMetadata();
    _log.info('STT provider changed to: ${provider.name}');
  }

  /// Change LLM model
  void setLlmModel(Model model) {
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

  /// Change TaskAgent LLM provider
  void setTaskAgentProvider(TaskAgentProvider provider) {
    _taskAgentProvider = provider;
    _updateMetadata();
    _log.info('TaskAgent provider changed to: ${provider.name}');
  }

  /// Set excluded agents (disabled agents)
  void setExcludedAgents(Set<String> excluded) {
    _excludedAgents = excluded;
    _updateMetadata();
    _log.info('Excluded agents: $excluded');
  }

  void _updateMetadata() {
    final metadata = jsonEncode({
      'stt_provider': _sttProvider.name,
      'llm_model': _llmModel.modelId,
      'agent_mode': _agentMode.name,
      'tts_enabled': _ttsEnabled,
      'task_agent_provider': _taskAgentProvider.name,
      'excluded_agents': _excludedAgents.toList(),
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
    final model = info?.attributes[LiveKitAttributes.model];
    final intent = info?.attributes[LiveKitAttributes.intent];
    final responseType = info?.attributes[LiveKitAttributes.responseType];

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
              model: model,
              intent: intent,
              responseType: responseType,
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

  Future<String?> startVoiceSession() async {
    if (_room == null || !isConnected) {
      throw Exception('Not connected to room');
    }

    if (_audioTrack != null) {
      _log.warning('Voice session already active');
      return _audioTrack!.sid;
    }

    _log.info('Starting voice session');
    await _room!.localParticipant?.setMicrophoneEnabled(true);

    // Get the audio track after enabling
    final publications = _room!.localParticipant?.audioTrackPublications;
    if (publications != null && publications.isNotEmpty) {
      _audioTrack = publications.first.track;
      _audioTrackIdController.add(_audioTrack?.sid);
      _log.info('Voice session started, track: ${_audioTrack?.sid}');
      return _audioTrack?.sid;
    }

    _log.warning('Voice session started but no audio track found');
    return null;
  }

  Future<void> stopVoiceSession() async {
    if (_room == null) {
      _log.warning('Cannot stop voice session: not connected');
      return;
    }

    _log.info('Stopping voice session');

    // Must unpublish track (not just mute) to trigger track_unsubscribed on agent
    final track = _audioTrack;
    final trackSid = track?.sid;
    if (trackSid != null) {
      await _room!.localParticipant?.removePublishedTrack(trackSid);
      _log.info('Audio track unpublished: $trackSid');
    }

    _audioTrack = null;
    _audioTrackIdController.add(null);
    _log.info('Voice session stopped');
  }

  /// Send a text message to the agent (bypasses voice session)
  Future<void> sendTextMessage(String text) async {
    if (_room == null || !isConnected) {
      _log.warning('Cannot send text message: not connected');
      return;
    }

    _log.info('Sending text message: ${text.length} chars');
    final writer = await _room!.localParticipant!.streamText(
      StreamTextOptions(topic: LiveKitTopics.textInput),
    );
    await writer.write(text);
    await writer.close();
    _log.fine('Text message sent');
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
    _agentConnectedController.close();
  }
}
