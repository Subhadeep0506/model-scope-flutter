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
    test('seeds one session on first launch and saves it', () async {
      // Arrange
      final repository = FakeSessionRepository();
      final container = ProviderContainer.test(
        overrides: fakeOverrides(llm: FakeLlmService(), sessions: repository),
      );

      // Act
      final loaded = await container.read(sessionsViewModelProvider.future);

      // Assert — the Chats list is never empty on a fresh install.
      check(loaded).length.equals(1);
      check(loaded.single.title).equals(SessionsViewModel.untitled);
      check(repository.stored).length.equals(1);
    });

    test('does not seed when sessions already exist', () async {
      // Arrange
      final container = containerWith(<ChatSession>[sessionWith(id: 'a')]);

      // Act
      final loaded = await container.read(sessionsViewModelProvider.future);

      // Assert
      check(loaded.map((s) => s.id).toList()).deepEquals(<String>['a']);
    });

    test('lists the most recently touched session first', () async {
      // Arrange
      final older = sessionWith(id: 'older');
      final newer = older.copyWith(
        updatedAt: older.updatedAt.add(const Duration(hours: 1)),
      );
      final container = containerWith(<ChatSession>[
        older,
        sessionWith(id: 'newer').copyWith(updatedAt: newer.updatedAt),
      ]);

      // Act
      final loaded = await container.read(sessionsViewModelProvider.future);

      // Assert
      check(loaded.first.id).equals('newer');
    });

    test('create puts a new session at the top and persists it', () async {
      // Arrange
      final repository = FakeSessionRepository(<ChatSession>[
        sessionWith(id: 'a'),
      ]);
      final container = ProviderContainer.test(
        overrides: fakeOverrides(llm: FakeLlmService(), sessions: repository),
      );
      await container.read(sessionsViewModelProvider.future);

      // Act
      final created = await container
          .read(sessionsViewModelProvider.notifier)
          .create();

      // Assert
      check(created.title).equals(SessionsViewModel.untitled);
      check(repository.stored).length.equals(2);
      check(container.read(sessionsViewModelProvider).value?.first.id)
          .equals(created.id);
    });

    test('delete removes the session and restore puts it back', () async {
      // Arrange
      final seed = sessionWith(id: 'a', title: 'Keep me');
      final container = containerWith(<ChatSession>[
        seed,
        sessionWith(id: 'b'),
      ]);
      await container.read(sessionsViewModelProvider.future);
      final notifier = container.read(sessionsViewModelProvider.notifier);

      // Act
      await notifier.delete('a');
      final afterDelete = container.read(sessionsViewModelProvider).value;
      await notifier.restore(seed);
      final afterRestore = container.read(sessionsViewModelProvider).value;

      // Assert
      check(afterDelete?.map((s) => s.id).toList())
          .isNotNull()
          .deepEquals(<String>['b']);
      check(afterRestore?.map((s) => s.id).toList())
          .isNotNull()
          .unorderedEquals(<String>['a', 'b']);
    });

    test(
      'upsert replaces in place rather than appending a duplicate',
      () async {
        // Arrange
        final seed = sessionWith(id: 'a', title: 'Before');
        final container = containerWith(<ChatSession>[seed]);
        await container.read(sessionsViewModelProvider.future);

        // Act
        await container
            .read(sessionsViewModelProvider.notifier)
            .upsert(seed.copyWith(title: 'After'));

        // Assert
        final loaded = container.read(sessionsViewModelProvider).value;
        check(loaded).isNotNull().length.equals(1);
        check(loaded?.single.title).equals('After');
      },
    );

    test('byId returns null for an unknown id', () async {
      // Arrange
      final container = containerWith(<ChatSession>[sessionWith(id: 'a')]);
      await container.read(sessionsViewModelProvider.future);

      // Act
      final found = container
          .read(sessionsViewModelProvider.notifier)
          .byId('z');

      // Assert
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
      // Assert
      check(container.read(filteredSessionsProvider)).length.equals(2);
    });

    test('matches the search query case-insensitively', () {
      // Act
      container.read(sessionFilterProvider.notifier).setQuery('QUANT');

      // Assert
      check(container.read(filteredSessionsProvider).single.id).equals('a');
    });

    test('filters by model', () {
      // Act
      container
          .read(sessionFilterProvider.notifier)
          .setModel('some-other-model');

      // Assert
      check(container.read(filteredSessionsProvider)).isEmpty();

      // Act — "All models" is modelled as null.
      container.read(sessionFilterProvider.notifier).setModel(null);

      // Assert
      check(container.read(filteredSessionsProvider)).length.equals(2);
    });

    test('filters by how recently a session was touched', () async {
      // Arrange — one session touched just now, one touched ten days ago. The
      // dropdown is relative to the clock, so the fixtures have to be too.
      final now = DateTime.now();
      final dated = containerWith(<ChatSession>[
        sessionWith(id: 'recent').copyWith(updatedAt: now),
        sessionWith(id: 'stale')
            .copyWith(updatedAt: now.subtract(const Duration(days: 10))),
      ]);
      await dated.read(sessionsViewModelProvider.future);
      final notifier = dated.read(sessionFilterProvider.notifier);

      // Act
      notifier.setTime(SessionTimeFilter.week);

      // Assert
      check(dated.read(filteredSessionsProvider).single.id).equals('recent');

      // Act
      notifier.setTime(SessionTimeFilter.month);

      // Assert
      check(dated.read(filteredSessionsProvider)).length.equals(2);

      // Act
      notifier.setTime(SessionTimeFilter.all);

      // Assert
      check(dated.read(filteredSessionsProvider)).length.equals(2);
    });

    test('clear drops every filter at once', () {
      // Arrange
      final notifier = container.read(sessionFilterProvider.notifier)
        ..setQuery('quant')
        ..setModel(fakeInstalledModel().id)
        ..setTime(SessionTimeFilter.today);

      // Act
      notifier.clear();

      // Assert
      check(container.read(sessionFilterProvider).isActive).isFalse();
      check(container.read(filteredSessionsProvider)).length.equals(2);
    });
  });
}
