import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class LiveTranscript extends StatelessWidget {
  final String? text;

  const LiveTranscript({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spacingMd),
      decoration: BoxDecoration(
        color: AppTokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        text!,
        style: const TextStyle(
          color: AppTokens.textSecondary,
          fontSize: AppTokens.fontSizeSm,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
