import 'json_read.dart';

class ScrapedPage {
  const ScrapedPage({
    required this.url,
    required this.markdown,
    this.title,
    this.description,
    this.statusCode = 0,
  });

  factory ScrapedPage.fromJson(
    Map<String, dynamic> json, {
    String requestedUrl = '',
  }) {
    final metadata = readMap(json['metadata']);

    final resolved =
        readStringOrNull(metadata['url']) ??
        readStringOrNull(metadata['sourceURL']) ??
        requestedUrl;

    return ScrapedPage(
      url: resolved,
      markdown: readString(json['markdown']).trim(),

      title: readStringOrNull(metadata['title']),
      description: readStringOrNull(metadata['description']),
      statusCode: readInt(metadata['statusCode']),
    );
  }

  final String url;

  final String markdown;

  final String? title;
  final String? description;

  final int statusCode;

  bool get isEmpty => markdown.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ScrapedPage && url == other.url;

  @override
  int get hashCode => url.hashCode;
}

enum BatchScrapeStatus {
  scraping,
  completed,
  failed,
  cancelled;

  static BatchScrapeStatus from(String value) =>
      BatchScrapeStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => BatchScrapeStatus.scraping,
      );

  bool get isFinished => this != BatchScrapeStatus.scraping;
}

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

  final List<ScrapedPage> pages;

  final int total;
  final int completed;

  final String? next;
}

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
