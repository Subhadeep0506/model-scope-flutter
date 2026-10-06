import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/data/models/agent_run.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/generation_metrics.dart';
import 'package:model_scope_flutter/data/models/home_stats.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/repositories/model_library_repository.dart';
import 'package:model_scope_flutter/domain/services/home_stats_builder.dart';

import '../support/fakes.dart';

/// A fixed "now", so every relative figure in these tests is deterministic.
final DateTime now = DateTime(2026, 10, 3, 14, 30);

/// One finished assistant reply.
ChatMessage reply({
  required String id,
  required DateTime at,
  int latencyMs = 100,
  double tokensPerSecond = 50,
  int tokenCount = 40,
}) => ChatMessage(
  id: id,
  role: MessageRole.assistant,
  text: 'answer',
  createdAt: at,
  metrics: GenerationMetrics(
    latencyMs: latencyMs,
    tokensPerSecond: tokensPerSecond,
    tokenCount: tokenCount,
  ),
);

/// A user turn, which carries no metrics and must never be counted as a run.
ChatMessage question(String id, DateTime at) =>
    ChatMessage(id: id, role: MessageRole.user, text: 'ask', createdAt: at);

ChatSession session({
  required String id,
  required String modelId,
  List<ChatMessage> messages = const <ChatMessage>[],
  String title = 'Quant notes',
  DateTime? updatedAt,
}) => ChatSession(
  id: id,
  title: title,
  modelId: modelId,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: updatedAt ?? now,
  messages: messages,
);

