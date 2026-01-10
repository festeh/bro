# Research: ASR Cost Optimization

**Feature**: 002-deepgram-cost-optimization
**Date**: 2026-01-10

## Executive Summary

The livekit-agents framework has a well-structured architecture for VAD and STT integration that enables VAD-gated audio transmission **without modifying the core framework**. The existing `StreamAdapter` class demonstrates the exact pattern needed, and Silero VAD provides all necessary configuration options.

## Research Questions Resolved

### 1. Can VAD gating be implemented without framework modifications?

**Decision**: Yes - use AsyncIterable wrapper layer pattern
**Rationale**: The `StreamAdapter` class in livekit-agents already demonstrates VAD-based audio filtering. This pattern wraps the audio stream and yields frames only during speech segments.
**Alternatives Considered**:
- Modifying `push_audio()` with `skip_stt` parameter (rejected: couples gating logic to core audio handling)
- Forking livekit-agents (rejected: maintenance burden)

### 2. How does audio routing work in AudioRecognition?

**Decision**: Audio routes independently to VAD and STT via separate channels
**Rationale**: From `audio_recognition.py:183-189`:
```python
def push_audio(self, frame: rtc.AudioFrame, *, skip_stt: bool = False) -> None:
    if not skip_stt and self._stt_ch is not None:
        self._stt_ch.send_nowait(frame)      # Routes to STT
    if self._vad_ch is not None:
        self._vad_ch.send_nowait(frame)      # Routes to VAD (always)
```
VAD always receives all audio; STT can be selectively gated.

### 3. What VAD configuration supports zero speech loss?

**Decision**: Use Silero VAD with conservative defaults, rely on its built-in pre-roll buffer
**Rationale**: Silero provides tunable parameters:
- `prefix_padding_duration=0.5` (500ms pre-roll buffer - captures speech onset, no custom buffer needed)
- `min_silence_duration=0.3` (300ms silence threshold - spec default)
- `activation_threshold=0.5` (conservative, favors transmission)
**Alternatives Considered**:
- Implementing our own pre-roll buffer (rejected: duplicates Silero's functionality, violates DRY)
- Lower activation_threshold=0.4 (more aggressive, higher speech loss risk)
- Higher min_silence_duration=0.6 (less filtering, defeats cost optimization)

### 4. How should turn duration be tracked?

**Decision**: Use existing VAD event timing infrastructure
**Rationale**: `INFERENCE_DONE` events fire at ~32ms intervals and include:
- `speech_duration` - current speech segment duration
- `timestamp` - relative timestamp in seconds
- `speech_start_time` already tracked in AudioRecognition
**Alternatives Considered**:
- Separate timer independent of VAD (rejected: duplicates existing infrastructure)

### 5. What notification mechanism for frontend?

**Decision**: LiveKit data topic `lk.vad_status` with JSON messages
**Rationale**: Follows existing pattern from `voice_agent.py` using `stream_text()`:
```python
await self._room.local_participant.stream_text(
    topic=TOPIC_VAD_STATUS,
    attributes={...},
)
```
**Alternatives Considered**:
- WebSocket separate channel (rejected: adds complexity)
- Room metadata (rejected: not designed for events)

## Key Technical Findings

### VAD Event System

| Event Type | Frequency | Use Case |
|------------|-----------|----------|
| `START_OF_SPEECH` | On speech onset | Begin transmission, start turn timer |
| `INFERENCE_DONE` | Every ~32ms | Track duration, check limits |
| `END_OF_SPEECH` | On silence confirm | Stop transmission, reset timer |

### Silero VAD Configuration (Recommended)

```python
silero.VAD.load(
    min_speech_duration=0.05,      # 50ms to confirm speech
    min_silence_duration=0.30,     # 300ms silence to end (spec default)
    prefix_padding_duration=0.5,   # 500ms pre-roll buffer
    activation_threshold=0.5,      # Conservative (favor transmission)
    max_buffered_speech=60.0,      # Aligns with turn limit
)
```

### StreamAdapter Pattern (Reference Implementation)

From `livekit-agents/livekit/agents/stt/stream_adapter.py`:
```python
class StreamAdapter(STT):
    def __init__(self, *, stt: STT, vad: VAD):
        self._vad = vad
        self._stt = stt

    # VAD controls when STT receives audio
    async for event in vad_stream:
        if event.type == VADEventType.END_OF_SPEECH:
            merged_frames = utils.merge_frames(event.frames)
            await self._wrapped_stt.recognize(buffer=merged_frames)
```

### Existing Turn Duration Tracking

From `audio_recognition.py:479-487`:
```python
if ev.raw_accumulated_speech > 0.0:
    self._last_speaking_time = time.time()
    if self._speech_start_time is None:
        self._speech_start_time = time.time()
```

Infrastructure exists - just needs limit enforcement.

## Architecture Decision

### Recommended: Extend RecognitionHooks (DRY Approach)

```
Room Audio
    ↓
push_audio(skip_stt=!speaking)  ← Controlled by hooks
    ├→ VAD Channel (always)
    └→ STT Channel (only when speaking)
    ↓
RecognitionHooks callbacks:
├→ on_start_of_speech: enable STT, start metrics
├→ on_vad_inference_done: check turn duration, send warnings
├→ on_end_of_speech: log metrics, reset state
    ↓
STT Provider (receives filtered audio)
```

**Advantages**:
1. Zero modifications to livekit-agents framework
2. Uses existing infrastructure (no duplicate state tracking)
3. Provider-agnostic (works with Deepgram, ElevenLabs, future providers)
4. DRY-compliant (leverages `_speaking`, `_speech_start_time`)
5. No new modules needed - extends existing `voice_agent.py`
6. Testable via hook mocking

## Metrics Collection Schema

```python
@dataclass
class VADGatingMetrics:
    session_id: str
    asr_provider: str
    total_audio_duration: float      # All audio received
    transmitted_duration: float      # Audio sent to STT
    filtered_duration: float         # Silence not sent
    turns_completed: int             # Natural turn endings
    turns_terminated: int            # Duration limit enforced
    speech_segments: int             # Number of speech segments
```

## Frontend Notification Schema

```json
// Turn warning (at 55 seconds)
{
    "type": "turn_warning",
    "remaining_seconds": 5,
    "turn_id": "turn_abc123"
}

// Turn termination (at 60 seconds)
{
    "type": "turn_terminated",
    "reason": "max_duration",
    "turn_id": "turn_abc123",
    "final_duration": 62.1
}

// Connection failure
{
    "type": "asr_connection_failed",
    "buffered_seconds": 5.0,
    "action": "discarded"
}
```

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Speech clipping at turn boundaries | Medium | High | 2s grace period (FR-012) |
| VAD misclassifies speech as silence | Low | High | Conservative thresholds (FR-011) |
| Silero pre-roll buffer insufficient | Very Low | Medium | 500ms default is generous; adjustable via `prefix_padding_duration` |
| Turn timer drift | Low | Low | Use wall clock, not accumulated duration |
| Frontend misses notification | Low | Medium | Include turn_id for reconciliation |

## Dependencies Confirmed

| Dependency | Version | Purpose |
|------------|---------|---------|
| livekit-agents | 0.12+ | Core agent framework |
| livekit-plugins-silero | 0.6+ | Silero VAD model |
| livekit-plugins-deepgram | Latest | Deepgram STT |
| livekit-plugins-elevenlabs | Latest | ElevenLabs STT |

No new dependencies required.
