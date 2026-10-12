import 'dart:developer' as developer;

import '../models/usage_record.dart';
import '../sources/json_file_store.dart';

class UsageRepository {
  const UsageRepository(this._store);
  final JsonFileStore _store;
  static const Duration _recentWindow = Duration(days: 30);
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

  Future<UsageLedger> add(UsageRecord record) async {
    final ledger = (await load()).plus(record);
    await save(ledger);
    return ledger;
  }

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
