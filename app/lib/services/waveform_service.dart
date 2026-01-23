import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:logging/logging.dart';

final _log = Logger('WaveformService');

/// Extracts waveform amplitude data from audio files using ffmpeg.
class WaveformService {
  /// Extract waveform data from an audio file.
  /// Returns a list of normalized amplitude values (0.0 to 1.0).
  /// Returns null if file doesn't exist yet (caller should retry later).
  /// Returns empty list on permanent failures.
  Future<List<double>?> extractWaveform(
    String filePath, {
    int samples = 50,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      _log.fine('File not ready yet: $filePath');
      return null; // Signal to retry later
    }

    try {
      // Use ffmpeg to convert to raw PCM (mono, 8kHz, 16-bit signed LE)
      final result = await Process.run(
        'ffmpeg',
        [
          '-i', filePath,
          '-ac', '1', // mono
          '-ar', '8000', // 8kHz sample rate
          '-f', 's16le', // raw 16-bit signed little-endian
          '-v', 'quiet', // suppress output
          'pipe:1', // output to stdout
        ],
        stdoutEncoding: null, // Return raw bytes
      );

      if (result.exitCode != 0) {
        _log.warning('ffmpeg failed with exit code ${result.exitCode}');
        return [];
      }

      final bytes = result.stdout as List<int>;
      if (bytes.isEmpty) {
        _log.warning('No audio data in file');
        return [];
      }

      return _calculateAmplitudes(Uint8List.fromList(bytes), samples);
    } catch (e) {
      _log.warning('Error extracting waveform', e);
      return [];
    }
  }

  /// Calculate peak amplitudes from raw PCM data.
  List<double> _calculateAmplitudes(Uint8List pcmData, int samples) {
    // Each sample is 2 bytes (16-bit)
    final totalSamples = pcmData.length ~/ 2;
    if (totalSamples == 0) {
      _log.warning('No PCM samples in data');
      return [];
    }

    final samplesPerBucket = totalSamples ~/ samples;
    if (samplesPerBucket == 0) {
      _log.warning('Audio too short for waveform extraction');
      return [];
    }

    final amplitudes = <double>[];
    final byteData = ByteData.sublistView(pcmData);

    for (var i = 0; i < samples; i++) {
      final start = i * samplesPerBucket;
      final end = math.min(start + samplesPerBucket, totalSamples);

      // Find peak amplitude in this bucket
      var peak = 0;
      for (var j = start; j < end; j++) {
        final sample = byteData.getInt16(j * 2, Endian.little).abs();
        if (sample > peak) {
          peak = sample;
        }
      }

      // Normalize to 0-1 range (max 16-bit value is 32767)
      amplitudes.add(peak / 32767);
    }

    // Normalize to use full range and apply curve for visual appeal
    final maxAmp = amplitudes.reduce(math.max);
    final minAmp = amplitudes.reduce(math.min);
    final range = maxAmp - minAmp;

    if (range > 0) {
      return amplitudes.map((a) {
        // Normalize to 0-1
        final normalized = (a - minAmp) / range;
        // Apply sqrt curve to boost quieter parts
        return (0.15 + 0.85 * math.sqrt(normalized)).clamp(0.15, 1.0);
      }).toList();
    }

    // Uniform amplitude (silent or constant tone)
    _log.warning('Uniform amplitude in audio - no variation to display');
    return [];
  }
}
