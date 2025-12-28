import 'package:flutter/material.dart';
import '../../../app/tokens.dart';
import '../../../core/models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: EdgeInsets.only(
          left: isUser ? Tokens.spacingXl : Tokens.spacingMd,
          right: isUser ? Tokens.spacingMd : Tokens.spacingXl,
          top: Tokens.spacingXs,
          bottom: Tokens.spacingXs,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.spacingMd,
          vertical: Tokens.spacingSm,
        ),
        decoration: BoxDecoration(
          color: isUser ? Tokens.primary : Tokens.surfaceVariant,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(Tokens.radiusMd),
            topRight: const Radius.circular(Tokens.radiusMd),
            bottomLeft: Radius.circular(
              isUser ? Tokens.radiusMd : Tokens.radiusSm,
            ),
            bottomRight: Radius.circular(
              isUser ? Tokens.radiusSm : Tokens.radiusMd,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: isUser ? Colors.black : Tokens.textPrimary,
                fontSize: 15,
              ),
            ),
            if (isStreaming) ...[
              const SizedBox(height: Tokens.spacingXs),
              const StreamingIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class StreamingIndicator extends StatefulWidget {
  const StreamingIndicator({super.key});

  @override
  State<StreamingIndicator> createState() => _StreamingIndicatorState();
}

class _StreamingIndicatorState extends State<StreamingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = ((_controller.value + delay) % 1.0);
            final opacity = (value < 0.5 ? value : 1.0 - value) * 2;

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Opacity(
                opacity: opacity.clamp(0.3, 1.0),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Tokens.textSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class StreamingBubble extends StatelessWidget {
  final String content;

  const StreamingBubble({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.only(
          left: Tokens.spacingMd,
          right: Tokens.spacingXl,
          top: Tokens.spacingXs,
          bottom: Tokens.spacingXs,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.spacingMd,
          vertical: Tokens.spacingSm,
        ),
        decoration: const BoxDecoration(
          color: Tokens.surfaceVariant,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(Tokens.radiusMd),
            topRight: Radius.circular(Tokens.radiusMd),
            bottomLeft: Radius.circular(Tokens.radiusSm),
            bottomRight: Radius.circular(Tokens.radiusMd),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (content.isNotEmpty)
              Text(
                content,
                style: const TextStyle(color: Tokens.textPrimary, fontSize: 15),
              ),
            const SizedBox(height: Tokens.spacingXs),
            const StreamingIndicator(),
          ],
        ),
      ),
    );
  }
}
