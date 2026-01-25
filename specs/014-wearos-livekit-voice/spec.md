# Spec: WearOS LiveKit Voice

## Problem

The WearOS app currently sends audio to the phone via Wear DataLayer API. We want it to talk directly to the LiveKit server instead.

## Solution

Add WearOS as a build flavor to the unified `app/` project. Reuse existing LiveKit infrastructure. Voice-only, minimal UI.

## Requirements

1. **Android build flavors** - Add `phone` and `wear` flavors to the app
2. **Reuse LiveKitService** - Same connection logic as phone/desktop
3. **Reuse TokenService** - Same token generation
4. **WearOS UI** - Mic button + connection status on round screen
5. **Voice only** - No text input, no chat history display
6. **No foreground service** - Audio capture bound to Activity lifecycle
7. **Delete old wear code** - Remove `/wear/` directory after migration

## Out of Scope

- Text messaging from watch
- Chat history on watch
- Settings/configuration on watch
- Foreground service for background audio
