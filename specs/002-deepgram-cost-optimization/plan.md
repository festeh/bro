# Implementation Plan: ASR Cost Optimization

**Branch**: `001-deepgram-cost-optimization` | **Date**: 2026-01-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-deepgram-cost-optimization/spec.md`

## Summary

Implement VAD-gated audio transmission to reduce ASR costs by filtering silence before sending to any ASR provider (Deepgram, ElevenLabs). Add 60-second turn duration limits with frontend notifications via LiveKit data topics. The VAD filtering layer sits above the STT provider abstraction, making it provider-agnostic.

## Technical Context

**Language/Version**: Python 3.12+ with type hints
**Primary Dependencies**: livekit-agents, livekit-plugins-silero (VAD), livekit-plugins-deepgram, livekit-plugins-elevenlabs
**Storage**: N/A (stateless audio filtering)
**Testing**: pytest with mocked audio streams
**Target Platform**: Linux server (LiveKit agent deployment)
**Project Type**: Backend service (voice agent)
**Performance Goals**: <50ms latency from speech onset to ASR transmission; zero speech loss
**Constraints**: Pre-roll buffer 200-300ms; 5s connection failure buffer; 60s max turn duration
**Scale/Scope**: Real-time audio processing; typical sessions 5-15 minutes with natural pauses

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Modular Services** | PASS | VAD gating is a separate concern; implemented as wrapper layer without coupling to STT internals |
| **II. Type Safety** | PASS | All new code will have type hints; use mypy --strict |
| **III. DRY with Pragmatism** | PASS | Single VAD gating implementation shared across all ASR providers |
| **IV. Structured Logging** | PASS | Metrics logged in JSON format with existing pattern; includes filtered/transmitted durations |
| **V. Break Things First** | PASS | No backwards compatibility needed; can modify audio flow directly |

## Project Structure

### Documentation (this feature)

```text
specs/002-deepgram-cost-optimization/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (LiveKit data topic schemas)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
agent/
├── voice_agent.py       # Extend hooks for VAD gating + turn limits
├── constants.py         # Add new topic: TOPIC_VAD_STATUS
└── requirements.txt     # Dependencies (no changes expected)

desktop/lib/
├── constants/
│   └── livekit_constants.dart  # Add vadStatus topic constant
└── services/
    └── livekit_service.dart    # Add VAD notification handler
```

**Structure Decision**: Extend existing `voice_agent.py` with hook implementations. No new modules needed - all logic fits in existing hooks pattern. Frontend receives notifications via existing LiveKit text stream pattern.

## Complexity Tracking

> No constitution violations - table not needed.

## Implementation Approach

### Audio Flow (Current → Proposed)

```text
CURRENT:
Room Audio → push_audio() → STT Channel (all audio) → Deepgram/ElevenLabs

PROPOSED:
Room Audio → push_audio(skip_stt=!speaking) → [if speech] → STT Channel → Deepgram/ElevenLabs
                                            → [if silence] → skip STT (log metrics)
         ↑
         └── Controlled by RecognitionHooks callbacks (on_start_of_speech, on_end_of_speech)
```

### Key Integration Points

1. **Extend RecognitionHooks**: Implement turn limit and notification logic in existing hook callbacks
2. **Use existing state**: Leverage `_speaking`, `_speech_start_time` already in AudioRecognition
3. **Use `skip_stt` parameter**: Already exists in `push_audio()` - just need to control it
4. **Notification Topic**: New `lk.vad_status` topic for warnings/terminations
5. **Metrics Extension**: Add filtered_duration, transmitted_duration to existing STT metrics pattern

### DRY Compliance

| What | Existing Infrastructure | Our Addition |
|------|------------------------|--------------|
| Speaking state | `AudioRecognition._speaking` | None needed |
| Turn start time | `AudioRecognition._speech_start_time` | None needed |
| VAD events | `RecognitionHooks` callbacks | Turn limit logic |
| Audio gating | `push_audio(skip_stt=...)` | Control flag |
| Pre-roll buffer | Silero `prefix_padding_duration` | None needed |

### Existing Patterns to Follow

- **Prewarm pattern**: VAD already preloaded via `silero.VAD.load()`
- **Factory pattern**: STT provider selection via `create_stt(provider)`
- **Event pattern**: Metrics via `session.stt.on("metrics_collected", callback)`
- **Text stream pattern**: Notifications via `stream_text(topic=..., attributes={...})`
- **Hooks pattern**: Extend `RecognitionHooks` for custom behavior
