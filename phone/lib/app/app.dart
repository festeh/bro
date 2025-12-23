import 'package:flutter/material.dart';
import 'theme.dart';
import '../features/home/home_page.dart';

class BroApp extends StatelessWidget {
  const BroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomePage(),
    );
  }
}
