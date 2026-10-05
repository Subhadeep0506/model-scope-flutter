# ModelScope — Chat

An on-device chat app built to evaluate [`nobodywho`](https://pub.dev/packages/nobodywho),
the Flutter binding for local GGUF inference. This is one part of a larger app, built and
tested on its own: the **Chat** area, running against a single hardcoded local model.

The UI is built from the mockups in [assets/design/](assets/design/) — a sessions list, a
transcript, and two modal sheets (Loaded models, Sampling).

## What this part does

- **Chat tab is real.** Multi-session list with search and model/date filters, create and
  delete behind a confirmation, a streaming transcript, and both sheets. Sessions persist
  to shared preferences and are replayed into the model's context when a session is reopened,
  up to the number of turns set by `CHAT_MEMORY` in the Sampling sheet.
- **Home, Agent and Settings are stubs.** They exist so the bottom navigation matches the
  design; each renders a placeholder.
- **Tool calling is not in this part.** Deferred to a later pass.
- **Images go to vision models.** The composer accepts `jpg`, `jpeg` and `png`, up to three
  per message; documents are deferred to the RAG agent. Seeing them takes a second file: a
  model's **projector** (`mmproj-*.gguf`), downloaded from the same repository as its weights
  in Settings → Browse models. One projector covers every quant installed from that
  repository. Without one the image button is disabled, because the model cannot read a
  picture and the app would only be pretending. Past images are replayed into context as
  `[image: name]` rather than re-encoded, which keeps a 4096-token window usable.

## Get the model

The weights are 386 MB and are not committed. Download the GGUF and drop it into
`assets/models/`, keeping the exact filename:

```
curl -L -o assets/models/smollm2-360m-instruct-q8_0.gguf \
  https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf
```

On first launch the app copies the asset out to `<app documents>/models/` — `nobodywho` needs
a real filesystem path and cannot read a bundle entry. That copy briefly holds the whole file
in memory; to skip it, put the `.gguf` straight into `<app documents>/models/` and leave
`assets/models/` holding only its README. See [assets/models/README.md](assets/models/README.md)
for both paths and the exact locations the app checks.

> The model URL originally supplied for this work,
> `mmproj-SmolVLM-256M-Instruct-f16.gguf`, is a vision *projector* — it has no language model
> and cannot generate text. SmolLM2 360M Instruct is what the mockups depict
> (`SmolLM2 360M Instruct`, `Q8_0`, `386 MB`) and what the app loads.

## Run it

`nobodywho` is an FFI plugin resolving a native binary, so it needs a real platform target —
there is no web build. **This repo has `android/`, `ios/`, `macos/` and `web/` but no
`windows/`.** Pick whichever toolchain you already have; each is a one-time setup.

### Android (uses the existing `android/` folder)

1. Install Android Studio, then its SDK and an emulator image (Tools → Device Manager → an AVD
   on API 34+). A physical device with USB debugging works too.
2. `flutter doctor` — the "Android toolchain" line must be green; run
   `flutter doctor --android-licenses` if it asks.
3. `flutter run`

A 386 MB asset makes for a large APK and a slow first install. If that gets tiresome, use the
documents-directory route above and `adb push` the file once.

### Windows desktop (needs scaffolding first)

1. Install Visual Studio 2022 with the **"Desktop development with C++"** workload (the Build
   Tools alone are not enough — Flutter looks for the full VS install).
2. `flutter create --platforms=windows .` — generates the missing `windows/` folder without
   touching `lib/`.
3. `flutter run -d windows`

Desktop is the faster loop for judging generation quality: no emulator, and the model file sits
on the same disk.

### Network permission

The app is fully offline as it stands, so no permission changes are needed. If you later swap
the bundled model for a downloaded one, add to
`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

## Develop

```
flutter pub get
dart run build_runner build   # regenerates the *.g.dart files after touching lib/data/models/
dart format .
flutter analyze .
flutter test
```

`flutter analyze .` is clean and all **75 tests pass**. They run on the Dart VM, so they need
no device or toolchain — which makes them the only gate that runs everywhere.

**What the tests do not cover, because no target could be built here:** that the native
`nobodywho` binary loads at all, that SmolLM2 360M produces sensible text, and the real
throughput. Every test runs against `FakeLlmService`. Judging the package — the point of this
part — needs one of the toolchains above.

## Layout

Layered, MVVM via Riverpod, per [CLAUDE.md](CLAUDE.md).

```
lib/
  config/     di/ (providers + view models) · router/ (GoRouter) · theme/ (palette, metrics, type)
  domain/     services/ — llm_service.dart is the seam; nobodywho_llm_service.dart is the only
              file importing package:nobodywho. Also model_installer, token_collector.
  data/       models/ (json_serializable, snake_case wire keys) · sources/ · repositories/
  presentation/
              screens/ · view_models/ (Notifier / AsyncNotifier) · widgets/
```

Routes: `/` Home · `/chat` sessions list · `/chat/session/:id` transcript · `/agent` ·
`/settings`. The four tabs are a `StatefulShellRoute.indexedStack`; the transcript sits outside
the shell so it covers the navigation bar, as drawn.

### Two things the package does not provide

Both are worked around in app code, and both are covered by tests:

- **Per-reply metrics** (`118ms · 93.4 tok/s · 96 tok`). `ChatStats` exposes only
  `contextSize`/`contextUsed`, so `TokenCollector` times the stream instead: latency is the wait
  for the first token, throughput excludes that wait, and the figures are stored on the message
  so they survive a reload.
- **A max-token cap.** `SamplerBuilder` has none, so `ChatViewModel` counts stream events and
  calls `stopGeneration()` on reaching the limit. The slider works exactly as designed; the
  enforcement is client-side.
