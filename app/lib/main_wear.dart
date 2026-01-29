import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'pages/wear_voice_page.dart';
import 'services/livekit_service.dart';
import 'services/token_service.dart';

const String _livekitUrl = String.fromEnvironment(
  'LIVEKIT_URL',
  defaultValue: 'ws://localhost:7880',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set up logging
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.ALL;
  Logger('livekit').level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.loggerName}: ${record.message}');
  });

  // Initialize services
  final tokenService = TokenService();
  final liveKitService = LiveKitService(
    tokenService: tokenService,
    wsUrl: _livekitUrl,
    identity: 'wear-user',
  );

  runApp(WearVoiceApp(liveKitService: liveKitService));
}

class WearVoiceApp extends StatefulWidget {
  final LiveKitService liveKitService;

  const WearVoiceApp({super.key, required this.liveKitService});

  @override
  State<WearVoiceApp> createState() => _WearVoiceAppState();
}

class _WearVoiceAppState extends State<WearVoiceApp> {
  @override
  void dispose() {
    widget.liveKitService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: WearVoicePage(liveKitService: widget.liveKitService),
    );
  }
}
