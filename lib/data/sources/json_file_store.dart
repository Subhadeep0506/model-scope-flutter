import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

class JsonFileStore {
  const JsonFileStore({required this.directory, required this.fileName});

  final Directory directory;
  final String fileName;
  File get _file => File('${directory.path}${Platform.pathSeparator}$fileName');

  Future<Map<String, dynamic>?> read() async {
    try {
      final file = _file;
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return await compute(_decode, raw);
    } catch (error, stackTrace) {
      developer.log(
        'Could not read $fileName',
        name: 'JsonFileStore',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

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
