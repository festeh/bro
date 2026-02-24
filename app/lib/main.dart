import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models/models_config.dart';
import 'pages/home_page.dart';
import 'providers/settings_provider.dart';
import 'providers/storage_providers.dart';
import 'services/assistant_service.dart';
import 'services/egress_service.dart';
import 'services/livekit_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'services/token_service.dart';
import 'theme/theme.dart';

const String _livekitUrl = String.fromEnvironment(
  'LIVEKIT_URL',
  defaultValue: 'ws://localhost:7880',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress flutter_webrtc "No active stream to cancel" PlatformException.
  // This is thrown asynchronously during Room.disconnect() cleanup and is harmless.
  FlutterError.onError = (details) {
    if (details.exception is PlatformException &&
        (details.exception as PlatformException).message == 'No active stream to cancel') {
      return;
    }
    FlutterError.presentError(details);
  };

  // Set up logging
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.ALL;
  // Suppress verbose livekit logs
  Logger('livekit').level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.loggerName}: ${record.message}');
  });

  // Initialize sqflite for Linux (uses FFI)
  if (Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize media_kit for audio playback
  MediaKit.ensureInitialized();

  // Initialize model configuration (loads cache, triggers async refresh)
  await ModelsConfig.instance.init();

  // Recordings directory - platform-specific
  final recordingsDir = await _getRecordingsDir();

  // Initialize services
  final settingsService = SettingsService();
  await settingsService.init();

  final tokenService = TokenService();
  final liveKitService = LiveKitService(
    tokenService: tokenService,
    wsUrl: _livekitUrl,
    deviceId: settingsService.deviceId,
  );

  // Sync persisted settings into LiveKitService before connect() sends metadata.
  // Without this, mobile clients send default values because SettingsNotifier
  // is only initialized lazily when the settings UI is opened.
  liveKitService.setSttProvider(settingsService.sttProvider);
  liveKitService.setLlmModel(settingsService.llmModel);
  liveKitService.setTtsEnabled(settingsService.ttsEnabled);
  liveKitService.setExcludedAgents(settingsService.excludedAgents);

  final egressService = EgressService(tokenService: tokenService);
  final storageService = StorageService(recordingsDir: recordingsDir);

  await storageService.init();

  // Check if launched from Android assistant trigger
  final assistantService = AssistantService();
  final launchedFromAssist =
      Platform.isAndroid ? await assistantService.checkAssistLaunch() : false;

  // Ensure the app is registered as the default digital assistant
  if (Platform.isAndroid) {
    final roleResult = await assistantService.requestDefaultRole();
    if (roleResult == 'misconfigured') {
      // Role is held but voice_interaction_service not set.
      // Open system settings so the user can re-select bro as assistant,
      // which properly configures the system.
      assistantService.openAssistantSettings();
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsService),
        liveKitServiceProvider.overrideWithValue(liveKitService),
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: BroApp(
        liveKitService: liveKitService,
        storageService: storageService,
        egressService: egressService,
        assistantService: assistantService,
        launchedFromAssist: launchedFromAssist,
      ),
    ),
  );
}

Future<String> _getRecordingsDir() async {
  if (Platform.isAndroid) {
    // Use app-specific external storage on Android
    final dir = await getExternalStorageDirectory();
    final recordingsDir = p.join(dir!.path, 'recordings');
    await Directory(recordingsDir).create(recursive: true);
    return recordingsDir;
  } else {
    // Linux: use project recordings dir (for LiveKit egress mount)
    final cwd = Directory.current.path;
    final recordingsDir = p.normalize(p.join(cwd, '..', 'recordings'));
    await Directory(recordingsDir).create(recursive: true);
    return recordingsDir;
  }
}

class BroApp extends StatefulWidget {
  final LiveKitService liveKitService;
  final StorageService storageService;
  final EgressService egressService;
  final AssistantService assistantService;
  final bool launchedFromAssist;

  const BroApp({
    super.key,
    required this.liveKitService,
    required this.storageService,
    required this.egressService,
    required this.assistantService,
    this.launchedFromAssist = false,
  });

  @override
  State<BroApp> createState() => _BroAppState();
}

class _BroAppState extends State<BroApp> {
  @override
  void dispose() {
    widget.liveKitService.dispose();
    widget.storageService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bro',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomePage(
        egressService: widget.egressService,
        assistantService: widget.assistantService,
        launchedFromAssist: widget.launchedFromAssist,
      ),
    );
  }
}
