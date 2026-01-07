import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

import 'token_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class LiveKitService {
  static const String _wsUrl = 'ws://localhost:7880';
  static const String _roomName = 'voice-recorder';
  static const String _identity = 'desktop-user';

  final TokenService _tokenService;
  Room? _room;
  LocalAudioTrack? _audioTrack;

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _audioTrackIdController = StreamController<String?>.broadcast();

  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;
  Stream<String?> get audioTrackId => _audioTrackIdController.stream;

  String? get currentAudioTrackId => _audioTrack?.sid;
  String get roomName => _roomName;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isMicrophoneEnabled => _audioTrack != null;

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

      _room = Room();

      _room!.addListener(_onRoomEvent);

      await _room!.connect(
        _wsUrl,
        token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(
            audioBitrate: 24000, // Speech quality
          ),
        ),
      );

      _connectionStatusController.add(ConnectionStatus.connected);
    } catch (e) {
      _connectionStatusController.add(ConnectionStatus.error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await disableMicrophone();
    await _room?.disconnect();
    _room?.removeListener(_onRoomEvent);
    _room = null;
    _connectionStatusController.add(ConnectionStatus.disconnected);
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
      _audioTrack = publications.first.track as LocalAudioTrack?;
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
  }
}
