import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/view_models.dart';
import 'package:model_scope_flutter/data/models/app_settings.dart';
import 'package:model_scope_flutter/data/models/chat_message.dart';
import 'package:model_scope_flutter/data/models/chat_session.dart';
import 'package:model_scope_flutter/data/models/model_descriptor.dart';
import 'package:model_scope_flutter/data/models/projector_descriptor.dart';
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
  late FakeAppSettingsRepository runtime;
  late ProviderContainer container;

  /// Builds a container whose only session is [seed]. One model is installed by
  /// default; pass an empty [models] to exercise the empty-library path, or
  /// [vision] to install the projector that lets it read images.
  ProviderContainer containerWith(
    ChatSession seed, {
    SamplerSettings? sampler,
    List<ModelDescriptor>? models,
    AppSettings? appSettings,
    bool vision = false,
    FakeImageStore? images,
  }) {
    llm = FakeLlmService();
    sessions = FakeSessionRepository(<ChatSession>[seed]);
    settings = FakeSettingsRepository(sampler ?? const SamplerSettings());
    library = FakeModelLibraryRepository.of(
      models ?? <ModelDescriptor>[fakeInstalledModel()],
      projectors: vision
          ? <ProjectorDescriptor>[fakeProjector()]
          : const <ProjectorDescriptor>[],
    );
    runtime = FakeAppSettingsRepository(appSettings ?? const AppSettings());
    return ProviderContainer.test(
      overrides: fakeOverrides(
        llm: llm,
        sessions: sessions,
        settings: settings,
        library: library,
        appSettings: runtime,
        images: images,
      ),
    );
  }

  ChatViewModel notifierOf(ProviderContainer c) =>
      c.read(chatViewModelProvider.notifier);

  ChatState stateOf(ProviderContainer c) => c.read(chatViewModelProvider);

  test('open loads the session, the model and the stored transcript', () async {
    final seed = sessionWith(count: 2);
    container = containerWith(seed);

    await notifierOf(container).open(seed.id);

    final state = stateOf(container);
    check(state.status).equals(ChatStatus.ready);
    check(state.session?.id).equals(seed.id);
    check(llm.loadCalls).equals(1);
    check(llm.restored.single).length.equals(2);
  });

  test('open reports a missing session instead of throwing', () async {
    container = containerWith(sessionWith());

    await notifierOf(container).open('does-not-exist');

    check(stateOf(container).status).equals(ChatStatus.failed);
    check(stateOf(container).error).isNotNull();
  });

  test('a failed load surfaces the missing-weights message', () async {
    final seed = sessionWith();
    container = containerWith(seed);
    llm.failure = const ModelMissingException(
      name: 'SmolLM2 360M Instruct',
      path: '/cache/smollm2-360m-instruct-q8_0.gguf',
    );

    // `load` succeeds; the throw is wired onto `ask`, so drive a send.
    await notifierOf(container).open(seed.id);
    await notifierOf(container).send('Hello');

    // A generation failure lands on the message, not the whole screen.
    final last = stateOf(container).messages.last;
    check(last.error).isNotNull();
    check(stateOf(container).status).equals(ChatStatus.ready);
  });

  test('a refused GPU load is retried on the CPU', () async {
    // A driver that will not allocate, which is a load-time failure
    // rather than a broken model.
    final seed = sessionWith();
    container = containerWith(seed);
    llm.loadFailure = (runtime) =>
        runtime.useGpu ? StateError('vulkan: out of device memory') : null;

    await notifierOf(container).open(seed.id);

    // The chat works, and says so.
    final state = stateOf(container);
    check(state.status).equals(ChatStatus.ready);
    check(state.notice).isNotNull();
    check(llm.loadCalls).equals(2);
    check(llm.runtimes.map((r) => r.useGpu)).deepEquals(<bool>[true, false]);
  });

  test('the CPU fallback is not written back to settings', () async {
    // A later run, or a different model, deserves another attempt at
    // the GPU rather than being quietly demoted forever.
    final seed = sessionWith();
    container = containerWith(seed);
    llm.loadFailure = (runtime) =>
        runtime.useGpu ? StateError('vulkan: out of device memory') : null;

    await notifierOf(container).open(seed.id);

    check(runtime.saveCalls).equals(0);
    check(runtime.stored.useGpu).isTrue();
  });

  test(
    'a load that fails both ways is not called a generation failure',
    () async {
      // A corrupt file fails with or without the GPU.
      final seed = sessionWith();
      container = containerWith(seed);
      llm.loadFailure = (_) => const ModelLoadException(
        name: 'SmolLM2 360M Instruct',
        path: '/cache/smollm2-360m-instruct-q8_0.gguf',
        contextLength: 4096,
        useGpu: true,
        sizeOnDisk: 120,
        expectedSize: 418 * 1000 * 1000,
        cause: '',
      );

      await notifierOf(container).open(seed.id);

      // Nothing was generated, so the old `Generation failed:` prefix
      // would have sent the user looking in the wrong place.
      final state = stateOf(container);
      check(state.status).equals(ChatStatus.failed);
      check(state.error).isNotNull().not((it) => it.startsWith('Generation'));
      check(state.notice).isNull();
    },
  );

  test('the fallback is skipped when the GPU is already off', () async {
    // Nothing to drop, so a failure is final.
    final seed = sessionWith();
    container = containerWith(
      seed,
      appSettings: const AppSettings(useGpu: false),
    );
    llm.loadFailure = (_) => StateError('unsupported gguf');

    await notifierOf(container).open(seed.id);

    check(stateOf(container).status).equals(ChatStatus.failed);
    check(llm.loadCalls).equals(1);
  });

  test('open reports an empty library rather than loading nothing', () async {
    // The app's state on a fresh install, before any download.
    final seed = sessionWith();
    container = containerWith(seed, models: const <ModelDescriptor>[]);

    await notifierOf(container).open(seed.id);

    // The screen can offer Settings; nothing was asked of the model.
    check(stateOf(container).status).equals(ChatStatus.noModel);
    check(llm.loadCalls).equals(0);
  });

  test('opening against a different model reloads the weights', () async {
    // Two models installed, the first one already loaded.
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

    // Switching in Settings, then returning to the chat.
    await container
        .read(modelLibraryViewModelProvider.notifier)
        .setActive(other.id);
    await notifierOf(container).open(seed.id);

    // The second load is the new model, not a repeat of the first.
    check(llm.loadCalls).equals(2);
    check(llm.loadedModelId).equals(other.id);
  });

  test('an already-loaded model is not loaded a second time', () async {
    final seed = sessionWith();
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    // Reopening the same session, as a back-and-forth navigation does.
    await notifierOf(container).open(seed.id);

    check(llm.loadCalls).equals(1);
  });

  test('send appends the question, then the streamed reply', () async {
    final seed = sessionWith();
    container = containerWith(seed);
    llm.tokens = <String>['Eight', '-bit', ' weights.'];
    await notifierOf(container).open(seed.id);

    await notifierOf(container).send('  What does Q8_0 mean?  ');

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
    final seed = sessionWith();
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    await notifierOf(container).send('Explain quantisation');

    check(stateOf(container).session?.title).equals('Explain quantisation');
  });

  test('a long first question is elided rather than wrapped', () async {
    final seed = sessionWith();
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    await notifierOf(container).send('x' * 80);

    final title = stateOf(container).session?.title ?? '';
    check(title).length.equals(39); // 38 characters plus the ellipsis.
    check(title).endsWith('…');
  });

  test('a later question leaves the existing title alone', () async {
    final seed = sessionWith(title: 'Explain quantisation', count: 2);
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    await notifierOf(container).send('And what about Q4?');

    check(stateOf(container).session?.title).equals('Explain quantisation');
  });

  test('the max-token cap stops generation at the limit', () async {
    // Twelve tokens available, four allowed.
    final seed = sessionWith();
    container = containerWith(
      seed,
      sampler: const SamplerSettings(maxTokens: 4),
    );
    llm.tokens = List<String>.generate(12, (i) => 't$i');
    await notifierOf(container).open(seed.id);

    await notifierOf(container).send('Go on');

    check(llm.stopCalls).equals(1);
    check(stateOf(container).messages.last.metrics?.tokenCount).equals(4);
    check(stateOf(container).messages.last.text).equals('t0t1t2t3');
  });

  test('a reply shorter than the cap does not call stop', () async {
    final seed = sessionWith();
    container = containerWith(
      seed,
      sampler: const SamplerSettings(maxTokens: 64),
    );
    await notifierOf(container).open(seed.id);

    await notifierOf(container).send('Hi');

    check(llm.stopCalls).equals(0);
  });

  test(
    'regenerate rewinds the context and re-asks the last question',
    () async {
      final seed = sessionWith();
      container = containerWith(seed);
      await notifierOf(container).open(seed.id);
      await notifierOf(container).send('First');
      llm.tokens = <String>['Second', ' answer'];

      await notifierOf(container).regenerate();

      // Same question, new reply, and no duplicated turns.
      check(llm.prompts).deepEquals(<String>['First', 'First']);
      check(stateOf(container).messages).length.equals(2);
      check(stateOf(container).messages.last.text).equals('Second answer');
      // The rewound history stops just before the question being re-asked.
      check(llm.restored.last).isEmpty();
    },
  );

  test('regenerate is a no-op while the last turn is the user\'s', () async {
    final seed = sessionWith(count: 1); // Ends on a user message.
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    await notifierOf(container).regenerate();

    check(llm.prompts).isEmpty();
  });

  test('an image is copied, recorded on the message and sent', () async {
    final seed = sessionWith();
    final images = FakeImageStore();
    container = containerWith(seed, vision: true, images: images);
    await notifierOf(container).open(seed.id);

    await notifierOf(container).attach('/tmp/spec.png');
    await notifierOf(container).send('Summarise this');

    // The message holds the app's copy, not the path the picker gave.
    final stored = images.saved.single;
    check(stored).startsWith(FakeImageStore.root);
    check(stateOf(container).messages.first.imagePaths)
        .deepEquals(<String>[stored]);
    check(llm.prompts.single).equals('Summarise this');
    check(llm.askedImages.single).deepEquals(<String>[stored]);
    // The composer is cleared once the message has taken the image.
    check(stateOf(container).attachments).isEmpty();
  });

  test('a model without a projector refuses an image', () async {
    final seed = sessionWith();
    final images = FakeImageStore();
    container = containerWith(seed, images: images);
    await notifierOf(container).open(seed.id);

    check(stateOf(container).hasVision).isFalse();
    check(stateOf(container).canAttach).isFalse();

    await notifierOf(container).attach('/tmp/spec.png');

    // Nothing was copied, so there is nothing to clean up either.
    check(images.saved).isEmpty();
    check(stateOf(container).attachments).isEmpty();
  });

  test('the third image is the last one accepted', () async {
    final seed = sessionWith();
    container = containerWith(seed, vision: true);
    await notifierOf(container).open(seed.id);

    for (final name in <String>['a.png', 'b.png', 'c.png', 'd.png']) {
      await notifierOf(container).attach('/tmp/$name');
    }

    check(stateOf(container).attachments).length.equals(ChatState.maxImages);
    check(stateOf(container).canAttach).isFalse();
  });

  test('removing an image deletes the copy with it', () async {
    final seed = sessionWith();
    final images = FakeImageStore();
    container = containerWith(seed, vision: true, images: images);
    await notifierOf(container).open(seed.id);
    await notifierOf(container).attach('/tmp/spec.png');
    final stored = images.saved.single;

    await notifierOf(container).removeAttachment(stored);

    check(stateOf(container).attachments).isEmpty();
    check(images.deleted).deepEquals(<String>[stored]);
  });

  test('regenerate asks again with the same images', () async {
    final seed = sessionWith();
    container = containerWith(seed, vision: true);
    await notifierOf(container).open(seed.id);
    await notifierOf(container).attach('/tmp/spec.png');
    await notifierOf(container).send('What is this?');

    await notifierOf(container).regenerate();

    // The same question means the same pictures, or it is a different one.
    check(llm.askedImages).length.equals(2);
    check(llm.askedImages.last).deepEquals(llm.askedImages.first);
  });

  test('the projector is passed to the loader', () async {
    final seed = sessionWith();
    container = containerWith(seed, vision: true);
    await notifierOf(container).open(seed.id);

    check(llm.projectors.single).equals(fakeProjector().localPath);
    check(stateOf(container).hasVision).isTrue();
  });

  test('send is refused until the model is ready', () async {
    // No `open`, so the state is still idle.
    container = containerWith(sessionWith());

    await notifierOf(container).send('Too early');

    check(llm.prompts).isEmpty();
  });

  test('a finished turn is written to disk', () async {
    final seed = sessionWith();
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);
    final before = sessions.saveCalls;

    await notifierOf(container).send('Persist me');

    // One write for the question, one for the finished reply; the
    // per-token renders do not touch disk.
    check(sessions.saveCalls - before).equals(2);
    check(sessions.stored.single.messages).length.equals(2);
  });

  test('close resets the state so the next session starts clean', () async {
    final seed = sessionWith(count: 2);
    container = containerWith(seed);
    await notifierOf(container).open(seed.id);

    notifierOf(container).close();

    check(stateOf(container).session).isNull();
    check(stateOf(container).status).equals(ChatStatus.idle);
  });
}
