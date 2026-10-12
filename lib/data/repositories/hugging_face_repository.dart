import '../models/gguf_file.dart';
import '../models/hf_repo_summary.dart';
import '../sources/hf_api_client.dart';

class HuggingFaceRepository {
  HuggingFaceRepository(this._client, this._token);

  final HfApiClient _client;

  final Future<String?> Function() _token;

  final Map<String, Future<HfRepoSummary>> _details =
      <String, Future<HfRepoSummary>>{};
  final Map<String, Future<List<GgufFile>>> _files =
      <String, Future<List<GgufFile>>>{};

  Future<HfRepoSummary> detailsOf(String repoId) => _details[repoId] ??= _guard(
    _details,
    repoId,
    () async => _client.repoDetails(repoId, token: await _token()),
  );

  Future<List<GgufFile>> filesOf(String repoId) => _files[repoId] ??= _guard(
    _files,
    repoId,
    () async => _client.listFiles(repoId, token: await _token()),
  );

  Future<String> verifyToken(String token) => _client.whoami(token);

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
