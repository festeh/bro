import 'package:flutter/material.dart';

import '../services/livekit_service.dart';
import '../theme/tokens.dart';

class ConnectionIndicator extends StatelessWidget {
  final ConnectionStatus status;
  final bool isAgentConnected;
  final String wsUrl;
  final String roomName;
  final String apiKey;

  const ConnectionIndicator({
    super.key,
    required this.status,
    required this.isAgentConnected,
    required this.wsUrl,
    required this.roomName,
    required this.apiKey,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String statusText;

    if (status != ConnectionStatus.connected) {
      switch (status) {
        case ConnectionStatus.connecting:
          color = AppTokens.accentPrimary;
          statusText = 'Connecting...';
          break;
        case ConnectionStatus.error:
          color = AppTokens.accentRecording;
          statusText = 'Error';
          break;
        case ConnectionStatus.disconnected:
        case ConnectionStatus.connected:
          color = AppTokens.textTertiary;
          statusText = 'Disconnected';
          break;
      }
    } else if (!isAgentConnected) {
      color = AppTokens.accentPrimary;
      statusText = 'No agent';
    } else {
      color = AppTokens.accentSuccess;
      statusText = 'Connected';
    }

    return GestureDetector(
      onTap: () => _showInfoDialog(context, statusText),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String statusText) {
    final isDefault = apiKey == 'devkey';
    final maskedKey = apiKey.length > 8
        ? '${apiKey.substring(0, 8)}...'
        : apiKey;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTokens.backgroundSecondary,
        title: const Text(
          'Connection Info',
          style: TextStyle(color: AppTokens.textPrimary, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Status', statusText),
            _infoRow('Server', wsUrl),
            _infoRow('Room', roomName),
            _infoRow('API Key', maskedKey),
            if (isDefault)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Using default dev credentials',
                  style: TextStyle(color: AppTokens.accentRecording, fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(color: AppTokens.textTertiary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppTokens.textPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
