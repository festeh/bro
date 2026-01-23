import 'dart:async';

import 'package:flutter/material.dart';

import '../models/recording.dart';
import '../theme/tokens.dart';
import 'waveform_widget.dart';

class RecordingTile extends StatefulWidget {
  final Recording recording;
  final bool isPlaying;
  final double playbackProgress;
  final VoidCallback? onPlayPause;
  final VoidCallback? onDelete;
  final VoidCallback? onExtractWaveform;

  const RecordingTile({
    super.key,
    required this.recording,
    this.isPlaying = false,
    this.playbackProgress = 0.0,
    this.onPlayPause,
    this.onDelete,
    this.onExtractWaveform,
  });

  @override
  State<RecordingTile> createState() => _RecordingTileState();
}

class _RecordingTileState extends State<RecordingTile> {
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _extractWaveformIfNeeded();
  }

  @override
  void didUpdateWidget(RecordingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If recording changed and new one has no waveform, extract it
    if (oldWidget.recording.id != widget.recording.id) {
      _retryTimer?.cancel();
      _extractWaveformIfNeeded();
    }
    // If waveform was populated, cancel retry timer
    if (widget.recording.waveformData != null) {
      _retryTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _extractWaveformIfNeeded() {
    if (widget.recording.waveformData == null) {
      widget.onExtractWaveform?.call();
      // Schedule retry in case file isn't ready yet
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 1), _extractWaveformIfNeeded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final waveform = widget.recording.waveformData;
    final hasWaveform = waveform != null && waveform.isNotEmpty;

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
          onTap: widget.onPlayPause,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spacingMd),
            child: Row(
              children: [
                _PlayButton(isPlaying: widget.isPlaying),
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
                              widget.recording.title,
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
                            widget.recording.formattedDuration,
                            style: const TextStyle(
                              color: AppTokens.textSecondary,
                              fontSize: AppTokens.fontSizeSm,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spacingXs),
                      Text(
                        widget.recording.formattedDate,
                        style: const TextStyle(
                          color: AppTokens.textTertiary,
                          fontSize: AppTokens.fontSizeXs,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingSm),
                      if (hasWaveform)
                        WaveformWidget(
                          waveformData: widget.recording.waveformData,
                          progress: widget.playbackProgress,
                          isPlaying: widget.isPlaying,
                        )
                      else
                        SizedBox(height: AppTokens.waveformHeight),
                      if (widget.recording.hasTranscript) ...[
                        const SizedBox(height: AppTokens.spacingSm),
                        Text(
                          widget.recording.transcript!,
                          style: const TextStyle(
                            color: AppTokens.textSecondary,
                            fontSize: AppTokens.fontSizeSm,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
                  onPressed: widget.onDelete,
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
