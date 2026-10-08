import '../../data/models/generation_metrics.dart';

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
  bool get isFull => _tokens >= maxTokens;

  bool add(String token) {
    if (_tokens == 0) _latencyMs = _clock.elapsedMilliseconds;
    _tokens++;
    _buffer.write(token);
    return !isFull;
  }

  GenerationMetrics finish() {
    _clock.stop();
    final total = _clock.elapsedMilliseconds;

    final generating = total - _latencyMs;
    final window = generating > 0 ? generating : total;

    return GenerationMetrics(
      latencyMs: _latencyMs,
      tokensPerSecond: window > 0 ? _tokens * 1000 / window : 0,
      tokenCount: _tokens,
    );
  }
}
