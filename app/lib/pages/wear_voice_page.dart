import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/livekit_service.dart';

class WearVoicePage extends StatefulWidget {
  final LiveKitService liveKitService;

  const WearVoicePage({super.key, required this.liveKitService});

  @override
  State<WearVoicePage> createState() => _WearVoicePageState();
}

class _WearVoicePageState extends State<WearVoicePage> {
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  bool _isVoiceActive = false;
  bool _isAgentConnected = false;
  bool _isConnecting = false;

  StreamSubscription<ConnectionStatus>? _connectionSub;
  StreamSubscription<String?>? _audioTrackSub;
  StreamSubscription<bool>? _agentSub;

  @override
  void initState() {
    super.initState();
    _setupSubscriptions();
    _connectToRoom();
  }

  void _setupSubscriptions() {
    _connectionSub = widget.liveKitService.connectionStatus.listen((status) {
      setState(() {
        _connectionStatus = status;
        _isConnecting = status == ConnectionStatus.connecting;
      });
    });

    _audioTrackSub = widget.liveKitService.audioTrackId.listen((trackId) {
      setState(() {
        _isVoiceActive = trackId != null;
      });
    });

    _agentSub = widget.liveKitService.agentConnectedStream.listen((connected) {
      setState(() {
        _isAgentConnected = connected;
      });
    });
  }

  Future<void> _connectToRoom() async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      return;
    }

    setState(() => _isConnecting = true);
    try {
      await widget.liveKitService.connect();
    } catch (e) {
      // Connection error handled by status stream
    }
  }

  Future<void> _toggleVoice() async {
    if (_connectionStatus != ConnectionStatus.connected) return;

    if (_isVoiceActive) {
      await widget.liveKitService.stopVoiceSession();
    } else {
      await widget.liveKitService.startVoiceSession();
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _audioTrackSub?.cancel();
    _agentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status indicator
            _buildStatusIndicator(),
            const SizedBox(height: 16),

            // Mic button
            _buildMicButton(),
            const SizedBox(height: 12),

            // Status text
            _buildStatusText(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    Color color;
    if (_connectionStatus == ConnectionStatus.connected && _isAgentConnected) {
      color = Colors.green;
    } else if (_connectionStatus == ConnectionStatus.connected) {
      color = Colors.orange;
    } else if (_connectionStatus == ConnectionStatus.connecting) {
      color = Colors.blue;
    } else {
      color = Colors.red;
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildMicButton() {
    final bool canPress = _connectionStatus == ConnectionStatus.connected;

    return GestureDetector(
      onTap: canPress ? _toggleVoice : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: _isVoiceActive ? Colors.red : Colors.grey[800],
          shape: BoxShape.circle,
          border: Border.all(
            color: _isVoiceActive ? Colors.red[300]! : Colors.grey[600]!,
            width: 3,
          ),
          boxShadow: _isVoiceActive
              ? [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ]
              : null,
        ),
        child: Icon(
          _isVoiceActive ? Icons.mic : Icons.mic_none,
          size: 48,
          color: canPress ? Colors.white : Colors.grey[500],
        ),
      ),
    );
  }

  Widget _buildStatusText() {
    String text;
    if (_isConnecting) {
      text = 'Connecting...';
    } else if (_connectionStatus == ConnectionStatus.error) {
      text = 'Connection error';
    } else if (_connectionStatus != ConnectionStatus.connected) {
      text = 'Disconnected';
    } else if (!_isAgentConnected) {
      text = 'Waiting for agent';
    } else if (_isVoiceActive) {
      text = 'Listening...';
    } else {
      text = 'Tap to speak';
    }

    return Text(text, style: TextStyle(color: Colors.grey[400], fontSize: 14));
  }
}
