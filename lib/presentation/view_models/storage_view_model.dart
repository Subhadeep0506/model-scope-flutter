import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';

/// Owns the Storage card: how much the app itself is holding on disk.
class StorageViewModel extends AsyncNotifier<int> {
  @override
  Future<int> build() => ref.read(appCacheServiceProvider).sizeInBytes();

  /// Deletes the app's own files and re-measures. Downloaded weights are
  /// untouched — those are removed one at a time from the Models list.
  Future<void> clear() async {
    await ref.read(appCacheServiceProvider).clear();
    state = await AsyncValue.guard(
      () => ref.read(appCacheServiceProvider).sizeInBytes(),
    );
  }
}
