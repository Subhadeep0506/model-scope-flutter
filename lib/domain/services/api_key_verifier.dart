import '../../data/models/api_keys.dart';
import '../../data/repositories/hugging_face_repository.dart';
import '../../data/sources/firecrawl_api_client.dart';
import '../../data/sources/tavily_api_client.dart';

/// Checks a credential against the service it belongs to, and says what it
/// found.
///
/// Every endpoint used here reports on the key rather than doing work with it,
/// so pressing Verify costs no credits on any of the three: Hugging Face's
/// `whoami` names the account, Tavily's `/usage` and Firecrawl's
/// `/team/credit-usage` read the billing cycle. Checking a search key by
/// searching would bill the user for pressing a button.
///
/// Throws the service's own exception when the key is bad, whose message is
/// already written to be shown as-is.
class ApiKeyVerifier {
  const ApiKeyVerifier(this._huggingFace, this._tavily, this._firecrawl);

  final HuggingFaceRepository _huggingFace;
  final TavilyApiClient _tavily;
  final FirecrawlApiClient _firecrawl;

  /// The caption for a key that checked out.
  Future<String> verify(ApiKeyKind kind, String token) async => switch (kind) {
    ApiKeyKind.huggingFace =>
      'Verified as ${await _huggingFace.verifyToken(token)}',
    ApiKeyKind.tavily => _describeTavily(await _tavily.usage(apiKey: token)),
    ApiKeyKind.firecrawl => _describeFirecrawl(
      await _firecrawl.creditUsage(apiKey: token),
    ),
  };

  /// `Verified · Bootstrap plan · 412 of 4000 credits used`, or without the
  /// total when the plan has no cap.
  static String _describeTavily(TavilyUsage usage) {
    final spend = usage.limit == null
        ? '${usage.used} credits used'
        : '${usage.used} of ${usage.limit} credits used';
    return 'Verified · ${usage.plan} plan · $spend';
  }

  /// `Verified · 3588 credits left`.
  static String _describeFirecrawl(FirecrawlCredits credits) =>
      'Verified · ${credits.remaining} '
      '${credits.remaining == 1 ? 'credit' : 'credits'} left';
}
