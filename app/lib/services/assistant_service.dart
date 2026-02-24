import 'dart:async';

import 'package:flutter/services.dart';

class AssistantService {
  static const _channel = MethodChannel('com.github.festeh.bro/assistant');
  static const _eventChannel = EventChannel('com.github.festeh.bro/assistant_events');

  Stream<void>? _assistStream;

  Future<bool> checkAssistLaunch() async {
    final result = await _channel.invokeMethod<bool>('isLaunchedFromAssist');
    return result ?? false;
  }

  Future<String> requestDefaultRole() async {
    final result = await _channel.invokeMethod<String>('requestAssistantRole');
    return result ?? 'unavailable';
  }

  Future<void> openAssistantSettings() async {
    await _channel.invokeMethod('openAssistantSettings');
  }

  /// Stream that emits when the assistant is triggered while the app is already running.
  Stream<void> get onAssistTriggered {
    _assistStream ??= _eventChannel.receiveBroadcastStream().map((_) {});
    return _assistStream!;
  }
}
