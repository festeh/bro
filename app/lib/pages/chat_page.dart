import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/livekit_service.dart';
import '../theme/tokens.dart';

final _log = Logger('ChatPage');

class ChatPage extends StatefulWidget {
  final LiveKitService liveKitService;

  const ChatPage({
    super.key,
    required this.liveKitService,
  });

  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  final _uuid = const Uuid();
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();

  final List<ChatMessage> _messages = [];
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  bool _isSessionActive = false;
  bool _isSessionLoading = false;

  // Track accumulated final segments for current user turn
  String _accumulatedFinals = '';

  StreamSubscription<ConnectionStatus>? _connectionSub;
  StreamSubscription<TranscriptionEvent>? _transcriptionSub;
  StreamSubscription<ImmediateTextEvent>? _immediateTextSub;
  StreamSubscription<SessionNotificationEvent>? _sessionNotificationSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    _connectionSub = widget.liveKitService.connectionStatus.listen((status) {
      if (!mounted) return;
      setState(() => _connectionStatus = status);
    });

    _transcriptionSub =
        widget.liveKitService.transcriptionStream.listen(_onTranscription);

    _immediateTextSub =
        widget.liveKitService.immediateTextStream.listen(_onImmediateText);

    _sessionNotificationSub =
        widget.liveKitService.sessionNotificationStream.listen(_onSessionNotification);

