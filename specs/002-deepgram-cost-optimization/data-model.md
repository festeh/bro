# Data Model: ASR Cost Optimization

**Feature**: 002-deepgram-cost-optimization
**Date**: 2026-01-10

## Entities

### VADGatingState

Minimal state for turn limit enforcement. Most state is reused from `AudioRecognition`.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `session_id` | `str` | Voice session identifier | New |
| `speaking` | `bool` | Whether speech is detected | **Reuse**: `AudioRecognition._speaking` |
| `turn_id` | `str \| None` | Current turn identifier | New |
| `turn_start_time` | `float \| None` | When turn started | **Reuse**: `AudioRecognition._speech_start_time` |
| `warning_sent` | `bool` | Whether 55s warning sent | New |
| `asr_provider` | `str` | Current ASR provider | From session settings |

**New fields only**: `session_id`, `turn_id`, `warning_sent` - everything else reused from existing infrastructure.

**State Transitions** (managed by existing hooks):
```
on_start_of_speech → speaking=True, generate turn_id
on_vad_inference_done → check duration, maybe send warning
on_end_of_speech → speaking=False, reset warning_sent
```

### VADGatingMetrics

Accumulated metrics for a voice session.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `session_id` | `str` | Voice session identifier | UUID format |
| `asr_provider` | `str` | ASR provider used | "deepgram" \| "elevenlabs" |
| `total_audio_duration` | `float` | Total audio received from room | Seconds |
| `transmitted_duration` | `float` | Audio sent to STT provider | Seconds |
| `filtered_duration` | `float` | Silence not transmitted | Seconds (total - transmitted) |
| `speech_segments` | `int` | Number of speech segments detected | >= 0 |
| `turns_completed` | `int` | Turns ended naturally (END_OF_SPEECH) | >= 0 |
| `turns_terminated` | `int` | Turns ended by duration limit | >= 0 |
| `session_start_time` | `float` | When session began | Unix timestamp |

**Derived Metrics**:
- `filtering_ratio = filtered_duration / total_audio_duration`
- `cost_savings_estimate = filtered_duration * rate_per_second`

### VADNotification

Message sent to frontend via LiveKit data topic.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `type` | `str` | Notification type | Enum: see below |
| `turn_id` | `str` | Associated turn identifier | UUID format |
| `timestamp` | `float` | When notification was generated | Unix timestamp |
| `payload` | `dict` | Type-specific data | Varies by type |

**Notification Types**:

| Type | Payload Fields | Description |
|------|----------------|-------------|
| `turn_warning` | `remaining_seconds: int` | Approaching duration limit |
| `turn_terminated` | `reason: str, final_duration: float` | Turn ended by limit |
| `asr_connection_failed` | `buffered_seconds: float, action: str` | ASR connection dropped |

### AudioBuffer

Temporary buffer for connection failure recovery.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `frames` | `list[AudioFrame]` | Buffered audio frames | Max 5s worth |
| `buffer_start_time` | `float` | When buffering began | Unix timestamp |
| `max_buffer_duration` | `float` | Maximum buffer duration | 5.0 seconds |

**Lifecycle**:
1. Created on ASR connection failure
2. Accumulates frames during reconnection attempt
3. Flushed to STT on successful reconnection
4. Discarded (with notification) if reconnection fails within 5s

## Relationships

```
┌─────────────────┐
│  VoiceSession   │
│  (from spec)    │
└────────┬────────┘
         │ 1:1
         ▼
┌─────────────────┐      ┌─────────────────┐
│ VADGatingState  │──────│ VADGatingMetrics│
│ (per session)   │ 1:1  │ (accumulator)   │
└────────┬────────┘      └─────────────────┘
         │ 1:N
         ▼
┌─────────────────┐
│ VADNotification │
│ (emitted events)│
└─────────────────┘
```

## Validation Rules

### VADGatingState

1. `turn_id` MUST be generated on `on_start_of_speech` callback
2. `turn_id` MUST be cleared on `on_end_of_speech` callback
3. `warning_sent` MUST reset to False on new turn
4. State relies on `AudioRecognition._speaking` and `._speech_start_time` (not duplicated)

### VADGatingMetrics

1. `filtered_duration` MUST equal `total_audio_duration - transmitted_duration`
2. `turns_completed + turns_terminated` MUST equal total turns processed
3. `transmitted_duration` MUST be <= `total_audio_duration`

### VADNotification

1. `turn_warning` MUST only be sent once per turn
2. `turn_terminated` MUST include `final_duration` > 60s
3. All notifications MUST include valid `turn_id`

## Configuration Entity

### VADGatingConfig

Runtime configuration for the VAD gating layer.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_turn_duration` | `float` | 60.0 | Maximum turn duration in seconds |
| `warning_threshold` | `float` | 55.0 | When to send warning notification |
| `grace_period` | `float` | 2.0 | Allow completion at boundary |
| `min_silence_duration` | `float` | 0.3 | Silence threshold (seconds) |
| `connection_buffer_max` | `float` | 5.0 | Max buffer on connection failure |
| `notification_topic` | `str` | "lk.vad_status" | LiveKit data topic for notifications |

## Type Definitions (Python)

```python
from dataclasses import dataclass
from typing import Literal
from livekit import rtc

NotificationType = Literal["turn_warning", "turn_terminated", "asr_connection_failed"]
ASRProvider = Literal["deepgram", "elevenlabs"]

@dataclass
class VADGatingConfig:
    max_turn_duration: float = 60.0
    warning_threshold: float = 55.0
    grace_period: float = 2.0
    min_silence_duration: float = 0.3
    connection_buffer_max: float = 5.0
    notification_topic: str = "lk.vad_status"

@dataclass
class VADGatingState:
    """Minimal state - most fields reused from AudioRecognition."""
    session_id: str
    turn_id: str | None = None      # New: generated on speech start
    warning_sent: bool = False       # New: track if 55s warning sent
    asr_provider: ASRProvider = "deepgram"
    # Reused from AudioRecognition (not stored here):
    # - speaking: bool (_speaking)
    # - turn_start_time: float (_speech_start_time)

@dataclass
class VADGatingMetrics:
    session_id: str
    asr_provider: ASRProvider
    total_audio_duration: float = 0.0
    transmitted_duration: float = 0.0
    filtered_duration: float = 0.0
    speech_segments: int = 0
    turns_completed: int = 0
    turns_terminated: int = 0
    session_start_time: float = 0.0

@dataclass
class VADNotification:
    type: NotificationType
    turn_id: str
    timestamp: float
    payload: dict
```
