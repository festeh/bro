# Plan: Unify Voice and Text Input

## Problem

Voice and text inputs use separate code paths:
- Voice: `ChatAgent.on_user_turn_completed()` - has intent classification, TaskAgent routing
- Text: `process_text_input()` - standalone function, no classification, no TaskAgent

This means:
- Text input can't access dimaist-cli (no TaskAgent)
- No shared conversation state between voice and text
- Duplicated LLM handling code

## Goal

Single input path that:
1. Works for both voice and text
2. Routes through intent classification
3. Shares TaskAgent state
4. Allows seamless voice/text conversation switching

## Tech Stack

- Language: Python 3.11+
- Framework: livekit-agents
- No storage changes

## Structure

```
agent/
└── voice_agent.py    # Modify ChatAgent to handle text input
```

## Approach

### 1. Add `process_text` method to ChatAgent

Move text processing into the agent class so it can access `self._task_agent`:

```python
class ChatAgent(Agent):
    async def process_text(self, text: str) -> None:
        """Process text input through same pipeline as voice."""
        # Reuse on_user_turn_completed logic
```

### 2. Create shared `_process_input` method

Extract common logic from `on_user_turn_completed`:

```python
async def _process_input(self, text: str) -> str | None:
    """Process user input, return response text or None to use default LLM."""
    # If TaskAgent active, route to it
    if self._task_agent and self._task_agent.is_active:
        response = await self._task_agent.process_message(text)
        if response.should_exit:
            self._task_agent = None
        return response.text

    # Classify intent
    classification = await classify_intent([("user", text)])

    # Route task management to TaskAgent
    if classification.intent == Intent.TASK_MANAGEMENT:
        if not self._task_agent:
            self._task_agent = TaskAgent(...)
        response = await self._task_agent.process_message(text)
        return response.text

    return None  # Use default LLM flow
```

### 3. Update `on_user_turn_completed` to use shared method

```python
async def on_user_turn_completed(self, turn_ctx, new_message):
    text = new_message.text_content or ""
    response = await self._process_input(text)
    if response:
        await self._speak_and_stop(response)
```

### 4. Add `process_text` for text input

```python
async def process_text(self, text: str) -> None:
    """Handle text input from client."""
    response = await self._process_input(text)

    if response:
        # TaskAgent response - stream to frontend
        await self._stream_response(response)
    else:
        # LLM response - stream chunks
        async for chunk in self._llm.astream([("user", text)]):
            if chunk.content:
                await self._send_immediate(chunk.content)
        await self._flush_immediate()
```

### 5. Extract `_stream_response` from `_speak_and_stop`

`_speak_and_stop()` streams text then raises `StopResponse()`. For text input we don't want the exception. Extract the streaming:

```python
async def _stream_response(self, text: str) -> None:
    """Stream text response to frontend."""
    if self._room:
        self._segment_id = f"RESP_{uuid.uuid4().hex[:8]}"
        writer = await self._room.local_participant.stream_text(...)
        await writer.write(text)
        await writer.aclose()

async def _speak_and_stop(self, text: str) -> None:
    """Stream response and stop voice flow."""
    await self._stream_response(text)
    raise StopResponse()
```

### 6. Update text handler to use agent

Change `on_text_input` to route through agent:

```python
def on_text_input(reader, participant_id):
    async def _handle():
        text = await reader.read_all()
        if state.agent and isinstance(state.agent, ChatAgent):
            await state.agent.process_text(text)
        else:
            # Fallback for when no voice session active
            await process_text_input_standalone(...)
    asyncio.create_task(_handle())
```

### 7. Handle case when no voice session active

If user sends text before starting voice:
- Create a ChatAgent instance in SessionState
- Keep it alive for text-only conversations
- Reuse when voice session starts

## Changes Summary

| Location | Change |
|----------|--------|
| `ChatAgent._process_input()` | New method - shared input processing |
| `ChatAgent._stream_response()` | New method - extracted from `_speak_and_stop` |
| `ChatAgent.process_text()` | New method - text entry point |
| `ChatAgent._speak_and_stop()` | Refactor to use `_stream_response` |
| `ChatAgent.on_user_turn_completed()` | Refactor to use `_process_input` |
| `on_text_input` handler | Route through agent instead of standalone function |
| `process_text_input()` | Remove (no longer needed) |

## Error Handling

Log errors for unhappy paths:

```python
async def _process_input(self, text: str) -> str | None:
    try:
        # TaskAgent routing...
        # Intent classification...
    except Exception as e:
        logger.error(f"Input processing failed: {e}", exc_info=True)
        return "Sorry, I encountered an error processing your request."

async def process_text(self, text: str) -> None:
    try:
        response = await self._process_input(text)
        # ...
    except Exception as e:
        logger.error(f"Text input failed: {e}", exc_info=True)
        await self._stream_response("Sorry, something went wrong.")
```

Specific errors to log:
- Intent classification failure
- TaskAgent creation failure
- TaskAgent processing failure
- LLM streaming failure
- Room/writer errors when streaming response

## Risks

- **Text without voice session**: Need to handle when ChatAgent doesn't exist yet
  - Mitigation: Create agent on first text input if none exists

- **TTS for text responses**: Currently text path has TTS but TaskAgent doesn't
  - Mitigation: Add TTS support to `_stream_text_response` if enabled

## Open Questions

None - requirements are clear from the bug context.
