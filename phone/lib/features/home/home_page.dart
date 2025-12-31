import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/tokens.dart';
import '../../core/models/speech_file.dart';
import 'widgets/sync_indicator.dart';
import 'widgets/audio_tile.dart';
import 'widgets/connection_status_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _channel = MethodChannel('com.github.festeh.bro/storage');

  List<SpeechFile> _files = [];
  bool _isLoading = false;
  bool _isPinging = false;
  bool? _lastPingSuccess;
  SyncStatus _syncStatus = SyncStatus.disconnected;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _checkConnection();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);

    try {
      final result = await _channel.invokeMethod('listFiles');
      final List<dynamic> filesList = result as List<dynamic>;

      setState(() {
        _files =
            filesList
                .map(
                  (item) => SpeechFile.fromMap(Map<String, dynamic>.from(item)),
                )
                .toList()
              ..sort(
                (a, b) => b.timestamp.compareTo(a.timestamp),
              ); // Newest first
      });
    } on PlatformException catch (e) {
      debugPrint('Failed to load files: ${e.message}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkConnection() async {
    try {
      final connected = await _channel.invokeMethod('isWatchConnected');
      setState(() {
        _syncStatus = connected
            ? SyncStatus.connected
            : SyncStatus.disconnected;
      });
    } on PlatformException catch (e) {
      debugPrint('Failed to check connection: ${e.message}');
      setState(() => _syncStatus = SyncStatus.disconnected);
    }
  }

  Future<void> _deleteFile(SpeechFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recording?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Tokens.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _channel.invokeMethod('deleteFile', {'path': file.path});
        setState(() {
          _files.removeWhere((f) => f.id == file.id);
        });
      } on PlatformException catch (e) {
        debugPrint('Failed to delete file: ${e.message}');
      }
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _syncStatus = SyncStatus.syncing);
    await _loadFiles();
    await _checkConnection();
  }

  Future<void> _pingWatch() async {
    if (_isPinging) return;

    setState(() => _isPinging = true);

    try {
      final success = await _channel.invokeMethod<bool>('pingWatch') ?? false;
      if (mounted) {
        setState(() => _lastPingSuccess = success);
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to ping watch: ${e.message}');
      if (mounted) {
        setState(() => _lastPingSuccess = false);
      }
    } finally {
      if (mounted) {
        setState(() => _isPinging = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bro'),
        actions: [SyncIndicator(status: _syncStatus, onTap: _onRefresh)],
      ),
      body: Column(
        children: [
          ConnectionStatusBar(
            status: _syncStatus,
            onPing: _pingWatch,
            onRefresh: _onRefresh,
            isPinging: _isPinging,
            lastPingSuccess: _lastPingSuccess,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: Tokens.primary,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _files.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Tokens.primary),
      );
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_off, size: 64, color: Tokens.textTertiary),
            const SizedBox(height: Tokens.spacingMd),
            Text(
              'No recordings yet',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Tokens.textSecondary),
            ),
            const SizedBox(height: Tokens.spacingSm),
            Text(
              'Pull down to refresh',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: Tokens.spacingSm),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return AudioTile(file: file, onDelete: () => _deleteFile(file));
      },
    );
  }
}
