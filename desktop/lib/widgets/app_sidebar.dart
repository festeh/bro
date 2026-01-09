import 'package:flutter/material.dart';

import '../services/livekit_service.dart';
import '../theme/tokens.dart';

enum AppMode { chat, recordings }

class AppSidebar extends StatelessWidget {
  final AppMode currentMode;
  final ValueChanged<AppMode> onModeChanged;
  final SttProvider sttProvider;
  final ValueChanged<SttProvider> onSttProviderChanged;
  final LlmModel llmModel;
  final ValueChanged<LlmModel> onLlmModelChanged;
  final bool ttsEnabled;
  final ValueChanged<bool> onTtsEnabledChanged;

  const AppSidebar({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    required this.sttProvider,
    required this.onSttProviderChanged,
    required this.llmModel,
    required this.onLlmModelChanged,
    required this.ttsEnabled,
    required this.onTtsEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
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
            child: Container(
              height: 1,
              color: AppTokens.backgroundTertiary,
            ),
          ),
          // Settings section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spacingSm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingDropdown<SttProvider>(
                  label: 'ASR',
                  value: sttProvider,
                  items: SttProvider.values,
                  onChanged: onSttProviderChanged,
                  itemLabel: _sttProviderLabel,
                ),
                const SizedBox(height: AppTokens.spacingSm),
                _SettingDropdown<LlmModel>(
                  label: 'LLM',
                  value: llmModel,
                  items: LlmModel.values,
                  onChanged: onLlmModelChanged,
                  itemLabel: _llmModelLabel,
                ),
                const SizedBox(height: AppTokens.spacingSm),
                _SettingToggle(
                  label: 'TTS',
                  value: ttsEnabled,
                  onChanged: onTtsEnabledChanged,
                ),
              ],
            ),
          ),
          const Spacer(),
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

  String _llmModelLabel(LlmModel model) {
    switch (model) {
      case LlmModel.glm47:
        return 'GLM-4.7';
      case LlmModel.mimoV2:
        return 'MiMo-V2';
      case LlmModel.minimax:
        return 'MiniMax-M2.1';
      case LlmModel.kimiK2:
        return 'Kimi-K2';
      case LlmModel.deepseekV31:
        return 'DeepSeek-V3.1';
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spacingSm,
          ),
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
