import '../models/gguf_file.dart';
import '../models/hf_repo_summary.dart';
import '../sources/hf_api_client.dart';

/// What the app asks Hugging Face about a repository it already knows of: the
/// two things that cannot be shipped — live stats, and downloadable files.
/// Both are memoised per repository, so a provider rebuild cannot make the
/// same request twice. The Hub rate-limits unauthenticated clients hard.
class HuggingFaceRepository {
  HuggingFaceRepository(this._client, this._token);

  final HfApiClient _client;

  /// Reads the stored Hugging Face token at call time rather than holding a
  /// copy, so a key typed into Settings takes effect on the next request.
  final Future<String?> Function() _token;

  final Map<String, Future<HfRepoSummary>> _details =
      <String, Future<HfRepoSummary>>{};
  final Map<String, Future<List<GgufFile>>> _files =
      <String, Future<List<GgufFile>>>{};

  /// Downloads, likes and file count for [repoId].
  Future<HfRepoSummary> detailsOf(String repoId) => _details[repoId] ??= _guard(
    _details,
    repoId,
    () async => _client.repoDetails(repoId, token: await _token()),
  );

  /// The `.gguf` files in [repoId], weights first.
  Future<List<GgufFile>> filesOf(String repoId) => _files[repoId] ??= _guard(
    _files,
    repoId,
    () async => _client.listFiles(repoId, token: await _token()),
  );

  /// The account name a token belongs to, for the Verify button.
  Future<String> verifyToken(String token) => _client.whoami(token);

  /// Caches the in-flight future so two cards asking at once share one
  /// request, but drops it on failure — otherwise one rate-limited response
  /// would be this repository's answer for the rest of the run, and Retry
  /// could never succeed.
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
