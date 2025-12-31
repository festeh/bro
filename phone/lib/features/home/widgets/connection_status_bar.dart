import 'package:flutter/material.dart';
import '../../../app/tokens.dart';
import 'sync_indicator.dart';

class ConnectionStatusBar extends StatelessWidget {
  final SyncStatus status;
  final VoidCallback? onPing;
  final bool isPinging;

  const ConnectionStatusBar({
    super.key,
    required this.status,
    this.onPing,
    this.isPinging = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Tokens.durationFast,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.spacingMd,
        vertical: Tokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor.withOpacity(0.15),
        border: Border(
          bottom: BorderSide(
            color: _backgroundColor.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildStatusIcon(),
          const SizedBox(width: Tokens.spacingSm),
          Text(
            _statusText,
            style: TextStyle(
              color: _backgroundColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          _buildPingButton(),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    if (status == SyncStatus.syncing) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: Tokens.warning),
      );
    }
    return Icon(
      status == SyncStatus.connected ? Icons.watch : Icons.watch_off,
      color: _backgroundColor,
      size: 16,
    );
  }

  Widget _buildPingButton() {
    return GestureDetector(
      onTap: isPinging ? null : onPing,
      child: AnimatedContainer(
        duration: Tokens.durationFast,
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.spacingSm,
          vertical: Tokens.spacingXs,
        ),
        decoration: BoxDecoration(
          color: Tokens.primary.withOpacity(isPinging ? 0.3 : 0.2),
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          border: Border.all(color: Tokens.primary.withOpacity(0.5), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPinging)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Tokens.primary,
                ),
              )
            else
              Icon(Icons.wifi_tethering, size: 12, color: Tokens.primary),
            const SizedBox(width: 4),
            Text(
              isPinging ? 'Pinging...' : 'Ping',
              style: TextStyle(
                color: Tokens.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _backgroundColor {
    switch (status) {
      case SyncStatus.connected:
        return Tokens.success;
      case SyncStatus.disconnected:
        return Tokens.error;
      case SyncStatus.syncing:
        return Tokens.warning;
    }
  }

  String get _statusText {
    switch (status) {
      case SyncStatus.connected:
        return 'Watch Connected';
      case SyncStatus.disconnected:
        return 'Watch Disconnected';
      case SyncStatus.syncing:
        return 'Checking...';
    }
  }
}
