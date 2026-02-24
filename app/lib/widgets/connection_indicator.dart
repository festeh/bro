import 'package:flutter/material.dart';

import '../services/livekit_service.dart';
import '../theme/tokens.dart';

/// Returns the color and label for a given connection state.
({Color color, String label}) connectionStatusInfo(
  ConnectionStatus status,
  bool isAgentConnected,
) {
  if (status != ConnectionStatus.connected) {
    switch (status) {
      case ConnectionStatus.connecting:
        return (color: AppTokens.accentPrimary, label: 'Connecting...');
      case ConnectionStatus.error:
        return (color: AppTokens.accentRecording, label: 'Error — tap to reconnect');
      case ConnectionStatus.disconnected:
      case ConnectionStatus.connected:
        return (color: AppTokens.textTertiary, label: 'Disconnected — tap to reconnect');
    }
  } else if (!isAgentConnected) {
    return (color: AppTokens.accentPrimary, label: 'No agent');
  } else {
    return (color: AppTokens.accentSuccess, label: 'Connected');
  }
}

/// Whether the status represents a reconnectable state.
bool isReconnectable(ConnectionStatus status) =>
    status == ConnectionStatus.disconnected || status == ConnectionStatus.error;

class ConnectionStatusLabel extends StatelessWidget {
  final ConnectionStatus status;
  final bool isAgentConnected;
  final VoidCallback? onReconnect;

  const ConnectionStatusLabel({
    super.key,
    required this.status,
    required this.isAgentConnected,
    this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final info = connectionStatusInfo(status, isAgentConnected);
    final canReconnect = isReconnectable(status) && onReconnect != null;

    return GestureDetector(
      onTap: canReconnect ? onReconnect : null,
      child: Text(
        info.label,
        style: TextStyle(
          color: info.color,
          fontSize: AppTokens.fontSizeSm,
          fontWeight: AppTokens.fontWeightMedium,
        ),
      ),
    );
  }
}

/// Small 8x8 dot indicator for desktop sidebar.
class ConnectionIndicator extends StatelessWidget {
  final ConnectionStatus status;
  final bool isAgentConnected;

  const ConnectionIndicator({
    super.key,
    required this.status,
    required this.isAgentConnected,
  });

  @override
  Widget build(BuildContext context) {
    final info = connectionStatusInfo(status, isAgentConnected);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: info.color, shape: BoxShape.circle),
    );
  }
}

/// Debug info rows for use in settings sheet.
Widget connectionInfoSection({
  required ConnectionStatus status,
  required bool isAgentConnected,
  required String wsUrl,
  required String roomName,
  required String apiKey,
}) {
  final info = connectionStatusInfo(status, isAgentConnected);
  final isDefault = apiKey == 'devkey';
  final maskedKey =
      apiKey.length > 8 ? '${apiKey.substring(0, 8)}...' : apiKey;

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Connection',
        style: TextStyle(
          color: AppTokens.textSecondary,
          fontSize: AppTokens.fontSizeMd,
          fontWeight: AppTokens.fontWeightMedium,
        ),
      ),
      const SizedBox(height: AppTokens.spacingSm),
      _infoRow('Status', info.label),
      _infoRow('Server', wsUrl),
      _infoRow('Room', roomName),
      _infoRow('API Key', maskedKey),
      if (isDefault)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Using default dev credentials',
            style:
                TextStyle(color: AppTokens.accentRecording, fontSize: 12),
          ),
        ),
    ],
  );
}

Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(
                  color: AppTokens.textTertiary, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: AppTokens.textPrimary, fontSize: 12)),
        ),
      ],
    ),
  );
}
