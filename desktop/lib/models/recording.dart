class Recording {
  final String id;
  final String? egressId;
  final String title;
  final int durationMs;
  final String filePath;
  final DateTime createdAt;
  final List<double>? waveformData;
  final String? transcript;

  Recording({
    required this.id,
    this.egressId,
    required this.title,
    required this.durationMs,
    required this.filePath,
    required this.createdAt,
    this.waveformData,
    this.transcript,
  });

  bool get hasTranscript => transcript != null && transcript!.isNotEmpty;

  Duration get duration => Duration(milliseconds: durationMs);

  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordingDate = DateTime(
      createdAt.year,
      createdAt.month,
      createdAt.day,
    );

    if (recordingDate == today) {
      return 'Today ${_formatTime(createdAt)}';
    } else if (recordingDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${_formatTime(createdAt)}';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year} ${_formatTime(createdAt)}';
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'egress_id': egressId,
      'title': title,
      'duration_ms': durationMs,
      'file_path': filePath,
      'created_at': createdAt.toIso8601String(),
      'waveform_data': waveformData?.join(','),
      'transcript': transcript,
    };
  }

  factory Recording.fromMap(Map<String, dynamic> map) {
    List<double>? waveform;
    if (map['waveform_data'] != null && map['waveform_data'].isNotEmpty) {
      waveform = (map['waveform_data'] as String)
          .split(',')
          .map((e) => double.tryParse(e) ?? 0.0)
          .toList();
    }

    return Recording(
      id: map['id'],
      egressId: map['egress_id'],
      title: map['title'],
      durationMs: map['duration_ms'],
      filePath: map['file_path'],
      createdAt: DateTime.parse(map['created_at']),
      waveformData: waveform,
      transcript: map['transcript'],
    );
  }

  Recording copyWith({
    String? id,
    String? egressId,
    String? title,
    int? durationMs,
    String? filePath,
    DateTime? createdAt,
    List<double>? waveformData,
    String? transcript,
  }) {
    return Recording(
      id: id ?? this.id,
      egressId: egressId ?? this.egressId,
      title: title ?? this.title,
      durationMs: durationMs ?? this.durationMs,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      waveformData: waveformData ?? this.waveformData,
      transcript: transcript ?? this.transcript,
    );
  }
}
