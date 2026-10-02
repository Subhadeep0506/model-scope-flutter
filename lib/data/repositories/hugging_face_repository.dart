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

  /// The largest model this app offers to download.
  ///
  /// The device runs inference on its own CPU or GPU, and anything above this
  /// either will not load or answers too slowly to judge the package by. The
  /// Hub has no parameter filter, so it is applied here.
  static const double maxParamsInBillions = 4;

  /// How many results a page should carry before it is handed back.
  ///
  /// Filtering client-side means an upstream page of twenty can yield two
  /// rows, which reads as a list that has stopped loading, so [search] keeps
  /// asking until it has roughly half a screen.
  static const int _minVisible = 10;

  /// How many upstream requests one [search] may make. The Hub rate-limits
  /// unauthenticated clients hard, so chasing pages has to stop somewhere.
  static const int _maxFetches = 5;

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
  }) async {
    final token = await _token();
    final items = <HfRepoSummary>[];
    var next = cursor;

    for (var fetch = 0; fetch < _maxFetches; fetch++) {
      final page = await _client.listModels(
        sort: sort,
        query: query,
        cursor: next,
        token: token,
      );
      items.addAll(page.items.where(_isSmallEnough));
      next = page.nextCursor;
      if (next == null || items.length >= _minVisible) break;
    }

    return HfRepoPage(items: items, nextCursor: next);
  }

  /// Keeps a repo whose name states no size.
  ///
  /// Plenty of small models never say (`Phi-3.5-mini-instruct-gguf` says
  /// `mini`), and hiding those would cost more than letting the occasional
  /// large one through — the size is on every quant chip either way.
  ///
  /// A mixture-of-experts name is the exception: `Mixtral-8x7B` states no total
  /// it can be read from, but `8x` of anything is past the cap regardless.
  static bool _isSmallEnough(HfRepoSummary repo) {
    if (repo.isMixtureOfExperts) return false;
    final params = repo.paramsInBillions;
    return params == null || params <= maxParamsInBillions;
  }

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
