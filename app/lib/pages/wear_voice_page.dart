import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/livekit_providers.dart';
import '../providers/settings_provider.dart';
import '../services/livekit_service.dart';
import 'wear_settings_page.dart';

class WearVoicePage extends ConsumerStatefulWidget {
  const WearVoicePage({super.key});

  @override
  ConsumerState<WearVoicePage> createState() => _WearVoicePageState();
}

class _WearVoicePageState extends ConsumerState<WearVoicePage> {
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _connectToRoom();
  }

  Future<void> _connectToRoom() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;

    setState(() => _isConnecting = true);
    try {
      await ref.read(liveKitServiceProvider).connect();
    } catch (e) {
      // Connection error handled by status stream
    }
    if (mounted) setState(() => _isConnecting = false);
  }

  Future<void> _toggleVoice(ConnectionStatus connectionStatus, bool isVoiceActive) async {
    if (connectionStatus != ConnectionStatus.connected) return;

    final liveKit = ref.read(liveKitServiceProvider);
    if (isVoiceActive) {
      await liveKit.stopVoiceSession();
    } else {
      await liveKit.startVoiceSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus =
        ref.watch(connectionStatusProvider).valueOrNull ??
            ConnectionStatus.disconnected;
    final isAgentConnected =
        ref.watch(agentConnectedProvider).valueOrNull ?? false;
    final isVoiceActive =
        ref.watch(audioTrackIdProvider).valueOrNull != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _SwipeDetector(
        onSwipeUp: _openSettings,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatusIndicator(connectionStatus, isAgentConnected),
              const SizedBox(height: 16),
              _buildMicButton(connectionStatus, isVoiceActive),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const WearSettingsPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  Widget _buildStatusIndicator(
      ConnectionStatus connectionStatus, bool isAgentConnected) {
    Color color;
    if (connectionStatus == ConnectionStatus.connected && isAgentConnected) {
      color = Colors.green;
    } else if (connectionStatus == ConnectionStatus.connected) {
      color = Colors.orange;
    } else if (connectionStatus == ConnectionStatus.connecting) {
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

  Widget _buildMicButton(
      ConnectionStatus connectionStatus, bool isVoiceActive) {
    final bool canPress = connectionStatus == ConnectionStatus.connected;

    return GestureDetector(
      onTap: canPress ? () => _toggleVoice(connectionStatus, isVoiceActive) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: isVoiceActive ? Colors.red : Colors.grey[800],
          shape: BoxShape.circle,
          border: Border.all(
            color: isVoiceActive ? Colors.red[300]! : Colors.grey[600]!,
            width: 3,
          ),
          boxShadow: isVoiceActive
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
          isVoiceActive ? Icons.mic : Icons.mic_none,
          size: 48,
          color: canPress ? Colors.white : Colors.grey[500],
        ),
      ),
    );
  }

  Widget _buildStatusText(ConnectionStatus connectionStatus,
      bool isAgentConnected, bool isVoiceActive) {
    String text;
    if (_isConnecting) {
      text = 'Connecting...';
    } else if (connectionStatus == ConnectionStatus.error) {
      text = 'Connection error';
    } else if (connectionStatus != ConnectionStatus.connected) {
      text = 'Disconnected';
    } else if (!isAgentConnected) {
      text = 'Waiting for agent';
    } else if (isVoiceActive) {
      text = 'Listening...';
    } else {
      text = 'Tap to speak';
    }

    return Text(text, style: TextStyle(color: Colors.grey[400], fontSize: 14));
  }
}

/// Detects vertical swipes using raw pointer events so it doesn't
/// interfere with child GestureDetector tap handlers.
class _SwipeDetector extends StatefulWidget {
  final VoidCallback onSwipeUp;
  final Widget child;

  const _SwipeDetector({required this.onSwipeUp, required this.child});

  @override
  State<_SwipeDetector> createState() => _SwipeDetectorState();
}

class _SwipeDetectorState extends State<_SwipeDetector> {
  double? _startY;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _startY = e.position.dy,
      onPointerUp: (e) {
        if (_startY != null) {
          final dy = e.position.dy - _startY!;
          if (dy < -50) widget.onSwipeUp();
          _startY = null;
        }
      },
      child: widget.child,
    );
  }
}
