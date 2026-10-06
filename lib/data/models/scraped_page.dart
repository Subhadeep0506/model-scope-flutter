import 'json_read.dart';

/// One web page fetched as markdown, from the `data` object of a Firecrawl
/// scrape. Only the fields a reader needs are kept — the response also carries
/// screenshots, link graphs, branding and a dozen other formats this app never
/// asks for.
class ScrapedPage {
  const ScrapedPage({
    required this.url,
    required this.markdown,
    this.title,
    this.description,
    this.statusCode = 0,
  });

  /// [requestedUrl] is what the caller asked for, and stands in when Firecrawl
  /// reports no source of its own — a page that redirected still has to be
  /// attributable to something.
  factory ScrapedPage.fromJson(
    Map<String, dynamic> json, {
    String requestedUrl = '',
  }) {
    final metadata = readMap(json['metadata']);
    // `url` is the address after redirects, `sourceURL` the one requested.
    // The final address is the honest citation, so it wins when present.
    final resolved =
        readStringOrNull(metadata['url']) ??
        readStringOrNull(metadata['sourceURL']) ??
        requestedUrl;

    return ScrapedPage(
      url: resolved,
      markdown: readString(json['markdown']).trim(),
      // Firecrawl types these as string-or-list, because a page may carry the
      // tag more than once. Only a single value is useful here.
      title: readStringOrNull(metadata['title']),
      description: readStringOrNull(metadata['description']),
      statusCode: readInt(metadata['statusCode']),
    );
  }

  /// The address the content actually came from, after redirects.
  final String url;

  /// The page body. Empty when the page was reached but held nothing
  /// extractable, which is a normal outcome for a paywall or a JS shell.
  final String markdown;

  final String? title;
  final String? description;

  /// What the site answered, not what Firecrawl answered. A 200 from Firecrawl
  /// can carry a 404 from the page.
  final int statusCode;

  bool get isEmpty => markdown.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ScrapedPage && url == other.url;

  @override
  int get hashCode => url.hashCode;
}

/// Where a batch scrape has got to. Firecrawl runs batches asynchronously: the
/// submit call returns an id and the work happens afterwards.
enum BatchScrapeStatus {
  /// Still working. The pages gathered so far are already readable.
  scraping,
  completed,
  failed,
  cancelled;

  /// Maps Firecrawl's string, treating anything unrecognised as still running
  /// — a new status name should make the poller wait, not declare failure.
  static BatchScrapeStatus from(String value) =>
      BatchScrapeStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => BatchScrapeStatus.scraping,
      );

  bool get isFinished => this != BatchScrapeStatus.scraping;
}

/// One poll of a batch scrape job.
class BatchScrape {
  const BatchScrape({
    required this.status,
    required this.pages,
    this.total = 0,
    this.completed = 0,
    this.next,
  });

  factory BatchScrape.fromJson(Map<String, dynamic> json) => BatchScrape(
    status: BatchScrapeStatus.from(readString(json['status'])),
    pages: <ScrapedPage>[
      for (final entry in readObjectList(json['data']))
        ScrapedPage.fromJson(entry),
    ],
    total: readInt(json['total']),
    completed: readInt(json['completed']),
    next: readStringOrNull(json['next']),
  );

  final BatchScrapeStatus status;

  /// The pages on this page of results, which is not every page in the job
  /// when [next] is set.
  final List<ScrapedPage> pages;

  final int total;
  final int completed;

  /// The URL of the next page of results, or null at the end. Firecrawl
  /// paginates a large batch rather than returning it whole.
  final String? next;
}

/// One URL a batch could not fetch, from `GET /batch/scrape/{id}/errors`.
class BatchScrapeError {
  const BatchScrapeError({required this.url, required this.reason});

  factory BatchScrapeError.fromJson(Map<String, dynamic> json) =>
      BatchScrapeError(
        url: readString(json['url']),
        reason: readString(json['error'], fallback: 'no reason given'),
      );

  final String url;
  final String reason;

  @override
  String toString() => '$url: $reason';
}
