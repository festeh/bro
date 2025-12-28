import 'package:flutter/material.dart';
import 'theme.dart';
import 'tokens.dart';
import '../features/home/home_page.dart';
import '../features/chat/chat_page.dart';

class BroApp extends StatelessWidget {
  const BroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [HomePage(), ChatPage()],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Tokens.surface,
        indicatorColor: Tokens.primary.withValues(alpha: 0.2),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
        ],
      ),
    );
  }
}
