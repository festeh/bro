# Quickstart: ASR Cost Optimization

**Feature**: 002-deepgram-cost-optimization

## Overview

This feature adds VAD-gated audio transmission to reduce ASR costs by filtering silence before sending to any ASR provider. It also enforces a 60-second turn duration limit with frontend notifications.

## Prerequisites

- Python 3.12+
- Existing voice agent setup (`agent/voice_agent.py`)
- LiveKit room connection
- Silero VAD already configured (via `prewarm()`)

## Quick Integration

### 1. Add Constants

In `agent/constants.py`:
```python
# VAD notification topic
TOPIC_VAD_STATUS = "lk.vad_status"
```

### 2. Extend Recognition Hooks

In `agent/voice_agent.py`, extend the existing agent to handle VAD gating:
```python
# Track turn state (minimal - reuse AudioRecognition state)
self._turn_id: str | None = None
self._warning_sent: bool = False

def on_start_of_speech(self, ev: vad.VADEvent) -> None:
    self._turn_id = f"turn_{uuid.uuid4().hex[:8]}"
    self._warning_sent = False
    # AudioRecognition already sets _speaking=True, _speech_start_time

def on_vad_inference_done(self, ev: vad.VADEvent) -> None:
    if self._speaking and self._speech_start_time:
        elapsed = time.time() - self._speech_start_time
        if elapsed >= 55.0 and not self._warning_sent:
            await self._send_vad_notification("turn_warning", remaining_seconds=5)
            self._warning_sent = True
        if elapsed >= 60.0:
            await self._send_vad_notification("turn_terminated", reason="max_duration")
            # Trigger turn end

def on_end_of_speech(self, ev: vad.VADEvent) -> None:
    self._warning_sent = False
    # Log metrics
```

### 3. Add Notification Helper

```python
async def _send_vad_notification(self, msg_type: str, **payload) -> None:
    if not self._room:
        return
    msg = json.dumps({"type": msg_type, "turn_id": self._turn_id, **payload})
    writer = await self._room.local_participant.stream_text(topic=TOPIC_VAD_STATUS)
    await writer.write(msg)
    await writer.aclose()
```

### 4. Handle Frontend Notifications

In `desktop/lib/services/livekit_service.dart`:
```dart
_room!.registerTextStreamHandler(
    'lk.vad_status',
    _onVadNotification,
);

void _onVadNotification(TextStreamReader reader, String participantId) {
    reader.listen((chunk) {
        final json = jsonDecode(utf8.decode(chunk.content.toList()));
        switch (json['type']) {
            case 'turn_warning':
                // Show "5 seconds remaining" UI
                break;
            case 'turn_terminated':
                // Show "Turn ended" feedback
                break;
        }
    });
}
```

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `max_turn_duration` | 60.0 | Maximum turn duration (seconds) |
| `warning_threshold` | 55.0 | When to send warning (seconds) |
| `grace_period` | 2.0 | Grace period at limit (seconds) |
| `min_silence_duration` | 0.3 | Silence threshold (seconds) |
| `connection_buffer_max` | 5.0 | Max buffer on connection failure (seconds) |

## Verification

### Check Filtering is Working

Review agent logs for metrics:
```
VAD gating: session=abc123 total=120.5s transmitted=72.3s filtered=48.2s ratio=40%
```

### Verify Turn Limits

Speak continuously for 60+ seconds:
1. At 55s: Frontend should receive `turn_warning` notification
2. At 60s: Frontend should receive `turn_terminated` notification
3. Agent stops sending audio to STT

### Verify Zero Speech Loss

Compare transcripts with and without VAD gating:
- Word accuracy should be within 2% of baseline
- No clipped words at speech boundaries

## Troubleshooting

### Audio Not Being Filtered

- Check VAD is loaded in `prewarm()`
- Verify `min_silence_duration` threshold (default 300ms)
- Check logs for VAD event callbacks

### Notifications Not Received

- Verify frontend registers handler for `lk.vad_status` topic
- Check LiveKit data channel is connected
- Verify JSON parsing in frontend handler

### Speech Clipping

- Increase Silero's `prefix_padding_duration` in VAD config (default 500ms)
- Decrease `min_silence_duration` threshold
- Check `activation_threshold` is not too high (default 0.5)

## Metrics Reference

Logged at session end:
```json
{
    "session_id": "abc123",
    "asr_provider": "deepgram",
    "total_audio_duration": 120.5,
    "transmitted_duration": 72.3,
    "filtered_duration": 48.2,
    "filtering_ratio": 0.40,
    "speech_segments": 15,
    "turns_completed": 14,
    "turns_terminated": 1
}
```

## Related Files

| File | Purpose |
|------|---------|
| `agent/voice_agent.py` | Hook implementations for VAD gating + turn limits |
| `agent/constants.py` | Topic constants (TOPIC_VAD_STATUS) |
| `desktop/lib/services/livekit_service.dart` | Frontend notification handler |
| `desktop/lib/constants/livekit_constants.dart` | Frontend topic constants |
