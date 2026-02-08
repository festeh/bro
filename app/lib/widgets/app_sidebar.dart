import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models_config.dart';
import '../providers/settings_provider.dart';
import '../services/livekit_service.dart';
import '../theme/tokens.dart';

enum AppMode { chat, recordings }

class AppSidebar extends ConsumerWidget {
  final AppMode currentMode;
  final ValueChanged<AppMode> onModeChanged;
  final ConnectionStatus connectionStatus;
  final bool isAgentConnected;
  final String wsUrl;
  final String roomName;
  final String apiKey;

  const AppSidebar({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    required this.connectionStatus,
    required this.isAgentConnected,
    required this.wsUrl,
    required this.roomName,
    required this.apiKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Container(
      width: 140,
      color: AppTokens.backgroundSecondary,
      child: Column(
        children: [
          const SizedBox(height: AppTokens.spacingLg),
          _NavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            isSelected: currentMode == AppMode.chat,
            onTap: () => onModeChanged(AppMode.chat),
          ),
          const SizedBox(height: AppTokens.spacingSm),
          _NavItem(
            icon: Icons.mic_none,
            label: 'Recordings',
            isSelected: currentMode == AppMode.recordings,
            onTap: () => onModeChanged(AppMode.recordings),
          ),
          // Separator
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spacingSm,
              vertical: AppTokens.spacingMd,
            ),
            child: Container(height: 1, color: AppTokens.backgroundTertiary),
          ),
          // Settings section
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spacingSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingDropdown<SttProvider>(
                  label: 'ASR',
                  value: settings.sttProvider,
                  items: SttProvider.values,
                  onChanged: notifier.setSttProvider,
                  itemLabel: _sttProviderLabel,
                ),
                const SizedBox(height: AppTokens.spacingSm),
                _SettingDropdown<Model>(
                  label: 'LLM',
                  value: settings.llmModel,
                  items: ModelsConfig.instance.llmModels,
                  onChanged: notifier.setLlmModel,
                  itemLabel: (m) => m.displayName,
                ),
                const SizedBox(height: AppTokens.spacingSm),
                _SettingToggle(
                  label: 'TTS',
                  value: settings.ttsEnabled,
                  onChanged: notifier.setTtsEnabled,
                ),
                const SizedBox(height: AppTokens.spacingMd),
                _AgentSelector(
                  excludedAgents: settings.excludedAgents,
                  onChanged: notifier.setExcludedAgents,
                ),
              ],
            ),
          ),
          const Spacer(),
          _ConnectionInfo(
            connectionStatus: connectionStatus,
            isAgentConnected: isAgentConnected,
            wsUrl: wsUrl,
            roomName: roomName,
            apiKey: apiKey,
          ),
          const SizedBox(height: AppTokens.spacingLg),
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(
          vertical: AppTokens.spacingSm,
          horizontal: AppTokens.spacingSm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTokens.accentPrimary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppTokens.accentPrimary
                  : AppTokens.textSecondary,
              size: 20,
            ),
            const SizedBox(width: AppTokens.spacingSm),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? AppTokens.accentPrimary
                    : AppTokens.textSecondary,
                fontSize: AppTokens.fontSizeSm,
                fontWeight: isSelected
                    ? AppTokens.fontWeightMedium
                    : AppTokens.fontWeightNormal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T) itemLabel;

  const _SettingDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTokens.textTertiary,
            fontSize: AppTokens.fontSizeXs,
            fontWeight: AppTokens.fontWeightMedium,
          ),
        ),
        const SizedBox(height: AppTokens.spacingXs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spacingSm),
          decoration: BoxDecoration(
            color: AppTokens.backgroundTertiary,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: AppTokens.backgroundTertiary,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: AppTokens.fontSizeXs,
              ),
              icon: const Icon(
                Icons.expand_more,
                color: AppTokens.textSecondary,
                size: 16,
              ),
              items: items.map((item) {
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(itemLabel(item)),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  onChanged(newValue);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTokens.textTertiary,
            fontSize: AppTokens.fontSizeXs,
            fontWeight: AppTokens.fontWeightMedium,
          ),
        ),
        SizedBox(
          height: 24,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppTokens.accentPrimary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

/// Available agents that can be enabled/disabled.
const _availableAgents = [
  (id: 'task', name: 'Tasks', icon: Icons.task_alt),
  (id: 'basidian', name: 'Notes', icon: Icons.note_alt),
];

class _AgentSelector extends StatelessWidget {
  final Set<String> excludedAgents;
  final ValueChanged<Set<String>> onChanged;

  const _AgentSelector({required this.excludedAgents, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Agents',
          style: TextStyle(
            color: AppTokens.textTertiary,
            fontSize: AppTokens.fontSizeXs,
            fontWeight: AppTokens.fontWeightMedium,
          ),
        ),
        const SizedBox(height: AppTokens.spacingXs),
        ..._availableAgents.map((agent) {
          final isEnabled = !excludedAgents.contains(agent.id);
          return _AgentRow(
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
              onChanged(newExcluded);
            },
          );
        }),
      ],
    );
  }
}

class _AgentRow extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  const _AgentRow({
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
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spacingXs),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
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
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTokens.backgroundTertiary,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Icon(icon, size: 14, color: AppTokens.textSecondary),
            ),
            const SizedBox(width: AppTokens.spacingSm),
            Text(
              name,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: AppTokens.fontSizeXs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionInfo extends StatelessWidget {
  final ConnectionStatus connectionStatus;
  final bool isAgentConnected;
  final String wsUrl;
  final String roomName;
  final String apiKey;

  const _ConnectionInfo({
    required this.connectionStatus,
    required this.isAgentConnected,
    required this.wsUrl,
    required this.roomName,
    required this.apiKey,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String statusText;

    if (connectionStatus != ConnectionStatus.connected) {
      switch (connectionStatus) {
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppTokens.spacingSm),
          Icon(
            Icons.info_outline,
            size: 14,
            color: AppTokens.textTertiary,
          ),
        ],
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
          style: TextStyle(color: AppTokens.textPrimary, fontSize: AppTokens.fontSizeMd),
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
                padding: EdgeInsets.only(top: AppTokens.spacingSm),
                child: Text(
                  'Using default dev credentials',
                  style: TextStyle(
                    color: AppTokens.accentRecording,
                    fontSize: AppTokens.fontSizeXs,
                  ),
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spacingXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTokens.textTertiary,
                fontSize: AppTokens.fontSizeXs,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: AppTokens.fontSizeXs,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
