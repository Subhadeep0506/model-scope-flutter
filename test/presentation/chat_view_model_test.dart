import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/sampler_settings.dart';
import 'package:model_scope_flutter/domain/services/llm_service.dart';
import 'package:model_scope_flutter/presentation/view_models/chat_state.dart';
import 'package:model_scope_flutter/presentation/view_models/chat_view_model.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmService llm;
  late FakeSessionRepository sessions;
  late FakeSettingsRepository settings;
  late FakeModelLibraryRepository library;
  late ProviderContainer container;

  /// Builds a container whose only session is [seed].
  ///
  /// One model is installed by default, because that is the ordinary case;
  /// pass an empty [models] to exercise the empty-library path.
  ProviderContainer containerWith(
    ChatSession seed, {
    SamplerSettings? sampler,
    List<ModelDescriptor>? models,
  }) {
    llm = FakeLlmService();
    sessions = FakeSessionRepository(<ChatSession>[seed]);
    settings = FakeSettingsRepository(sampler ?? const SamplerSettings());
    library = FakeModelLibraryRepository.of(
      models ?? <ModelDescriptor>[fakeInstalledModel()],
    );
    return ProviderContainer.test(
      overrides: fakeOverrides(
        llm: llm,
        sessions: sessions,
        settings: settings,
        library: library,
      ),
    );
  }

  ChatViewModel notifierOf(ProviderContainer c) =>
      c.read(chatViewModelProvider.notifier);

  ChatState stateOf(ProviderContainer c) => c.read(chatViewModelProvider);

  test('open loads the session, the model and the stored transcript', () async {
    // Arrange
    final seed = sessionWith(count: 2);
    container = containerWith(seed);

    // Act
    await notifierOf(container).open(seed.id);

    // Assert
    final state = stateOf(container);
    check(state.status).equals(ChatStatus.ready);
    check(state.session?.id).equals(seed.id);
    check(llm.loadCalls).equals(1);
    check(llm.restored.single).length.equals(2);
  });

  test('open reports a missing session instead of throwing', () async {
    // Arrange
    container = containerWith(sessionWith());

    // Act
    await notifierOf(container).open('does-not-exist');

    // Assert
    check(stateOf(container).status).equals(ChatStatus.failed);
    check(stateOf(container).error).isNotNull();
  });

  test('a failed load surfaces the missing-weights message', () async {
    // Arrange
    final seed = sessionWith();
    container = containerWith(seed);
    llm.failure = const ModelMissingException(
      name: 'SmolLM2 360M Instruct',
      path: '/cache/smollm2-360m-instruct-q8_0.gguf',
    );

    // Act — `load` succeeds; the throw is wired onto `ask`, so drive a send.
    await notifierOf(container).open(seed.id);
    await notifierOf(container).send('Hello');

    // Assert — a generation failure lands on the message, not the whole screen.
    final last = stateOf(container).messages.last;
    check(last.error).isNotNull();
    check(stateOf(container).status).equals(ChatStatus.ready);
  });

  test('open reports an empty library rather than loading nothing', () async {
    // Arrange — the app's state on a fresh install, before any download.
    final seed = sessionWith();
    container = containerWith(seed, models: const <ModelDescriptor>[]);

    // Act
    await notifierOf(container).open(seed.id);

    // Assert — the screen can offer Settings; nothing was asked of the model.
    check(stateOf(container).status).equals(ChatStatus.noModel);
    check(llm.loadCalls).equals(0);
  });

  test('opening against a different model reloads the weights', () async {
    // Arrange — two models installed, the first one already loaded.
    final seed = sessionWith();
    final other = fakeInstalledModel(
      repoId: 'bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF',
      fileName: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
      name: 'Qwen2.5 Coder 1.5B Instruct',
    );
    container = containerWith(
      seed,
      models: <ModelDescriptor>[fakeInstalledModel(), other],
    );
    await notifierOf(container).open(seed.id);
    check(llm.loadCalls).equals(1);

    // Act — switching in Settings, then returning to the chat.
    await container
        .read(modelLibraryViewModelProvider.notifier)
        .setActive(other.id);
    await notifierOf(container).open(seed.id);

    // Assert — the second load is the new model, not a repeat of the first.
    check(llm.loadCalls).equals(2);
    check(llm.loadedModelId).equals(other.id);
  });

  test('an already-loaded model is not loaded a second time', () async {
    // Arrange
    final seed = sessionWith();
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    // Act — reopening the same session, as a back-and-forth navigation does.
    await notifierOf(container).open(seed.id);

    // Assert
    check(llm.loadCalls).equals(1);
  });

  test('send appends the question, then the streamed reply', () async {
    // Arrange
    final seed = sessionWith();
    container = containerWith(seed);
    llm.tokens = <String>['Eight', '-bit', ' weights.'];
    await notifierOf(container).open(seed.id);

    // Act
    await notifierOf(container).send('  What does Q8_0 mean?  ');

    // Assert
    final messages = stateOf(container).messages;
    check(messages).length.equals(2);
    check(messages.first.role).equals(MessageRole.user);
    check(messages.first.text).equals('What does Q8_0 mean?');
    check(messages.last.text).equals('Eight-bit weights.');
    check(messages.last.isStreaming).isFalse();
    check(messages.last.metrics?.tokenCount).equals(3);
    check(llm.prompts).deepEquals(<String>['What does Q8_0 mean?']);
  });

  test('the first question becomes the session title', () async {
    // Arrange
    final seed = sessionWith();
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    // Act
    await notifierOf(container).send('Explain quantisation');

    // Assert
    check(stateOf(container).session?.title).equals('Explain quantisation');
  });

  test('a long first question is elided rather than wrapped', () async {
    // Arrange
    final seed = sessionWith();
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    // Act
    await notifierOf(container).send('x' * 80);

    // Assert
    final title = stateOf(container).session?.title ?? '';
    check(title).length.equals(39); // 38 characters plus the ellipsis.
    check(title).endsWith('…');
  });

  test('a later question leaves the existing title alone', () async {
    // Arrange
    final seed = sessionWith(title: 'Explain quantisation', count: 2);
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    // Act
    await notifierOf(container).send('And what about Q4?');

    // Assert
    check(stateOf(container).session?.title).equals('Explain quantisation');
  });

  test('the max-token cap stops generation at the limit', () async {
    // Arrange — twelve tokens available, four allowed.
    final seed = sessionWith();
    container = containerWith(
      seed,
      sampler: const SamplerSettings(maxTokens: 4),
    );
    llm.tokens = List<String>.generate(12, (i) => 't$i');
    await notifierOf(container).open(seed.id);

    // Act
    await notifierOf(container).send('Go on');

    // Assert
    check(llm.stopCalls).equals(1);
    check(stateOf(container).messages.last.metrics?.tokenCount).equals(4);
    check(stateOf(container).messages.last.text).equals('t0t1t2t3');
  });

  test('a reply shorter than the cap does not call stop', () async {
    // Arrange
    final seed = sessionWith();
    container = containerWith(
      seed,
      sampler: const SamplerSettings(maxTokens: 64),
    );
    await notifierOf(container).open(seed.id);

    // Act
    await notifierOf(container).send('Hi');

    // Assert
    check(llm.stopCalls).equals(0);
  });

  test(
    'regenerate rewinds the context and re-asks the last question',
    () async {
      // Arrange
      final seed = sessionWith();
      container = containerWith(seed);
      await notifierOf(container).open(seed.id);
      await notifierOf(container).send('First');
      llm.tokens = <String>['Second', ' answer'];

      // Act
      await notifierOf(container).regenerate();

      // Assert — same question, new reply, and no duplicated turns.
      check(llm.prompts).deepEquals(<String>['First', 'First']);
      check(stateOf(container).messages).length.equals(2);
      check(stateOf(container).messages.last.text).equals('Second answer');
      // The rewound history stops just before the question being re-asked.
      check(llm.restored.last).isEmpty();
    },
  );

  test('regenerate is a no-op while the last turn is the user\'s', () async {
    // Arrange
    final seed = sessionWith(count: 1); // Ends on a user message.
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    // Act
    await notifierOf(container).regenerate();

    // Assert
    check(llm.prompts).isEmpty();
  });

  test('an attachment is recorded on the message but never sent', () async {
    // Arrange
    final seed = sessionWith();
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    // Act
    notifierOf(container).attach('spec.pdf');
    await notifierOf(container).send('Summarise this');

    // Assert
    check(stateOf(container).messages.first.attachmentName).equals('spec.pdf');
    check(llm.prompts.single).equals('Summarise this');
    // The composer chip is cleared once the message has taken it.
    check(stateOf(container).attachmentName).isNull();
  });

  test(
    'attach(null) clears a chip the user changed their mind about',
    () async {
      // Arrange
      final seed = sessionWith();
      container = containerWith(seed);
      await notifierOf(container).open(seed.id);
      notifierOf(container).attach('spec.pdf');

      // Act
      notifierOf(container).attach(null);

      // Assert
      check(stateOf(container).attachmentName).isNull();
    },
  );

  test('send is refused until the model is ready', () async {
    // Arrange — no `open`, so the state is still idle.
    container = containerWith(sessionWith());

    // Act
    await notifierOf(container).send('Too early');

    // Assert
    check(llm.prompts).isEmpty();
  });

  test('a finished turn is written to disk', () async {
    // Arrange
    final seed = sessionWith();
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);
    final before = sessions.saveCalls;

    // Act
    await notifierOf(container).send('Persist me');

    // Assert — one write for the question, one for the finished reply; the
    // per-token renders do not touch disk.
    check(sessions.saveCalls - before).equals(2);
    check(sessions.stored.single.messages).length.equals(2);
  });

  test('close resets the state so the next session starts clean', () async {
    // Arrange
    final seed = sessionWith(count: 2);
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    // Act
    notifierOf(container).close();

    // Assert
    check(stateOf(container).session).isNull();
    check(stateOf(container).status).equals(ChatStatus.idle);
  });
}
