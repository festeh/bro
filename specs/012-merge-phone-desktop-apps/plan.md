# Plan: bro - Unified Voice Chat App

**Spec**: specs/012-merge-phone-desktop-apps/spec.md

## Tech Stack

- Language: Dart 3.10+
- Framework: Flutter (Linux + Android)
- Voice: LiveKit (livekit_client)
- Audio playback: media_kit (platform-specific libs)
- Storage: sqflite (cross-platform SQLite)
- Testing: flutter_test

## Approach

### Phase 1: Rename and Restructure

1. **Rename desktop/ to app/**
   Move the desktop folder to `app/` to reflect its new cross-platform role.

2. **Update package name**
   Change `name: desktop` to `name: bro` in pubspec.yaml.

3. **Update app title**
   Change "Voice Recorder" to "bro" in main.dart.

### Phase 2: Add Android Support

4. **Add Android platform**
   Run `flutter create --platforms=android .` inside the app folder to scaffold Android.

5. **Configure AndroidManifest.xml permissions**
   Add required permissions (based on LiveKit Flutter SDK docs):
   ```xml
   <uses-permission android:name="android.permission.RECORD_AUDIO" />
   <uses-permission android:name="android.permission.CAMERA" />
   <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
   <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
   <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
   <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
   ```

6. **Update dependencies for cross-platform**
   - Replace `media_kit_libs_linux: any` with conditional platform imports
   - Add `media_kit_libs_android` for Android audio playback
   - Add `permission_handler` for runtime permission requests

7. **Fix Linux-specific code**
   - Remove hardcoded `/home/dima/projects/bro/recordings` path
   - Use `path_provider` to get platform-appropriate storage location
   - Add permission request flow before first voice session

### Phase 3: Responsive UI

8. **Create adaptive navigation**
   - Detect screen width using `MediaQuery` or `LayoutBuilder`
   - Desktop (>600px): Keep sidebar layout
   - Mobile (<600px): Use bottom navigation bar

9. **Update HomePage to switch layouts**
   - Extract sidebar content to reusable settings widget
   - Create `MobileNavBar` widget for bottom tabs
   - Use `LayoutBuilder` to pick layout based on width

10. **Adjust message bubble width constraints**
    - Desktop: 70% max width (current)
    - Mobile: 85% max width for better use of narrow screen

### Phase 4: Cleanup

11. **Remove phone app**
    Delete `phone/` directory entirely (WebSocket chat and watch sync dropped).

12. **Update justfile and build scripts**
    Update any references from `desktop/` to `app/`.

13. **Test on both platforms**
    Build and run on Linux and Android to verify functionality.

## Structure

After changes:

```
app/                          # Renamed from desktop/
├── lib/
│   ├── main.dart             # Entry point, updated title
│   ├── constants/
│   │   └── livekit_constants.dart
│   ├── models/
│   │   ├── chat_message.dart
│   │   ├── models_config.dart
│   │   └── recording.dart
│   ├── pages/
│   │   ├── home_page.dart    # Adaptive layout (sidebar vs bottom nav)
│   │   └── chat_page.dart
│   ├── services/
│   │   ├── egress_service.dart
│   │   ├── livekit_service.dart
│   │   ├── storage_service.dart
│   │   ├── token_service.dart
│   │   └── waveform_service.dart
│   ├── theme/
│   │   ├── theme.dart
│   │   └── tokens.dart
│   └── widgets/
│       ├── app_sidebar.dart       # Desktop navigation
│       ├── mobile_nav_bar.dart    # NEW: Mobile bottom tabs
│       ├── settings_panel.dart    # NEW: Shared settings (ASR, LLM, TTS)
│       ├── live_transcript.dart
│       ├── record_button.dart
│       ├── recording_list.dart
│       ├── recording_tile.dart
│       ├── stt_provider_selector.dart
│       └── waveform_widget.dart
├── android/                  # NEW: Android platform
├── linux/                    # Existing Linux platform
├── assets/
│   └── models.json
└── pubspec.yaml              # Updated name and dependencies
```

## Risks

Based on analysis of ~/github/client-sdk-flutter (LiveKit Flutter SDK):

- **LiveKit Android compatibility**: LOW RISK. Fully supported with mature Kotlin implementation. Min SDK 21. All known Android issues fixed in recent versions. Example app works on Android.

- **media_kit Android setup**: MEDIUM RISK. Need to add media_kit_libs_android and follow setup docs. May need ProGuard rules depending on media_kit version.

- **Permission handling**: LOW RISK. Well documented. Add `permission_handler` package and configure AndroidManifest.xml with:
  - RECORD_AUDIO, CAMERA (for video if needed)
  - MODIFY_AUDIO_SETTINGS
  - BLUETOOTH, BLUETOOTH_CONNECT (for headset support)
  - ACCESS_NETWORK_STATE, CHANGE_NETWORK_STATE

- **Path differences**: LOW RISK. Use path_provider - already a dependency.

- **Waveform extraction on Android**: MEDIUM RISK. Current WaveformService uses FFmpeg CLI. Alternative: `audio_waveforms` package (~/github/audio_waveforms) provides cross-platform waveform extraction with native Android implementation. Consider if FFmpeg approach doesn't work.

## File Changes Summary

| Action | Path | Notes |
|--------|------|-------|
| Move | desktop/ → app/ | Rename folder |
| Edit | app/pubspec.yaml | name: bro, add Android deps |
| Edit | app/lib/main.dart | Title change, path handling |
| Edit | app/lib/pages/home_page.dart | Adaptive layout |
| Add | app/lib/widgets/mobile_nav_bar.dart | Bottom navigation |
| Add | app/lib/widgets/settings_panel.dart | Shared settings widget |
| Edit | app/lib/widgets/app_sidebar.dart | Use settings_panel |
| Delete | phone/ | Remove entire directory |
| Edit | justfile | Update paths |
