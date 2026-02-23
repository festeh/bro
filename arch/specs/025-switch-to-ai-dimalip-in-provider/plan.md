# Plan: Switch to ai.dimalip.in LLM Provider

## Tech Stack

- Language: Python (agent), Dart (Flutter app)
- Framework: livekit-agents + LangChain (Python), Flutter + Riverpod (Dart)
- External: CLIProxyAPI at `https://ai.dimalip.in` (OpenAI-compatible)
- Storage: SharedPreferences (cached model list)

## What Changes

Replace multi-provider LLM setup (Groq, Kimi, OpenRouter, Gemini with separate API keys) with a single provider: `ai.dimalip.in`. Replace hardcoded model list with a dynamic list fetched from `/v1/models`. ASR and TTS providers stay the same.

## Structure

Files to change:

```
my-agents/
├── models.json                          # Remove LLM providers + models, keep ASR/TTS
├── my_agents/models_config.py           # Simplify: single base_url + API key for LLM

bro/
├── agent/settings.py                    # Simplify create_llm(): no provider lookup
├── app/lib/models/models_config.dart    # Fetch models from API, cache, default to "default"
├── app/lib/services/settings_service.dart  # Handle unknown model IDs gracefully
├── app/lib/providers/settings_provider.dart # Refresh model list on startup
├── app/lib/widgets/app_sidebar.dart     # Use dynamic model list
├── app/lib/pages/wear_settings_page.dart   # Use dynamic model list
├── app/lib/main.dart                    # Trigger async model fetch
├── app/assets/models.json               # Remove (no longer bundled)
├── app/pubspec.yaml                     # Remove models.json asset
├── justfile                             # Remove sync-models step
├── .env                                 # Add AI_API_KEY, AI_BASE_URL
```

## Approach

### 1. Simplify `my-agents/models.json`

Remove LLM providers and models. Keep only ASR and TTS entries (Deepgram, ElevenLabs are separate services, not proxied through ai.dimalip.in).

### 2. Rewrite `my_agents/models_config.py` LLM section

- Remove `Provider` dataclass and all provider-related code for LLM
- LLM config becomes two env vars: `AI_BASE_URL` (default `https://ai.dimalip.in/v1`) and `AI_API_KEY`
- `create_chat_llm(model_id)` passes model_id directly to ChatOpenAI with the single base_url + api_key
- `get_llm_by_model_id()` no longer needed for resolution — just return a simple Model with the id
- Keep ASR/TTS config loading from models.json as-is

### 3. Simplify `bro/agent/settings.py`

- `create_llm(model_id)` uses ai.dimalip.in directly: `openai.LLM(model=model_id, base_url=AI_BASE_URL, api_key=AI_API_KEY)`
- No extra_headers, no extra_body, no provider lookup
- Default model becomes `"default"` (string) instead of looking up first model from JSON

### 4. Rewrite `models_config.dart` with async model fetching

Replace the static asset-loading singleton with a dynamic model list:

- **Default state**: single model `Model(id: "default", name: "default")`
- **On app start**: fire-and-forget HTTP GET to `https://ai.dimalip.in/v1/models`
- **On success**: update model list, save to SharedPreferences as JSON cache
- **On failure**: use cached list from SharedPreferences, or fall back to default
- **API key**: pass via `--dart-define=AI_API_KEY=...` (same as LIVEKIT keys)
- **Base URL**: pass via `--dart-define=AI_BASE_URL=https://ai.dimalip.in/v1` (with localhost default for dev)

The `/v1/models` response format (standard OpenAI):
```json
{"data": [{"id": "model-name", "owned_by": "provider"}, ...], "object": "list"}
```

Map each entry to `Model(id: data.id, name: data.id, ownedBy: data.owned_by)`.
Show all models — no filtering. Group by `owned_by` in the UI.

### 5. Update `settings_service.dart`

- `llmModel` getter returns stored model_id string (not Model object lookup)
- If stored model_id is not in current list, keep it (the proxy still accepts it)
- Default to `"default"` instead of looking up `ModelsConfig.instance.defaultLlm`

### 6. Update `settings_provider.dart`

- Trigger model list refresh on build (non-blocking)
- Listen to model list updates to refresh state

### 7. Update UI widgets

**app_sidebar.dart**: Replace `_SettingDropdown<Model>` with a popup menu button.
- Tap opens a `PopupMenuButton` or `showMenu()` anchored to the LLM selector area.
- Popup is wider than sidebar (anchored right edge, grows left).
- Models grouped by `owned_by` field with sticky section headers.
- "default" model shown at top, outside any group.
- Within each group, models sorted alphabetically by display name.
- Display names: strip known prefixes (`deepseek-ai/`, `moonshotai/`, etc.) and `-TEE` suffix for readability.
- Selected model highlighted with accent color.

**wear_settings_page.dart**: Keep tap-to-cycle but cycle within current group, long-press to switch group. Or simpler: just cycle through flat list (26 taps worst case, but in practice user picks one and sticks with it).

### 8. Update `main.dart` and `justfile`

- Remove `await ModelsConfig.load()` (sync asset load) — replace with `ModelsConfig.init()` that sets default and triggers async fetch
- Remove `sync-models` from justfile targets
- Remove `app/assets/models.json` from pubspec.yaml and .gitignore
- Add `AI_API_KEY` and `AI_BASE_URL` to `--dart-define` in justfile build commands

### 9. Update `.env` files

- Add `AI_API_KEY` and `AI_BASE_URL` to `bro/.env` and `my-agents/.env`
- Old per-provider LLM keys (GROQ_API_KEY, KIMI_API_KEY, OPENROUTER_API_KEY, GEMINI_API_KEY) can be removed from my-agents

## Risks

- **Proxy down**: App falls back to cached model list or "default". Agent side: if ai.dimalip.in is down, LLM calls fail regardless of model list — same as any single-provider setup.
- **Saved model ID becomes invalid**: User had "qwen/qwen3-32b" saved from old config. The proxy still accepts it (Groq upstream), so it still works. No migration needed.

## Decisions Made

- **Show all models**: No filtering. All 26 models from `/v1/models` shown, grouped by `owned_by`.
- **Desktop menu**: Popup menu anchored to sidebar LLM area, with provider group headers.
- **Wear menu**: Keep tap-to-cycle through flat list.
