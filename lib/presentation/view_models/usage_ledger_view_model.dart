import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/di/providers.dart';
import '../../config/di/view_models.dart';
import '../../data/models/usage_record.dart';

/// Owns the permanent record of what the models on this device have done.
///
/// Everything on Home that is a performance figure reads this, so a deleted
/// chat cannot lower it. It is written at exactly two points — when a chat
/// reply finishes, and when an agent run finishes — and is otherwise only
/// read.
class UsageLedgerViewModel extends AsyncNotifier<UsageLedger> {
  static const String _logName = 'UsageLedgerViewModel';

  /// Loads the ledger, importing anything already on the device the first
  /// time it runs.
  ///
  /// Without the import, upgrading to the build that added the ledger would
  /// reset every figure on Home to zero — indistinguishable, from the user's
  /// side, from the bug the ledger exists to fix.
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

  /// Records a finished reply. Failures are logged and swallowed: losing a
  /// statistic must never cost the user the reply it was about.
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
