import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../app/tokens.dart';
import '../../../core/models/speech_file.dart';
import 'waveform_painter.dart';

class AudioTile extends StatefulWidget {
  final SpeechSegment segment;
  final VoidCallback? onDelete;

  const AudioTile({super.key, required this.segment, this.onDelete});

  @override
  State<AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<AudioTile> {
  static const _channel = MethodChannel('com.github.festeh.bro/storage');

  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Timer? _positionTimer;

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  void _startPositionUpdates() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      if (!_isPlaying || !mounted) {
        _positionTimer?.cancel();
        return;
      }

      try {
        // Check if this tile's segment is still the one playing
        final currentId =
            await _channel.invokeMethod<String>('getCurrentPlayingId');
        if (currentId != widget.segment.id) {
          // Different segment is playing now, stop our updates
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _position = Duration.zero;
            });
          }
          _positionTimer?.cancel();
          return;
        }

        final positionMs =
            await _channel.invokeMethod<int>('getPlaybackPosition') ?? 0;
        final isPlaying =
            await _channel.invokeMethod<bool>('isPlaying') ?? false;

        if (mounted) {
          setState(() {
            _position = Duration(milliseconds: positionMs);
            _isPlaying = isPlaying;
          });

          // Check if playback finished
          if (!isPlaying) {
            _positionTimer?.cancel();
            setState(() {
              _position = Duration.zero;
            });
          }
        }
      } catch (e) {
        debugPrint('Error getting position: $e');
      }
    });
  }

  Future<void> _togglePlayPause() async {
    if (_isLoading) return;

    if (_isPlaying) {
      try {
        await _channel.invokeMethod('pauseAudio');
        setState(() => _isPlaying = false);
        _positionTimer?.cancel();
      } catch (e) {
        debugPrint('Error pausing: $e');
      }
    } else {
      setState(() => _isLoading = true);

      try {
        await _channel.invokeMethod('playAudio', {'id': widget.segment.id});
        if (mounted) {
          setState(() {
            _isPlaying = true;
            _isLoading = false;
          });
          _startPositionUpdates();
        }
      } catch (e) {
        debugPrint('Error playing: $e');
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, HH:mm:ss');
    final duration = widget.segment.duration;
    final progress = duration.inMilliseconds > 0
        ? _position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    // Convert waveform to int (0-100 range) for painter
    final waveformData = widget.segment.waveform
        .map((d) => (d * 100).toInt())
        .toList();

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: Tokens.spacingMd,
        vertical: Tokens.spacingSm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _togglePlayPause,
                  icon: _isLoading
                      ? SizedBox(
                          width: Tokens.iconSizeLg,
                          height: Tokens.iconSizeLg,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Tokens.primary,
                          ),
                        )
                      : Icon(
                          _isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          size: Tokens.iconSizeLg,
                          color: Tokens.primary,
                        ),
                ),
                const SizedBox(width: Tokens.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateFormat.format(widget.segment.timestamp),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: Tokens.spacingXs),
                      Text(
                        widget.segment.formattedDuration,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Tokens.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.spacingSm),
            AudioWaveform(amplitudes: waveformData, progress: progress),
            const SizedBox(height: Tokens.spacingXs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  _formatDuration(duration),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
