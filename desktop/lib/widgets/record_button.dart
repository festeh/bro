import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class RecordButton extends StatefulWidget {
  final bool isRecording;
  final bool isLoading;
  final VoidCallback? onPressed;

  const RecordButton({
    super.key,
    required this.isRecording,
    this.isLoading = false,
    this.onPressed,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isRecording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isRecording ? _pulseAnimation.value : 1.0,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: AppTokens.animMedium,
          width: AppTokens.recordButtonSize,
          height: AppTokens.recordButtonSize,
          decoration: BoxDecoration(
            color: widget.isRecording
                ? AppTokens.accentRecording
                : AppTokens.accentPrimary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color:
                    (widget.isRecording
                            ? AppTokens.accentRecording
                            : AppTokens.accentPrimary)
                        .withOpacity(0.4),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: AppTokens.textPrimary,
                      strokeWidth: 2,
                    ),
                  )
                : AnimatedSwitcher(
                    duration: AppTokens.animFast,
                    child: widget.isRecording
                        ? Icon(
                            Icons.stop_rounded,
                            key: const ValueKey('stop'),
                            color: AppTokens.textPrimary,
                            size: AppTokens.recordButtonIconSize,
                          )
                        : Icon(
                            Icons.mic_rounded,
                            key: const ValueKey('mic'),
                            color: AppTokens.textPrimary,
                            size: AppTokens.recordButtonIconSize,
                          ),
                  ),
          ),
        ),
      ),
    );
  }
}
