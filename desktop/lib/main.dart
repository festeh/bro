import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'pages/home_page.dart';
import 'services/egress_service.dart';
import 'services/livekit_service.dart';
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

  // Initialize media_kit for Linux audio playback
  MediaKit.ensureInitialized();

  // Recordings directory - must match the egress mount in justfile
  final cwd = Directory.current.path;

  // Try relative path first, fall back to absolute
  var recordingsDir = p.normalize(p.join(cwd, '..', 'recordings'));
  if (!Directory(recordingsDir).existsSync()) {
    // Fallback to absolute path for development
    recordingsDir = '/home/dima/projects/bro/recordings';
  }

  // Initialize services
  final tokenService = TokenService();
  final liveKitService = LiveKitService(tokenService: tokenService);
  final egressService = EgressService(tokenService: tokenService);
  final storageService = StorageService(recordingsDir: recordingsDir);

  await storageService.init();

  runApp(
    VoiceRecorderApp(
      liveKitService: liveKitService,
      egressService: egressService,
      storageService: storageService,
    ),
  );
}

class VoiceRecorderApp extends StatefulWidget {
  final LiveKitService liveKitService;
  final EgressService egressService;
  final StorageService storageService;

  const VoiceRecorderApp({
    super.key,
    required this.liveKitService,
    required this.egressService,
    required this.storageService,
  });

  @override
  State<VoiceRecorderApp> createState() => _VoiceRecorderAppState();
}

class _VoiceRecorderAppState extends State<VoiceRecorderApp> {
  @override
  void dispose() {
    widget.liveKitService.dispose();
    widget.storageService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Recorder',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomePage(
        liveKitService: widget.liveKitService,
        egressService: widget.egressService,
        storageService: widget.storageService,
        recordingsDir: widget.storageService.recordingsDir,
      ),
    );
  }
}
