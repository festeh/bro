import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'waveform_widget.dart';

class RecordingIndicator extends StatelessWidget {
  final String duration;

  const RecordingIndicator({super.key, required this.duration});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spacingMd,
        vertical: AppTokens.spacingSm,
      ),
      color: AppTokens.backgroundSecondary,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTokens.accentRecording,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppTokens.spacingSm),
          Text(
            'Recording $duration',
            style: const TextStyle(
              color: AppTokens.textPrimary,
              fontSize: AppTokens.fontSizeMd,
              fontWeight: AppTokens.fontWeightMedium,
            ),
          ),
          const SizedBox(width: AppTokens.spacingMd),
          const SizedBox(
            width: 100,
            child: AnimatedRecordingWaveform(isRecording: true),
          ),
        ],
      ),
    );
  }
}
