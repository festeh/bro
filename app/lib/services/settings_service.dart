import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models_config.dart';
import 'livekit_service.dart';

/// Persists user settings using SharedPreferences.
class SettingsService {
  static const String _keyDeviceId = 'deviceId';
  static const String _keySttProvider = 'sttProvider';
  static const String _keyLlmModelId = 'llmModelId';
  static const String _keyTtsEnabled = 'ttsEnabled';
  static const String _keyExcludedAgents = 'excludedAgents';

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Generate and persist device ID on first launch
    if (_prefs.getString(_keyDeviceId) == null) {
      await _prefs.setString(_keyDeviceId, const Uuid().v4().substring(0, 8));
    }
  }

  // Device ID (persistent, generated once)
  String get deviceId => _prefs.getString(_keyDeviceId)!;

  // STT Provider
  SttProvider get sttProvider {
    final value = _prefs.getString(_keySttProvider);
    if (value == null) return SttProvider.deepgram;
    return SttProvider.values.firstWhere(
      (p) => p.name == value,
      orElse: () => SttProvider.deepgram,
    );
  }

  Future<void> setSttProvider(SttProvider provider) async {
    await _prefs.setString(_keySttProvider, provider.name);
  }

  // LLM Model (stored by modelId)
  Model get llmModel {
    final modelId = _prefs.getString(_keyLlmModelId);
    if (modelId == null) return ModelsConfig.instance.defaultLlm;
    return ModelsConfig.instance.llmModels.firstWhere(
      (m) => m.modelId == modelId,
      orElse: () => ModelsConfig.instance.defaultLlm,
    );
  }

  Future<void> setLlmModel(Model model) async {
    await _prefs.setString(_keyLlmModelId, model.modelId);
  }

  // TTS Enabled
  bool get ttsEnabled {
    return _prefs.getBool(_keyTtsEnabled) ?? true;
  }

  Future<void> setTtsEnabled(bool enabled) async {
    await _prefs.setBool(_keyTtsEnabled, enabled);
  }

  // Excluded Agents (empty = all enabled)
  Set<String> get excludedAgents {
    final list = _prefs.getStringList(_keyExcludedAgents);
    return list?.toSet() ?? {};
  }

  Future<void> setExcludedAgents(Set<String> excluded) async {
    await _prefs.setStringList(_keyExcludedAgents, excluded.toList());
  }
}
