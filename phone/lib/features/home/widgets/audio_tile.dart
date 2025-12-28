import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import '../../../app/tokens.dart';
import '../../../core/models/speech_file.dart';

class AudioTile extends StatefulWidget {
  final SpeechFile file;
  final VoidCallback? onDelete;

  const AudioTile({super.key, required this.file, this.onDelete});

  @override
  State<AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<AudioTile> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setupPlayer();
  }

  Future<void> _setupPlayer() async {
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });

    _player.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _player.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() {
          _duration = duration;
        });
      }
    });

    // Load the file
    try {
      await _player.setFilePath(widget.file.path);
    } catch (e) {
      debugPrint('Error loading audio: $e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, HH:mm');

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
                // Play/Pause button
                IconButton(
                  onPressed: _togglePlayPause,
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: Tokens.iconSizeLg,
                    color: Tokens.primary,
                  ),
                ),
                const SizedBox(width: Tokens.spacingSm),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateFormat.format(widget.file.timestamp),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: Tokens.spacingXs),
                      Text(
                        widget.file.formattedSize,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),

                // Delete button
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Tokens.textTertiary,
                  ),
                ),
              ],
            ),

            // Progress bar
            if (_duration > Duration.zero) ...[
              const SizedBox(height: Tokens.spacingSm),
              Row(
                children: [
                  Text(
                    _formatDuration(_position),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Expanded(
                    child: Slider(
                      value: _position.inMilliseconds.toDouble(),
                      max: _duration.inMilliseconds.toDouble(),
                      onChanged: (value) {
                        _player.seek(Duration(milliseconds: value.toInt()));
                      },
                      activeColor: Tokens.primary,
                      inactiveColor: Tokens.surfaceVariant,
                    ),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
