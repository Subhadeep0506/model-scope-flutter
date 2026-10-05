import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage for secrets, backed by the iOS Keychain and the Android Keystore.
/// A Hugging Face token is a real credential and does not belong in the
/// plaintext `settings.json`. Widget tests swap in an in-memory stand-in:
/// [FlutterSecureStorage] needs a platform channel `flutter test` lacks.
class SecureKeyStore {
  const SecureKeyStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (error, stackTrace) {
      // A keychain that refuses to open should not stop Settings from
      // rendering; the field simply comes up empty.
      developer.log(
        'Could not read $key',
        name: 'SecureKeyStore',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Writing an empty value deletes the entry rather than storing a blank.
  Future<void> write(String key, String value) async {
    try {
      if (value.isEmpty) {
        await _storage.delete(key: key);
        return;
      }
      await _storage.write(key: key, value: value);
    } catch (error, stackTrace) {
      developer.log(
        'Could not write $key',
        name: 'SecureKeyStore',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
