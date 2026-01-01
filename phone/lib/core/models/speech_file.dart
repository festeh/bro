class SpeechSegment {
  final String id;
  final DateTime timestamp;
  final Duration duration;
  final List<double> waveform;

  const SpeechSegment({
    required this.id,
    required this.timestamp,
    required this.duration,
    required this.waveform,
  });

  factory SpeechSegment.fromMap(Map<String, dynamic> map) {
    return SpeechSegment(
      id: map['id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      duration: Duration(milliseconds: map['durationMs'] as int),
      waveform: (map['waveform'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  String get formattedDuration {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
