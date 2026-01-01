import 'dart:async';
import 'package:flutter/services.dart';
import 'vad_state.dart';
import '../log.dart';

class AudioBridge {
  static const _eventChannel = EventChannel(
    'com.github.festeh.bro/vad_state',
  );
  static const _pingEventChannel = EventChannel(
    'com.github.festeh.bro/ping',
  );
  static const _methodChannel = MethodChannel(
    'com.github.festeh.bro/commands',
  );

  Stream<VadState>? _vadStateStream;
  Stream<DateTime>? _pingStream;

  Stream<VadState> get vadStateStream {
    log.d('AudioBridge: setting up vadStateStream');
    _vadStateStream ??= _eventChannel.receiveBroadcastStream().map(
      (event) => VadState.fromMap(event as Map<dynamic, dynamic>),
    );
    return _vadStateStream!;
  }

  Stream<DateTime> get pingStream {
    log.d('AudioBridge: setting up pingStream');
    _pingStream ??= _pingEventChannel.receiveBroadcastStream().map((event) {
      final timestamp = event as int;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    });
    return _pingStream!;
  }

  Future<bool> isPhoneConnected() async {
    log.d('AudioBridge: isPhoneConnected');
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isPhoneConnected',
      );
      return result ?? false;
    } catch (e) {
      log.d('AudioBridge: isPhoneConnected error=$e');
      return false;
    }
  }

  Future<PermissionStatus> checkPermission() async {
    log.d('AudioBridge: checkPermission');
    final result = await _methodChannel.invokeMethod<String>('checkPermission');
    log.d('AudioBridge: checkPermission result=$result');
    return _parsePermissionStatus(result);
  }

  Future<void> requestPermission() async {
    log.d('AudioBridge: requestPermission');
    await _methodChannel.invokeMethod<bool>('requestPermission');
  }

  Future<void> openSettings() async {
    log.d('AudioBridge: openSettings');
    await _methodChannel.invokeMethod<bool>('openSettings');
  }

  Future<bool> start() async {
    log.d('AudioBridge: start');
    final result = await _methodChannel.invokeMethod<bool>('start');
    log.d('AudioBridge: start result=$result');
    return result ?? false;
  }

  Future<void> stop() async {
    log.d('AudioBridge: stop');
    await _methodChannel.invokeMethod<bool>('stop');
  }

  Future<Map<String, dynamic>> getStatus() async {
    log.d('AudioBridge: getStatus');
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
