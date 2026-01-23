import 'package:flutter/material.dart';

import '../services/livekit_service.dart';
import '../theme/tokens.dart';

class SttProviderSelector extends StatelessWidget {
  final SttProvider currentProvider;
  final ValueChanged<SttProvider> onChanged;

  const SttProviderSelector({
    super.key,
    required this.currentProvider,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SttProvider>(
      initialValue: currentProvider,
      onSelected: onChanged,
      tooltip: 'Select STT provider',
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: SttProvider.deepgram,
          child: Text('Deepgram'),
        ),
        const PopupMenuItem(
          value: SttProvider.elevenlabs,
          child: Text('ElevenLabs'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spacingSm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic, size: 16, color: AppTokens.textSecondary),
            const SizedBox(width: 4),
            Text(
              currentProvider.name,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                fontSize: AppTokens.fontSizeSm,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: AppTokens.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
