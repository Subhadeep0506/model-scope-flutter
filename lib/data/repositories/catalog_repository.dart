import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/catalog_model.dart';

/// The models this build offers to download.
abstract interface class CatalogRepository {
  /// The curated list, in the order it should be drawn.
  Future<List<CatalogModel>> load();
}

/// [CatalogRepository] over the `assets/catalog/models.json` manifest.
///
/// The manifest ships with the app, so this never touches the network and never
/// fails for a user — which is the whole point of the curated catalog. Adding a
/// model means editing the JSON and shipping a build.
class AssetCatalogRepository implements CatalogRepository {
  AssetCatalogRepository({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const String assetPath = 'assets/catalog/models.json';

  final AssetBundle _bundle;

  /// Decoded once and held: the manifest cannot change while the app runs, and
  /// the catalog screen rebuilds on every keystroke in its search field.
  Future<List<CatalogModel>>? _cached;

  @override
  Future<List<CatalogModel>> load() => _cached ??= _read();

  Future<List<CatalogModel>> _read() async {
    final body = await _bundle.loadString(assetPath);
    return compute(_decodeCatalog, body);
  }
}

/// Parsed off the UI isolate, for consistency with the Hub responses rather
/// than because the manifest is large.
///
/// A malformed entry throws rather than being skipped: the file is authored in
/// this repository, so a bad one is a build-time mistake that should be loud.
List<CatalogModel> _decodeCatalog(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const FormatException('The model catalog must be a JSON list.');
  }
  return <CatalogModel>[
    for (final entry in decoded)
      CatalogModel.fromJson(entry as Map<String, dynamic>),
  ];
}
