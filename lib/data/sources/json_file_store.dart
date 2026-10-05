import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Reads and writes one JSON document on disk. Writes go to a temporary file
/// renamed over the real one, so an interrupted write cannot leave half a
/// document behind. Encoding and decoding run on [compute].
class JsonFileStore {
  const JsonFileStore({required this.directory, required this.fileName});

  final Directory directory;
  final String fileName;

  File get _file => File('${directory.path}${Platform.pathSeparator}$fileName');

  /// Returns the stored document, or `null` when nothing has been saved yet or
  /// the file on disk is unreadable.
  Future<Map<String, dynamic>?> read() async {
    try {
      final file = _file;
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return await compute(_decode, raw);
    } catch (error, stackTrace) {
      // A corrupt store should not stop the app from opening; callers fall
      // back to defaults and the next write repairs the file.
      developer.log(
        'Could not read $fileName',
        name: 'JsonFileStore',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Writes [data] over matching top-level keys, leaving the rest untouched.
  /// Several repositories share `settings.json`, and a plain [write] from one
  /// of them would drop the others' keys.
  Future<void> merge(Map<String, dynamic> data) async {
    final existing = await read() ?? <String, dynamic>{};
    await write(<String, dynamic>{...existing, ...data});
  }

  Future<void> write(Map<String, dynamic> data) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final encoded = await compute(_encode, data);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(_file.path);
    } catch (error, stackTrace) {
      developer.log(
        'Could not write $fileName',
        name: 'JsonFileStore',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

Map<String, dynamic> _decode(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

String _encode(Map<String, dynamic> data) => jsonEncode(data);
