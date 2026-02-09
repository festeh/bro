import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/livekit_service.dart';
import 'settings_provider.dart';

final _log = Logger('ChatProvider');
const _uuid = Uuid();

class ChatState {
  final List<ChatMessage> messages;
  final bool isSessionActive;
  final bool isSessionLoading;
  final ConnectionStatus connectionStatus;

  const ChatState({
    this.messages = const [],
    this.isSessionActive = false,
    this.isSessionLoading = false,
    this.connectionStatus = ConnectionStatus.disconnected,
  });

  bool get isConnected => connectionStatus == ConnectionStatus.connected;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isSessionActive,
    bool? isSessionLoading,
    ConnectionStatus? connectionStatus,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isSessionActive: isSessionActive ?? this.isSessionActive,
      isSessionLoading: isSessionLoading ?? this.isSessionLoading,
      connectionStatus: connectionStatus ?? this.connectionStatus,
    );
  }
}

final chatProvider =
    NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

class ChatNotifier extends Notifier<ChatState> {
  // Track accumulated final segments for current user turn
  String _accumulatedFinals = '';

  @override
  ChatState build() => const ChatState();

  // --- Helpers operating on mutable message list ---

  ChatMessage? _findStreamingMessage(
    List<ChatMessage> msgs, {
    required bool isUser,
  }) {
    for (final msg in msgs.reversed) {
      if (msg.isUser == isUser && msg.isStreaming) return msg;
    }
    return null;
  }

  void _completeAllStreaming(List<ChatMessage> msgs) {
    for (final msg in msgs) {
      if (msg.isStreaming) msg.status = MessageStatus.complete;
    }
  }

  void _addOrUpdateMessage(
    List<ChatMessage> msgs,
    String text, {
    required bool isUser,
    bool streaming = false,
    String? model,
    String? intent,
    String? responseType,
  }) {
    final existing = _findStreamingMessage(msgs, isUser: isUser);
    if (existing != null && streaming) {
      existing.text = text;
    } else {
      _completeAllStreaming(msgs);
      msgs.add(
        ChatMessage(
          id: _uuid.v4(),
          text: text,
          isUser: isUser,
          timestamp: DateTime.now(),
          status: streaming ? MessageStatus.streaming : MessageStatus.complete,
          model: model,
          intent: intent,
          responseType: responseType,
        ),
      );
    }
  }

  // --- Event handlers called by the page via ref.listen ---

  void onConnectionStatus(ConnectionStatus status) {
    state = state.copyWith(connectionStatus: status);
  }

  void onTranscription(TranscriptionEvent event) {
    final isAgent = event.participantId.contains('agent');
    if (isAgent) return; // agent transcription handled via immediate text

    final msgs = List<ChatMessage>.from(state.messages);
    final existingUser = _findStreamingMessage(msgs, isUser: true);

    if (existingUser == null) {
      _completeAllStreaming(msgs);
      _accumulatedFinals = '';
    }

    if (event.isFinal) {
      if (_accumulatedFinals.isEmpty) {
        _accumulatedFinals = event.text;
      } else {
        _accumulatedFinals = '$_accumulatedFinals ${event.text}';
      }

      final userMsg = _findStreamingMessage(msgs, isUser: true);
      if (userMsg != null) {
        userMsg.text = _accumulatedFinals;
        userMsg.status = MessageStatus.complete;
      } else {
        _addOrUpdateMessage(msgs, _accumulatedFinals,
            isUser: true, streaming: false);
      }

      _addOrUpdateMessage(msgs, '', isUser: false, streaming: true);
      _accumulatedFinals = '';
    } else {
      final displayText = _accumulatedFinals.isEmpty
          ? event.text
          : '$_accumulatedFinals ${event.text}';
      _addOrUpdateMessage(msgs, displayText, isUser: true, streaming: true);
    }

    state = state.copyWith(messages: msgs);
  }

  void onImmediateText(ImmediateTextEvent event) {
    if (!event.participantId.contains('agent')) return;

    final msgs = List<ChatMessage>.from(state.messages);

    final userMsg = _findStreamingMessage(msgs, isUser: true);
    if (userMsg != null) {
      userMsg.status = MessageStatus.complete;
    }

    final assistantMsg = _findStreamingMessage(msgs, isUser: false);
    if (assistantMsg != null) {
      assistantMsg.text = '${assistantMsg.text}${event.text}';
      assistantMsg.model ??= event.model;
      assistantMsg.intent ??= event.intent;
      assistantMsg.responseType ??= event.responseType;
    } else {
      _addOrUpdateMessage(
        msgs,
        event.text,
        isUser: false,
        streaming: true,
        model: event.model,
        intent: event.intent,
        responseType: event.responseType,
      );
    }

    state = state.copyWith(messages: msgs);
  }

  void onSessionNotification(SessionNotificationEvent event) {
    _log.info(
      'Session notification: ${event.type} remaining=${event.remainingSeconds} idle=${event.idleDuration}',
    );

    if (event.type == SessionNotificationType.sessionReady) {
      _log.info('Session ready, activating');
      state = state.copyWith(isSessionLoading: false, isSessionActive: true);
    } else if (event.type == SessionNotificationType.sessionTimeout) {
      _log.info('Session timeout');
      ref.read(liveKitServiceProvider).stopVoiceSession();
      state = state.copyWith(isSessionActive: false, isSessionLoading: false);
    }
  }

  Future<void> toggleSession() async {
    final liveKit = ref.read(liveKitServiceProvider);

    if (state.isSessionActive || state.isSessionLoading) {
      await liveKit.stopVoiceSession();
      state = state.copyWith(isSessionActive: false, isSessionLoading: false);
    } else {
      state = state.copyWith(isSessionLoading: true);
      try {
        await liveKit.startVoiceSession();
      } catch (e, st) {
        _log.severe('Failed to start voice session', e, st);
        state = state.copyWith(isSessionLoading: false);
      }
    }
  }

  void submitTextMessage(String text) {
    if (text.isEmpty) return;

    final msgs = List<ChatMessage>.from(state.messages);
    _completeAllStreaming(msgs);
    _addOrUpdateMessage(msgs, text, isUser: true, streaming: false);
    _addOrUpdateMessage(msgs, '', isUser: false, streaming: true);
    state = state.copyWith(messages: msgs);

    ref.read(liveKitServiceProvider).sendTextMessage(text);
    _log.info('Text message submitted: $text');
  }

  void clearChat() {
    _accumulatedFinals = '';
    state = state.copyWith(messages: []);
  }

  bool get hasMessages => state.messages.isNotEmpty;
}
