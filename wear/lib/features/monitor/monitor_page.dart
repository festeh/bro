import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/platform/audio_bridge.dart';
import '../../core/platform/vad_state.dart';
import '../../core/log.dart';
import 'widgets/vad_indicator.dart';
import 'widgets/connection_status_bar.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  final _audioBridge = AudioBridge();
  StreamSubscription<VadState>? _vadSubscription;
  StreamSubscription<DateTime>? _pingSubscription;

  VadState _state = const VadState();
  bool _isListening = false;
  PhoneConnectionStatus _phoneStatus = PhoneConnectionStatus.disconnected;
  DateTime? _lastPingTime;

  @override
  void initState() {
    super.initState();
    log.d('MonitorPage: initState');
    _checkPermissionAndSetup();
    _checkPhoneConnection();
    _setupPingStream();
  }

  Future<void> _checkPhoneConnection() async {
    final connected = await _audioBridge.isPhoneConnected();
    if (mounted) {
      setState(() {
        _phoneStatus = connected
            ? PhoneConnectionStatus.connected
            : PhoneConnectionStatus.disconnected;
      });
    }
  }

  void _setupPingStream() {
    _pingSubscription = _audioBridge.pingStream.listen((pingTime) {
      log.d('MonitorPage: ping received at $pingTime');
      if (mounted) {
        setState(() {
          _phoneStatus = PhoneConnectionStatus.pingReceived;
          _lastPingTime = pingTime;
        });
        // Reset to connected after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _phoneStatus == PhoneConnectionStatus.pingReceived) {
            setState(() {
              _phoneStatus = PhoneConnectionStatus.connected;
            });
          }
        });
      }
    });
  }

  Future<void> _checkPermissionAndSetup() async {
    log.d('MonitorPage: _checkPermissionAndSetup');
    final permission = await _audioBridge.checkPermission();
    log.d('MonitorPage: permission=$permission');
    setState(() {
      _state = _state.copyWith(permission: permission);
    });

    if (permission == PermissionStatus.granted) {
      _setupVadStream();
    }
  }

  void _setupVadStream() {
    _vadSubscription = _audioBridge.vadStateStream.listen((state) {
      setState(() {
        _state = state.copyWith(permission: _state.permission);
      });
    });
  }

  Future<void> _requestPermission() async {
    await _audioBridge.requestPermission();
    // Check again after request
    await Future.delayed(const Duration(milliseconds: 500));
    await _checkPermissionAndSetup();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _audioBridge.stop();
      setState(() {
        _isListening = false;
        _state = _state.copyWith(status: VadStatus.idle);
      });
    } else {
      final success = await _audioBridge.start();
      if (success) {
        setState(() {
          _isListening = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _vadSubscription?.cancel();
    _pingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ConnectionStatusBar(
                status: _phoneStatus,
                lastPingTime: _lastPingTime,
              ),
            ),
            Expanded(child: Center(child: _buildContent())),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_state.permission != PermissionStatus.granted) {
      return _buildPermissionRequest();
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          VadIndicator(status: _state.status),
          const SizedBox(height: 8),
          Text(
            _getStatusText(),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _buildToggleButton(),
        ],
      ),
    );
  }

  Widget _buildPermissionRequest() {
    final isPermanentlyDenied =
        _state.permission == PermissionStatus.permanentlyDenied;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic_off, size: 40, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              isPermanentlyDenied
                  ? 'Mic permission denied'
                  : 'Mic permission required',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: isPermanentlyDenied
                  ? () => _audioBridge.openSettings()
                  : _requestPermission,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                isPermanentlyDenied ? 'Settings' : 'Grant',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton() {
    return GestureDetector(
      onTap: _toggleListening,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _isListening ? Colors.red.shade700 : Colors.blue.shade700,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _isListening ? 'Stop' : 'Start',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  String _getStatusText() {
    switch (_state.status) {
      case VadStatus.speech:
        return 'Speaking...';
      case VadStatus.silence:
        return 'Listening';
      case VadStatus.listening:
        return 'Ready';
      case VadStatus.error:
        return 'Error';
      case VadStatus.idle:
        return 'Stopped';
    }
  }
}
