import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/gguf_file.dart';
import '../models/hf_repo_summary.dart';

/// How the catalog is ordered. The values are Hugging Face's `sort` parameter.
enum CatalogSort {
  downloads('downloads', 'Downloads'),
  likes('likes', 'Likes'),
  trending('trendingScore', 'Trending');

  const CatalogSort(this.query, this.label);

  final String query;
  final String label;
}

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

/// Thin client over the Hugging Face Hub REST API.
///
/// Takes its [http.Client] by injection so tests can drive it with a
/// `MockClient` instead of the network.
class HfApiClient {
  const HfApiClient(this._client);

  final http.Client _client;

  static const String _host = 'huggingface.co';

  /// Hugging Face paginates with an opaque cursor, so a page size only sets how
  /// much arrives per request. Twenty fills roughly two screens of repo cards.
  static const int pageSize = 20;

  /// Lists GGUF repositories, newest cursor-paginated page first.
  ///
  /// [cursor] comes from a previous page's `nextCursor`; pass null for page
  /// one. `pipeline_tag=text-generation` is not optional: `filter=gguf` alone
  /// also returns embedding, vision and object-detection repos, none of which
  /// can answer a chat prompt.
  Future<HfRepoPage> listModels({
    CatalogSort sort = CatalogSort.downloads,
    String query = '',
    String? cursor,
    String? token,
  }) async {
    final uri = Uri.https(_host, '/api/models', <String, String>{
      'filter': 'gguf',
      'pipeline_tag': 'text-generation',
      'sort': sort.query,
      'direction': '-1',
      'limit': '$pageSize',
      if (query.trim().isNotEmpty) 'search': query.trim(),
      'cursor': ?cursor,
    });

    final response = await _get(uri, token);
    final items = await compute(_decodeRepos, response.body);
    return HfRepoPage(items: items, nextCursor: _nextCursor(response.headers));
  }

  /// Lists the loadable `.gguf` files in [repoId], largest detail first.
  ///
  /// Two kinds of file are filtered out rather than shown:
  ///
  /// * `mmproj-*` — vision projectors. They are `.gguf` files but cannot
  ///   generate text on their own, so offering one is offering a broken model.
  /// * `*-00001-of-00009.gguf` — shards of a split model. Downloading a single
  ///   shard always fails at load time, and this build has no multi-file
  ///   download flow.
  Future<List<GgufFile>> listFiles(String repoId, {String? token}) async {
    final uri = Uri.https(_host, '/api/models/$repoId/tree/main');
    final response = await _get(uri, token);
    final entries = await compute(_decodeTree, response.body);

    return <GgufFile>[
      for (final (name, size) in entries)
        if (_isLoadableGguf(name))
          GgufFile(repoId: repoId, fileName: name, sizeBytes: size),
    ]..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
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

  /// The bearer header for [token], or no headers when there is none.
  ///
  /// Shared with the downloader, which needs the identical header to pull a
  /// gated repository.
  static Map<String, String> authHeaders(String? token) {
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) return const <String, String>{};
    return <String, String>{'Authorization': 'Bearer $trimmed'};
  }

  /// Extracts the cursor from `Link: <…&cursor=abc>; rel="next"`.
  ///
  /// Returns null on the last page, where the header is absent entirely.
  static String? _nextCursor(Map<String, String> headers) {
    final link = headers['link'] ?? headers['Link'];
    if (link == null) return null;

    for (final part in link.split(',')) {
      if (!part.contains('rel="next"')) continue;
      final start = part.indexOf('<');
      final end = part.indexOf('>');
      if (start < 0 || end <= start) continue;
      final uri = Uri.tryParse(part.substring(start + 1, end));
      return uri?.queryParameters['cursor'];
    }
    return null;
  }

  static bool _isLoadableGguf(String name) {
    final lower = name.toLowerCase();
    if (!lower.endsWith('.gguf')) return false;
    if (lower.contains('mmproj')) return false;
    if (RegExp(r'-\d{5}-of-\d{5}\.gguf$').hasMatch(lower)) return false;
    return true;
  }
}

/// Parsed off the UI isolate: a catalog page is tens of kilobytes of JSON and a
/// tree response for a large repository can run to hundreds.
List<HfRepoSummary> _decodeRepos(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) return const <HfRepoSummary>[];
  return <HfRepoSummary>[
    for (final entry in decoded)
      if (entry is Map<String, dynamic>) HfRepoSummary.fromJson(entry),
  ];
}

/// Returns `(fileName, sizeBytes)` for every file in the tree.
///
/// `lfs.size` is the authoritative byte count for a GGUF — the top-level `size`
/// can be the size of the LFS pointer rather than the payload — so it wins when
/// present.
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
