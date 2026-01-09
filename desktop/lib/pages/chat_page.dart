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
  bool _isMicEnabled = false;

  // Live user message state
  String _liveUserText = '';
  DateTime? _liveUserTimestamp;
  bool _isUserTurnActive = false;

  // Agent response state
  String? _pendingAssistantMessage;

  StreamSubscription<ConnectionStatus>? _connectionSub;
  StreamSubscription<TranscriptionEvent>? _transcriptionSub;

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

    _connectionStatus = widget.liveKitService.isConnected
        ? ConnectionStatus.connected
        : ConnectionStatus.disconnected;
  }

  void _onTranscription(TranscriptionEvent event) {
    if (!mounted) return;

    final isAgentResponse = event.participantId.contains('agent');

    if (isAgentResponse) {
      // Agent is responding - first finalize user message if pending
      if (_isUserTurnActive && _liveUserText.isNotEmpty) {
        _finalizeUserMessage();
      }

      // Update agent response
      setState(() {
        _pendingAssistantMessage = event.text;
      });

      if (event.isFinal && event.text.isNotEmpty) {
        _addMessage(event.text, isUser: false);
        setState(() {
          _pendingAssistantMessage = null;
        });
      }
    } else {
      // User speech - update live text
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

          // User turn is complete - finalize and show agent thinking
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

  Future<void> _toggleMic() async {
    if (_isMicEnabled) {
      await widget.liveKitService.disableMicrophone();
      setState(() => _isMicEnabled = false);
    } else {
      try {
        await widget.liveKitService.enableMicrophone();
        setState(() => _isMicEnabled = true);
      } catch (e, st) {
        _log.severe('Failed to enable microphone', e, st);
      }
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _transcriptionSub?.cancel();
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

        // Bottom bar with mic button
        Container(
          padding: const EdgeInsets.all(AppTokens.spacingMd),
          color: AppTokens.backgroundSecondary,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RecordButton(
                isRecording: _isMicEnabled,
                isLoading: false,
                onPressed: _connectionStatus == ConnectionStatus.connected
                    ? _toggleMic
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
