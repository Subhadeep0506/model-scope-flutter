import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/services/token_collector.dart';

void main() {
  test('joins tokens in arrival order', () {
    // Arrange
    final collector = TokenCollector(maxTokens: 10, clock: _ManualClock());

    // Act
    for (final token in <String>['Eight', '-bit', ' weights']) {
      collector.add(token);
    }

    // Assert
    check(collector.text).equals('Eight-bit weights');
    check(collector.tokenCount).equals(3);
  });

  test('reports the wait for the first token as latency', () {
    // Arrange
    final clock = _ManualClock();
    final collector = TokenCollector(maxTokens: 10, clock: clock);

    // Act
    clock.millis = 118;
    collector.add('a');
    clock.millis = 218;
    collector.add('b');
    clock.millis = 318;
    final metrics = collector.finish();

    // Assert — throughput covers the 200ms of generating, not the 118ms wait.
    check(metrics.latencyMs).equals(118);
    check(metrics.tokenCount).equals(2);
    check(metrics.tokensPerSecond).equals(10);
  });

  test('a reply that arrives instantly still reports a finite rate', () {
    // Arrange
    final clock = _ManualClock();
    final collector = TokenCollector(maxTokens: 10, clock: clock);

    // Act
    collector.add('a');
    final metrics = collector.finish();

    // Assert — no division by zero, and no NaN reaching the metrics row.
    check(metrics.tokensPerSecond).equals(0);
    check(metrics.latencyMs).equals(0);
  });

  test('add returns false exactly on the max-token boundary', () {
    // Arrange
    final collector = TokenCollector(maxTokens: 3, clock: _ManualClock());

    // Act
    final room = <bool>[
      collector.add('1'),
      collector.add('2'),
      collector.add('3'),
    ];

    // Assert
    check(room).deepEquals(<bool>[true, true, false]);
    check(collector.isFull).isTrue();
  });

  test('formats the metrics line exactly as the mockup prints it', () {
    // Arrange
    final clock = _ManualClock();
    final collector = TokenCollector(maxTokens: 200, clock: clock);

    // Act
    clock.millis = 118;
    for (var i = 0; i < 96; i++) {
      collector.add('t');
    }
    clock.millis = 1146;
    final metrics = collector.finish();

    // Assert
    check(metrics.label).equals('118ms · 93.4 tok/s · 96 tok');
  });
}

/// A [Stopwatch] whose reading the test sets by hand, so throughput assertions
/// do not depend on how fast the machine running them happens to be.
class _ManualClock extends Stopwatch {
  int millis = 0;

  @override
  int get elapsedMilliseconds => millis;
}
