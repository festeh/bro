import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models_config.dart';
import '../services/livekit_service.dart';
import '../services/settings_service.dart';

class SettingsState {
  final SttProvider sttProvider;
  final Model llmModel;
  final bool ttsEnabled;
  final Set<String> excludedAgents;

  const SettingsState({
    required this.sttProvider,
    required this.llmModel,
    required this.ttsEnabled,
    required this.excludedAgents,
  });

  SettingsState copyWith({
    SttProvider? sttProvider,
    Model? llmModel,
    bool? ttsEnabled,
    Set<String>? excludedAgents,
  }) {
    return SettingsState(
      sttProvider: sttProvider ?? this.sttProvider,
      llmModel: llmModel ?? this.llmModel,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      excludedAgents: excludedAgents ?? this.excludedAgents,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsState &&
          sttProvider == other.sttProvider &&
          llmModel.modelId == other.llmModel.modelId &&
          ttsEnabled == other.ttsEnabled &&
          setEquals(excludedAgents, other.excludedAgents);

  @override
  int get hashCode => Object.hash(
        sttProvider,
        llmModel.modelId,
        ttsEnabled,
        Object.hashAll(excludedAgents.toList()..sort()),
      );
}

final settingsServiceProvider = Provider<SettingsService>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final liveKitServiceProvider = Provider<LiveKitService>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final settings = ref.read(settingsServiceProvider);
    final liveKit = ref.read(liveKitServiceProvider);

    final initial = SettingsState(
      sttProvider: settings.sttProvider,
      llmModel: settings.llmModel,
      ttsEnabled: settings.ttsEnabled,
      excludedAgents: settings.excludedAgents,
    );

    // Sync initial state to LiveKit
    liveKit.setSttProvider(initial.sttProvider);
    liveKit.setLlmModel(initial.llmModel);
    liveKit.setTtsEnabled(initial.ttsEnabled);
    liveKit.setExcludedAgents(initial.excludedAgents);

    return initial;
  }

  void setSttProvider(SttProvider provider) {
    state = state.copyWith(sttProvider: provider);
    ref.read(liveKitServiceProvider).setSttProvider(provider);
    ref.read(settingsServiceProvider).setSttProvider(provider);
  }

  void setLlmModel(Model model) {
    state = state.copyWith(llmModel: model);
    ref.read(liveKitServiceProvider).setLlmModel(model);
    ref.read(settingsServiceProvider).setLlmModel(model);
  }

  void setTtsEnabled(bool enabled) {
    state = state.copyWith(ttsEnabled: enabled);
    ref.read(liveKitServiceProvider).setTtsEnabled(enabled);
    ref.read(settingsServiceProvider).setTtsEnabled(enabled);
  }

  void setExcludedAgents(Set<String> excluded) {
    state = state.copyWith(excludedAgents: excluded);
    ref.read(liveKitServiceProvider).setExcludedAgents(excluded);
    ref.read(settingsServiceProvider).setExcludedAgents(excluded);
  }
}
