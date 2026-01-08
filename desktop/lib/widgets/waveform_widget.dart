import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class WaveformWidget extends StatelessWidget {
  final List<double>? waveformData;
  final double progress;
  final bool isPlaying;
  final int barCount;

  const WaveformWidget({
    super.key,
    this.waveformData,
    this.progress = 0.0,
    this.isPlaying = false,
    this.barCount = 40,
  });

  @override
  Widget build(BuildContext context) {
    final data = waveformData ?? _generatePlaceholder();
    final normalizedData = _normalizeToBarCount(data, barCount);

    return SizedBox(
      height: AppTokens.waveformHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (index) {
          final isActive = index / barCount <= progress;
          final amplitude = normalizedData[index];

          return _WaveformBar(
            amplitude: amplitude,
            isActive: isActive,
            isPlaying: isPlaying,
          );
        }),
      ),
    );
  }

  List<double> _generatePlaceholder() {
    final random = math.Random(42);
    return List.generate(barCount, (_) => 0.2 + random.nextDouble() * 0.6);
  }

  List<double> _normalizeToBarCount(List<double> data, int count) {
    if (data.isEmpty) return List.filled(count, 0.3);

    final result = <double>[];
    final step = data.length / count;

    for (var i = 0; i < count; i++) {
      final start = (i * step).floor();
      final end = ((i + 1) * step).floor().clamp(0, data.length);

      if (start >= data.length) {
        result.add(0.3);
        continue;
      }

      var sum = 0.0;
      var count = 0;
      for (var j = start; j < end && j < data.length; j++) {
        sum += data[j];
        count++;
      }
      result.add(count > 0 ? sum / count : 0.3);
    }

    return result;
  }
}

class _WaveformBar extends StatelessWidget {
  final double amplitude;
  final bool isActive;
  final bool isPlaying;

  const _WaveformBar({
    required this.amplitude,
    required this.isActive,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final minHeight = AppTokens.waveformHeight * 0.15;
    final maxHeight = AppTokens.waveformHeight * 0.9;
    final height =
        minHeight + (maxHeight - minHeight) * amplitude.clamp(0.0, 1.0);

    return AnimatedContainer(
      duration: AppTokens.animFast,
      width: AppTokens.waveformBarWidth,
      height: height,
      margin: EdgeInsets.symmetric(horizontal: AppTokens.waveformBarGap / 2),
      decoration: BoxDecoration(
        color: isActive ? AppTokens.waveformActive : AppTokens.waveformInactive,
        borderRadius: BorderRadius.circular(AppTokens.waveformBarWidth / 2),
      ),
    );
  }
}

class AnimatedRecordingWaveform extends StatefulWidget {
  final bool isRecording;

  const AnimatedRecordingWaveform({super.key, required this.isRecording});

  @override
  State<AnimatedRecordingWaveform> createState() =>
      _AnimatedRecordingWaveformState();
}

class _AnimatedRecordingWaveformState extends State<AnimatedRecordingWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    if (widget.isRecording) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedRecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isRecording && _controller.isAnimating) {
      _controller.stop();
    }
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
        return SizedBox(
          height: AppTokens.waveformHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(20, (index) {
              final amplitude = widget.isRecording
                  ? 0.3 + _random.nextDouble() * 0.7
                  : 0.2;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: AppTokens.waveformBarWidth,
                height:
                    AppTokens.waveformHeight * 0.15 +
                    AppTokens.waveformHeight * 0.75 * amplitude,
                margin: EdgeInsets.symmetric(
                  horizontal: AppTokens.waveformBarGap / 2,
                ),
                decoration: BoxDecoration(
                  color: widget.isRecording
                      ? AppTokens.accentRecording
                      : AppTokens.waveformInactive,
                  borderRadius: BorderRadius.circular(
                    AppTokens.waveformBarWidth / 2,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
