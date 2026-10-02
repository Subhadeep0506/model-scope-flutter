import '../models/gguf_file.dart';
import '../models/hf_repo_summary.dart';
import '../sources/hf_api_client.dart';

/// What the app asks Hugging Face about a repository it already knows of.
///
/// There is no search: the list of models comes from the shipped catalog, so
/// the Hub is only consulted for the two things that cannot be shipped — live
/// stats, and the files available to download.
abstract interface class HuggingFaceRepository {
  /// Downloads, likes and file count for [repoId].
  Future<HfRepoSummary> detailsOf(String repoId);

  /// The `.gguf` files in [repoId], weights first.
  Future<List<GgufFile>> filesOf(String repoId);

  /// The account name a token belongs to, for the Verify button.
  Future<String> verifyToken(String token);
}

/// [HuggingFaceRepository] over the Hub REST API.
///
/// Both lookups are memoised per repository. Riverpod caches them a second time
/// at the provider level, but keeping the cache here as well means the catalog
/// and the model sheet cannot ask twice for the same thing across a provider
/// rebuild — the Hub rate-limits unauthenticated clients hard.
class HfHuggingFaceRepository implements HuggingFaceRepository {
  HfHuggingFaceRepository(this._client, this._token);

  final HfApiClient _client;

  /// Reads the stored Hugging Face token at call time rather than holding a
  /// copy, so a key typed into Settings takes effect on the next request.
  final Future<String?> Function() _token;

  final Map<String, Future<HfRepoSummary>> _details =
      <String, Future<HfRepoSummary>>{};
  final Map<String, Future<List<GgufFile>>> _files =
      <String, Future<List<GgufFile>>>{};

  @override
  Future<HfRepoSummary> detailsOf(String repoId) => _details[repoId] ??= _guard(
    _details,
    repoId,
    () async => _client.repoDetails(repoId, token: await _token()),
  );

  @override
  Future<List<GgufFile>> filesOf(String repoId) => _files[repoId] ??= _guard(
    _files,
    repoId,
    () async => _client.listFiles(repoId, token: await _token()),
  );

  @override
  Future<String> verifyToken(String token) => _client.whoami(token);

  /// Caches the in-flight future so two cards asking at once share one request,
  /// but drops it again on failure — otherwise a single rate-limited response
  /// would be remembered as this repository's answer for the rest of the run,
  /// and the user's Retry button could never succeed.
  Future<T> _guard<T>(
    Map<String, Future<T>> cache,
    String key,
    Future<T> Function() request,
  ) async {
    try {
      return await request();
    } catch (_) {
      cache.remove(key);
      rethrow;
    }
  }
}
