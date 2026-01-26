enum MessageStatus { streaming, complete }

class ChatMessage {
  final String id;
  String text;
  final bool isUser;
  final DateTime timestamp;
  MessageStatus status;
  String? model;
  String? intent;
  String? responseType;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.status = MessageStatus.complete,
    this.model,
    this.intent,
    this.responseType,
  });

  bool get isStreaming => status == MessageStatus.streaming;
  bool get isComplete => status == MessageStatus.complete;
}
