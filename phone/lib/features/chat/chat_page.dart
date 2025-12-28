import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/tokens.dart';
import '../../core/models/chat_message.dart';
import 'chat_service.dart';
import 'widgets/message_bubble.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _chatService = ChatService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];

  StreamSubscription<ChatMessage>? _messagesSubscription;
  StreamSubscription<String>? _chunksSubscription;
  StreamSubscription<ConnectionState>? _connectionSubscription;

  ConnectionState _connectionState = ConnectionState.disconnected;
  String _streamingContent = '';
  bool _isStreaming = false;

  // Server configuration
  static const _serverUrl = 'ws://10.0.2.2:8000';
  static const _threadId = 'default';

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _connect();
  }

  void _setupListeners() {
    _messagesSubscription = _chatService.messages.listen((message) {
      if (!mounted) return;
      setState(() {
        _messages.add(message);
        _isStreaming = false;
        _streamingContent = '';
      });
      _scrollToBottom();
    });

    _chunksSubscription = _chatService.chunks.listen((chunk) {
      if (!mounted) return;
      setState(() {
        _isStreaming = true;
        _streamingContent += chunk;
      });
      _scrollToBottom();
    });

    _connectionSubscription = _chatService.connectionState.listen((state) {
      if (!mounted) return;
      setState(() {
        _connectionState = state;
      });
    });
  }

  Future<void> _connect() async {
    try {
      await _chatService.connect(serverUrl: _serverUrl, threadId: _threadId);
    } catch (e) {
      debugPrint('Failed to connect: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Tokens.durationFast,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();

    try {
      await _chatService.sendMessage(text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: Tokens.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _chunksSubscription?.cancel();
    _connectionSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _chatService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.background,
      appBar: AppBar(
        backgroundColor: Tokens.surface,
        title: const Text('Chat'),
        actions: [
          _buildConnectionIndicator(),
          const SizedBox(width: Tokens.spacingMd),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && !_isStreaming
                ? _buildEmptyState()
                : _buildMessageList(),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator() {
    Color color;
    IconData icon;
    String tooltip;

    switch (_connectionState) {
      case ConnectionState.connected:
        color = Tokens.success;
        icon = Icons.cloud_done;
        tooltip = 'Connected';
        break;
      case ConnectionState.connecting:
      case ConnectionState.reconnecting:
        color = Tokens.warning;
        icon = Icons.cloud_sync;
        tooltip = 'Connecting...';
        break;
      case ConnectionState.disconnected:
        color = Tokens.error;
        icon = Icons.cloud_off;
        tooltip = 'Disconnected';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Icon(icon, color: color, size: Tokens.iconSizeMd),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Tokens.textTertiary),
          const SizedBox(height: Tokens.spacingMd),
          Text(
            'Start a conversation',
            style: TextStyle(color: Tokens.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: Tokens.spacingMd),
      itemCount: _messages.length + (_isStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isStreaming && index == _messages.length) {
          return StreamingBubble(content: _streamingContent);
        }
        return MessageBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildInputBar() {
    final canSend = _connectionState == ConnectionState.connected;

    return Container(
      padding: EdgeInsets.only(
        left: Tokens.spacingMd,
        right: Tokens.spacingMd,
        top: Tokens.spacingSm,
        bottom: MediaQuery.of(context).padding.bottom + Tokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: Tokens.surface,
        border: Border(top: BorderSide(color: Tokens.surfaceVariant, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: canSend,
              style: const TextStyle(color: Tokens.textPrimary),
              decoration: InputDecoration(
                hintText: canSend ? 'Type a message...' : 'Connecting...',
                hintStyle: TextStyle(color: Tokens.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusLg),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Tokens.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Tokens.spacingMd,
                  vertical: Tokens.spacingSm,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: Tokens.spacingSm),
          IconButton(
            onPressed: canSend && !_isStreaming ? _sendMessage : null,
            icon: Icon(
              Icons.send,
              color: canSend && !_isStreaming
                  ? Tokens.primary
                  : Tokens.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
