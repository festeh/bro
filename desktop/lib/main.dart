import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'pages/home_page.dart';
import 'services/egress_service.dart';
import 'services/livekit_service.dart';
import 'services/storage_service.dart';
import 'services/token_service.dart';
import 'theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Setup recordings directory
  final homeDir = Platform.environment['HOME'] ?? '/tmp';
  final recordingsDir = p.join(homeDir, '.bro', 'recordings');

  // Initialize services
  final tokenService = TokenService();
  final liveKitService = LiveKitService(tokenService: tokenService);
  final egressService = EgressService(tokenService: tokenService);
  final storageService = StorageService(recordingsDir: recordingsDir);

  await storageService.init();

  runApp(VoiceRecorderApp(
    liveKitService: liveKitService,
    egressService: egressService,
    storageService: storageService,
  ));
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
      ),
    );
  }
}
