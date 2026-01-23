# bro - Unified Voice Chat App

## What Users Can Do

1. **Have voice conversations with an AI agent**
   User speaks into their device and gets real-time voice responses from an AI.
   - Works when: Device has microphone access, internet connection, conversation flows naturally
   - Fails when: No microphone permission, offline, or service unavailable (show clear error)

2. **See live transcription during conversation**
   User sees their words and the AI's responses as text in real-time.
   - Works when: Transcription appears within a few seconds of speech
   - Fails when: Transcription service unavailable (conversation continues, text just missing)

3. **Choose AI model and voice settings**
   User picks which LLM to use and can toggle text-to-speech on/off.
   - Works when: Settings persist between sessions, changes apply immediately
   - Fails when: Selected model unavailable (fall back to default, notify user)

4. **Browse and play past recordings**
   User sees a list of saved conversations and can play them back.
   - Works when: Recordings show date/time, playback has progress indicator
   - Fails when: Recording file missing (show "unavailable" state)

5. **Send text messages instead of voice**
   User types a message when voice isn't convenient.
   - Works when: Text submitted, AI responds via voice or text
   - Fails when: Empty message (disable send button)

## Requirements

- [ ] Works on Linux (desktop) and Android (mobile)
- [ ] Same core features on both platforms
- [ ] UI adapts to screen size (sidebar on desktop, tabs on mobile)
- [ ] Voice communication via LiveKit only
- [ ] Recordings handled by LiveKit (egress)
- [ ] Settings persist between sessions
- [ ] Connection status visible to user

## Decisions

- **App name:** bro
- **Platforms:** Linux and Android only (no iOS/Mac)
- **Watch/wearable sync:** Dropped
- **WebSocket chat:** Dropped (LiveKit only)
- **Recording storage:** Via LiveKit egress
