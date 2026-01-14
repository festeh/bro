# Plan: Multi-LLM Provider Support

## Tech Stack

- Language: Python 3.11+ (agent), Dart/Flutter (desktop)
- Framework: langchain-openai (LLM calls), Flutter (UI)
- Storage: None (provider selection is runtime state)
- Testing: pytest

## Structure

Changes to existing files:

```
agent/
├── task_agent.py     # Add provider parameter
├── repl.py           # Add /model command
ai/
├── config.py         # Already has providers (groq, openrouter, chutes, gemini)
desktop/lib/
├── services/
│   └── livekit_service.dart  # Add TaskAgentProvider enum
├── pages/
│   └── chat_page.dart        # Add provider dropdown
```

## Approach

### 1. TaskAgent: Accept provider and model parameters

Current code hardcodes `get_provider_config("chutes")` in two places:
- `_call_llm()` at line 202
- `_get_llm()` at line 219

Change:
- Add `provider: str = "chutes"` to `__init__`
- Add `model: str | None = None` to `__init__` (None = use provider default)
- Store as `self._provider` and `self._model`
- Get config with `get_provider_config(self._provider)`
- Override model if `self._model` is set

### 2. REPL: Add /model command

**Syntax:**
```
/model                        # Show current provider + model
/model <provider> <model>     # Switch to provider with model
```

**Provider aliases:**
- `c` = chutes
- `g` = groq
- `o` = openrouter
- `ge` = gemini

**Examples:**
```
/model c deepseek-ai/DeepSeek-V3-0324
/model g llama-3.3-70b-versatile
/model o meta-llama/llama-3.3-70b-instruct
/model ge gemini-2.0-flash
```

**Behavior:**
- No args: Show current provider and model
- With args: Both provider and model required
- No API key validation on switch (fails on first LLM call if missing)
- Keep conversation history after switch

**Implementation:**
- Store `provider` and `model` in REPL state (not just provider)
- Pass both to TaskAgent (need to modify TaskAgent to accept model override)
- Update `/help` to show syntax and aliases

### 3. Desktop: Add provider dropdown

The desktop already has `LlmModel` enum for voice agent models. Add a separate enum for TaskAgent providers.

In `livekit_service.dart`:
- Add `TaskAgentProvider` enum (groq, openrouter, chutes, gemini)
- Add `_taskAgentProvider` field
- Add `setTaskAgentProvider()` method
- Include in `_updateMetadata()`

In `chat_page.dart`:
- Add dropdown in bottom bar (next to clear button)
- Call `liveKitService.setTaskAgentProvider()` on change

### 4. Voice agent: Read provider from metadata

In `voice_agent.py`:
- Read `task_agent_provider` from participant metadata
- Pass to TaskAgent constructor

## Risks

- API key missing for selected provider: Show clear error message
- Provider API down: Falls back gracefully (existing error handling)

## Open Questions

None. The provider infrastructure already exists in `ai/config.py`.
