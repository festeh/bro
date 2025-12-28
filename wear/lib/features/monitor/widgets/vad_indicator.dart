import 'package:flutter/material.dart';
import '../../../core/platform/vad_state.dart';

class VadIndicator extends StatelessWidget {
  final VadStatus status;

  const VadIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _getBackgroundColor(),
        boxShadow: status == VadStatus.speech
            ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ]
            : null,
      ),
      child: Center(child: Icon(_getIcon(), size: 48, color: Colors.white)),
    );
  }

  Color _getBackgroundColor() {
    switch (status) {
      case VadStatus.speech:
        return Colors.green;
      case VadStatus.silence:
        return Colors.grey.shade700;
      case VadStatus.listening:
        return Colors.blue.shade700;
      case VadStatus.error:
        return Colors.red;
      case VadStatus.idle:
        return Colors.grey.shade800;
    }
  }

  IconData _getIcon() {
    switch (status) {
      case VadStatus.speech:
        return Icons.mic;
      case VadStatus.silence:
        return Icons.mic_none;
      case VadStatus.listening:
        return Icons.hearing;
      case VadStatus.error:
        return Icons.error;
      case VadStatus.idle:
        return Icons.mic_off;
    }
  }
}
