# Maintaining this app

How to find things, change them, and check you didn't break anything.

Every example below is real code copied out of this repo, not invented.

---

## 1. The commands

Run these from the project root (`model_scope_flutter/`).

| What you want | Command |
| --- | --- |
| Check the code compiles and is clean | `flutter analyze .` |
| Run all the tests | `flutter test` |
| Run one test file | `flutter test test/domain/token_collector_test.dart` |
| Tidy the formatting | `dart format lib test` |
| Regenerate the `.g.dart` files | `dart run build_runner build` |
| Install a new package | `flutter pub add <name>` |

**`flutter analyze .` always reports exactly 1 issue** — an empty `catch` in
[app_cache_service.dart:18](lib/domain/services/app_cache_service.dart#L18). That
one is deliberate and known. If you ever see **2** issues, your change caused it.

**`flutter test` should say `572 passed`.** If the number drops, you broke
something. If it rises, you added a test — good.

There is nothing to run locally on this machine. The only way to see the app
actually work is: pass these three commands → build the APK in CI → install it
on your phone.

---

## 2. The map

Four folders under `lib/`. The rule is simple: **each layer may only talk to the
one below it.** Nothing ever reaches back up.

```
lib/
├── presentation/   ← what you see and touch
│   ├── screens/        a whole page (Home, Settings, Chat)
│   ├── widgets/        a reusable piece (a card, a button, a chip)
│   └── view_models/    the brain behind a screen — ALL logic lives here
│
├── domain/         ← things that do work
│   ├── services/       talks to the model, the disk, the downloader, the web
│   │                   — and runs an agent (agent_runner.dart)
│   └── tools/          jobs the model itself is allowed to ask for
│
├── data/           ← things that hold or fetch information
│   ├── models/         plain data shapes (a chat message, a setting)
│   ├── repositories/   "save this" / "load that"
│   └── sources/        the raw plumbing (a JSON file, the keychain, HTTP)
│
└── config/         ← wiring
    ├── di/             the list of every part and how it's built
    ├── router/         the URLs of every screen
    └── theme/          colours, sizes, fonts
```

**The one rule that matters:** a screen or a widget never decides anything. It
reads a value and draws it; when you tap something it calls a method on the view
model and forgets about it. If you find yourself writing an `if` about *business*
rules inside a screen file, it belongs in the view model instead.

### Following one change all the way through

Tap **Clear cache** in Settings. Here is every file that is involved, in order:

1. **[storage_card.dart:69](lib/presentation/widgets/storage_card.dart#L69)** — the
   button. All it does is point at a method:

   ```dart
   OutlinedButton.icon(
     onPressed: bytes.isLoading
         ? null
         : ref.read(storageViewModelProvider.notifier).clear,
     icon: const Icon(Icons.delete_outline_rounded, size: 18),
     label: const Text('Clear cache'),
   )
   ```

2. **[storage_view_model.dart](lib/presentation/view_models/storage_view_model.dart)** —
   the brain. The whole file is 18 lines:

   ```dart
   class StorageViewModel extends AsyncNotifier<int> {
     @override
     Future<int> build() => ref.read(appCacheServiceProvider).sizeInBytes();

     Future<void> clear() async {
       await ref.read(appCacheServiceProvider).clear();
       state = await AsyncValue.guard(
         () => ref.read(appCacheServiceProvider).sizeInBytes(),
       );
     }
   }
   ```

3. **[app_cache_service.dart](lib/domain/services/app_cache_service.dart)** — the
   thing that actually deletes files off the disk.

4. Setting `state` at the end of step 2 makes the card in step 1 redraw itself.
   You never tell it to. That happens because the card used `ref.watch(...)`.

That's the shape of every feature in this app. Button → view model → service.

### `watch` vs `read` — the only two you need

- **`ref.watch(x)`** — "give me the value, and redraw me when it changes."
  Use inside `build`.
- **`ref.read(x)`** — "give it to me once, I'm about to call a method on it."
  Use inside button handlers, never inside `build`.

Getting these backwards is the single most common mistake. `watch` in a button
handler, or `read` in `build`, will compile fine and then misbehave.

---

## 3. Adding things

### Using a widget that already exists

Before writing anything new, look in
[lib/presentation/widgets/](lib/presentation/widgets/). There are ~50 pieces
already built. The ones you'll reach for most:

| Widget | What it is |
| --- | --- |
| `SectionCard` | the standard white, outlined, rounded box |
| `SectionHeading` | a section title, optionally with an action link |
| `MonoLabel` | small monospaced text (`94.2 tok/s`, `TOKENS GENERATED`) |
| `MarkdownText` | a message body — models answer in markdown, so never use plain `Text` |
| `StatTile` | one figure on the Home dashboard |
| `SquareIconButton` | the 44dp square icon buttons |
| `LabelledSlider` | a slider with its name and current value |
| `SheetScaffold` | the frame every pop-up sheet sits in |

Using one is just calling it:

```dart
StatTile(
  label: 'AVG LATENCY',
  value: '${stats.averageLatencyMs}ms',
  caption: 'time to first token',
)
```

### Adding a new widget

Make a new file in `lib/presentation/widgets/`, named in `snake_case`. Copy the
shape of [stat_tile.dart](lib/presentation/widgets/stat_tile.dart):

```dart
import 'package:flutter/material.dart';

import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import 'section_card.dart';

/// One line saying what this is.
class MyThing extends StatelessWidget {
  const MyThing({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return SectionCard(
      padding: EdgeInsets.all(metrics.gapMd),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
```

Checklist for a new widget:

- `const` on the constructor, and `required` on anything it can't work without.
- Every field `final`. Widgets never change their own values.
- **Never type a colour or a number directly.** Use `context.palette.primary`,
  `context.metrics.gapMd`. See section 4.
- If the widget needs to *read app state*, use `ConsumerWidget` instead of
  `StatelessWidget` and take a second `WidgetRef ref` argument in `build` — that
  is what [storage_card.dart](lib/presentation/widgets/storage_card.dart) does.

### Adding a screen

Two steps.

**Step 1** — the file in `lib/presentation/screens/`, same shape as a widget but
wrapped in a `Scaffold`:

```dart
class MyScreen extends ConsumerWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(body: SafeArea(child: /* ... */));
  }
}
```

**Step 2** — register its URL in
[app_router.dart](lib/config/router/app_router.dart). Add the path to `Routes`
first so the string is written once:

```dart
abstract final class Routes {
  static const String home = '/';
  static const String settings = '/settings';
  static const String catalog = '/settings/catalog';   // ← nested under Settings
}
```

Then add the route itself. Nesting it under an existing tab keeps the bottom
navigation bar visible and makes the back button return to that tab:

```dart
_branch(
  Routes.settings,
  const SettingsScreen(),
  routes: <RouteBase>[
    GoRoute(path: 'catalog', builder: (_, _) => const ModelCatalogScreen()),
  ],
),
```

To go there from a button: `context.push(Routes.catalog)` (stacks on top, back
returns) or `context.go(Routes.settings)` (switches tab).

### Adding a view model

A view model is a class holding one piece of state plus the methods that change
it. Two flavours:

- **`Notifier<T>`** — the value is available immediately. `build()` returns `T`.
- **`AsyncNotifier<T>`** — the value has to be loaded from disk or the network
  first. `build()` returns `Future<T>`.

Write the class in `lib/presentation/view_models/`, then **register it** in
[view_models.dart](lib/config/di/view_models.dart) — one line:

```dart
final storageViewModelProvider = AsyncNotifierProvider<StorageViewModel, int>(
  StorageViewModel.new,
);
```

That line is what screens use to reach it. Without it the view model is
unreachable.

### Adding a service or a repository

Write the class in `lib/domain/services/` or `lib/data/repositories/`, then
register it in [providers.dart](lib/config/di/providers.dart):

```dart
final appCacheServiceProvider = Provider<AppCacheService>(
  (ref) => AppCacheService(ref.watch(documentsDirectoryProvider)),
);
```

If it holds something that must be released — a network connection, a
subscription — add `ref.onDispose`:

```dart
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
```

**Two files, two purposes:** `providers.dart` holds the things that *do work*
(services, repositories, plumbing). `view_models.dart` holds the brains behind
screens. Put a new thing in the matching one.

### Adding a tool the model can call

A **tool** is a job the model asks *you* to do mid-answer. It writes something
like "call `web_search` with `query: flutter 4 release date`", the app runs the
real work, and the text you hand back goes into the model's context as if it
had always known it. Two exist so far, in
[lib/domain/tools/web_tools.dart](lib/domain/tools/web_tools.dart): one searches
the web, one reads a page.

A tool is a plain Dart function wrapped in a
[ToolDefinition](lib/domain/tools/tool_definition.dart):

```dart
Future<String> run({required String query}) async { ... }

ToolDefinition(
  name: 'web_search',
  description: 'Search the web and get back a numbered list of pages...',
  function: run,
  parameterDescriptions: const <String, String>{'query': 'What to search for...'},
);
```

Four rules, and breaking any of them fails at runtime rather than in `analyze`:

1. **Every parameter must be named and `required`.** The library works out what
   to tell the model by reading the function's signature at runtime, and only
   this shape is known to work.
2. **Types must be** `String`, `int`, `double`, `bool`, or a list of those.
3. **It must return a `String`** (or a `Future<String>`). That string *is* the
   answer the model sees.
4. **It must never throw.** An exception's text gets handed to the model as
   though it were a result, which reads like an answer. Catch everything and
   return a sentence that says what went wrong — that way the model can tell
   the user instead of inventing something.

Keep the output short. It is spent out of the same few thousand tokens the
conversation lives in, which is why both web tools cut their text to a budget
and say when they have.

Register the tool in the list in
[providers.dart](lib/config/di/providers.dart), under `webToolsProvider`. The
one file that knows about `nobodywho` is
[nobodywho_tools.dart](lib/domain/tools/nobodywho_tools.dart) — it turns these
definitions into the thing the chat accepts. Everything else stays plain Dart,
which is what lets `flutter test` call a tool directly.

### Adding an agent

An **agent** is a saved recipe: a list of steps the app walks in order, each
one asking the model to do a single thing. It is a JSON file and nothing else —
drop one in [assets/agents/](assets/agents/) and it appears on the Agent tab.
The app finds it by listing the directory, so there is no index to update.

A file looks like this ([web_answer.json](assets/agents/web_answer.json) is the
shortest real one):

```jsonc
{
  "id": "web_answer",                  // also the file name
  "name": "Web Answer",                // the card title
  "purpose": "Answer one question from a live web search",
  "icon": "search",
  "system_prompt": "You are a careful research assistant.",

  "inputs": [
    { "name": "question", "label": "Question",
      "type": "text", "default": "What is the latest Flutter release?" }
  ],

  "pipeline": [
    { "id": "search", "kind": "tool", "tool": "web_search",
      "prompt": "Search the web for: {{input.question}}" }
  ],

  "answer": {
    "prompt": "Answer using only the results above, and give the URL.",
    "reads": ["input.question", "step.search"]
  }
}
```

**Steps come in two kinds.** A `tool` step names one tool and gives the model
*only* that tool — it decides what arguments to pass, nothing else. A `reason`
step gives it no tools and just asks it to think. The `answer` step is always
last, always has no tools, and every agent has one.

**Wiring steps together.** A step sees nothing by default. It gets data two
ways, and both accept `input.<name>` (what the user typed) or `step.<id>`
(what an earlier step produced):

- `"reads": ["step.search"]` — pastes that value in above the instruction.
- `{{input.question}}` — drops it into the middle of a sentence.

A step can only read something that comes **before** it. Reading a later step
is caught before the agent runs.

**Rules that are checked for you.** `flutter test` has a test that loads every
file in `assets/agents/` and validates it, so a typo fails the suite rather
than the phone. It will catch: a tool this build does not have, a step reading
something that does not exist, two steps with the same `id`, and an unknown
`kind` or input `type`.

**The five tools you can name** are `web_search`, `read_web_page`,
`calculator`, `date_math` and `unit_convert` — see `ToolRegistry.standard` in
[tool_registry.dart](lib/domain/tools/tool_registry.dart). The first two need
an API key; the last three need nothing, which is why
[tool_stress_test.json](assets/agents/tool_stress_test.json) runs on a fresh
install.

**One thing that is parsed and ignored:** a step may carry `"model"`. Every
step of a run uses the one model, because swapping GGUF weights mid-run costs
seconds a step on a phone. The field is kept so files written now still work
the day that changes.

A **custom agent** — one the user builds in the app — is the same JSON, written
to its own file under `agents/` in the documents directory by
[agent_file_store.dart](lib/data/sources/agent_file_store.dart). Nothing in the
file says whether it is built in; the repository knows by where it loaded it.
There is no screen for building one yet; the Agent tab runs what is shipped.

### What happens when you press Run

Worth knowing, because the model is handled differently here than in Chat.

1. **[agent_detail_screen.dart](lib/presentation/screens/agent_detail_screen.dart)**
   — the green button calls one method and forgets about it, as every button in
   this app does.
2. **[agent_run_view_model.dart](lib/presentation/view_models/agent_run_view_model.dart)**
   — **this is the only place an agent loads a model.** Opening the screen
   loads nothing; pressing Run loads the weights (falling back to the CPU if
   the GPU refuses, via
   [model_loader.dart](lib/domain/services/model_loader.dart), which Chat shares),
   then subscribes to the run.
3. **[agent_runner.dart](lib/domain/services/agent_runner.dart)** — walks the
   steps and reports as it goes. Four kinds of event: a trace row, a token of
   the answer, a log line, and the finished record.
4. When the run ends — or you press **Stop**, or you leave the screen — the run
   is saved and **the model is released**. That last part matters: left loaded,
   the weights would still carry the agent's system prompt and its tools, and
   Chat only reloads when the model *id* changes, so the next chat would answer
   as the agent.

**The trace and the log are different things.** The trace is the list of rows
on screen — one per step, saved with the run in `agent_runs.json`. The log is
what **Show logs** opens: the exact prompt each step was sent, the raw reply,
and every tool call's arguments and result in full. The log is **not saved** —
a single scraped page runs to tens of kilobytes, and fifty runs of those would
cost more storage than every transcript on the device. It lives for as long as
the run screen is open.

### Three things an agent run does that Chat does not

All three exist because a model that reasons, or that samples loosely, will
answer a question instead of calling the tool it was handed — and this app is
built to measure tool calling.

1. **Thinking is turned off.** `AgentRunner.run` calls `llm.setThinking(false)`,
   which is `setTemplateVariable("enable_thinking", false)` underneath. A
   reasoning model otherwise works the answer out inside `<think>…</think>` and
   then states it, never reaching for the tool. A chat template that has no such
   variable makes this throw; the run carries on and the log says so. Chat is
   untouched and keeps its collapsible thinking block.
2. **A skipped tool step is asked again, once.** `AgentRunner.toolRetries`
   defaults to 1. The second prompt is the first plus a line leaving no room —
   *"You did not call the X tool. Call it now."* The failed first attempt stays
   in the trace as an amber `— not called, retrying` row, because a model that
   has to be told twice is a worse model and hiding that defeats the point.
3. **The sampler is low and fixed.** `SamplerSettings.forAgentRun()` pins
   temperature to `agentTemperature` (0.2) whatever the Chat sliders say, so two
   runs of one agent differ because of the model rather than the sampler.

Reasoning is also stripped everywhere it would travel: a step passes its answer
to the next step, not its thinking, and `AgentRun.output` holds the answer
alone. The raw text stays in the log, which is the one place it is worth
reading.

### Adding or changing a stored setting

Anything saved to disk lives in `lib/data/models/` and is converted to and from
JSON by a generator, so you don't hand-write that conversion.

To add a field to
[sampler_settings.dart](lib/data/models/sampler_settings.dart), you touch it in
four places inside the same file:

```dart
const int _topK = 40;                              // 1. the default

class SamplerSettings {
  const SamplerSettings({ this.topK = _topK });    // 2. the constructor

  final int topK;                                  // 3. the field

  SamplerSettings copyWith({ int? topK }) =>       // 4. copyWith
      SamplerSettings(topK: topK ?? this.topK);
}
```

**Then run `dart run build_runner build`.** That rewrites
`sampler_settings.g.dart`, which handles the saving and loading. If you forget,
`flutter analyze` will complain.

Never edit a `.g.dart` file. They are overwritten every time you run that
command.

---

## 4. Colours and sizes — never type them in

Two files hold every colour and every measurement in the app.

- **[app_palette.dart](lib/config/theme/app_palette.dart)** — colours.
  Read with `context.palette`.
- **[app_metrics.dart](lib/config/theme/app_metrics.dart)** — sizes, gaps,
  corner radii. Read with `context.metrics`.

```dart
final palette = context.palette;
final metrics = context.metrics;

Container(
  padding: EdgeInsets.all(metrics.gapMd),     // 12 — not a typed 12
  color: palette.surface,                      // not Colors.white
)
```

Why it matters: the app has a light mode and a dark mode. A hardcoded
`Colors.white` stays white in dark mode and the text becomes unreadable.
`palette.surface` switches on its own.

The gap scale, so you pick the right one: `gapXs` 4, `gapSm` 8, `gapMd` 12,
`gapLg` 16, `gapXl` 24.

---

## 5. Tests

### Running them

```bash
flutter test                                        # all 572
flutter test test/presentation/home_screen_test.dart  # just one file
```

Tests mirror the source layout: `lib/domain/services/token_collector.dart` is
tested by `test/domain/token_collector_test.dart`.

### The shape of a test

Three parts, separated by a blank line: set it up, do the thing, check the
result. The test's *name* says what it proves — write the name as a sentence.

```dart
test('add returns false exactly on the max-token boundary', () {
  final collector = TokenCollector(maxTokens: 3, clock: _ManualClock());

  final room = <bool>[
    collector.add('1'),
    collector.add('2'),
    collector.add('3'),
  ];

  check(room).deepEquals(<bool>[true, true, false]);
  check(collector.isFull).isTrue();
});
```

`check(...)` is the assertion. Common ones: `.equals(x)`, `.isTrue()`,
`.isNull()`, `.isNotNull()`, `.isEmpty()`, `.isNotEmpty()`,
`.deepEquals([...])`, `.length.equals(n)`.

### Testing something on screen

Use `testWidgets` instead of `test`, and wrap the thing in `harness(...)` from
[test/support/fakes.dart](test/support/fakes.dart). `harness` gives it the app's
theme and swaps in the fakes:

```dart
testWidgets('folds the stored replies into the tiles', (tester) async {
  await tester.pumpWidget(
    harness(
      const HomeScreen(),
      overrides: fakeOverrides(
        llm: FakeLlmService(),
        sessions: FakeSessionRepository(<ChatSession>[seeded()]),
      ),
    ),
  );
  await tester.pumpAndSettle();

  check(valueOf(tester, 'TOKENS GENERATED')).equals('3.5k');
});
```

`pumpWidget` draws it. `pumpAndSettle` waits for animations and loading to
finish. `find.text('...')` locates things on screen.

### The fakes

[test/support/fakes.dart](test/support/fakes.dart) is the most useful file in
the test folder. It contains stand-ins for everything real: the model, the disk,
the keychain, the network, the downloader.

`fakeOverrides(...)` hands you all of them at once with sensible defaults — one
model installed, no sessions. Pass only the ones your test needs to be
different:

```dart
// Default: one model installed.
fakeOverrides(llm: FakeLlmService(), sessions: FakeSessionRepository([]))

// A fresh install with nothing downloaded:
fakeOverrides(
  llm: FakeLlmService(),
  sessions: FakeSessionRepository([]),
  library: FakeModelLibraryRepository(),   // empty
)

// An agent test: two agents, no run history, and web_search gated
// behind a key it hasn't got.
fakeOverrides(
  llm: FakeLlmService(),
  sessions: FakeSessionRepository([]),
  agents: FakeAgentRepository.builtIn([fakeAgentTemplate()]),
  agentRuns: FakeAgentRunRepository(),
  tools: fakeToolRegistry(needingKeys: ['web_search']),
)
```

**Never let a test touch the real disk, network or model.** It will be slow,
flaky, and on a loaded CI machine it will hang.

### When to add a test

Add one whenever you fix a bug or add behaviour someone could break later.
Don't add one for a widget that only arranges other widgets — there is nothing
there to be wrong.

---

## 6. Rules that will bite you

These are enforced by `flutter analyze`, so you'll find out either way — but
knowing them up front saves a round trip.

- **Never use `!`.** Writing `value!` means "trust me, this isn't empty" and
  crashes the app when you're wrong. Use `?` and a fallback instead:

  ```dart
  // Good
  final name = stats.peakModelName ?? 'no replies yet';
  Text(style: Theme.of(context).textTheme.bodySmall?.copyWith(...))
  ```

- **Never use `print`.** Use `developer.log` with a name:

  ```dart
  import 'dart:developer' as developer;

  developer.log('Could not delete ${file.path}', name: 'AppCacheService',
      error: error);
  ```

- **`const` wherever it's offered.** `const Text('Clear cache')` is built once
  and reused; without it Flutter rebuilds it on every frame.

- **Keep functions under about 20 lines.** If a `build` method is getting long,
  pull a chunk into a private widget class in the same file — `_StatGrid`,
  `_Block`, `_Note` in [home_screen.dart](lib/presentation/screens/home_screen.dart)
  are exactly that.

- **Wrap anything that can fail in `try`/`catch`.** Disk, network, and the model
  all fail in normal use.

- **Comments.** One line saying what a class is. Beyond that, only write a
  comment when it explains a *decision* someone couldn't work out by reading the
  code — why something is deliberately not retried, why a number is 85% and not
  100%. Don't restate what the line below already says.

---

## 7. Before you call it done

```bash
dart format lib test     # tidy
flutter analyze .        # must say "1 issue found"
flutter test             # must say "572 passed" (or more)
```

If you changed anything that runs on the phone — a screen, a permission, the
downloader, the model — the three green commands are **not** proof it works.
They only prove it compiles and the logic holds. Build the APK in CI, install
it, and check the actual behaviour on the phone.

Comments and formatting are the exception: the compiler throws comments away, so
changing them can't change behaviour.
