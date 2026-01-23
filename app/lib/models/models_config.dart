/// Centralized model configuration loaded from models.json asset.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Provider configuration.
class Provider {
  final String name;
  final String? baseUrl;
  final String apiKeyEnv;

  const Provider({
    required this.name,
    this.baseUrl,
    required this.apiKeyEnv,
  });

  factory Provider.fromJson(String name, Map<String, dynamic> json) {
    return Provider(
      name: name,
      baseUrl: json['base_url'] as String?,
      apiKeyEnv: json['api_key_env'] as String,
    );
  }
}

/// Model configuration.
class Model {
  final String name;
  final String provider;
  final String modelId;

  const Model({
    required this.name,
    required this.provider,
    required this.modelId,
  });

  factory Model.fromJson(Map<String, dynamic> json) {
    return Model(
      name: json['name'] as String,
      provider: json['provider'] as String,
      modelId: json['model_id'] as String,
    );
  }

  /// Display name with provider prefix.
  String get displayName => '$provider/$name';
}

/// Singleton holding loaded model configuration.
class ModelsConfig {
  static ModelsConfig? _instance;

  final Map<String, Provider> providers;
  final List<Model> llmModels;
  final List<Model> asrModels;
  final List<Model> ttsModels;

  ModelsConfig._({
    required this.providers,
    required this.llmModels,
    required this.asrModels,
    required this.ttsModels,
  });

  /// Load configuration from asset. Call once at app startup.
  static Future<void> load() async {
    if (_instance != null) return;

    final jsonString = await rootBundle.loadString('assets/models.json');
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    // Parse providers
    final providersJson = json['providers'] as Map<String, dynamic>;
    final providers = <String, Provider>{};
    for (final entry in providersJson.entries) {
      providers[entry.key] = Provider.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
    }

    // Parse models
    final llmJson = json['llm'] as List<dynamic>;
    final llmModels = llmJson
        .map((m) => Model.fromJson(m as Map<String, dynamic>))
        .toList();

    final asrJson = json['asr'] as List<dynamic>;
    final asrModels = asrJson
        .map((m) => Model.fromJson(m as Map<String, dynamic>))
        .toList();

    final ttsJson = json['tts'] as List<dynamic>;
    final ttsModels = ttsJson
        .map((m) => Model.fromJson(m as Map<String, dynamic>))
        .toList();

    _instance = ModelsConfig._(
      providers: providers,
      llmModels: llmModels,
      asrModels: asrModels,
      ttsModels: ttsModels,
    );
  }

  /// Get the loaded instance. Throws if not loaded.
  static ModelsConfig get instance {
    if (_instance == null) {
      throw StateError('ModelsConfig not loaded. Call ModelsConfig.load() first.');
    }
    return _instance!;
  }

  /// Get provider by name.
  Provider getProvider(String name) {
    final provider = providers[name];
    if (provider == null) {
      throw ArgumentError('Unknown provider: $name');
    }
    return provider;
  }

  /// Get LLM model by index, wrapping around.
  Model getLlmByIndex(int index) {
    return llmModels[index % llmModels.length];
  }

  /// Get default LLM model (first in list).
  Model get defaultLlm => llmModels.first;

  /// Get default ASR model (first in list).
  Model get defaultAsr => asrModels.first;

  /// Get default TTS model (first in list).
  Model get defaultTts => ttsModels.first;
}
