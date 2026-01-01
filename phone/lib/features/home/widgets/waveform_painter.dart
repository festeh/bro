import 'package:flutter/material.dart';
import '../../../app/tokens.dart';

class WaveformPainter extends CustomPainter {
  final List<int> amplitudes;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  WaveformPainter({
    required this.amplitudes,
    required this.progress,
    this.playedColor = Tokens.primary,
    this.unplayedColor = Tokens.surfaceVariant,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final barCount = amplitudes.length;
    final barWidth = size.width / barCount;
    final centerY = size.height / 2;
    final maxAmplitude = amplitudes.reduce((a, b) => a > b ? a : b).toDouble();
    final progressIndex = (progress * barCount).floor();

    final playedPaint = Paint()
      ..color = playedColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (barWidth * 0.6).clamp(2.0, 4.0);

    final unplayedPaint = Paint()
      ..color = unplayedColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (barWidth * 0.6).clamp(2.0, 4.0);

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth + barWidth / 2;
      final normalizedAmplitude = maxAmplitude > 0
          ? (amplitudes[i] / maxAmplitude).clamp(0.1, 1.0)
          : 0.1;
      final barHeight = size.height * 0.8 * normalizedAmplitude;

      final paint = i < progressIndex ? playedPaint : unplayedPaint;

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.amplitudes != amplitudes;
  }
}

class AudioWaveform extends StatelessWidget {
  final List<int> amplitudes;
  final double progress;
  final ValueChanged<double>? onSeek;
  final bool isLoading;
  final double height;

  const AudioWaveform({
    super.key,
    required this.amplitudes,
    required this.progress,
    this.onSeek,
    this.isLoading = false,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: height,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Tokens.primary,
            ),
          ),
        ),
      );
    }

    if (amplitudes.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Container(height: 2, color: Tokens.surfaceVariant),
        ),
      );
    }

    return GestureDetector(
      onTapDown: (details) => _handleSeek(details.localPosition.dx, context),
      onHorizontalDragUpdate: (details) =>
          _handleSeek(details.localPosition.dx, context),
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: WaveformPainter(amplitudes: amplitudes, progress: progress),
      ),
    );
  }

  void _handleSeek(double x, BuildContext context) {
    if (onSeek == null) return;
    final box = context.findRenderObject() as RenderBox;
    final seekProgress = (x / box.size.width).clamp(0.0, 1.0);
    onSeek!(seekProgress);
  }
}
