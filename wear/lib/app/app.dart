import 'package:flutter/material.dart';
import '../features/monitor/monitor_page.dart';
import 'theme.dart';

class BroWearApp extends StatelessWidget {
  const BroWearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const MonitorPage(),
    );
  }
}
