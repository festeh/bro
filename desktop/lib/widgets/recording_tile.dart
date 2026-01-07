import 'package:flutter/material.dart';

import '../models/recording.dart';
import '../theme/tokens.dart';
import 'waveform_widget.dart';

class RecordingTile extends StatelessWidget {
  final Recording recording;
  final bool isPlaying;
  final double playbackProgress;
  final VoidCallback? onPlayPause;
  final VoidCallback? onDelete;

  const RecordingTile({
    super.key,
    required this.recording,
    this.isPlaying = false,
    this.playbackProgress = 0.0,
    this.onPlayPause,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spacingSm),
      decoration: BoxDecoration(
        color: AppTokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          onTap: onPlayPause,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spacingMd),
            child: Row(
              children: [
                _PlayButton(isPlaying: isPlaying),
                const SizedBox(width: AppTokens.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              recording.title,
                              style: const TextStyle(
                                color: AppTokens.textPrimary,
                                fontSize: AppTokens.fontSizeMd,
                                fontWeight: AppTokens.fontWeightMedium,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            recording.formattedDuration,
                            style: const TextStyle(
                              color: AppTokens.textSecondary,
                              fontSize: AppTokens.fontSizeSm,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spacingXs),
                      Text(
                        recording.formattedDate,
                        style: const TextStyle(
                          color: AppTokens.textTertiary,
                          fontSize: AppTokens.fontSizeXs,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingSm),
                      WaveformWidget(
                        waveformData: recording.waveformData,
                        progress: playbackProgress,
                        isPlaying: isPlaying,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.spacingSm),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppTokens.textTertiary,
                    size: 20,
                  ),
                  onPressed: onDelete,
                  splashRadius: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;

  const _PlayButton({required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isPlaying
            ? AppTokens.accentPrimary
            : AppTokens.backgroundTertiary,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: AppTokens.textPrimary,
        size: 24,
      ),
    );
  }
}
