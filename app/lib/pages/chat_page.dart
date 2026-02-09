import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/livekit_providers.dart';
import '../theme/tokens.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends ConsumerState<ChatPage> {
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
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

  void _submitTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    ref.read(chatProvider.notifier).submitTextMessage(text);
    _textController.clear();
    _textFocusNode.requestFocus();
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

  bool get hasMessages => ref.read(chatProvider.notifier).hasMessages;

  void clearChat() => ref.read(chatProvider.notifier).clearChat();

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);

    // Listen to streams and forward events to the chat notifier
    ref.listen(connectionStatusProvider, (_, next) {
      next.whenData((status) {
        ref.read(chatProvider.notifier).onConnectionStatus(status);
      });
    });

    ref.listen(transcriptionProvider, (_, next) {
      next.whenData((event) {
        ref.read(chatProvider.notifier).onTranscription(event);
        _scrollToBottom();
      });
    });

    ref.listen(immediateTextProvider, (_, next) {
      next.whenData((event) {
        ref.read(chatProvider.notifier).onImmediateText(event);
        _scrollToBottom();
      });
    });

    ref.listen(sessionNotificationProvider, (_, next) {
      next.whenData((event) {
        ref.read(chatProvider.notifier).onSessionNotification(event);
      });
    });

    return Column(
      children: [
        Expanded(
          child: chat.messages.isEmpty
              ? _EmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppTokens.spacingMd),
                  itemCount: chat.messages.length,
                  itemBuilder: (context, index) {
                    final message = chat.messages[index];
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
          isSessionActive: chat.isSessionActive,
          isSessionLoading: chat.isSessionLoading,
          isConnected: chat.isConnected,
          onToggleSession: () =>
              ref.read(chatProvider.notifier).toggleSession(),
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

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spacingSm),
          child: bubble,
        ),
      );
    }

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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppTokens.spacingMd,
        AppTokens.spacingMd,
        AppTokens.spacingMd,
        AppTokens.spacingMd + bottomPadding,
      ),
      color: AppTokens.backgroundSecondary,
      child: Row(
        children: [
          IconButton(
            icon: Icon(isSessionActive ? Icons.stop : Icons.mic, size: 24),
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
