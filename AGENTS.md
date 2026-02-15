# Repository Guidelines

## Project Structure & Module Organization
- `lib/` holds the Dart source code; the app entry point is `lib/main.dart`.
- `test/` contains Flutter widget tests (example: `test/widget_test.dart`).
- `ios/` contains the iOS runner, Xcode project files, and native assets.
- `pubspec.yaml` defines dependencies, SDK constraints, and Flutter assets.
- `analysis_options.yaml` configures analyzer rules via `flutter_lints`.

## Build, Test, and Development Commands
- `flutter pub get` installs dependencies from `pubspec.yaml`.
- `flutter run` launches the app on a connected device or simulator.
- `flutter test` runs the test suite in `test/`.
- `flutter analyze` runs static analysis with the configured lints.
- `flutter build ios` produces a release build for iOS (macOS required).

## Coding Style & Naming Conventions
- Indentation: 2 spaces, as per Dart and Flutter defaults.
- Naming: `UpperCamelCase` for classes, `lowerCamelCase` for methods/vars, and `lower_snake_case` for filenames (e.g., `main.dart`).
- Prefer formatting with `dart format .` before committing.
- Linting: follow `flutter_lints` from `analysis_options.yaml`; suppress only when necessary.

## Testing Guidelines
- Framework: `flutter_test` with `testWidgets` for UI-level tests.
- Name tests descriptively (e.g., `Counter increments smoke test`).
- Place new tests in `test/` and keep them close to the feature they cover.
- Run tests locally with `flutter test` before opening a PR.

## Commit & Pull Request Guidelines
- No commit message conventions are defined in this repository yet; use short, imperative subjects (e.g., "Add plant detail view").
- PRs should include a clear description, testing notes (commands + results), and screenshots for UI changes.
- Link related issues or tasks when applicable.

## Security & Configuration Tips
- Do not commit secrets or platform signing files.
- Keep SDK and dependency changes limited to what the feature requires and note them in the PR.
