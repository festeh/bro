import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/models_config.dart';
import '../models/recording.dart';
import '../services/egress_service.dart';
import '../services/livekit_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/waveform_service.dart';
import '../theme/tokens.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/live_transcript.dart';
import '../widgets/record_button.dart';
import '../widgets/recording_list.dart';
import '../widgets/waveform_widget.dart';
import 'chat_page.dart';

final _log = Logger('HomePage');

class HomePage extends StatefulWidget {
  final LiveKitService liveKitService;
  final EgressService egressService;
  final StorageService storageService;
  final SettingsService settingsService;
  final String recordingsDir;

  const HomePage({
    super.key,
    required this.liveKitService,
    required this.egressService,
    required this.storageService,
    required this.settingsService,
    required this.recordingsDir,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Player _player;
  final _uuid = const Uuid();
  final _waveformService = WaveformService();

  final _chatPageKey = GlobalKey<ChatPageState>();
  AppMode _currentMode = AppMode.chat;
  List<Recording> _recordings = [];
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  bool _isAgentConnected = false;
  SttProvider _sttProvider = SttProvider.deepgram;
  late Model _llmModel;
  bool _ttsEnabled = true;
  Set<String> _excludedAgents = {};
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
  StreamSubscription<bool>? _agentConnectedSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingStateSub;
  StreamSubscription<TranscriptionEvent>? _transcriptionSub;

  @override
  void initState() {
    super.initState();
    // Load persisted settings
    _sttProvider = widget.settingsService.sttProvider;
    _llmModel = widget.settingsService.llmModel;
    _ttsEnabled = widget.settingsService.ttsEnabled;
    _excludedAgents = widget.settingsService.excludedAgents;
    // Apply to LiveKitService (will be sent on connect)
    widget.liveKitService.setSttProvider(_sttProvider);
    widget.liveKitService.setLlmModel(_llmModel);
    widget.liveKitService.setTtsEnabled(_ttsEnabled);
    widget.liveKitService.setExcludedAgents(_excludedAgents);
    _player = Player();
    _init();
  }

  Future<void> _init() async {
    // Subscribe to recordings
    _recordingsSub = widget.storageService.recordingsStream.listen((
      recordings,
    ) {
      if (!mounted) return;
      setState(() => _recordings = recordings);
    });

    // Subscribe to connection status
    _connectionSub = widget.liveKitService.connectionStatus.listen((status) {
      if (!mounted) return;
      setState(() => _connectionStatus = status);
    });

    // Subscribe to agent connection status
    _agentConnectedSub = widget.liveKitService.agentConnectedStream.listen((
      connected,
    ) {
      if (!mounted) return;
      setState(() => _isAgentConnected = connected);
    });

    // Subscribe to audio player position
    _positionSub = _player.stream.position.listen((position) {
      if (!mounted) return;
      final duration = _player.state.duration;
      if (duration.inMilliseconds > 0) {
        setState(() {
          _playbackProgress = position.inMilliseconds / duration.inMilliseconds;
        });
      }
    });

    // Subscribe to player state - reset when playback completes
    _playingStateSub = _player.stream.playing.listen((playing) {
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _currentTranscript = event.text;
      });

      if (event.isFinal && _isRecording) {
        // Append final transcript segments
        if (_pendingTranscript == null || _pendingTranscript!.isEmpty) {
          _pendingTranscript = event.text;
        } else {
          _pendingTranscript = '$_pendingTranscript ${event.text}';
        }
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
    final trackId = await widget.liveKitService.startVoiceSession();
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

    await widget.liveKitService.stopVoiceSession();

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
    // Cancel player subscriptions first to prevent callbacks during disposal
    _positionSub?.cancel();
    _playingStateSub?.cancel();
    // Stop player before disposing to clean up native resources
    _player.stop();
    _player.dispose();
    // Cancel other subscriptions
    _recordingsSub?.cancel();
    _connectionSub?.cancel();
    _agentConnectedSub?.cancel();
    _transcriptionSub?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _onSttProviderChanged(SttProvider provider) {
    setState(() => _sttProvider = provider);
    widget.liveKitService.setSttProvider(provider);
    widget.settingsService.setSttProvider(provider);
  }

  void _onLlmModelChanged(Model model) {
    setState(() => _llmModel = model);
    widget.liveKitService.setLlmModel(model);
    widget.settingsService.setLlmModel(model);
  }

  void _onTtsEnabledChanged(bool enabled) {
    setState(() => _ttsEnabled = enabled);
    widget.liveKitService.setTtsEnabled(enabled);
    widget.settingsService.setTtsEnabled(enabled);
  }

  void _onExcludedAgentsChanged(Set<String> excluded) {
    setState(() => _excludedAgents = excluded);
    widget.liveKitService.setExcludedAgents(excluded);
    widget.settingsService.setExcludedAgents(excluded);
  }

  void _onModeChanged(AppMode mode) {
    setState(() => _currentMode = mode);
    // Update agent mode based on app mode
    final agentMode = mode == AppMode.chat
        ? AgentMode.chat
        : AgentMode.transcribe;
    widget.liveKitService.setAgentMode(agentMode);
  }

  static const double _mobileBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        return isMobile ? _buildMobileLayout() : _buildDesktopLayout();
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            currentMode: _currentMode,
            onModeChanged: _onModeChanged,
            sttProvider: _sttProvider,
            onSttProviderChanged: _onSttProviderChanged,
            llmModel: _llmModel,
            onLlmModelChanged: _onLlmModelChanged,
            ttsEnabled: _ttsEnabled,
            onTtsEnabledChanged: _onTtsEnabledChanged,
            excludedAgents: _excludedAgents,
            onExcludedAgentsChanged: _onExcludedAgentsChanged,
            connectionStatus: _connectionStatus,
            isAgentConnected: _isAgentConnected,
          ),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(
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
            status: _connectionStatus,
            isAgentConnected: _isAgentConnected,
          ),
          const SizedBox(width: AppTokens.spacingMd),
        ],
      ),
      body: _buildMainContent(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentMode == AppMode.chat ? 0 : 1,
        onDestinationSelected: (index) {
          _onModeChanged(index == 0 ? AppMode.chat : AppMode.recordings);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none),
            selectedIcon: Icon(Icons.mic),
            label: 'Recordings',
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return _currentMode == AppMode.chat
        ? ChatPage(key: _chatPageKey, liveKitService: widget.liveKitService)
        : _buildRecordingsContent();
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SettingsSheet(
        sttProvider: _sttProvider,
        onSttProviderChanged: (provider) {
          _onSttProviderChanged(provider);
          Navigator.pop(context);
        },
        llmModel: _llmModel,
        onLlmModelChanged: (model) {
          _onLlmModelChanged(model);
          Navigator.pop(context);
        },
        ttsEnabled: _ttsEnabled,
        onTtsEnabledChanged: _onTtsEnabledChanged,
        excludedAgents: _excludedAgents,
        onExcludedAgentsChanged: _onExcludedAgentsChanged,
      ),
    );
  }

