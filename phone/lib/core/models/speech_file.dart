class SpeechFile {
  final String path;
  final String id;
  final DateTime timestamp;
  final int sizeBytes;

  const SpeechFile({
    required this.path,
    required this.id,
    required this.timestamp,
    required this.sizeBytes,
  });

  factory SpeechFile.fromMap(Map<String, dynamic> map) {
    return SpeechFile(
      path: map['path'] as String,
      id: map['id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      sizeBytes: map['sizeBytes'] as int,
    );
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024)
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
