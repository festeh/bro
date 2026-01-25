import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models/models_config.dart';
import 'pages/home_page.dart';
import 'services/egress_service.dart';
import 'services/livekit_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'services/token_service.dart';
import 'theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Load model configuration from asset
  await ModelsConfig.load();

  // Recordings directory - platform-specific
  final recordingsDir = await _getRecordingsDir();

  // Initialize services
  final tokenService = TokenService();
  final liveKitService = LiveKitService(tokenService: tokenService);
  final egressService = EgressService(tokenService: tokenService);
  final storageService = StorageService(recordingsDir: recordingsDir);
  final settingsService = SettingsService();

  await storageService.init();
  await settingsService.init();

  runApp(
    BroApp(
      liveKitService: liveKitService,
      egressService: egressService,
      storageService: storageService,
      settingsService: settingsService,
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
    var recordingsDir = p.normalize(p.join(cwd, '..', 'recordings'));
    if (!Directory(recordingsDir).existsSync()) {
      // Fallback to absolute path for development
      recordingsDir = '/home/dima/projects/bro/recordings';
    }
    return recordingsDir;
  }
}

class BroApp extends StatefulWidget {
  final LiveKitService liveKitService;
  final EgressService egressService;
  final StorageService storageService;
  final SettingsService settingsService;

  const BroApp({
    super.key,
    required this.liveKitService,
    required this.egressService,
    required this.storageService,
    required this.settingsService,
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
        liveKitService: widget.liveKitService,
        egressService: widget.egressService,
        storageService: widget.storageService,
        settingsService: widget.settingsService,
        recordingsDir: widget.storageService.recordingsDir,
      ),
    );
  }
}
