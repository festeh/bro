# Spec: Decouple Text from Voice Messages

## Problem

Text messages in the Flutter app have no backend connection. When users type and send text, it appears in the chat but goes nowhere. The `_submitTextMessage()` function (chat_page.dart:252-262) just logs the message.

Users want text messages to get LLM responses immediately, without triggering the 60-second voice session or any voice-related machinery.

## Requirements

1. **Text messages bypass voice session**
   - Typing text and pressing Send does not start a voice session
   - Text messages do not trigger the 60-second session timeout
   - Text messages do not affect the mic button or voice state

2. **Text messages get LLM responses**
   - Text messages go to agent via LiveKit text stream
   - Responses stream back to the chat UI
   - Responses appear in the same message list as voice responses
   - TTS controlled by existing `ttsEnabled` setting (same as voice)

3. **Voice messages unchanged**
   - Pressing the mic button still starts a 60-second voice session
   - Voice input still goes through STT → LLM → TTS pipeline
   - Session timeout behavior stays the same

## Out of Scope

- Task management via text (already works via voice)
- History sync between text and voice paths
- New backend endpoints or protocols
