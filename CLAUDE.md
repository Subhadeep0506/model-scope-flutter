# AI Rules for Flutter

## Persona & Tools
* **Role:** Expert Flutter Developer. Focus: Beautiful, performant, maintainable code.
* **Explanation:** Explain Dart features (null safety, streams, futures) for new users.
* **Tools:** ALWAYS run `dart_format`. Use `dart_fix` for cleanups. Use `analyze_files` with `flutter_lints` to catch errors early.
* **Dependencies:** Add with `flutter pub add`. Use `pub_dev_search` for discovery. Explain why a package is needed.

## Architecture & Structure
* **Architecture:** Strict MVVM (Model-View-ViewModel) architecture MUST be used everywhere. Do not hardcode data or business logic in the screens/widgets.
* **Entry:** Standard `lib/main.dart`.
* **Layers:** Organized by layer, not by feature.
  * **View (Presentation):** `lib/presentation/screens/` and `lib/presentation/widgets/`. Dumb components that strictly observe ViewModels.
  * **ViewModel:** `lib/presentation/view_models/`. Orchestrates data flow, contains business logic, and exposes state for the View.
  * **Model/Data:** `lib/data/` (repositories, APIs, sync) and `lib/domain/` (services).
* **SOLID:** Strictly enforced.
* **State Management & DI:**
  * **Pattern:** MVVM specifically enforced via `flutter_riverpod`.
  * **Views:** Must extend `ConsumerWidget` or `ConsumerStatefulWidget` and use `ref.watch()` / `ref.read()` to bind to ViewModels.
  * **ViewModels:** Implement using current Riverpod standards like `Notifier` or `AsyncNotifier`.
  * **DI:** Handle all dependency injection via Riverpod `Provider`s in `lib/config/di/`.

## Code Style & Quality
* **Naming:** `PascalCase` (Types), `camelCase` (Members), `snake_case` (Files).
* **Conciseness:** Functions <20 lines. Avoid verbosity.
* **Null Safety:** NO `!` operator. Use `?` and flow analysis (e.g. `if (x != null)`).
* **Async:** Use `async/await` for Futures. Catch all errors with `try-catch`.
* **Logging:** Use `dart:developer` `log()` locally. NEVER use `print`.

## Flutter Best Practices
* **Build Methods:** Keep pure and fast. No side effects. No network calls.
* **Isolates:** Use `compute()` for heavy tasks like JSON parsing.
* **Lists:** `ListView.builder` or `SliverList` for performance.
* **Immutability:** `const` constructors everywhere validation. `StatelessWidget` preference.
* **Composition:** Break complex builds into private `class MyWidget extends StatelessWidget`.

## Routing (GoRouter)
Use `go_router` exclusively for deep linking and web support.

```dart
final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => Home()),
  GoRoute(path: 'details/:id', builder: (_, s) => Detail(id: s.pathParameters['id']!)),
]);
MaterialApp.router(routerConfig: _router);
```

## Data (JSON)
Use `json_serializable` with `fieldRename: FieldRename.snake`.

```dart
@JsonSerializable(fieldRename: FieldRename.snake)
class User {
  final String name;
  User({required this.name});
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

## Arxplorer API
* Refer the `docs/api-docs.md` file for the API specifications and input/output format.


## Visual Design (Material 3)
* **Aesthetics:** Premium, custom look. "Wow" the user. Avoid default blue.
* **Theme:** Material 3 components, with custom app specific themes.
* **Modes:** Support Light & Dark modes (`ThemeMode.system`).
* **Typography:** `google_fonts`. Define a consistent Type Scale.
* **Layout:** `LayoutBuilder` for responsiveness. `OverlayPortal` for popups.
* **Components:** Use `ThemeExtension` for custom tokens (colors/sizes).
* **Widgets**: Use native Material3 widgets with app specific customizations. Create customizations based on design inside the `presentation/widgets` directory for reuse throughout the app.

## Testing
* **Tools:** `flutter test` (Unit), `flutter_test` (Widget), `integration_test` (E2E).
* **Mocks:** Prefer Fakes. Use `mockito` sparingly.
* **Pattern:** Arrange-Act-Assert.
* **Assertions:** Use `package:checks`.

## Accessibility (A11Y)
* **Contrast:** 4.5:1 minimum for text.
* **Semantics:** Label all interactive elements specifically.
* **Scale:** Test dynamic font sizes (up to 200%).
* **Screen Readers:** Verify with TalkBack/VoiceOver.

## Commands Reference

* **Analyze:** `flutter analyze .`
* **Skip building after each change**: Only build if user asks for.