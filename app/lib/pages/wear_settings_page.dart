import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models_config.dart';
import '../providers/settings_provider.dart';
import '../services/livekit_service.dart';

class WearSettingsPage extends ConsumerWidget {
  const WearSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: _SwipeDetector(
        onSwipeDown: () => Navigator.of(context).pop(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          children: [
            const Center(
              child: Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Container(
                width: 24,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _WearSettingTile(
              label: 'TTS',
              trailing: Switch(
                value: settings.ttsEnabled,
                onChanged: notifier.setTtsEnabled,
                activeTrackColor: Colors.blue,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(height: 8),
            _WearSettingTile(
              label: 'ASR',
              value: _sttLabel(settings.sttProvider),
              onTap: () {
                final values = SttProvider.values;
                final next = values[
                    (values.indexOf(settings.sttProvider) + 1) % values.length];
                notifier.setSttProvider(next);
              },
            ),
            const SizedBox(height: 8),
            _WearSettingTile(
              label: 'LLM',
              value: settings.llmModel.name,
              onTap: () {
                final models = ModelsConfig.instance.llmModels;
                final currentIdx =
                    models.indexWhere((m) => m.modelId == settings.llmModel.modelId);
                final next = models[(currentIdx + 1) % models.length];
                notifier.setLlmModel(next);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _sttLabel(SttProvider provider) {
    switch (provider) {
      case SttProvider.deepgram:
        return 'Deepgram';
      case SttProvider.elevenlabs:
        return 'ElevenLabs';
    }
  }
}

class _SwipeDetector extends StatefulWidget {
  final VoidCallback onSwipeDown;
  final Widget child;

  const _SwipeDetector({required this.onSwipeDown, required this.child});

  @override
  State<_SwipeDetector> createState() => _SwipeDetectorState();
}

class _SwipeDetectorState extends State<_SwipeDetector> {
  double? _startY;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _startY = e.position.dy,
      onPointerUp: (e) {
        if (_startY != null) {
          final dy = e.position.dy - _startY!;
          if (dy > 50) widget.onSwipeDown();
          _startY = null;
        }
      },
      child: widget.child,
    );
  }
}

class _WearSettingTile extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _WearSettingTile({
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            if (trailing != null)
              trailing!
            else if (value != null)
              Flexible(
                child: Text(
                  value!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