    _connectionStatus = widget.liveKitService.isConnected
        ? ConnectionStatus.connected
        : ConnectionStatus.disconnected;
  }

  // Find the current streaming message for a given role, or null
  ChatMessage? _findStreamingMessage({required bool isUser}) {
    for (final msg in _messages.reversed) {
      if (msg.isUser == isUser && msg.isStreaming) {
        return msg;
      }
    }
    return null;
  }

  // Complete all streaming messages
  void _completeAllStreaming() {
    for (final msg in _messages) {
      if (msg.isStreaming) {
        msg.status = MessageStatus.complete;
      }
    }
  }

  // Add a new message or update existing streaming message
  void _addOrUpdateMessage(
    String text, {
    required bool isUser,
    bool streaming = false,
    String? model,
    String? intent,
    String? responseType,
  }) {
    final existing = _findStreamingMessage(isUser: isUser);

    if (existing != null && streaming) {
      // Update existing streaming message
      existing.text = text;
    } else {
      // Complete any existing streaming messages first
      _completeAllStreaming();

      // Add new message
      _messages.add(ChatMessage(
        id: _uuid.v4(),
        text: text,
        isUser: isUser,
        timestamp: DateTime.now(),
        status: streaming ? MessageStatus.streaming : MessageStatus.complete,
        model: model,
        intent: intent,
        responseType: responseType,
      ));
    }
  }

  void _onTranscription(TranscriptionEvent event) {
    if (!mounted) return;

    final isAgent = event.participantId.contains('agent');

    // Agent transcription handled via immediate text stream
    if (isAgent) return;

    // User speech
    setState(() {
      final existingUser = _findStreamingMessage(isUser: true);

      if (existingUser == null) {
        // First speech in this turn - complete any streaming assistant message
        _completeAllStreaming();
        _accumulatedFinals = '';
      }

      if (event.isFinal) {
        // Accumulate final segment
        if (_accumulatedFinals.isEmpty) {
          _accumulatedFinals = event.text;
        } else {
          _accumulatedFinals = '$_accumulatedFinals ${event.text}';
        }

        // Update or add user message as complete
        final userMsg = _findStreamingMessage(isUser: true);
        if (userMsg != null) {
          userMsg.text = _accumulatedFinals;
          userMsg.status = MessageStatus.complete;
        } else {
          _addOrUpdateMessage(_accumulatedFinals, isUser: true, streaming: false);
        }

        // Start assistant streaming placeholder
        _addOrUpdateMessage('', isUser: false, streaming: true);
        _accumulatedFinals = '';
      } else {
        // Interim - show accumulated + current
        final displayText = _accumulatedFinals.isEmpty
            ? event.text
            : '$_accumulatedFinals ${event.text}';
        _addOrUpdateMessage(displayText, isUser: true, streaming: true);
      }
    });

    _scrollToBottom();
  }

  void _onSessionNotification(SessionNotificationEvent event) {
    if (!mounted) return;

    _log.info('Session notification: ${event.type} remaining=${event.remainingSeconds} idle=${event.idleDuration}');

    if (event.type == SessionNotificationType.sessionReady) {
      _log.info('Session ready, activating');
      setState(() {
        _isSessionLoading = false;
        _isSessionActive = true;
      });
    } else if (event.type == SessionNotificationType.sessionTimeout) {
      _log.info('Session timeout');
      widget.liveKitService.stopVoiceSession();
      setState(() {
        _isSessionActive = false;
        _isSessionLoading = false;
      });
    }
  }

  void _onImmediateText(ImmediateTextEvent event) {
    if (!mounted) return;

    // Only handle agent responses
    if (!event.participantId.contains('agent')) return;

    setState(() {
      // Complete any streaming user message first
      final userMsg = _findStreamingMessage(isUser: true);
      if (userMsg != null) {
        userMsg.status = MessageStatus.complete;
      }

      // Find or create assistant streaming message
      final assistantMsg = _findStreamingMessage(isUser: false);
      if (assistantMsg != null) {
        assistantMsg.text = '${assistantMsg.text}${event.text}';
        // Update metadata if not set yet
        assistantMsg.model ??= event.model;
        assistantMsg.intent ??= event.intent;
        assistantMsg.responseType ??= event.responseType;
      } else {
        _addOrUpdateMessage(
          event.text,
          isUser: false,
          streaming: true,
          model: event.model,
          intent: event.intent,
          responseType: event.responseType,
        );
      }
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppTokens.animMedium,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleSession() async {
    if (_isSessionActive || _isSessionLoading) {
      await widget.liveKitService.stopVoiceSession();
      setState(() {
        _isSessionActive = false;
        _isSessionLoading = false;
      });
    } else {
      setState(() => _isSessionLoading = true);
      try {
        await widget.liveKitService.startVoiceSession();
      } catch (e, st) {
        _log.severe('Failed to start voice session', e, st);
        setState(() => _isSessionLoading = false);
      }
    }
  }

  bool get hasMessages => _messages.isNotEmpty;

  void clearChat() {
    setState(() {
      _messages.clear();
      _accumulatedFinals = '';
    });
  }

  void _submitTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      // Complete all streaming messages before adding new user message
      _completeAllStreaming();

      // Add user message
      _addOrUpdateMessage(text, isUser: true, streaming: false);

      // Add assistant streaming placeholder
      _addOrUpdateMessage('', isUser: false, streaming: true);
    });

    _textController.clear();
    _textFocusNode.requestFocus();

    // Send to agent
    widget.liveKitService.sendTextMessage(text);
    _log.info('Text message submitted: $text');
    _scrollToBottom();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed) {
      _submitTextMessage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _transcriptionSub?.cancel();
    _immediateTextSub?.cancel();
    _sessionNotificationSub?.cancel();
    _scrollController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _EmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppTokens.spacingMd),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return _MessageBubble(
                      key: ValueKey(message.id),
                      message: message,
                    );
                  },
                ),
        ),
        _BottomBar(
          textController: _textController,
          textFocusNode: _textFocusNode,
          isSessionActive: _isSessionActive,
          isSessionLoading: _isSessionLoading,
          isConnected: _connectionStatus == ConnectionStatus.connected,
          onToggleSession: _toggleSession,
          onSubmit: _submitTextMessage,
          onKeyEvent: _handleKeyEvent,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppTokens.textTertiary,
          ),
          const SizedBox(height: AppTokens.spacingMd),
          Text(
            'Start a conversation',
            style: TextStyle(
              color: AppTokens.textSecondary,
              fontSize: AppTokens.fontSizeLg,
            ),
          ),
          const SizedBox(height: AppTokens.spacingSm),
          Text(
            'Type a message or use the mic',
            style: TextStyle(
              color: AppTokens.textTertiary,
              fontSize: AppTokens.fontSizeMd,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({super.key, required this.message});

  IconData _getIntentIcon(String? intent) {
    switch (intent) {
      case 'task_management':
        return Icons.task_alt;
      case 'web_search':
        return Icons.search;
      case 'end_dialog':
        return Icons.waving_hand;
      case 'direct_response':
      default:
        return Icons.smart_toy_outlined;
    }
  }

  String _formatModel(String? model) {
    if (model == null) return '';
    // Extract last part after / for cleaner display
    final parts = model.split('/');
    return parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isStreaming = message.isStreaming;
    final displayText = isStreaming && message.text.isEmpty
        ? '...'
        : isStreaming && isUser
            ? '${message.text}...'
            : message.text;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spacingMd,
        vertical: AppTokens.spacingSm,
      ),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.65,
      ),
      decoration: BoxDecoration(
        color: isUser
            ? isStreaming
                ? AppTokens.accentPrimary.withValues(alpha: 0.7)
                : AppTokens.accentPrimary
            : isStreaming
                ? AppTokens.backgroundTertiary.withValues(alpha: 0.7)
                : AppTokens.backgroundTertiary,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayText,
            style: TextStyle(
              color: AppTokens.textPrimary,
              fontSize: AppTokens.fontSizeMd,
            ),
          ),
          // Model badge for assistant messages
          if (!isUser && message.model != null) ...[
            const SizedBox(height: AppTokens.spacingXs),
            Text(
              _formatModel(message.model),
              style: TextStyle(
                color: AppTokens.textTertiary,
                fontSize: AppTokens.fontSizeXs,
              ),
            ),
          ],
        ],
      ),
    );

    // User messages: just the bubble, right-aligned
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spacingSm),
          child: bubble,
        ),
      );
    }

    // Assistant messages: icon + bubble, left-aligned
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: AppTokens.spacingSm),
            decoration: BoxDecoration(
              color: AppTokens.backgroundTertiary,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Icon(
              _getIntentIcon(message.intent),
              size: 16,
              color: AppTokens.textSecondary,
            ),
          ),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final TextEditingController textController;
  final FocusNode textFocusNode;
  final bool isSessionActive;
  final bool isSessionLoading;
  final bool isConnected;
  final VoidCallback onToggleSession;
  final VoidCallback onSubmit;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  const _BottomBar({
    required this.textController,
    required this.textFocusNode,
    required this.isSessionActive,
    required this.isSessionLoading,
    required this.isConnected,
    required this.onToggleSession,
    required this.onSubmit,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.spacingMd),
      color: AppTokens.backgroundSecondary,
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              isSessionActive ? Icons.stop : Icons.mic,
              size: 24,
            ),
            style: IconButton.styleFrom(
              backgroundColor: isSessionActive
                  ? AppTokens.accentRecording
                  : AppTokens.accentPrimary,
              foregroundColor: AppTokens.textPrimary,
              fixedSize: const Size(40, 40),
            ),
            onPressed: isConnected ? onToggleSession : null,
            tooltip: isSessionActive ? 'Stop' : 'Voice input',
          ),
          const SizedBox(width: AppTokens.spacingSm),
          Expanded(
            child: Focus(
              focusNode: textFocusNode,
              onKeyEvent: onKeyEvent,
              child: TextField(
                controller: textController,
                style: TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: AppTokens.fontSizeMd,
                ),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(
                    color: AppTokens.textTertiary,
                    fontSize: AppTokens.fontSizeMd,
                  ),
                  filled: true,
                  fillColor: AppTokens.backgroundTertiary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spacingMd,
                    vertical: AppTokens.spacingSm,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.newline,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spacingSm),
          IconButton(
            icon: const Icon(Icons.send, size: 24),
            style: IconButton.styleFrom(
              backgroundColor: AppTokens.accentPrimary,
              foregroundColor: AppTokens.textPrimary,
              fixedSize: const Size(40, 40),
            ),
            onPressed: onSubmit,
            tooltip: 'Send (Ctrl+Enter)',
          ),
        ],
      ),
    );
  }
}
