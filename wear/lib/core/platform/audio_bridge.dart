import 'dart:async';
import 'package:flutter/services.dart';
import 'vad_state.dart';

class AudioBridge {
  static const _eventChannel = EventChannel('com.github.festeh.bro_wear/vad_state');
  static const _methodChannel = MethodChannel('com.github.festeh.bro_wear/commands');

  Stream<VadState>? _vadStateStream;

  Stream<VadState> get vadStateStream {
    _vadStateStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => VadState.fromMap(event as Map<dynamic, dynamic>));
    return _vadStateStream!;
  }

  Future<PermissionStatus> checkPermission() async {
    final result = await _methodChannel.invokeMethod<String>('checkPermission');
    return _parsePermissionStatus(result);
  }

  Future<void> requestPermission() async {
    await _methodChannel.invokeMethod<bool>('requestPermission');
  }

  Future<void> openSettings() async {
    await _methodChannel.invokeMethod<bool>('openSettings');
  }

  Future<bool> start() async {
    final result = await _methodChannel.invokeMethod<bool>('start');
    return result ?? false;
  }

  Future<void> stop() async {
    await _methodChannel.invokeMethod<bool>('stop');
  }

  Future<Map<String, dynamic>> getStatus() async {
    final result = await _methodChannel.invokeMethod<Map>('getStatus');
    return Map<String, dynamic>.from(result ?? {});
  }

  PermissionStatus _parsePermissionStatus(String? status) {
    switch (status) {
      case 'granted':
        return PermissionStatus.granted;
      case 'denied':
        return PermissionStatus.denied;
      case 'permanentlyDenied':
        return PermissionStatus.permanentlyDenied;
      default:
        return PermissionStatus.unknown;
    }
  }
}
