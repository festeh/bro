enum MessageStatus { streaming, complete }

class ChatMessage {
  final String id;
  String text;
  final bool isUser;
  final DateTime timestamp;
  MessageStatus status;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.status = MessageStatus.complete,
  });

  bool get isStreaming => status == MessageStatus.streaming;
  bool get isComplete => status == MessageStatus.complete;
}
