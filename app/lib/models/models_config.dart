/// Dynamic model configuration fetched from AI API.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _cacheKey = 'cached_llm_models';
const _defaultModel = LlmModel(id: 'default', name: 'default', ownedBy: '');

const _aiBaseUrl = String.fromEnvironment(
  'AI_BASE_URL',
  defaultValue: 'https://ai.dimalip.in/v1',
);

const _aiApiKey = String.fromEnvironment('AI_API_KEY', defaultValue: '');

/// Single LLM model from /v1/models.
class LlmModel {
  final String id;
  final String name;
  final String ownedBy;

  const LlmModel({
    required this.id,
    required this.name,
    required this.ownedBy,
  });

  factory LlmModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return LlmModel(
      id: id,
      name: _displayName(id),
      ownedBy: json['owned_by'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'owned_by': ownedBy,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LlmModel && id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// Clean up model ID for display: strip known prefixes and -TEE suffix.
  static String _displayName(String id) {
    var name = id;
    // Strip org prefixes like "deepseek-ai/", "moonshotai/", etc.
    final slash = name.lastIndexOf('/');
    if (slash >= 0) {
      name = name.substring(slash + 1);
    }
    // Strip -TEE suffix
    if (name.endsWith('-TEE')) {
      name = name.substring(0, name.length - 4);
    }
    return name;
  }
}

/// Groups models by owned_by for display.
class ModelGroup {
  final String provider;
  final List<LlmModel> models;

  const ModelGroup({required this.provider, required this.models});
}

/// Singleton holding the dynamic model list.
/// Call [init] at startup, then [refresh] fires in the background.
class ModelsConfig extends ChangeNotifier {
  static ModelsConfig? _instance;

  List<LlmModel> _llmModels = [_defaultModel];

  ModelsConfig._();

  static ModelsConfig get instance {
    _instance ??= ModelsConfig._();
    return _instance!;
  }

  /// All available LLM models.
  List<LlmModel> get llmModels => _llmModels;

  /// Default model.
  LlmModel get defaultLlm => _llmModels.first;

  /// Get model by ID, or null if not found.
  LlmModel? getLlmById(String id) {
    for (final m in _llmModels) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Models grouped by owned_by, sorted. "default" model at top as its own group.
  List<ModelGroup> get groupedModels {
    final groups = <String, List<LlmModel>>{};
    final topLevel = <LlmModel>[];

    for (final m in _llmModels) {
      if (m.id == 'default') {
        topLevel.add(m);
      } else if (m.ownedBy.isNotEmpty) {
        groups.putIfAbsent(m.ownedBy, () => []).add(m);
      } else {
        topLevel.add(m);
      }
    }

    final result = <ModelGroup>[];

    if (topLevel.isNotEmpty) {
      result.add(ModelGroup(provider: '', models: topLevel));
    }

    final sortedKeys = groups.keys.toList()..sort();
    for (final key in sortedKeys) {
      final models = groups[key]!..sort((a, b) => a.name.compareTo(b.name));
      result.add(ModelGroup(provider: key, models: models));
    }

    return result;
  }

  /// Initialize with cached data, then trigger background refresh.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      try {
        final list = (jsonDecode(cached) as List)
            .map((e) => LlmModel.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          _llmModels = list;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Failed to load cached models: $e');
      }
    }

    // Fire-and-forget refresh
    refresh();
  }

  /// Fetch model list from API and update cache.
  Future<void> refresh() async {
    try {
      final uri = Uri.parse('$_aiBaseUrl/models');
      final response = await http.get(uri, headers: {
        if (_aiApiKey.isNotEmpty) 'Authorization': 'Bearer $_aiApiKey',
      });

      if (response.statusCode != 200) {
        debugPrint('Models API returned ${response.statusCode}');
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>;

      final models = data
          .map((e) => LlmModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

      // Ensure "default" is always first
      final defaultIdx = models.indexWhere((m) => m.id == 'default');
      if (defaultIdx > 0) {
        final d = models.removeAt(defaultIdx);
        models.insert(0, d);
      } else if (defaultIdx < 0) {
        models.insert(0, _defaultModel);
      }

      _llmModels = models;
      notifyListeners();

      // Cache
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(models.map((m) => m.toJson()).toList());
      await prefs.setString(_cacheKey, encoded);
    } catch (e) {
      debugPrint('Failed to fetch models: $e');
    }
  }
}
