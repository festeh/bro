# Standardize Model Configuration

## Problem

Model definitions for LLM, ASR, and TTS are scattered across multiple files:
- Desktop app (Dart enums + display names in sidebar)
- Test stand (Python dataclass list)
- Voice agent (Python dict mappings)
- Config (Python provider presets)

When adding or changing models, developers must update multiple files. This leads to drift and inconsistencies.

## Solution

Single JSON file (`models.json`) at repo root containing all LLM, ASR, and TTS configurations.

**Consumers:**
- Python (test stand, voice agent) - reads file directly
- Dart (desktop) - bundles copy as asset at build time

## What Users Can Do

1. **Add a new model**
   Developer adds model to `models.json`. All apps pick it up.
   - Works when: Model appears in desktop dropdown, test stand list, and voice agent
   - Fails when: Required fields missing (show clear error on load)

2. **Remove a model**
   Developer removes model from `models.json`. All apps stop showing it.
   - Works when: Model disappears from all UIs
   - Fails when: App references removed model (graceful fallback to default)

3. **View available models**
   Desktop and test stand show consistent model list from same source.
   - Works when: Both apps show same models in same order

## Requirements

- [ ] Single `models.json` file at repo root
- [ ] Contains LLM, ASR (speech-to-text), and TTS sections
- [ ] Each model has: name (display), provider, model_id (API identifier)
- [ ] Provider info: base_url, api_key_env (env var name, not actual key)
- [ ] Desktop bundles copy as asset, no API keys in app
- [ ] Python loads file at runtime
- [ ] Adding a model requires changing only `models.json`

## File Structure

```json
{
  "providers": {
    "chutes": {
      "base_url": "https://llm.chutes.ai/v1",
      "api_key_env": "CHUTES_API_KEY"
    },
    "groq": {
      "base_url": "https://api.groq.com/openai/v1",
      "api_key_env": "GROQ_API_KEY"
    }
  },
  "llm": [
    {
      "name": "DeepSeek V3",
      "provider": "chutes",
      "model_id": "deepseek-ai/DeepSeek-V3-0324"
    }
  ],
  "asr": [
    {
      "name": "Deepgram Nova 2",
      "provider": "deepgram",
      "model_id": "nova-2"
    }
  ],
  "tts": [
    {
      "name": "ElevenLabs Turbo",
      "provider": "elevenlabs",
      "model_id": "eleven_turbo_v2"
    }
  ]
}
```
