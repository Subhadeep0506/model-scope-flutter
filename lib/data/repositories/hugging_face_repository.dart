import '../models/gguf_file.dart';
import '../models/hf_repo_summary.dart';
import '../sources/hf_api_client.dart';

/// The app's view of the Hugging Face catalog.
abstract interface class HuggingFaceRepository {
  /// One page of GGUF repositories. Pass a previous page's `nextCursor` to go
  /// on; pass null for the first page.
  Future<HfRepoPage> search({
    required CatalogSort sort,
    required String query,
    String? cursor,
  });

  /// The downloadable quants in [repoId].
  Future<List<GgufFile>> filesOf(String repoId);

  /// The account name a token belongs to, for the Verify button.
  Future<String> verifyToken(String token);
}

/// [HuggingFaceRepository] over the Hub REST API.
///
/// Holds a per-repository file cache. The browse sheet resolves quant chips
/// lazily, one call per card as it scrolls into view, so a user scrolling back
/// and forth would otherwise re-request the same trees and walk straight into
/// the Hub's rate limit.
class HfHuggingFaceRepository implements HuggingFaceRepository {
  HfHuggingFaceRepository(this._client, this._token);

  final HfApiClient _client;

  /// Reads the stored Hugging Face token at call time rather than holding a
  /// copy, so a key typed into Settings takes effect on the next request.
  final Future<String?> Function() _token;

  final Map<String, List<GgufFile>> _files = <String, List<GgufFile>>{};

  @override
  Future<HfRepoPage> search({
    required CatalogSort sort,
    required String query,
    String? cursor,
  }) async => _client.listModels(
    sort: sort,
    query: query,
    cursor: cursor,
    token: await _token(),
  );

  @override
  Future<List<GgufFile>> filesOf(String repoId) async {
    final cached = _files[repoId];
    if (cached != null) return cached;

    final files = await _client.listFiles(repoId, token: await _token());
    _files[repoId] = files;
    return files;
  }

  @override
  Future<String> verifyToken(String token) => _client.whoami(token);
}
