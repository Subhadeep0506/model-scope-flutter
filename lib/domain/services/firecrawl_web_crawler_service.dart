import 'dart:developer' as developer;

import '../../data/models/scraped_page.dart';
import '../../data/sources/firecrawl_api_client.dart';

typedef BatchScrapeOutcome = ({
  List<ScrapedPage> pages,
  List<BatchScrapeError> errors,
});

class FirecrawlWebCrawlerService {
  FirecrawlWebCrawlerService(
    this._client,
    this._apiKey, {
    this.onlyMainContent = true,
    this.timeout = const Duration(seconds: 60),
  });

  final FirecrawlApiClient _client;

  /// Returns the stored Firecrawl key, or an empty string when none is set.
  final Future<String> Function() _apiKey;

  /// Strip navigation, footers and sidebars. On by default: the boilerplate of
  /// a typical page is most of its bytes and none of its meaning.
  final bool onlyMainContent;

  /// How long Firecrawl may spend on one page before giving up.
  final Duration timeout;

  static const String _logName = 'FirecrawlWebCrawlerService';

  /// Whether a scrape can be run at all.
  Future<bool> get isConfigured async => (await _apiKey()).isNotEmpty;

  /// Fetches [url] as markdown.
  Future<ScrapedPage> read(String url) async {
    final target = _requireUrl(url);
    final page = await _client.scrape(
      apiKey: await _requireKey(),
      url: target,
      onlyMainContent: onlyMainContent,
      timeout: timeout,
    );
    developer.log(
      'Read $target: ${page.markdown.length} characters',
      name: _logName,
    );
    return page;
  }

  Future<BatchScrapeOutcome> readAll(
    List<String> urls, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration deadline = const Duration(minutes: 5),
  }) async {
    final targets = urls.map(_requireUrl).toList(growable: false);
    if (targets.isEmpty) {
      throw const FirecrawlApiException('A batch needs at least one URL.');
    }

    final key = await _requireKey();
    final jobId = await _client.startBatch(
      apiKey: key,
      urls: targets,
      onlyMainContent: onlyMainContent,
    );
    developer.log(
      'Batch $jobId started on ${targets.length} URLs',
      name: _logName,
    );

    await _awaitJob(key, jobId, pollInterval, deadline);
    return (
      pages: await _collectPages(key, jobId),
      errors: await _client.batchErrors(apiKey: key, jobId: jobId),
    );
  }

  Future<void> _awaitJob(
    String key,
    String jobId,
    Duration pollInterval,
    Duration deadline,
  ) async {
    final expiry = DateTime.now().add(deadline);
    while (true) {
      final poll = await _client.batchStatus(apiKey: key, jobId: jobId);
      if (poll.status.isFinished) return;
      if (DateTime.now().isAfter(expiry)) {
        throw FirecrawlApiException(
          'Firecrawl was still scraping after ${deadline.inSeconds}s '
          '(${poll.completed} of ${poll.total} done).',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<List<ScrapedPage>> _collectPages(String key, String jobId) async {
    final pages = <ScrapedPage>[];
    String? cursor;
    do {
      final poll = await _client.batchStatus(
        apiKey: key,
        jobId: jobId,
        page: cursor,
      );
      pages.addAll(poll.pages);
      cursor = poll.next;
    } while (cursor != null);
    return pages;
  }

  static String _requireUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const FirecrawlApiException('No address was given to read.');
    }

    final parsed = trimmed.contains(RegExp(r'\s'))
        ? null
        : Uri.tryParse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
    if (parsed == null ||
        !parsed.host.contains('.') ||
        !<String>['http', 'https'].contains(parsed.scheme)) {
      throw FirecrawlApiException(
        '"$url" is not a web address. Give a full address such as '
        'https://example.com/page, or search for one first.',
      );
    }
    return parsed.toString();
  }

  /// The stored key, or a failure a caller can show as-is.
  Future<String> _requireKey() async {
    final key = await _apiKey();
    if (key.isEmpty) {
      throw const FirecrawlApiException(
        'No Firecrawl key is set. Add one under Settings, API keys to read '
        'web pages.',
      );
    }
    return key;
  }
}
