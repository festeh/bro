# Plan: WearOS LiveKit Voice

**Spec**: specs/014-wearos-livekit-voice/spec.md

## Tech Stack

- Language: Dart (Flutter) + Kotlin (Android native)
- Framework: Flutter 3.x with Android build flavors
- Dependencies: livekit_client (existing), permission_handler (existing)
- Testing: flutter test

## Structure

New and modified files:

```
app/
├── lib/
│   ├── main.dart                    # Modified: conditional entry point
│   ├── main_phone.dart              # New: phone-specific entry
│   ├── main_wear.dart               # New: wear-specific entry
│   ├── pages/
│   │   └── wear_voice_page.dart     # New: WearOS voice UI
│   └── services/
│       └── livekit_service.dart     # Modified: add wear identity option
├── android/
│   ├── app/
│   │   ├── build.gradle.kts         # Modified: add flavors
│   │   └── src/
│   │       ├── main/                # Shared code
│   │       ├── phone/               # New: phone-specific manifest
│   │       │   └── AndroidManifest.xml
│   │       └── wear/                # New: wear-specific manifest
│   │           └── AndroidManifest.xml
│   └── settings.gradle.kts          # May need modification
└── pubspec.yaml                     # Modified: add wear_plus dependency

wear/                                # Delete after migration
```

## Approach

### 1. Set up Android build flavors

Add `phone` and `wear` product flavors to `build.gradle.kts`:

```kotlin
flavorDimensions += "device"
productFlavors {
    create("phone") {
        dimension = "device"
        applicationIdSuffix = ""
    }
    create("wear") {
        dimension = "device"
        applicationIdSuffix = ".wear"
        minSdk = 30  // WearOS 3.0+
    }
}
```

### 2. Create flavor-specific manifests

**phone/AndroidManifest.xml** - Copy existing manifest (phone/tablet intent filter)

**wear/AndroidManifest.xml** - WearOS-specific:
- Add `<uses-feature android:name="android.hardware.type.watch" />`
- Remove camera permissions (not needed for voice)
- Keep RECORD_AUDIO, INTERNET, BLUETOOTH permissions
- Set standalone mode: `android:name="com.google.android.wearable.standalone" android:value="true"`

### 3. Create separate entry points

**main_phone.dart** - Current main.dart logic (MediaKit, storage, egress, full UI)

**main_wear.dart** - Minimal setup:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupLogging();

  final tokenService = TokenService();
  final liveKitService = LiveKitService(
    tokenService: tokenService,
    identity: 'wear-user',  // Different identity
  );

  runApp(WearVoiceApp(liveKitService: liveKitService));
}
```

### 4. Modify LiveKitService

Add optional `identity` parameter:
- Default: `'desktop-user'` (current behavior)
- WearOS: `'wear-user'`
- Server URL could also be configurable for production

### 5. Create WearOS voice page

**wear_voice_page.dart** - Minimal round UI:
- Large center mic button (tap to toggle voice session)
- Connection status indicator (dot or ring color)
- Agent status (connected/waiting)
- Simple visual feedback during speech

No text display, no chat history, no settings. Just voice.

### 6. Handle permissions without foreground service

WearOS approach:
- Request RECORD_AUDIO permission on first launch
- Audio capture works while Activity is visible (no background)
- When user leaves app, voice session stops automatically
- LiveKit handles the audio track lifecycle

This is simpler than the current WearOS app which uses a foreground service.

### 7. Delete old wear directory

After migration is complete and tested:
- Remove `/wear/` directory entirely
- Update any scripts or docs that reference it

## Build Commands

```bash
# Build phone APK
flutter build apk --flavor phone -t lib/main_phone.dart

# Build WearOS APK
flutter build apk --flavor wear -t lib/main_wear.dart

# Run on phone
flutter run --flavor phone -t lib/main_phone.dart

# Run on WearOS (device connected)
flutter run --flavor wear -t lib/main_wear.dart
```

## Risks

- **LiveKit client on WearOS**: Should work (it's just Android), but may have performance considerations on constrained hardware. Mitigation: test early on real device.

- **Round screen layout**: Flutter's Material components may not look great on round WearOS screens. Mitigation: use simple centered layout, avoid edges.

- **Battery drain**: LiveKit connection uses network and CPU. Mitigation: voice session only active while user holds/taps button; no background activity.

- **Network on watch**: WiFi or LTE required (Bluetooth to phone won't work for direct LiveKit). Mitigation: show clear connection error if no network.

- **Audio latency**: WebRTC on WearOS may have higher latency than phone. Mitigation: acceptable for voice assistant use case.

## Decisions

1. **Server URL** - Make configurable via build-time constant (e.g., `--dart-define=LIVEKIT_URL=wss://...`). Default to `ws://localhost:7880` for dev.

2. **Token service secrets** - Keep hardcoded pattern, secrets inserted during build from env vars.

3. **Voice activation** - Toggle (tap to start, tap to stop).
