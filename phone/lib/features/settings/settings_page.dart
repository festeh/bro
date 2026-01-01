import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/tokens.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _channel = MethodChannel('com.github.festeh.bro/storage');

  bool _isClearing = false;

  Future<void> _clearDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all recordings?'),
        content: const Text(
          'This will permanently delete all recordings. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear All', style: TextStyle(color: Tokens.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isClearing = true);

      try {
        final deleted = await _channel.invokeMethod<int>('clearAll') ?? 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted $deleted recordings')),
          );
          Navigator.pop(context, true); // Return true to indicate data changed
        }
      } on PlatformException catch (e) {
        debugPrint('Failed to clear database: ${e.message}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear: ${e.message}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isClearing = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.delete_forever, color: Tokens.error),
            title: const Text('Clear all recordings'),
            subtitle: const Text('Delete all audio from database'),
            trailing: _isClearing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _isClearing ? null : _clearDatabase,
          ),
        ],
      ),
    );
  }
}
