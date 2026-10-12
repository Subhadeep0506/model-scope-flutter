import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';

/// Owns the Storage card: how much the app itself is holding on disk.
class StorageViewModel extends AsyncNotifier<int> {
  @override
  Future<int> build() => ref.read(appCacheServiceProvider).sizeInBytes();

  Future<void> clear() async {
    await ref.read(appCacheServiceProvider).clear();
    state = await AsyncValue.guard(
      () => ref.read(appCacheServiceProvider).sizeInBytes(),
    );
  }
}
