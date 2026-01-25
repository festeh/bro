import 'package:shared_preferences/shared_preferences.dart';

import '../models/models_config.dart';
import 'livekit_service.dart';

/// Persists user settings using SharedPreferences.
class SettingsService {
  static const String _keySttProvider = 'sttProvider';
  static const String _keyLlmModelId = 'llmModelId';
  static const String _keyTtsEnabled = 'ttsEnabled';

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

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
}
