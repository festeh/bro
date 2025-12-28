import 'package:flutter/material.dart';
import '../../../app/tokens.dart';

enum SyncStatus { connected, disconnected, syncing }

class SyncIndicator extends StatelessWidget {
  final SyncStatus status;
  final VoidCallback? onTap;

  const SyncIndicator({super.key, required this.status, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: AnimatedSwitcher(
        duration: Tokens.durationFast,
        child: _buildIcon(),
      ),
      tooltip: _tooltip,
    );
  }

  Widget _buildIcon() {
    switch (status) {
      case SyncStatus.connected:
        return const Icon(
          Icons.watch,
          key: ValueKey('connected'),
          color: Tokens.success,
        );
      case SyncStatus.disconnected:
        return const Icon(
          Icons.watch_off,
          key: ValueKey('disconnected'),
          color: Tokens.textTertiary,
        );
      case SyncStatus.syncing:
        return const SizedBox(
          key: ValueKey('syncing'),
          width: Tokens.iconSizeMd,
          height: Tokens.iconSizeMd,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Tokens.primary,
          ),
        );
    }
  }

  String get _tooltip {
    switch (status) {
      case SyncStatus.connected:
        return 'Watch connected';
      case SyncStatus.disconnected:
        return 'Watch disconnected';
      case SyncStatus.syncing:
        return 'Syncing...';
    }
  }
}
