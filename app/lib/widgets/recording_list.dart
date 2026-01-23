import 'package:flutter/material.dart';

import '../models/recording.dart';
import '../theme/tokens.dart';
import 'recording_tile.dart';

class RecordingList extends StatelessWidget {
  final List<Recording> recordings;
  final String? playingRecordingId;
  final double playbackProgress;
  final void Function(Recording recording)? onPlayPause;
  final void Function(Recording recording)? onDelete;
  final void Function(Recording recording)? onExtractWaveform;

  const RecordingList({
    super.key,
    required this.recordings,
    this.playingRecordingId,
    this.playbackProgress = 0.0,
    this.onPlayPause,
    this.onDelete,
    this.onExtractWaveform,
  });

  @override
  Widget build(BuildContext context) {
    if (recordings.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spacingMd,
        vertical: AppTokens.spacingSm,
      ),
      itemCount: recordings.length,
      itemBuilder: (context, index) {
        final recording = recordings[index];
        final isPlaying = recording.id == playingRecordingId;

        return RecordingTile(
          key: ValueKey(recording.id),
          recording: recording,
          isPlaying: isPlaying,
          playbackProgress: isPlaying ? playbackProgress : 0.0,
          onPlayPause: () => onPlayPause?.call(recording),
          onDelete: () => onDelete?.call(recording),
          onExtractWaveform: () => onExtractWaveform?.call(recording),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic_none_rounded,
            size: 64,
            color: AppTokens.textTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppTokens.spacingMd),
          const Text(
            'No recordings yet',
            style: TextStyle(
              color: AppTokens.textSecondary,
              fontSize: AppTokens.fontSizeLg,
              fontWeight: AppTokens.fontWeightMedium,
            ),
          ),
          const SizedBox(height: AppTokens.spacingSm),
          const Text(
            'Tap the record button to start',
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
