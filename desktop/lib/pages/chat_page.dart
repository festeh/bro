import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/livekit_service.dart';
import '../theme/tokens.dart';
import '../widgets/record_button.dart';

final _log = Logger('ChatPage');

class ChatPage extends StatefulWidget {
  final LiveKitService liveKitService;

  const ChatPage({
    super.key,
    required this.liveKitService,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _uuid = const Uuid();
  final _scrollController = ScrollController();

  List<ChatMessage> _messages = [];
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  bool _isSessionActive = false;
  bool _isSessionLoading = false;
  bool _isSessionWarning = false;

  // Live user message state
  String _liveUserText = '';
  DateTime? _liveUserTimestamp;
  bool _isUserTurnActive = false;

  // Agent response state
  String? _pendingAssistantMessage;

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

  void _onTranscription(TranscriptionEvent event) {
    if (!mounted) return;

    final isAgentResponse = event.participantId.contains('agent');

    // Agent transcription is handled via immediate text stream (lk.llm_stream)
    // This stream (lk.transcription) is synced with TTS - could use for word highlighting
    if (isAgentResponse) {
      return;
    }

    // User speech - finalize any pending agent message first
    if (_pendingAssistantMessage != null &&
        _pendingAssistantMessage!.isNotEmpty) {
      _addMessage(_pendingAssistantMessage!, isUser: false);
      setState(() {
        _pendingAssistantMessage = null;
      });
    }

    // Update live text
    setState(() {
      if (!_isUserTurnActive) {
        // First speech in this turn
        _isUserTurnActive = true;
        _liveUserTimestamp = DateTime.now();
        _accumulatedFinals = '';
      }

      if (event.isFinal) {
        // Final segment - append to accumulated finals
        if (_accumulatedFinals.isEmpty) {
          _accumulatedFinals = event.text;
        } else {
          _accumulatedFinals = '$_accumulatedFinals ${event.text}';
        }
        _liveUserText = _accumulatedFinals;

        // User turn is complete - reset warning and finalize
        _isSessionWarning = false;
        _finalizeUserMessage();
        _pendingAssistantMessage = ''; // Empty = show "..." thinking indicator
      } else {
        // Interim - show accumulated finals + current interim
        if (_accumulatedFinals.isEmpty) {
          _liveUserText = event.text;
        } else {
          _liveUserText = '$_accumulatedFinals ${event.text}';
        }
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
    } else if (event.type == SessionNotificationType.sessionWarning) {
      setState(() => _isSessionWarning = true);
    } else if (event.type == SessionNotificationType.sessionTimeout) {
      _log.info('Session timeout');
      widget.liveKitService.stopVoiceSession();
      setState(() {
        _isSessionActive = false;
        _isSessionLoading = false;
        _isSessionWarning = false;
      });
    }
  }

  void _onImmediateText(ImmediateTextEvent event) {
    if (!mounted) return;

    // Only handle agent responses
    if (!event.participantId.contains('agent')) {
      return;
    }

    // Agent is responding - first finalize user message if pending
    if (_isUserTurnActive && _liveUserText.isNotEmpty) {
      _finalizeUserMessage();
    }

    // Accumulate immediate text chunks
    setState(() {
      if (_pendingAssistantMessage == null || _pendingAssistantMessage!.isEmpty) {
        _pendingAssistantMessage = event.text;
      } else {
        _pendingAssistantMessage = '$_pendingAssistantMessage${event.text}';
      }
    });

    _scrollToBottom();
  }

  String _accumulatedFinals = '';

  void _finalizeUserMessage() {
    if (_liveUserText.isEmpty) return;

    _addMessage(_liveUserText, isUser: true, timestamp: _liveUserTimestamp);
    setState(() {
      _liveUserText = '';
      _accumulatedFinals = '';
      _liveUserTimestamp = null;
      _isUserTurnActive = false;
    });
  }

  void _addMessage(String text, {required bool isUser, DateTime? timestamp}) {
    final message = ChatMessage(
      id: _uuid.v4(),
      text: text,
      isUser: isUser,
      timestamp: timestamp ?? DateTime.now(),
    );

    setState(() {
      _messages = [..._messages, message]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
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
      // Stop session
      await widget.liveKitService.stopVoiceSession();
      setState(() {
        _isSessionActive = false;
        _isSessionLoading = false;
        _isSessionWarning = false;
      });
    } else {
      // Start session - show loading, wait for session_ready notification
      setState(() => _isSessionLoading = true);
      try {
        await widget.liveKitService.startVoiceSession();
        // Don't set _isSessionActive yet - wait for session_ready notification
      } catch (e, st) {
        _log.severe('Failed to start voice session', e, st);
        setState(() => _isSessionLoading = false);
      }
    }
  }

  void _clearChat() {
    setState(() {
      _messages = [];
      _liveUserText = '';
      _liveUserTimestamp = null;
      _isUserTurnActive = false;
      _accumulatedFinals = '';
      _pendingAssistantMessage = null;
    });
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _transcriptionSub?.cancel();
    _immediateTextSub?.cancel();
    _sessionNotificationSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate item count: messages + live user bubble + pending assistant
    final hasLiveUserBubble = _isUserTurnActive && _liveUserText.isNotEmpty;
    final hasPendingAssistant = _pendingAssistantMessage != null;
    final itemCount = _messages.length +
        (hasLiveUserBubble ? 1 : 0) +
        (hasPendingAssistant ? 1 : 0);

    return Column(
      children: [
        // Messages list
        Expanded(
          child: itemCount == 0
              ? _EmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppTokens.spacingMd),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    // Regular messages
                    if (index < _messages.length) {
                      return _MessageBubble(message: _messages[index]);
                    }

                    // Live user bubble (after messages, before pending assistant)
                    final liveUserIndex = _messages.length;
                    if (hasLiveUserBubble && index == liveUserIndex) {
                      return _LiveUserBubble(text: _liveUserText);
                    }

                    // Pending assistant message (last)
                    return _PendingMessageBubble(
                      text: _pendingAssistantMessage!,
                    );
                  },
                ),
        ),

        // Bottom bar with mic button and clear
        Container(
          padding: const EdgeInsets.all(AppTokens.spacingMd),
          color: AppTokens.backgroundSecondary,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: AppTokens.textSecondary,
                onPressed: _messages.isNotEmpty ? _clearChat : null,
                tooltip: 'Clear chat',
              ),
              const SizedBox(width: AppTokens.spacingMd),
              RecordButton(
                isRecording: _isSessionActive,
                isLoading: _isSessionLoading,
                isWarning: _isSessionWarning,
                onPressed: _connectionStatus == ConnectionStatus.connected
                    ? _toggleSession
                    : null,
              ),
            ],
          ),
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
            'Press the mic button and speak',
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

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTokens.spacingSm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spacingMd,
          vertical: AppTokens.spacingSm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: message.isUser
              ? AppTokens.accentPrimary
              : AppTokens.backgroundTertiary,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: AppTokens.textPrimary,
            fontSize: AppTokens.fontSizeMd,
          ),
        ),
      ),
    );
  }
}

class _LiveUserBubble extends StatelessWidget {
  final String text;

  const _LiveUserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTokens.spacingSm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spacingMd,
          vertical: AppTokens.spacingSm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: AppTokens.accentPrimary.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Text(
          '$text...',
          style: TextStyle(
            color: AppTokens.textPrimary,
            fontSize: AppTokens.fontSizeMd,
          ),
        ),
      ),
    );
  }
}

class _PendingMessageBubble extends StatelessWidget {
  final String text;

  const _PendingMessageBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTokens.spacingSm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spacingMd,
          vertical: AppTokens.spacingSm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: AppTokens.backgroundTertiary.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Text(
          text.isEmpty ? '...' : text,
          style: TextStyle(
            color: AppTokens.textSecondary,
            fontSize: AppTokens.fontSizeMd,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
