import 'package:flutter/material.dart';

enum PhoneConnectionStatus { connected, disconnected, pingReceived }

class ConnectionStatusBar extends StatelessWidget {
  final PhoneConnectionStatus status;
  final DateTime? lastPingTime;

  const ConnectionStatusBar({
    super.key,
    required this.status,
    this.lastPingTime,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _backgroundColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _backgroundColor.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 14, color: _backgroundColor),
          const SizedBox(width: 6),
          Text(
            _statusText,
            style: TextStyle(
              color: _backgroundColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon {
    switch (status) {
      case PhoneConnectionStatus.connected:
      case PhoneConnectionStatus.pingReceived:
        return Icons.phone_android;
      case PhoneConnectionStatus.disconnected:
        return Icons.phone_disabled;
    }
  }

  Color get _backgroundColor {
    switch (status) {
      case PhoneConnectionStatus.connected:
        return Colors.green.shade400;
      case PhoneConnectionStatus.pingReceived:
        return Colors.green.shade300;
      case PhoneConnectionStatus.disconnected:
        return Colors.grey.shade500;
    }
  }

  String get _statusText {
    switch (status) {
      case PhoneConnectionStatus.connected:
        return 'Phone OK';
      case PhoneConnectionStatus.pingReceived:
        if (lastPingTime != null) {
          final hour = lastPingTime!.hour.toString().padLeft(2, '0');
          final minute = lastPingTime!.minute.toString().padLeft(2, '0');
          return '$hour:$minute';
        }
        return 'Ping!';
      case PhoneConnectionStatus.disconnected:
        return 'No Phone';
    }
  }
}