  Widget _buildRecordingsContent() {
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
            recordings: _recordings,
            playingRecordingId: _playingRecordingId,
            playbackProgress: _playbackProgress,
            onPlayPause: _playPauseRecording,
            onDelete: _deleteRecording,
            onExtractWaveform: _extractWaveformIfNeeded,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spacingLg),
          child: RecordButton(
            isRecording: _isRecording,
            isLoading: _isLoading,
            onPressed: _connectionStatus == ConnectionStatus.connected
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

  const _ConnectionIndicator({
    required this.status,
    required this.isAgentConnected,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String tooltip;

    if (status != ConnectionStatus.connected) {
      // Not connected to LiveKit
      switch (status) {
        case ConnectionStatus.connecting:
          color = AppTokens.accentPrimary;
          tooltip = 'Connecting to server...';
          break;
        case ConnectionStatus.error:
          color = AppTokens.accentRecording;
          tooltip = 'Connection error';
          break;
        case ConnectionStatus.disconnected:
        case ConnectionStatus.connected: // Won't reach here
          color = AppTokens.textTertiary;
          tooltip = 'Disconnected';
          break;
      }
    } else if (!isAgentConnected) {
      // Connected to LiveKit but agent not present
      color = AppTokens.accentPrimary;
      tooltip = 'Waiting for agent...';
    } else {
      // Connected and agent present
      color = AppTokens.accentSuccess;
      tooltip = 'Agent connected';
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

class _SettingsSheet extends StatelessWidget {
  final SttProvider sttProvider;
  final ValueChanged<SttProvider> onSttProviderChanged;
  final Model llmModel;
  final ValueChanged<Model> onLlmModelChanged;
  final bool ttsEnabled;
  final ValueChanged<bool> onTtsEnabledChanged;
  final Set<String> excludedAgents;
  final ValueChanged<Set<String>> onExcludedAgentsChanged;

  const _SettingsSheet({
    required this.sttProvider,
    required this.onSttProviderChanged,
    required this.llmModel,
    required this.onLlmModelChanged,
    required this.ttsEnabled,
    required this.onTtsEnabledChanged,
    required this.excludedAgents,
    required this.onExcludedAgentsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
              value: sttProvider,
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
                if (value != null) onSttProviderChanged(value);
              },
            ),
          ),
          const SizedBox(height: AppTokens.spacingMd),
          _SettingRow(
            label: 'LLM Model',
            child: DropdownButton<Model>(
              value: llmModel,
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
                if (value != null) onLlmModelChanged(value);
              },
            ),
          ),
          const SizedBox(height: AppTokens.spacingMd),
          _SettingRow(
            label: 'Text-to-Speech',
            child: Switch(
              value: ttsEnabled,
              onChanged: onTtsEnabledChanged,
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
            final isEnabled = !excludedAgents.contains(agent.id);
            return _AgentTile(
              name: agent.name,
              icon: agent.icon,
              isEnabled: isEnabled,
              onChanged: (enabled) {
                final newExcluded = Set<String>.from(excludedAgents);
                if (enabled) {
                  newExcluded.remove(agent.id);
                } else {
                  newExcluded.add(agent.id);
                }
                onExcludedAgentsChanged(newExcluded);
              },
            );
          }),
          const SizedBox(height: AppTokens.spacingMd),
        ],
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
