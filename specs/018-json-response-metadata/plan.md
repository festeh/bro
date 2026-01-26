# Plan: JSON Response Metadata

**Spec**: specs/018-json-response-metadata/spec.md

## Tech Stack

- Language: Python (agent), Dart (frontend)
- Framework: livekit-agents, Flutter
- Storage: none
- Testing: manual

## Structure

```
agent/
├── voice_agent.py          # Modify _send_immediate, _send to emit JSON
└── constants.py            # Add response type constants

app/lib/
├── models/
│   └── chat_message.dart   # Add metadata fields to ChatMessage
├── services/
│   └── livekit_service.dart # Parse JSON in _onImmediateText
└── pages/
    └── chat_page.dart      # Display metadata (model badge)
```

## Approach

### 1. Define JSON response format (agent)

Add response type enum in `constants.py`:

```python
class ResponseType(StrEnum):
    LLM_RESPONSE = "llm_response"
    TASK_RESPONSE = "task_response"
    ERROR = "error"
```

### 2. Modify agent to send JSON chunks

In `voice_agent.py`, change `_send_immediate()` and `_send()`:

- First chunk: send JSON header with metadata
- Subsequent chunks: send JSON with text delta
- Format: `{"type": "...", "text": "...", "model": "...", "intent": "..."}`

Challenge: Streaming chunks. Options:
- **Option A**: Send metadata once at stream start, then plain text
- **Option B**: Send JSON for every chunk (more overhead)
- **Option C**: Send metadata as stream attributes, text as content

**Chosen: Option C** - Use LiveKit stream attributes for metadata, keep text content as-is. This:
- Avoids JSON parsing overhead per chunk
- Keeps streaming efficient
- Metadata arrives with first chunk

Implementation:
- Add `model`, `intent`, `response_type` to stream attributes
- Text content stays plain text (as now)

### 3. Update ImmediateTextEvent model (frontend)

Add metadata fields to `ImmediateTextEvent` in `livekit_service.dart`:

```dart
class ImmediateTextEvent {
  final String segmentId;
  final String text;
  final String participantId;
  final String? model;        // NEW
  final String? intent;       // NEW
  final String? responseType; // NEW
}
```

Parse from stream attributes in `_onImmediateText()`.

### 4. Update ChatMessage model (frontend)

Add metadata fields to `ChatMessage` in `chat_message.dart`:

```dart
class ChatMessage {
  // existing fields...
  final String? model;
  final String? intent;
  final String? responseType;
}
```

### 5. Update chat page to display metadata

In `chat_page.dart`, modify `_MessageBubble`:
- Show intent icon on the left of assistant messages
- Show model name as small badge below message

Intent icons (for assistant messages only):
- `task_management` → task icon
- `general_chat` → chat icon
- `error` → warning icon
- default → assistant icon

### 6. Wire up metadata flow

In `chat_page.dart` `_onImmediateText()`:
- Pass metadata from event to ChatMessage on creation
- Update existing streaming message metadata if not set

## Risks

- **LiveKit attribute size limits**: Stream attributes have size limits. Model IDs and intents are short strings, should be fine.
- **Frontend crash on missing fields**: Use nullable types with fallbacks.

## Open Questions

None - approach is clear.
