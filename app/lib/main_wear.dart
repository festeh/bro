import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models/models_config.dart';
import 'pages/wear_voice_page.dart';
import 'providers/settings_provider.dart';
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

  // Generate persistent device ID
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('deviceId');
  if (deviceId == null) {
    deviceId = const Uuid().v4().substring(0, 8);
    await prefs.setString('deviceId', deviceId);
  }

  // Load model configuration
  await ModelsConfig.load();

  // Initialize services
  final tokenService = TokenService();
  final liveKitService = LiveKitService(
    tokenService: tokenService,
    wsUrl: _livekitUrl,
    identity: 'wear-user',
    deviceId: deviceId,
  );

  runApp(
    ProviderScope(
      overrides: [
        liveKitServiceProvider.overrideWithValue(liveKitService),
      ],
      child: WearVoiceApp(liveKitService: liveKitService),
    ),
  );
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
      home: const WearVoicePage(),
    );
  }
}
