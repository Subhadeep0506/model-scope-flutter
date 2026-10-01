import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage for secrets.
///
/// An interface rather than a concrete class so widget tests can swap in an
/// in-memory fake — [FlutterSecureStorage] talks to a platform channel that is
/// not available under `flutter test`.
abstract interface class SecureKeyStore {
  Future<String?> read(String key);

  /// Writing an empty value deletes the entry rather than storing a blank.
  Future<void> write(String key, String value);
}

/// [SecureKeyStore] backed by the iOS Keychain and the Android Keystore.
///
/// A Hugging Face token can read gated repositories and, depending on its
/// scopes, write to them — so it is a real credential and does not belong in
/// the plaintext `settings.json` that holds the sampler knobs.
class PlatformSecureKeyStore implements SecureKeyStore {
  const PlatformSecureKeyStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (error, stackTrace) {
      // A keychain that refuses to open should not stop Settings from
      // rendering; the field simply comes up empty.
      developer.log(
        'Could not read $key',
        name: 'PlatformSecureKeyStore',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
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
        name: 'PlatformSecureKeyStore',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
