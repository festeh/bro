import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models_config.dart';
import '../providers/settings_provider.dart';
import '../services/livekit_service.dart';
import '../theme/tokens.dart';

/// Shows the settings bottom sheet.
void showSettingsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTokens.backgroundSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => const SettingsSheet(),
  );
}

class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

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
