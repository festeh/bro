# Plan: Standardize Model Configuration

**Spec**: specs/010-standardize-llm-model-list/spec.md

## Tech Stack

- Config format: JSON
- Python: dataclass + json loader
- Dart: json asset + model class
- Testing: pytest (Python), flutter test (Dart)

## Structure

Files to create/modify:

```
bro/
├── models.json                          # NEW: single source of truth
├── justfile                             # MODIFY: add sync-models task
├── ai/
│   └── models_config.py                 # NEW: Python loader
├── agent/
│   ├── teststand/
│   │   └── models.py                    # MODIFY: use models_config
│   └── voice_agent.py                   # MODIFY: use models_config
└── desktop/
    ├── assets/
    │   └── models.json                  # GENERATED: .gitignored, copied by justfile
    └── lib/
        ├── models/
        │   └── models_config.dart       # NEW: Dart loader
        ├── services/
        │   └── livekit_service.dart     # MODIFY: remove enums
        └── widgets/
            └── app_sidebar.dart         # MODIFY: use loaded models
```

## Approach

1. **Create `models.json` at repo root**
   Populate with all current LLM, ASR, TTS models from existing code.

2. **Create Python loader (`ai/models_config.py`)**
   - Load JSON file once at import
   - Dataclasses: `Provider`, `Model`, `ModelsConfig`
   - Helper: `get_llm_models()`, `get_provider(name)`
   - Read API key from env using `api_key_env` field

3. **Update test stand (`agent/teststand/models.py`)**
   - Import from `ai.models_config`
   - Remove hardcoded `MODELS` list
   - Keep `get_model_by_index()` and `get_default_model()` wrappers

4. **Update voice agent (`agent/voice_agent.py`)**
   - Import from `ai.models_config`
   - Remove `LLM_MODELS` dict
   - Lookup model by name from config

5. **Justfile task for asset sync**
   - Add `sync-models` task to justfile
   - Make `desktop`, `desktop-build` depend on `sync-models`
   - Add `desktop/assets/models.json` to `.gitignore`
   - Add to `pubspec.yaml` assets

6. **Create Dart loader (`desktop/lib/models/models_config.dart`)**
   - Load JSON from assets at app start
   - Classes: `Provider`, `LlmModel`, `AsrModel`, `TtsModel`
   - Singleton or provider pattern for access

7. **Update desktop UI**
   - Remove `LlmModel` enum from `livekit_service.dart`
   - Update `app_sidebar.dart` to use loaded models
   - Build dropdowns from model lists

## Tasks

1. Create `models.json` with all current models
2. Create `ai/models_config.py` Python loader
3. Update `agent/teststand/models.py` to use loader
4. Update `agent/voice_agent.py` to use loader
5. Remove old `ai/config.py` provider presets (merged into models.json)
6. Add `sync-models` task to justfile, make desktop tasks depend on it
7. Add `desktop/assets/models.json` to `.gitignore`
8. Create `desktop/lib/models/models_config.dart`
9. Update `livekit_service.dart` - remove enums
10. Update `app_sidebar.dart` - use loaded models

## Risks

- **JSON parse errors**: Validate JSON on load, fail fast with clear error message
- **Missing env vars**: Log warning, skip model if API key missing
- **Raw flutter commands bypass sync**: Document to always use `just desktop`
