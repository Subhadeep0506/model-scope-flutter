import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/presentation/view_models/session_filter_view_model.dart';
import 'package:model_scope_flutter/presentation/view_models/sessions_view_model.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerWith(List<ChatSession> seed) =>
      ProviderContainer.test(
        overrides: fakeOverrides(
          llm: FakeLlmService(),
          sessions: FakeSessionRepository(seed),
        ),
      );

  group('SessionsViewModel', () {
    test('starts empty on a first launch and writes nothing', () async {
      final repository = FakeSessionRepository();
      final container = ProviderContainer.test(
        overrides: fakeOverrides(llm: FakeLlmService(), sessions: repository),
      );

      final loaded = await container.read(sessionsViewModelProvider.future);

      // Nothing is seeded: the Chats screen offers a button instead, and a
      // fresh install touches the store only once the user starts a chat.
      check(loaded).isEmpty();
      check(repository.stored).isEmpty();
    });

    test('loads the sessions that exist', () async {
      final container = containerWith(<ChatSession>[sessionWith(id: 'a')]);

      final loaded = await container.read(sessionsViewModelProvider.future);

      check(loaded.map((s) => s.id).toList()).deepEquals(<String>['a']);
    });

    test('lists the most recently touched session first', () async {
      final older = sessionWith(id: 'older');
      final newer = older.copyWith(
        updatedAt: older.updatedAt.add(const Duration(hours: 1)),
      );
      final container = containerWith(<ChatSession>[
        older,
        sessionWith(id: 'newer').copyWith(updatedAt: newer.updatedAt),
      ]);

      final loaded = await container.read(sessionsViewModelProvider.future);

      check(loaded.first.id).equals('newer');
    });

    test('create puts a new session at the top and persists it', () async {
      final repository = FakeSessionRepository(<ChatSession>[
        sessionWith(id: 'a'),
      ]);
      final container = ProviderContainer.test(
        overrides: fakeOverrides(llm: FakeLlmService(), sessions: repository),
      );
      await container.read(sessionsViewModelProvider.future);

      final created = await container
          .read(sessionsViewModelProvider.notifier)
          .create();

      check(created.title).equals(SessionsViewModel.untitled);
      check(repository.stored).length.equals(2);
      check(container.read(sessionsViewModelProvider).value?.first.id)
          .equals(created.id);
    });

    test('delete removes the session and persists the rest', () async {
      final repository = FakeSessionRepository(<ChatSession>[
        sessionWith(id: 'a', title: 'Drop me'),
        sessionWith(id: 'b'),
      ]);
      final container = ProviderContainer.test(
        overrides: fakeOverrides(llm: FakeLlmService(), sessions: repository),
      );
      await container.read(sessionsViewModelProvider.future);

      await container.read(sessionsViewModelProvider.notifier).delete('a');

      check(container.read(sessionsViewModelProvider).value?.map((s) => s.id))
          .isNotNull()
          .deepEquals(<String>['b']);
      check(repository.stored.map((s) => s.id)).deepEquals(<String>['b']);
    });

    test(
      'upsert replaces in place rather than appending a duplicate',
      () async {
        final seed = sessionWith(id: 'a', title: 'Before');
        final container = containerWith(<ChatSession>[seed]);
        await container.read(sessionsViewModelProvider.future);

        await container
            .read(sessionsViewModelProvider.notifier)
            .upsert(seed.copyWith(title: 'After'));

        final loaded = container.read(sessionsViewModelProvider).value;
        check(loaded).isNotNull().length.equals(1);
        check(loaded?.single.title).equals('After');
      },
    );

    test('byId returns null for an unknown id', () async {
      final container = containerWith(<ChatSession>[sessionWith(id: 'a')]);
      await container.read(sessionsViewModelProvider.future);

      final found = container
          .read(sessionsViewModelProvider.notifier)
          .byId('z');

      check(found).isNull();
    });
  });

  group('filteredSessionsProvider', () {
    late ProviderContainer container;

    setUp(() async {
      container = containerWith(<ChatSession>[
        sessionWith(id: 'a', title: 'Explain quantisation'),
        sessionWith(id: 'b', title: 'Draft a changelog'),
      ]);
      await container.read(sessionsViewModelProvider.future);
    });

    test('returns everything when no filter is set', () {
      check(container.read(filteredSessionsProvider)).length.equals(2);
    });

    test('matches the search query case-insensitively', () {
      container.read(sessionFilterProvider.notifier).setQuery('QUANT');

      check(container.read(filteredSessionsProvider).single.id).equals('a');
    });

    test('filters by model', () {
      container
          .read(sessionFilterProvider.notifier)
          .setModel('some-other-model');

      check(container.read(filteredSessionsProvider)).isEmpty();

      // "All models" is modelled as null.
      container.read(sessionFilterProvider.notifier).setModel(null);

      check(container.read(filteredSessionsProvider)).length.equals(2);
    });

    test('filters by how recently a session was touched', () async {
      // One session touched just now, one touched ten days ago. The
      // dropdown is relative to the clock, so the fixtures have to be too.
      final now = DateTime.now();
      final dated = containerWith(<ChatSession>[
        sessionWith(id: 'recent').copyWith(updatedAt: now),
        sessionWith(id: 'stale')
            .copyWith(updatedAt: now.subtract(const Duration(days: 10))),
      ]);
      await dated.read(sessionsViewModelProvider.future);
      final notifier = dated.read(sessionFilterProvider.notifier);

      notifier.setTime(SessionTimeFilter.week);

      check(dated.read(filteredSessionsProvider).single.id).equals('recent');

      notifier.setTime(SessionTimeFilter.month);

      check(dated.read(filteredSessionsProvider)).length.equals(2);

      notifier.setTime(SessionTimeFilter.all);

      check(dated.read(filteredSessionsProvider)).length.equals(2);
    });

    test('clear drops every filter at once', () {
      final notifier = container.read(sessionFilterProvider.notifier)
        ..setQuery('quant')
        ..setModel(fakeInstalledModel().id)
        ..setTime(SessionTimeFilter.today);

      notifier.clear();

      check(container.read(sessionFilterProvider).isActive).isFalse();
      check(container.read(filteredSessionsProvider)).length.equals(2);
    });
  });
}
