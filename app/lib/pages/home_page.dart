import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/models_config.dart';
import '../models/recording.dart';
import '../providers/livekit_providers.dart';
import '../providers/settings_provider.dart';
import '../providers/storage_providers.dart';
import '../services/egress_service.dart';
import '../services/livekit_service.dart';
import '../services/waveform_service.dart';
import '../theme/tokens.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/live_transcript.dart';
import '../widgets/record_button.dart';
import '../widgets/recording_list.dart';
import '../widgets/waveform_widget.dart';
import 'chat_page.dart';

final _log = Logger('HomePage');

class HomePage extends ConsumerStatefulWidget {
  final EgressService egressService;

  const HomePage({
    super.key,
    required this.egressService,
  });

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final Player _player;
  final _uuid = const Uuid();
  final _waveformService = WaveformService();

  final _chatPageKey = GlobalKey<ChatPageState>();
  AppMode _currentMode = AppMode.chat;
  bool _isRecording = false;
  bool _isLoading = false;
  String? _currentEgressId;
  String? _playingRecordingId;
  double _playbackProgress = 0.0;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _currentTranscript;
  String? _pendingTranscript;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingStateSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _initPlayer();
    _connectToLiveKit();
  }

  void _initPlayer() {
    _positionSub = _player.stream.position.listen((position) {
      if (!mounted) return;
      final duration = _player.state.duration;
      if (duration.inMilliseconds > 0) {
        setState(() {
          _playbackProgress =
              position.inMilliseconds / duration.inMilliseconds;
        });
      }
    });

    _playingStateSub = _player.stream.playing.listen((playing) {
      if (!mounted) return;
      if (!playing && _player.state.completed) {
        setState(() {
          _playingRecordingId = null;
          _playbackProgress = 0.0;
        });
      }
    });
  }

  Future<void> _connectToLiveKit() async {
    try {
      await ref.read(liveKitServiceProvider).connect();
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
    final liveKit = ref.read(liveKitServiceProvider);

    final trackId = await liveKit.startVoiceSession();
    if (trackId == null) {
      throw Exception('Failed to enable microphone');
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final filepath = '/out/recording-$timestamp.ogg';

    final egress = await widget.egressService.startTrackEgress(
      roomName: liveKit.roomName,
      trackId: trackId,
      filepath: filepath,
    );

    _currentEgressId = egress.egressId;
    _recordingDuration = Duration.zero;
    _currentTranscript = null;
    _pendingTranscript = null;

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

    final liveKit = ref.read(liveKitServiceProvider);
    final storage = ref.read(storageServiceProvider);

    if (_currentEgressId != null) {
      final egress = await widget.egressService.stopEgress(_currentEgressId!);

      final filePath = egress.filename != null
          ? p.join(storage.recordingsDir, egress.filename!)
          : '';

      final recording = Recording(
        id: _uuid.v4(),
        egressId: _currentEgressId,
        title: 'Recording',
        durationMs: _recordingDuration.inMilliseconds,
        filePath: filePath,
        createdAt: DateTime.now(),
        transcript: _pendingTranscript,
      );

      await storage.addRecording(recording);
    }

    await liveKit.stopVoiceSession();

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
      await _player.playOrPause();
    } else {
      await _player.open(Media(recording.filePath));
      setState(() {
        _playingRecordingId = recording.id;
        _playbackProgress = 0.0;
      });
    }
  }

  Future<void> _extractWaveformIfNeeded(Recording recording) async {
    if (recording.waveformData != null) return;

    final waveform = await _waveformService.extractWaveform(recording.filePath);
    if (waveform == null) return;

    final updated = recording.copyWith(waveformData: waveform);
    await ref.read(storageServiceProvider).updateRecording(updated);
  }

  Future<void> _deleteRecording(Recording recording) async {
    if (_playingRecordingId == recording.id) {
      await _player.stop();
      setState(() {
        _playingRecordingId = null;
        _playbackProgress = 0.0;
      });
    }
    await ref.read(storageServiceProvider).deleteRecording(recording.id);
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
    _positionSub?.cancel();
    _playingStateSub?.cancel();
    _player.stop();
    _player.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _onModeChanged(AppMode mode) {
    setState(() => _currentMode = mode);
    final agentMode =
        mode == AppMode.chat ? AgentMode.chat : AgentMode.transcribe;
    ref.read(liveKitServiceProvider).setAgentMode(agentMode);
  }

  static const double _mobileBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    // Watch shared Riverpod state
    final connectionAsync = ref.watch(connectionStatusProvider);
    final agentConnectedAsync = ref.watch(agentConnectedProvider);
    final recordingsAsync = ref.watch(recordingsProvider);

    final connectionStatus = connectionAsync.valueOrNull ??
        ConnectionStatus.disconnected;
    final isAgentConnected = agentConnectedAsync.valueOrNull ?? false;
    final recordings = recordingsAsync.valueOrNull ?? [];

    // Listen to transcription events for recording mode
    ref.listen(transcriptionProvider, (_, next) {
      next.whenData((event) {
        if (!_isRecording && _currentMode != AppMode.recordings) return;
        setState(() {
          _currentTranscript = event.text;
        });
        if (event.isFinal && _isRecording) {
          if (_pendingTranscript == null || _pendingTranscript!.isEmpty) {
            _pendingTranscript = event.text;
          } else {
            _pendingTranscript = '$_pendingTranscript ${event.text}';
          }
        }
      });
    });

    final liveKit = ref.watch(liveKitServiceProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        return isMobile
            ? _buildMobileLayout(
                connectionStatus, isAgentConnected, recordings, liveKit)
            : _buildDesktopLayout(
                connectionStatus, isAgentConnected, recordings, liveKit);
      },
    );
  }

  Widget _buildDesktopLayout(
    ConnectionStatus connectionStatus,
    bool isAgentConnected,
    List<Recording> recordings,
    LiveKitService liveKit,
  ) {
    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            currentMode: _currentMode,
            onModeChanged: _onModeChanged,
            connectionStatus: connectionStatus,
            isAgentConnected: isAgentConnected,
            wsUrl: liveKit.wsUrl,
            roomName: liveKit.roomName,
            apiKey: liveKit.tokenService.apiKey,
          ),
          Expanded(child: _buildMainContent(connectionStatus, recordings)),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
    ConnectionStatus connectionStatus,
    bool isAgentConnected,
    List<Recording> recordings,
    LiveKitService liveKit,
  ) {
    return Scaffold(
      appBar: AppBar(
        leading: PopupMenuButton<AppMode>(
          icon: Icon(
            _currentMode == AppMode.chat ? Icons.chat_bubble : Icons.mic,
            color: AppTokens.textPrimary,
            size: 22,
          ),
          tooltip: 'Navigate',
          color: AppTokens.backgroundSecondary,
          onSelected: _onModeChanged,
          itemBuilder: (context) => [
            PopupMenuItem(
              value: AppMode.chat,
              child: Row(
                children: [
                  Icon(
                    _currentMode == AppMode.chat
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                    size: 20,
                    color: _currentMode == AppMode.chat
                        ? AppTokens.accentPrimary
                        : AppTokens.textSecondary,
                  ),
                  const SizedBox(width: AppTokens.spacingSm),
                  Text(
                    'Chat',
                    style: TextStyle(
                      color: _currentMode == AppMode.chat
                          ? AppTokens.accentPrimary
                          : AppTokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: AppMode.recordings,
              child: Row(
                children: [
                  Icon(
                    _currentMode == AppMode.recordings
                        ? Icons.mic
                        : Icons.mic_none,
                    size: 20,
                    color: _currentMode == AppMode.recordings
                        ? AppTokens.accentPrimary
                        : AppTokens.textSecondary,
                  ),
                  const SizedBox(width: AppTokens.spacingSm),
                  Text(
                    'Recordings',
                    style: TextStyle(
                      color: _currentMode == AppMode.recordings
                          ? AppTokens.accentPrimary
                          : AppTokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        title: Text(_currentMode == AppMode.chat ? 'Chat' : 'Recordings'),
        actions: [
          if (_currentMode == AppMode.chat)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppTokens.textSecondary,
              onPressed: () => _chatPageKey.currentState?.clearChat(),
              tooltip: 'Clear chat',
            ),
          IconButton(
            icon: const Icon(Icons.settings, size: 20),
            color: AppTokens.textSecondary,
            onPressed: _showSettingsSheet,
            tooltip: 'Settings',
          ),
          _ConnectionIndicator(
            status: connectionStatus,
            isAgentConnected: isAgentConnected,
            wsUrl: liveKit.wsUrl,
            roomName: liveKit.roomName,
            apiKey: liveKit.tokenService.apiKey,
          ),
          const SizedBox(width: AppTokens.spacingMd),
        ],
      ),
      body: _buildMainContent(connectionStatus, recordings),
    );
  }

  Widget _buildMainContent(
    ConnectionStatus connectionStatus,
    List<Recording> recordings,
  ) {
    return _currentMode == AppMode.chat
        ? ChatPage(key: _chatPageKey)
        : _buildRecordingsContent(connectionStatus, recordings);
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const _SettingsSheet(),
    );
  }

  Widget _buildRecordingsContent(
    ConnectionStatus connectionStatus,
    List<Recording> recordings,
  ) {
    return Column(
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
            recordings: recordings,
            playingRecordingId: _playingRecordingId,
            playbackProgress: _playbackProgress,
            onPlayPause: _playPauseRecording,
            onDelete: _deleteRecording,
            onExtractWaveform: _extractWaveformIfNeeded,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: AppTokens.spacingLg +
                MediaQuery.of(context).padding.bottom,
          ),
          child: RecordButton(
            isRecording: _isRecording,
            isLoading: _isLoading,
            onPressed: connectionStatus == ConnectionStatus.connected
                ? _toggleRecording
                : null,
          ),
        ),
      ],
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final ConnectionStatus status;
  final bool isAgentConnected;
  final String wsUrl;
  final String roomName;
  final String apiKey;

  const _ConnectionIndicator({
    required this.status,
    required this.isAgentConnected,
    required this.wsUrl,
    required this.roomName,
    required this.apiKey,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String statusText;

    if (status != ConnectionStatus.connected) {
      switch (status) {
        case ConnectionStatus.connecting:
          color = AppTokens.accentPrimary;
          statusText = 'Connecting...';
          break;
        case ConnectionStatus.error:
          color = AppTokens.accentRecording;
          statusText = 'Error';
          break;
        case ConnectionStatus.disconnected:
        case ConnectionStatus.connected:
          color = AppTokens.textTertiary;
          statusText = 'Disconnected';
          break;
      }
    } else if (!isAgentConnected) {
      color = AppTokens.accentPrimary;
      statusText = 'No agent';
    } else {
      color = AppTokens.accentSuccess;
      statusText = 'Connected';
    }

    return GestureDetector(
      onTap: () => _showInfoDialog(context, statusText),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String statusText) {
    final isDefault = apiKey == 'devkey';
    final maskedKey = apiKey.length > 8
        ? '${apiKey.substring(0, 8)}...'
        : apiKey;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTokens.backgroundSecondary,
        title: const Text(
          'Connection Info',
          style: TextStyle(color: AppTokens.textPrimary, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Status', statusText),
            _infoRow('Server', wsUrl),
            _infoRow('Room', roomName),
            _infoRow('API Key', maskedKey),
            if (isDefault)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Using default dev credentials',
                  style: TextStyle(color: AppTokens.accentRecording, fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(color: AppTokens.textTertiary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppTokens.textPrimary, fontSize: 12)),
          ),
        ],
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

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                color: AppTokens.textPrimary,
                fontSize: AppTokens.fontSizeLg,
                fontWeight: AppTokens.fontWeightMedium,
              ),
            ),
            const SizedBox(height: AppTokens.spacingLg),
            _SettingRow(
              label: 'ASR Provider',
              child: DropdownButton<SttProvider>(
                value: settings.sttProvider,
                dropdownColor: AppTokens.backgroundTertiary,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: AppTokens.fontSizeMd,
                ),
                underline: const SizedBox(),
                items: SttProvider.values.map((provider) {
                  return DropdownMenuItem(
                    value: provider,
                    child: Text(_sttProviderLabel(provider)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    notifier.setSttProvider(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            const SizedBox(height: AppTokens.spacingMd),
            _SettingRow(
              label: 'LLM Model',
              child: DropdownButton<Model>(
                value: settings.llmModel,
                dropdownColor: AppTokens.backgroundTertiary,
                style: const TextStyle(
                  color: AppTokens.textPrimary,
                  fontSize: AppTokens.fontSizeMd,
                ),
                underline: const SizedBox(),
                items: ModelsConfig.instance.llmModels.map((model) {
                  return DropdownMenuItem(
                    value: model,
                    child: Text(model.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    notifier.setLlmModel(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            const SizedBox(height: AppTokens.spacingMd),
            _SettingRow(
              label: 'Text-to-Speech',
              child: Switch(
                value: settings.ttsEnabled,
                onChanged: notifier.setTtsEnabled,
                activeTrackColor: AppTokens.accentPrimary,
              ),
            ),
            const SizedBox(height: AppTokens.spacingLg),
            const Text(
              'Agents',
              style: TextStyle(
                color: AppTokens.textSecondary,
                fontSize: AppTokens.fontSizeMd,
                fontWeight: AppTokens.fontWeightMedium,
              ),
            ),
            const SizedBox(height: AppTokens.spacingSm),
            ..._availableAgents.map((agent) {
              final isEnabled = !settings.excludedAgents.contains(agent.id);
              return _AgentTile(
                name: agent.name,
                icon: agent.icon,
                isEnabled: isEnabled,
                onChanged: (enabled) {
                  final newExcluded = Set<String>.from(settings.excludedAgents);
                  if (enabled) {
                    newExcluded.remove(agent.id);
                  } else {
                    newExcluded.add(agent.id);
                  }
                  notifier.setExcludedAgents(newExcluded);
                },
              );
            }),
            const SizedBox(height: AppTokens.spacingMd),
          ],
        ),
      ),
    );
  }

  String _sttProviderLabel(SttProvider provider) {
    switch (provider) {
      case SttProvider.deepgram:
        return 'Deepgram';
      case SttProvider.elevenlabs:
        return 'ElevenLabs';
    }
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTokens.textSecondary,
            fontSize: AppTokens.fontSizeMd,
          ),
        ),
        child,
      ],
    );
  }
}

/// Available agents that can be enabled/disabled.
const _availableAgents = [
  (id: 'task', name: 'Tasks', icon: Icons.task_alt),
  (id: 'basidian', name: 'Notes', icon: Icons.note_alt),
];

class _AgentTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  const _AgentTile({
    required this.name,
    required this.icon,
    required this.isEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!isEnabled),
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spacingSm),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isEnabled,
                onChanged: (value) => onChanged(value ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeColor: AppTokens.accentPrimary,
                side: const BorderSide(color: AppTokens.textTertiary),
              ),
            ),
            const SizedBox(width: AppTokens.spacingSm),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTokens.backgroundTertiary,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Icon(icon, size: 16, color: AppTokens.textSecondary),
            ),
            const SizedBox(width: AppTokens.spacingSm),
            Text(
              name,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: AppTokens.fontSizeMd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
