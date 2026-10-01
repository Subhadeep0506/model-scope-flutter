import '../../data/models/generation_metrics.dart';

/// Accumulates a reply while measuring what `nobodywho` does not report.
///
/// `ChatStats` exposes only `contextSize` and `contextUsed`, so the latency,
/// throughput and token count shown under each reply are timed here as the
/// stream is drained. The same counter enforces the `MAX_TOKENS` slider, which
/// the sampler API has no setting for.
class TokenCollector {
  TokenCollector({required this.maxTokens, Stopwatch? clock})
    : _clock = clock ?? Stopwatch() {
    _clock.start();
  }

  final int maxTokens;
  final Stopwatch _clock;
  final StringBuffer _buffer = StringBuffer();

  int _tokens = 0;
  int _latencyMs = 0;

  String get text => _buffer.toString();

  int get tokenCount => _tokens;

  /// True once [maxTokens] tokens have arrived.
  bool get isFull => _tokens >= maxTokens;

  /// Records one token. Returns `false` when the cap has been reached and the
  /// caller should stop generation.
  bool add(String token) {
    if (_tokens == 0) _latencyMs = _clock.elapsedMilliseconds;
    _tokens++;
    _buffer.write(token);
    return !isFull;
  }

  /// Stops the clock and reports the run. Safe to call more than once.
  GenerationMetrics finish() {
    _clock.stop();
    final total = _clock.elapsedMilliseconds;

    // Time spent generating excludes the wait for the first token, so a slow
    // prompt ingestion does not drag the throughput figure down.
    final generating = total - _latencyMs;
    final window = generating > 0 ? generating : total;

    return GenerationMetrics(
      latencyMs: _latencyMs,
      tokensPerSecond: window > 0 ? _tokens * 1000 / window : 0,
      tokenCount: _tokens,
    );
  }
}
