import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/recording.dart';

class StorageService {
  static const String _dbName = 'recordings.db';
  static const String _tableName = 'recordings';

  Database? _db;
  final String _recordingsDir;

  final _recordingsController = StreamController<List<Recording>>.broadcast();
  Stream<List<Recording>> get recordingsStream => _recordingsController.stream;

  StorageService({required String recordingsDir})
    : _recordingsDir = recordingsDir;

  String get recordingsDir => _recordingsDir;

  Future<void> init() async {
    // Initialize FFI for desktop
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Ensure recordings directory exists
    final dir = Directory(_recordingsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Open database
    final dbPath = p.join(_recordingsDir, _dbName);
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            egress_id TEXT,
            title TEXT NOT NULL,
            duration_ms INTEGER NOT NULL,
            file_path TEXT NOT NULL,
            created_at TEXT NOT NULL,
            waveform_data TEXT
          )
        ''');
      },
    );

    // Load initial recordings
    await _emitRecordings();
  }

  Future<List<Recording>> getRecordings() async {
    if (_db == null) return [];

    final maps = await _db!.query(_tableName, orderBy: 'created_at DESC');

    return maps.map((m) => Recording.fromMap(m)).toList();
  }

  Future<void> addRecording(Recording recording) async {
    if (_db == null) return;

    await _db!.insert(
      _tableName,
      recording.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _emitRecordings();
  }

  Future<void> updateRecording(Recording recording) async {
    if (_db == null) return;

    await _db!.update(
      _tableName,
      recording.toMap(),
      where: 'id = ?',
      whereArgs: [recording.id],
    );

    await _emitRecordings();
  }

  Future<void> deleteRecording(String id) async {
    if (_db == null) return;

    // Get the recording first to delete the file
    final maps = await _db!.query(_tableName, where: 'id = ?', whereArgs: [id]);

    if (maps.isNotEmpty) {
      final recording = Recording.fromMap(maps.first);
      final file = File(recording.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    await _db!.delete(_tableName, where: 'id = ?', whereArgs: [id]);

    await _emitRecordings();
  }

  Future<void> _emitRecordings() async {
    final recordings = await getRecordings();
    _recordingsController.add(recordings);
  }

  /// Scan the recordings directory for new files not in the database
  Future<List<String>> scanForNewFiles() async {
    final dir = Directory(_recordingsDir);
    if (!await dir.exists()) return [];

    final existingPaths = (await getRecordings())
        .map((r) => r.filePath)
        .toSet();
    final newFiles = <String>[];

    await for (final entity in dir.list()) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (['.ogg', '.mp3', '.wav', '.opus'].contains(ext)) {
          if (!existingPaths.contains(entity.path)) {
            newFiles.add(entity.path);
          }
        }
      }
    }

    return newFiles;
  }

  String get recordingsDirectory => _recordingsDir;

  void dispose() {
    _recordingsController.close();
    _db?.close();
  }
}
