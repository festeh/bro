# Plan: Riverpod Migration for Chat, Home, and Wear Pages

**Branch**: 023-riverpod-migration-for-chat-home-and-wear-pages

## Tech Stack

- Language: Dart
- Framework: Flutter + flutter_riverpod 2.6.1
- Pattern: `StreamProvider` for service streams, `Notifier` for page-local state
- Testing: manual (no test infrastructure in project)

## Structure

New and changed files:

```
app/lib/
├── providers/
│   ├── settings_provider.dart      # existing, no changes
│   ├── livekit_providers.dart      # NEW — stream providers for LiveKitService
│   ├── storage_providers.dart      # NEW — stream provider for StorageService recordings
│   └── chat_provider.dart          # NEW — chat messages + session state notifier
├── pages/
│   ├── chat_page.dart              # CHANGE — ConsumerStatefulWidget, drop stream subs
│   ├── home_page.dart              # CHANGE — drop stream subs, use ref.watch/ref.listen
│   └── wear_voice_page.dart        # CHANGE — ConsumerStatefulWidget, drop stream subs
├── main.dart                       # CHANGE — add storageServiceProvider override
└── main_wear.dart                  # CHANGE — wrap in ProviderScope
```

## Approach

### 1. Create `livekit_providers.dart` — shared stream providers

Wrap each `LiveKitService` broadcast stream as a `StreamProvider`:

```dart
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  return ref.watch(liveKitServiceProvider).connectionStatus;
});

final agentConnectedProvider = StreamProvider<bool>((ref) {
  return ref.watch(liveKitServiceProvider).agentConnectedStream;
});

final transcriptionProvider = StreamProvider<TranscriptionEvent>((ref) {
  return ref.watch(liveKitServiceProvider).transcriptionStream;
});

final immediateTextProvider = StreamProvider<ImmediateTextEvent>((ref) {
  return ref.watch(liveKitServiceProvider).immediateTextStream;
});

final sessionNotificationProvider = StreamProvider<SessionNotificationEvent>((ref) {
  return ref.watch(liveKitServiceProvider).sessionNotificationStream;
});

final audioTrackIdProvider = StreamProvider<String?>((ref) {
  return ref.watch(liveKitServiceProvider).audioTrackId;
});
```

These are broadcast streams that emit events (not latest-value). Pages will use `ref.listen` to react to each event rather than `ref.watch` on the AsyncValue.

### 2. Create `storage_providers.dart` — recordings stream

```dart
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Must be overridden');
});

final recordingsProvider = StreamProvider<List<Recording>>((ref) {
  return ref.watch(storageServiceProvider).recordingsStream;
});
```

### 3. Create `chat_provider.dart` — chat page state

Chat page has complex local state (message list, accumulated transcription, session status). Move this into a `Notifier`:

```dart
class ChatState {
  final List<ChatMessage> messages;
  final bool isSessionActive;
  final bool isSessionLoading;
  final ConnectionStatus connectionStatus;
}

class ChatNotifier extends Notifier<ChatState> { ... }
```

The notifier will:
- Hold message list and session flags
- Expose methods: `onTranscription()`, `onImmediateText()`, `onSessionNotification()`, `toggleSession()`, `submitTextMessage()`, `clearChat()`
- Be used with `ref.listen` on the stream providers to feed events in

This keeps the business logic testable and out of the widget tree.

### 4. Migrate `chat_page.dart`

- Change from `StatefulWidget` to `ConsumerStatefulWidget`
- Remove all `StreamSubscription` fields and `_init()` / `dispose()` cancellations
- Use `ref.listen(transcriptionProvider, ...)` etc. in `build()` or `initState` equivalent
- Keep `ScrollController`, `TextEditingController`, `FocusNode` as local widget state (they are view-specific)
- Read chat state via `ref.watch(chatProvider)`

### 5. Migrate `home_page.dart`

- Already a `ConsumerStatefulWidget` — keep it
- Remove 6 `StreamSubscription` fields and their `listen()`/`cancel()` calls
- Replace with `ref.watch(connectionStatusProvider)`, `ref.watch(agentConnectedProvider)`, `ref.watch(recordingsProvider)`
- Use `ref.listen(transcriptionProvider, ...)` for transcript events
- Keep `Player`, `Timer`, and recording logic as local state (media player lifecycle is view-specific)
- Keep `_playingRecordingId`, `_playbackProgress` as local state (audio player subs stay local since `Player` is widget-scoped)

### 6. Migrate `wear_voice_page.dart`

- Change from `StatefulWidget` to `ConsumerStatefulWidget`
- Remove 3 `StreamSubscription` fields
- Use `ref.watch(connectionStatusProvider)`, `ref.watch(agentConnectedProvider)`, `ref.watch(audioTrackIdProvider)`
- Keep `_isConnecting` as local state (transient UI flag)

### 7. Update `main.dart`

- Add `storageServiceProvider` override in the `ProviderScope`
- Services are already created in `main()`, just add the override

### 8. Update `main_wear.dart`

- Wrap app in `ProviderScope` with `liveKitServiceProvider` override
- Change `WearVoiceApp` to pass service via provider instead of constructor
- This allows `WearVoicePage` to access `liveKitServiceProvider` via `ref`

## Order of work

1. `livekit_providers.dart` + `storage_providers.dart` (new files, no breakage)
2. `chat_provider.dart` (new file, no breakage)
3. `main.dart` — add `storageServiceProvider` override
4. `main_wear.dart` — add `ProviderScope`
5. `chat_page.dart` — migrate
6. `home_page.dart` — migrate
7. `wear_voice_page.dart` — migrate
8. Build and verify

## Risks

- **Broadcast streams miss events**: `StreamProvider` subscribes when first watched and stays alive while watched. As long as the provider is active before events fire, no events are missed. The streams are broadcast, so multiple listeners work fine. Mitigation: services connect after app starts, so providers are watched before events start.
- **Chat state complexity**: The transcription accumulation logic is intricate (interim vs final segments, accumulated finals). Mitigation: move it into `ChatNotifier` methods verbatim, keeping the same logic.
- **Player lifecycle**: `Player` (media_kit) must be created/disposed with the widget. Keeping it as local state in `ConsumerStatefulWidget` is correct — don't try to put it in a provider.

## Open Questions

None — the pattern is clear and the existing `settings_provider.dart` sets the precedent.
