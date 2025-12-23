enum VadStatus { idle, listening, speech, silence, error }

enum PermissionStatus { unknown, granted, denied, permanentlyDenied }

class VadState {
  final VadStatus status;
  final PermissionStatus permission;
  final double? speechProbability;
  final Duration? speechDuration;
  final DateTime? lastSpeechAt;

  const VadState({
    this.status = VadStatus.idle,
    this.permission = PermissionStatus.unknown,
    this.speechProbability,
    this.speechDuration,
    this.lastSpeechAt,
  });

  VadState copyWith({
    VadStatus? status,
    PermissionStatus? permission,
    double? speechProbability,
    Duration? speechDuration,
    DateTime? lastSpeechAt,
  }) {
    return VadState(
      status: status ?? this.status,
      permission: permission ?? this.permission,
      speechProbability: speechProbability ?? this.speechProbability,
      speechDuration: speechDuration ?? this.speechDuration,
      lastSpeechAt: lastSpeechAt ?? this.lastSpeechAt,
    );
  }

  factory VadState.fromMap(Map<dynamic, dynamic> map) {
    final statusStr = map['status'] as String? ?? 'idle';
    VadStatus status;
    switch (statusStr) {
      case 'listening':
        status = VadStatus.listening;
        break;
      case 'speech':
        status = VadStatus.speech;
        break;
      case 'silence':
        status = VadStatus.silence;
        break;
      case 'error':
        status = VadStatus.error;
        break;
      default:
        status = VadStatus.idle;
    }

    return VadState(
      status: status,
      speechProbability: map['probability'] as double?,
      lastSpeechAt: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : null,
    );
  }
}
