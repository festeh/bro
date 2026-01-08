import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/recording.dart';
import '../services/egress_service.dart';
import '../services/livekit_service.dart';
import '../services/storage_service.dart';
import '../services/waveform_service.dart';
import '../theme/tokens.dart';
import '../widgets/live_transcript.dart';
import '../widgets/record_button.dart';
import '../widgets/recording_list.dart';
import '../widgets/stt_provider_selector.dart';
import '../widgets/waveform_widget.dart';

final _log = Logger('HomePage');

class HomePage extends StatefulWidget {
  final LiveKitService liveKitService;
  final EgressService egressService;
  final StorageService storageService;
  final String recordingsDir;

  const HomePage({
    super.key,
    required this.liveKitService,
    required this.egressService,
    required this.storageService,
    required this.recordingsDir,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Player _player;
  final _uuid = const Uuid();
  final _waveformService = WaveformService();

  List<Recording> _recordings = [];
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  SttProvider _sttProvider = SttProvider.deepgram;
  bool _isRecording = false;
  bool _isLoading = false;
  String? _currentEgressId;
  String? _playingRecordingId;
  double _playbackProgress = 0.0;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _currentTranscript;
  String? _pendingTranscript;

  StreamSubscription<List<Recording>>? _recordingsSub;
  StreamSubscription<ConnectionStatus>? _connectionSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingStateSub;
  StreamSubscription<TranscriptionEvent>? _transcriptionSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _init();
  }

  Future<void> _init() async {
    // Subscribe to recordings
    _recordingsSub = widget.storageService.recordingsStream.listen((
      recordings,
    ) {
      setState(() => _recordings = recordings);
    });

    // Subscribe to connection status
    _connectionSub = widget.liveKitService.connectionStatus.listen((status) {
      setState(() => _connectionStatus = status);
    });

    // Subscribe to audio player position
    _positionSub = _player.stream.position.listen((position) {
      final duration = _player.state.duration;
      if (duration.inMilliseconds > 0) {
        setState(() {
          _playbackProgress = position.inMilliseconds / duration.inMilliseconds;
        });
      }
    });

    // Subscribe to player state - reset when playback completes
    _playingStateSub = _player.stream.playing.listen((playing) {
      if (!playing && _player.state.completed) {
        setState(() {
          _playingRecordingId = null;
          _playbackProgress = 0.0;
        });
      }
    });

    // Subscribe to transcription events
    _transcriptionSub = widget.liveKitService.transcriptionStream.listen((
      event,
    ) {
      setState(() {
        _currentTranscript = event.text;
      });

      if (event.isFinal && _isRecording) {
        // Store final transcript with recording
        _pendingTranscript = event.text;
      }
    });

    // Load initial recordings
    final recordings = await widget.storageService.getRecordings();
    setState(() => _recordings = recordings);

    // Connect to LiveKit
    await _connectToLiveKit();
  }

  Future<void> _connectToLiveKit() async {
    try {
      await widget.liveKitService.connect();
    } catch (e, st) {
      _showError('Failed to connect to LiveKit: $e', e, st);
    }
  }

  Future<void> _toggleRecording() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
    } catch (e, st) {
      _showError('Recording error: $e', e, st);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startRecording() async {
    // Enable microphone first
    final trackId = await widget.liveKitService.enableMicrophone();
    if (trackId == null) {
      throw Exception('Failed to enable microphone');
    }

    // Generate filename with timestamp
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final filepath = '/out/recording-$timestamp.ogg';

    // Start egress
    final egress = await widget.egressService.startTrackEgress(
      roomName: widget.liveKitService.roomName,
      trackId: trackId,
      filepath: filepath,
    );

    _currentEgressId = egress.egressId;
    _recordingDuration = Duration.zero;
    _currentTranscript = null;
    _pendingTranscript = null;

    // Start timer
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _recordingDuration += const Duration(seconds: 1);
      });
    });

    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    if (_currentEgressId != null) {
      final egress = await widget.egressService.stopEgress(_currentEgressId!);

      // Construct full path from recordings dir and filename
      final filePath = egress.filename != null
          ? p.join(widget.recordingsDir, egress.filename!)
          : '';

      // Create recording entry (waveform extracted lazily on display)
      final recording = Recording(
        id: _uuid.v4(),
        egressId: _currentEgressId,
        title: 'Recording ${_recordings.length + 1}',
        durationMs: _recordingDuration.inMilliseconds,
        filePath: filePath,
        createdAt: DateTime.now(),
        transcript: _pendingTranscript,
      );

      await widget.storageService.addRecording(recording);
    }

    await widget.liveKitService.disableMicrophone();

    setState(() {
      _isRecording = false;
      _currentEgressId = null;
      _recordingDuration = Duration.zero;
      _currentTranscript = null;
      _pendingTranscript = null;
    });
  }

  Future<void> _playPauseRecording(Recording recording) async {
    if (_playingRecordingId == recording.id) {
      // Pause/resume current
      await _player.playOrPause();
    } else {
      // Play new recording
      await _player.open(Media(recording.filePath));
      setState(() {
        _playingRecordingId = recording.id;
        _playbackProgress = 0.0;
      });
    }
  }

  /// Extract waveform for a recording if not already present
  Future<void> _extractWaveformIfNeeded(Recording recording) async {
    if (recording.waveformData != null) return;

    final waveform = await _waveformService.extractWaveform(recording.filePath);
    // null means file not ready yet - don't store, will retry on next trigger
    if (waveform == null) return;

    final updated = recording.copyWith(waveformData: waveform);
    await widget.storageService.updateRecording(updated);
  }

  Future<void> _deleteRecording(Recording recording) async {
    if (_playingRecordingId == recording.id) {
      await _player.stop();
      setState(() {
        _playingRecordingId = null;
        _playbackProgress = 0.0;
      });
    }
    await widget.storageService.deleteRecording(recording.id);
  }

  void _showError(String message, [Object? error, StackTrace? stackTrace]) {
    _log.severe(message, error, stackTrace);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTokens.accentRecording,
      ),
    );
  }

  String get _formattedRecordingDuration {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _recordingsSub?.cancel();
    _connectionSub?.cancel();
    _positionSub?.cancel();
    _playingStateSub?.cancel();
    _transcriptionSub?.cancel();
    _recordingTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _onSttProviderChanged(SttProvider provider) {
    setState(() => _sttProvider = provider);
    widget.liveKitService.setSttProvider(provider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recorder'),
        actions: [
          SttProviderSelector(
            currentProvider: _sttProvider,
            onChanged: _onSttProviderChanged,
          ),
          _ConnectionIndicator(status: _connectionStatus),
          const SizedBox(width: AppTokens.spacingMd),
        ],
      ),
      body: Column(
        children: [
          if (_isRecording) ...[
            _RecordingIndicator(duration: _formattedRecordingDuration),
            if (_currentTranscript != null && _currentTranscript!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spacingMd,
                ),
                child: LiveTranscript(text: _currentTranscript),
              ),
          ],
          Expanded(
            child: RecordingList(
              recordings: _recordings,
              playingRecordingId: _playingRecordingId,
              playbackProgress: _playbackProgress,
              onPlayPause: _playPauseRecording,
              onDelete: _deleteRecording,
              onExtractWaveform: _extractWaveformIfNeeded,
            ),
          ),
        ],
      ),
      floatingActionButton: RecordButton(
        isRecording: _isRecording,
        isLoading: _isLoading,
        onPressed: _connectionStatus == ConnectionStatus.connected
            ? _toggleRecording
            : null,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final ConnectionStatus status;

  const _ConnectionIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String tooltip;

    switch (status) {
      case ConnectionStatus.connected:
        color = AppTokens.accentSuccess;
        tooltip = 'Connected';
        break;
      case ConnectionStatus.connecting:
        color = AppTokens.accentPrimary;
        tooltip = 'Connecting...';
        break;
      case ConnectionStatus.error:
        color = AppTokens.accentRecording;
        tooltip = 'Connection error';
        break;
      case ConnectionStatus.disconnected:
        color = AppTokens.textTertiary;
        tooltip = 'Disconnected';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  final String duration;

  const _RecordingIndicator({required this.duration});

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
