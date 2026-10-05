import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/gguf_file.dart';
import '../models/hf_repo_summary.dart';

/// A call to the Hub failed in a way worth telling the user about.
class HfApiException implements Exception {
  const HfApiException(this.message, {this.isRateLimit = false});

  final String message;

  /// Hugging Face throttles unauthenticated clients hard, and the fix — add a
  /// token — is something the user can act on, so it is called out separately.
  final bool isRateLimit;

  @override
  String toString() => message;
}

/// Thin client over the Hugging Face Hub REST API. No search: the app browses
/// a catalog it ships, so the Hub is only asked about a repository the user has
/// named, which is what keeps the device under the rate limit.
class HfApiClient {
  const HfApiClient(this._client);

  final http.Client _client;

  static const String _host = 'huggingface.co';

  /// The live stats for [repoId]. A failure here costs the card's stats row
  /// and nothing else; the rest comes from the shipped manifest.
  Future<HfRepoSummary> repoDetails(String repoId, {String? token}) async {
    final response = await _get(Uri.https(_host, '/api/models/$repoId'), token);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const HfApiException(
        'Hugging Face returned an unexpected response.',
      );
    }
    return HfRepoSummary.fromJson(decoded);
  }

  /// Lists the `.gguf` files in [repoId], smallest first. Projectors and
  /// adapters are kept as reference rows; shards of a split model
  /// (`*-00001-of-00009.gguf`) are dropped, as one shard always fails to load.
  Future<List<GgufFile>> listFiles(String repoId, {String? token}) async {
    final uri = Uri.https(_host, '/api/models/$repoId/tree/main');
    final response = await _get(uri, token);
    final entries = await compute(_decodeTree, response.body);

    return <GgufFile>[
      for (final (name, size) in entries)
        if (_isGguf(name) && !_isShard(name))
          GgufFile(
            repoId: repoId,
            fileName: name,
            sizeBytes: size,
            kind: _kindOf(name),
          ),
    ]..sort(_byKindThenSize);
  }

  /// Returns the account name [token] belongs to. Backs the Verify button.
  Future<String> whoami(String token) async {
    final response = await _get(Uri.https(_host, '/api/whoami-v2'), token);
    final body = jsonDecode(response.body);
    if (body is Map<String, dynamic> && body['name'] is String) {
      return body['name'] as String;
    }
    throw const HfApiException('Hugging Face returned an unexpected response.');
  }

  Future<http.Response> _get(Uri uri, String? token) async {
    final http.Response response;
    try {
      response = await _client.get(uri, headers: authHeaders(token));
    } on SocketException {
      throw const HfApiException('No connection to Hugging Face.');
    } on http.ClientException catch (error) {
      throw HfApiException('Could not reach Hugging Face: ${error.message}');
    }

    return switch (response.statusCode) {
      200 => response,
      401 || 403 => throw const HfApiException(
        'That token was rejected by Hugging Face.',
      ),
      404 => throw const HfApiException('That repository no longer exists.'),
      429 => throw const HfApiException(
        'Hugging Face is rate-limiting this device. Add a token under API '
        'keys to raise the limit.',
        isRateLimit: true,
      ),
      _ => throw HfApiException(
        'Hugging Face returned ${response.statusCode}.',
      ),
    };
  }

  /// The bearer header for [token], or no headers when there is none. Shared
  /// with the downloader, which needs the identical header for a gated repo.
  static Map<String, String> authHeaders(String? token) {
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) return const <String, String>{};
    return <String, String>{'Authorization': 'Bearer $trimmed'};
  }

  /// Weights first, then projectors and adapters, each smallest first — so the
  /// rows the user can act on are at the top of the sheet.
  static int _byKindThenSize(GgufFile a, GgufFile b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    return a.sizeBytes.compareTo(b.sizeBytes);
  }

  static bool _isGguf(String name) => name.toLowerCase().endsWith('.gguf');

  static bool _isShard(String name) =>
      RegExp(r'-\d{5}-of-\d{5}\.gguf$', caseSensitive: false).hasMatch(name);

  static GgufFileKind _kindOf(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('mmproj')) return GgufFileKind.mmproj;
    if (lower.contains('lora') || lower.contains('adapter')) {
      return GgufFileKind.adapter;
    }
    return GgufFileKind.model;
  }
}

/// Returns `(fileName, sizeBytes)` for every file in the tree, off the UI
/// isolate — a large repository's tree runs to hundreds of kilobytes of JSON.
/// `lfs.size` wins when present: the top-level `size` can be the size of the
/// LFS pointer rather than the payload.
List<(String, int)> _decodeTree(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) return const <(String, int)>[];

  final files = <(String, int)>[];
  for (final entry in decoded) {
    if (entry is! Map<String, dynamic>) continue;
    if (entry['type'] != 'file') continue;
    final path = entry['path'];
    if (path is! String) continue;

    final size = switch (entry['lfs']) {
      <String, dynamic>{'size': final int lfsSize} => lfsSize,
      _ => entry['size'] is int ? entry['size'] as int : 0,
    };
    files.add((path, size));
  }
  return files;
}
