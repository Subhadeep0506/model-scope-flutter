import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/usage_record.dart';

/// Owns the permanent record of what the models on this device have done.
class UsageLedgerViewModel extends AsyncNotifier<UsageLedger> {
  static const String _logName = 'UsageLedgerViewModel';

  @override
  Future<UsageLedger> build() async {
    final repository = ref.read(usageRepositoryProvider);
    final stored = await repository.load();
    if (stored.migrated) return stored;

    final sessions = await ref.read(sessionsViewModelProvider.future);
    final library = await ref.read(modelLibraryViewModelProvider.future);
    return repository.importOnce(
      recordsFromSessions(
        sessions,
        nameOf: (modelId) => library.byId(modelId)?.name ?? '',
      ),
    );
  }

  Future<void> record(UsageRecord record) async {
    try {
      state = AsyncData<UsageLedger>(
        await ref.read(usageRepositoryProvider).add(record),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Could not record usage',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
