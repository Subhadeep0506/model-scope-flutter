import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/catalog_model.dart';

class CatalogRepository {
  CatalogRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetPath = 'assets/catalog/models.json';
  final AssetBundle _bundle;
  Future<List<CatalogModel>>? _cached;
  Future<List<CatalogModel>> load() => _cached ??= _read();

  Future<List<CatalogModel>> _read() async {
    final body = await _bundle.loadString(assetPath);
    return compute(_decodeCatalog, body);
  }
}

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