void main() {
  final ModelDescriptor small = fakeInstalledModel();
  final ModelDescriptor large = fakeInstalledModel(
    repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    name: 'Qwen2.5 1.5B Instruct',
    quantization: 'Q4_K_M',
    sizeBytes: 1000 * 1000 * 1000,
    paramLabel: '1.5B',
  );

  ModelLibrary libraryOf(List<ModelDescriptor> models) => ModelLibrary(
    models: models,
    activeId: models.isEmpty ? null : models.first.id,
  );

  group('buildHomeStats', () {
    test('reports zeros on a device that has done nothing', () {
      final stats = buildHomeStats(
        sessions: const <ChatSession>[],
        library: ModelLibrary.empty,
        now: now,
      );

      // Every tile reads zero rather than being absent.
      check(stats.totalTokens).equals(0);
      check(stats.averageLatencyMs).equals(0);
      check(stats.peakTokensPerSecond).equals(0);
      check(stats.modelCount).equals(0);
      check(stats.agentRuns).equals(0);
      check(stats.hasNoReplies).isTrue();
    });

    test('chatting alone never produces an agent run', () {
      // The two counts are folded from different stores, so no amount of
      // chatting can move the agent tile.
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: small.id,
          messages: <ChatMessage>[reply(id: 'a1', at: now)],
        ),
      ];

      final stats = buildHomeStats(
        sessions: sessions,
        library: libraryOf(<ModelDescriptor>[small]),
        now: now,
      );

      check(stats.agentRuns).equals(0);
      check(stats.agentCount).equals(0);
    });

    test('totals and means fold over every reply, ignoring user turns', () {
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: small.id,
          messages: <ChatMessage>[
            question('q1', now),
            reply(id: 'a1', at: now, latencyMs: 100, tokenCount: 30),
            reply(id: 'a2', at: now, latencyMs: 300, tokenCount: 70),
          ],
        ),
      ];

      final stats = buildHomeStats(
        sessions: sessions,
        library: libraryOf(<ModelDescriptor>[small]),
        now: now,
      );

      check(stats.totalTokens).equals(100);
      check(stats.averageLatencyMs).equals(200);
    });

    test('peak throughput names the model that reached it', () {
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: small.id,
          messages: <ChatMessage>[
            reply(id: 'a1', at: now, tokensPerSecond: 94.2),
          ],
        ),
        session(
          id: 's2',
          modelId: large.id,
          messages: <ChatMessage>[
            reply(id: 'a2', at: now, tokensPerSecond: 41.0),
          ],
        ),
      ];

      final stats = buildHomeStats(
        sessions: sessions,
        library: libraryOf(<ModelDescriptor>[small, large]),
        now: now,
      );

      // The smaller model is faster, so it gets the caption.
      check(stats.peakTokensPerSecond).equals(94.2);
      check(stats.peakModelName).equals('SmolLM2 360M Instruct');
    });

    test('replies today are counted from midnight, not from 24h ago', () {
      // One reply late yesterday, one early today.
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: small.id,
          messages: <ChatMessage>[
            reply(id: 'a1', at: DateTime(2026, 10, 2, 23, 50)),
            reply(id: 'a2', at: DateTime(2026, 10, 3, 0, 10)),
            reply(id: 'a3', at: DateTime(2026, 10, 3, 9)),
          ],
        ),
      ];

      final stats = buildHomeStats(
        sessions: sessions,
        library: libraryOf(<ModelDescriptor>[small]),
        now: now,
      );

      check(stats.repliesToday).equals(2);
      check(stats.sessionCount).equals(1);
    });

    test('the trend holds seven buckets and leaves quiet days null', () {
      // One reply today, one three days back.
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: small.id,
          messages: <ChatMessage>[
            reply(id: 'a1', at: DateTime(2026, 10, 3, 9), latencyMs: 400),
            reply(id: 'a2', at: DateTime(2026, 9, 30, 9), latencyMs: 600),
          ],
        ),
      ];

      final trend = buildHomeStats(
        sessions: sessions,
        library: libraryOf(<ModelDescriptor>[small]),
        now: now,
      ).latencyTrend;

      // Oldest first, today last, gaps where nothing was generated.
      check(trend).length.equals(7);
      check(trend.last.day).equals(DateTime(2026, 10, 3));
      check(trend.last.averageLatencyMs).equals(400);
      check(trend[3].averageLatencyMs).equals(600);
      check(trend[0].averageLatencyMs).isNull();
      check(trend[5].averageLatencyMs).isNull();
    });

    test('throughput bars sort by parameter count, not alphabetically', () {
      // `1.5B` sorts before `360M` as a string, and must not.
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: large.id,
          messages: <ChatMessage>[
            reply(id: 'a1', at: now, tokensPerSecond: 40),
            reply(id: 'a2', at: now, tokensPerSecond: 42),
          ],
        ),
        session(
          id: 's2',
          modelId: small.id,
          messages: <ChatMessage>[
            reply(id: 'a3', at: now, tokensPerSecond: 94),
          ],
        ),
      ];

      final bars = buildHomeStats(
        sessions: sessions,
        library: libraryOf(<ModelDescriptor>[small, large]),
        now: now,
      ).throughputBySize;

      check(bars.map((bar) => bar.paramLabel).toList())
          .deepEquals(<String>['360M', '1.5B']);
      check(bars.last.tokensPerSecond).equals(41);
    });

    test('a model with no parameter label is left off the size axis', () {
      final unlabelled = fakeInstalledModel(
        repoId: 'someone/Mystery-GGUF',
        fileName: 'mystery.gguf',
        name: 'Mystery',
        paramLabel: null,
      );
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: unlabelled.id,
          messages: <ChatMessage>[reply(id: 'a1', at: now)],
        ),
      ];

      final bars = buildHomeStats(
        sessions: sessions,
        library: libraryOf(<ModelDescriptor>[unlabelled]),
        now: now,
      ).throughputBySize;

      // An unlabelled bar would say nothing about size.
      check(bars).isEmpty();
    });

    test('models with runs come first, unused ones follow at zero', () {
      // `large` is installed but has never answered.
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: small.id,
          messages: <ChatMessage>[
            reply(id: 'a1', at: DateTime(2026, 10, 3, 10), latencyMs: 118),
            reply(id: 'a2', at: DateTime(2026, 10, 3, 11), latencyMs: 122),
          ],
        ),
      ];

      final usage = buildHomeStats(
        sessions: sessions,
        library: libraryOf(<ModelDescriptor>[large, small]),
        now: now,
      ).modelUsage;

      check(usage).length.equals(2);
      check(usage.first.name).equals('SmolLM2 360M Instruct');
      check(usage.first.runs).equals(2);
      check(usage.first.averageLatencyMs).equals(120);
      check(usage.first.lastUsedAt).equals(DateTime(2026, 10, 3, 11));
      check(usage.last.runs).equals(0);
      check(usage.last.lastUsedAt).isNull();
    });

    test('activity merges sessions and downloads, newest first', () {
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: small.id,
          title: 'Quant notes',
          updatedAt: DateTime(2026, 10, 3, 10),
          messages: <ChatMessage>[
            question('q1', now),
            reply(id: 'a1', at: now),
          ],
        ),
      ];

      // The model was installed on 30 Sep, the session touched today.
      final feed = buildHomeStats(
        sessions: sessions,
        library: libraryOf(<ModelDescriptor>[small]),
        now: now,
      ).activity;

      check(feed).length.equals(2);
      check(feed.first.kind).equals(ActivityKind.session);
      check(feed.first.title).equals('Session "Quant notes"');
      check(feed.first.subtitle).equals('smollm2-360m-instruct · 2 messages');
      check(feed.last.kind).equals(ActivityKind.install);
      check(feed.last.title).equals('Pulled SmolLM2 360M Instruct');
      check(feed.last.subtitle).equals('Q8_0 · 399 MB');
    });

    test('a session whose model was removed still reports', () {
      // The weights are gone from the library, the transcript is not.
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: 'gone/forever.gguf',
          messages: <ChatMessage>[reply(id: 'a1', at: now, tokenCount: 12)],
        ),
      ];

      final stats = buildHomeStats(
        sessions: sessions,
        library: ModelLibrary.empty,
        now: now,
      );

      // The tokens still count; only the model's name is unknown.
      check(stats.totalTokens).equals(12);
      check(stats.peakModelName).isNull();
      check(stats.activity.first.subtitle).startsWith('removed model');
    });

    test('a session created before any model says so', () {
      // The blank session seeded on first launch carries no model id.
      final sessions = <ChatSession>[session(id: 's1', modelId: '')];

      final stats = buildHomeStats(
        sessions: sessions,
        library: ModelLibrary.empty,
        now: now,
      );

      // Nothing was removed, so the feed must not claim it was.
      check(stats.activity.first.subtitle).equals('no model · 0 messages');
    });

    test('counts the stored agent runs and the agents available', () {
      final stats = buildHomeStats(
        sessions: const <ChatSession>[],
        library: ModelLibrary.empty,
        now: now,
        runs: <AgentRun>[
          fakeAgentRun(id: 'r1'),
          fakeAgentRun(id: 'r2'),
        ],
        agentCount: 4,
      );

      check(stats.agentRuns).equals(2);
      check(stats.agentCount).equals(4);
    });

    test('a run on a device with nothing else is not an empty device', () {
      // Without this, a device whose only activity was an agent run would
      // fold to HomeStats.empty and report nothing at all.
      final stats = buildHomeStats(
        sessions: const <ChatSession>[],
        library: ModelLibrary.empty,
        now: now,
        runs: <AgentRun>[fakeAgentRun()],
        agentCount: 1,
      );

      check(stats.agentRuns).equals(1);
      check(stats.activity).length.equals(1);
    });

    test('agent runs join the activity feed in time order', () {
      final sessions = <ChatSession>[
        session(
          id: 's1',
          modelId: small.id,
          title: 'Quant notes',
          updatedAt: DateTime(2026, 10, 1, 10),
        ),
      ];

      final feed = buildHomeStats(
        sessions: sessions,
        library: ModelLibrary.empty,
        now: now,
        runs: <AgentRun>[
          fakeAgentRun(
            agentName: 'Web Answer',
            startedAt: DateTime(2026, 10, 3, 9),
          ),
        ],
      ).activity;

      check(feed.first.kind).equals(ActivityKind.agentRun);
      check(feed.first.title).equals('Ran Web Answer');
      check(feed.first.subtitle).startsWith('smollm2-360m · 2 steps · ');
      check(feed.last.kind).equals(ActivityKind.session);
    });

    test('a failed run says so rather than claiming it ran', () {
      final feed = buildHomeStats(
        sessions: const <ChatSession>[],
        library: ModelLibrary.empty,
        now: now,
        runs: <AgentRun>[
          fakeAgentRun(agentName: 'Price Comparison', error: 'Needs a key'),
        ],
      ).activity;

      check(feed.single.title).equals('Price Comparison failed');
    });
  });
}
