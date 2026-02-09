import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recording.dart';
import '../services/storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

/// Recordings list, updated whenever storage changes.
final recordingsProvider = StreamProvider<List<Recording>>((ref) {
  return ref.watch(storageServiceProvider).recordingsStream;
});
