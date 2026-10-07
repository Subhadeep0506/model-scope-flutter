import 'dart:developer' as developer;

import '../models/usage_record.dart';
import '../sources/json_file_store.dart';

/// The permanent record of what the models on this device have done.
///
/// Separate from sessions on purpose. Home used to fold its figures out of the
/// stored transcripts, so deleting a chat lowered the lifetime token count and
/// erased a model from the usage list — the work had still happened, and the
/// dashboard said otherwise. Nothing here is ever removed by deleting a
/// session; only [_recentWindow] ages out, and only the day-by-day chart reads
/// that part.
class UsageRepository {
  const UsageRepository(this._store);

  final JsonFileStore _store;

  /// How far back individual records are kept. The latency chart covers seven
  /// days; thirty leaves room to widen it without another migration, and caps
  /// what the file can grow to on a device where storage is the user's.
  static const Duration _recentWindow = Duration(days: 30);

  /// A ceiling as well as a window, for the pathological case of thousands of
  /// replies inside thirty days.
  static const int _recentLimit = 2000;

  static const String _recentKey = 'recent';
  static const String _totalsKey = 'totals';
  static const String _byModelKey = 'by_model';
  static const String _migratedKey = 'migrated';
  static const String _logName = 'UsageRepository';

  Future<UsageLedger> load() async {
    final document = await _store.read();
    if (document == null) return UsageLedger.empty;

    return UsageLedger(
      recent: _parseRecords(document[_recentKey]),
      totals: _parseTotals(document[_totalsKey]),
      byModel: _parseByModel(document[_byModelKey]),
      migrated: document[_migratedKey] == true,
    );
  }

  /// Adds [record] and writes the ledger back.
  ///
  /// Returns what was written, so a caller holding the ledger in state does
  /// not have to read the file again to show the new figure.
  Future<UsageLedger> add(UsageRecord record) async {
    final ledger = (await load()).plus(record);
    await save(ledger);
    return ledger;
  }

  /// Folds [records] in at once and marks the ledger migrated.
  ///
  /// Used for the one-time import of replies that were already on the device
  /// when the ledger was introduced.
  Future<UsageLedger> importOnce(List<UsageRecord> records) async {
    var ledger = await load();
    if (ledger.migrated) return ledger;

    for (final record in records) {
      ledger = ledger.plus(record);
    }
    ledger = ledger.copyWith(migrated: true);
    await save(ledger);

    if (records.isNotEmpty) {
      developer.log(
        'Imported ${records.length} replies from stored sessions',
        name: _logName,
      );
    }
    return ledger;
  }

  Future<void> save(UsageLedger ledger) {
    final recent = _prune(ledger.recent);
    return _store.write(<String, dynamic>{
      _recentKey: <Map<String, dynamic>>[
        for (final record in recent) record.toJson(),
      ],
      _totalsKey: ledger.totals.toJson(),
      _byModelKey: <String, dynamic>{
        for (final entry in ledger.byModel.entries)
          entry.key: entry.value.toJson(),
      },
      _migratedKey: ledger.migrated,
    });
  }

  /// Records inside the window, newest kept when the ceiling bites.
  ///
  /// Only [UsageLedger.recent] is pruned. The totals it was folded into are
  /// already counted and stay exactly as they are — which is what makes a
  /// lifetime figure a lifetime figure.
  static List<UsageRecord> _prune(List<UsageRecord> records, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(_recentWindow);
    final kept = <UsageRecord>[
      for (final record in records)
        if (record.at.isAfter(cutoff)) record,
    ];
    return kept.length <= _recentLimit
        ? kept
        : kept.sublist(kept.length - _recentLimit);
  }

  static List<UsageRecord> _parseRecords(Object? raw) {
    if (raw is! List) return const <UsageRecord>[];

    final records = <UsageRecord>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        records.add(UsageRecord.fromJson(entry));
      } catch (error) {
        // One unreadable row should not cost the whole history.
        developer.log('Skipped an unreadable usage record', name: _logName);
      }
    }
    return records;
  }

  static UsageTotals _parseTotals(Object? raw) {
    if (raw is! Map<String, dynamic>) return UsageTotals.empty;
    try {
      return UsageTotals.fromJson(raw);
    } catch (error) {
      developer.log('Usage totals would not read', name: _logName);
      return UsageTotals.empty;
    }
  }

  static Map<String, ModelTotals> _parseByModel(Object? raw) {
    if (raw is! Map<String, dynamic>) return const <String, ModelTotals>{};

    final totals = <String, ModelTotals>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      try {
        totals[entry.key] = ModelTotals.fromJson(value);
      } catch (error) {
        developer.log(
          'Skipped unreadable totals for ${entry.key}',
          name: _logName,
        );
      }
    }
    return totals;
  }
}
