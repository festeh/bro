import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/models/chat_message.dart';

enum ConnectionState { disconnected, connecting, connected, reconnecting }

class ChatService {
  static const _methodChannel = MethodChannel('com.github.festeh.bro/chat');
  static const _eventChannel = EventChannel(
    'com.github.festeh.bro/chat_events',
  );

  final _messagesController = StreamController<ChatMessage>.broadcast();
  final _chunksController = StreamController<String>.broadcast();
  final _connectionController = StreamController<ConnectionState>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  ConnectionState _connectionState = ConnectionState.disconnected;

  Stream<ChatMessage> get messages => _messagesController.stream;
  Stream<String> get chunks => _chunksController.stream;
  Stream<ConnectionState> get connectionState => _connectionController.stream;
  ConnectionState get currentState => _connectionState;

  ChatService() {
    _listenToEvents();
  }

  void _listenToEvents() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final type = event['type'] as String?;

        switch (type) {
          case 'message':
            final data = event['data'] as Map<String, dynamic>?;
            if (data != null) {
              _messagesController.add(ChatMessage.fromMap(data));
            }
            break;

          case 'chunk':
            final content = event['content'] as String?;
            if (content != null) {
              _chunksController.add(content);
            }
            break;

          case 'history':
            final messagesList = event['messages'] as List<dynamic>?;
            if (messagesList != null) {
              for (final msg in messagesList) {
                if (msg is Map<String, dynamic>) {
                  _messagesController.add(ChatMessage.fromMap(msg));
                }
              }
            }
            break;

          case 'connection':
            final state = event['state'] as String?;
            _updateConnectionState(state);
            break;
        }
      },
      onError: (error) {
        _connectionState = ConnectionState.disconnected;
        _connectionController.add(_connectionState);
      },
    );
  }

  void _updateConnectionState(String? state) {
    switch (state) {
      case 'connected':
        _connectionState = ConnectionState.connected;
        break;
      case 'connecting':
        _connectionState = ConnectionState.connecting;
        break;
      case 'reconnecting':
        _connectionState = ConnectionState.reconnecting;
        break;
      default:
        _connectionState = ConnectionState.disconnected;
    }
    _connectionController.add(_connectionState);
  }

  Future<void> connect({
    required String serverUrl,
    required String threadId,
  }) async {
    try {
      await _methodChannel.invokeMethod('connect', {
        'serverUrl': serverUrl,
        'threadId': threadId,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to connect: ${e.message}');
    }
  }

  Future<void> disconnect() async {
    try {
      await _methodChannel.invokeMethod('disconnect');
    } on PlatformException catch (e) {
      throw Exception('Failed to disconnect: ${e.message}');
    }
  }

  Future<bool> sendMessage(String content) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('sendMessage', {
        'content': content,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to send message: ${e.message}');
    }
  }

  Future<List<ChatMessage>> getHistory() async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>(
        'getHistory',
      );
      if (result == null) return [];

      return result
          .map((item) => ChatMessage.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } on PlatformException catch (e) {
      throw Exception('Failed to get history: ${e.message}');
    }
  }

  Future<String> getConnectionState() async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'getConnectionState',
      );
      return result ?? 'disconnected';
    } on PlatformException catch (e) {
      throw Exception('Failed to get connection state: ${e.message}');
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _messagesController.close();
    _chunksController.close();
    _connectionController.close();
  }
}
