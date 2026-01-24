# Plan: Decouple Text from Voice Messages

**Spec**: specs/012-decouple-text-from-voice-messages/spec.md

## Tech Stack

- Language: Dart (Flutter) + Python (agent)
- Transport: LiveKit text streams (reuse existing connection)
- Testing: Manual testing

## Structure

Files to modify:

```
app/lib/
├── constants/
│   └── livekit_constants.dart   # Add TOPIC_TEXT_INPUT
├── services/
│   └── livekit_service.dart     # Add sendTextMessage() method
└── pages/
    └── chat_page.dart           # Wire _submitTextMessage() to service

agent/
├── constants.py                 # Add TOPIC_TEXT_INPUT
└── voice_agent.py               # Register text input handler, process via LLM
```

## Approach

### 1. Add new topic constant

Add `lk.text_input` topic to both sides:

**agent/constants.py**:
```python
TOPIC_TEXT_INPUT = "lk.text_input"  # Text messages from client
```

**app/lib/constants/livekit_constants.dart**:
```dart
static const textInput = 'lk.text_input';
```

### 2. Flutter: Add sendTextMessage to LiveKitService

Add method to `livekit_service.dart`:
```dart
Future<void> sendTextMessage(String text) async {
  if (_room == null || !isConnected) return;

  final writer = await _room!.localParticipant!.streamText(
    topic: LiveKitTopics.textInput,
  );
  await writer.write(text);
  await writer.close();
}
```

### 3. Flutter: Wire ChatPage to send text

In `chat_page.dart`, update `_submitTextMessage()`:
```dart
void _submitTextMessage() {
  final text = _textController.text.trim();
  if (text.isEmpty) return;

  _addMessage(text, isUser: true);
  _textController.clear();

  // Show thinking indicator
  setState(() => _pendingAssistantMessage = '');

  // Send via LiveKit
  widget.liveKitService.sendTextMessage(text);
}
```

Response already comes via `lk.llm_stream` → `_onImmediateText()` handles it.

### 4. Agent: Register text input handler

In `voice_agent.py`, register handler in `entrypoint()`:
```python
ctx.room.register_text_stream_handler(TOPIC_TEXT_INPUT, on_text_input)
```

Handler processes text directly through LLM:
```python
async def on_text_input(reader: rtc.TextStreamReader, participant_id: str):
    text = await reader.read_all()
    # Process via LLM, respond on lk.llm_stream
    # If ttsEnabled: also speak response via TTS
    # No STT, no session timer
```

### 5. Keep voice path unchanged

The 60-sec session timer only starts on `track_subscribed` (audio track).
Text messages don't publish audio, so no timer involvement.

## Flow Diagram

```
TEXT PATH (no voice session):
┌─────────┐    lk.text_input    ┌─────────┐    lk.llm_stream    ┌─────────┐
│ Flutter │ ──────────────────► │  Agent  │ ──────────────────► │ Flutter │
│  Send   │                     │   LLM   │  (+ TTS if enabled) │ Display │
└─────────┘                     └─────────┘                     └─────────┘

VOICE PATH (unchanged):
┌─────────┐   audio track   ┌─────────┐   lk.llm_stream   ┌─────────┐
│   Mic   │ ──────────────► │ STT→LLM │ ────────────────► │ Display │
│ Button  │                 │  →TTS   │  (+ TTS if enabled)│ + Audio │
└─────────┘                 └─────────┘                   └─────────┘
           ◄── 60 sec timer active ──►
```

## Risks

- **No room connection**: Text send fails silently if not connected. Mitigation: check `isConnected` before send, show error state.
- **Agent not running**: Text goes nowhere. Mitigation: same as voice - need agent running.

## Open Questions

- None - approach is clear.
