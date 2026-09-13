# COMPILE_NOTES.md

First successful compile pass for `puck`.

- Flutter **3.47.4** • Dart **3.13.3** • Linux x86_64
- `flutter analyze` → **No issues found!**
- `flutter test` → **29/29 passed** (exit 0)
- `flutter build apk --debug` → attempted; see §7
- `flutter build ios --debug --no-codesign` → **not possible on this host**; see §8

Every change below is tied to a specific analyzer error, test failure, or build
failure. No `// ignore:` comments, no dependency downgrades, no commented-out
code.

---

## 1. Environment (prerequisite, not a code change)

The sandbox had no Dart or Flutter at all. Installed:

| Tool | Where | Why |
| --- | --- | --- |
| Flutter 3.47.4 / Dart 3.13.3 | `/usr/local/flutter` | satisfies `environment: sdk: ^3.5.0` |
| Temurin JDK 17 | `/usr/local/jdk17` | host had JDK 11; the Gradle wrapper pins 9.3.1, which requires 17+ |
| Android SDK (platform-tools, platform-35, build-tools 35.0.0) | `/usr/local/android-sdk` | required by `flutter build apk` |

All outside `/home/user`, so nothing here is part of the repo.

---

## 2. `pubspec.yaml` — the only resolution failure

```
Because puck depends on torch_light ^1.2.0 which doesn't match any versions,
version solving failed.
```

**Change:** `torch_light: ^1.2.0` → `^2.0.0`.

The highest published 1.x is **1.1.0**, so `^1.2.0` matched nothing and
`flutter pub get` could not resolve at all. This is an upgrade, not a
downgrade, and no call site changed — `enableTorch()` / `disableTorch()`
kept their signatures in 2.0.0.

No other constraint needed touching; every other package had a valid version
inside its declared range.

---

## 3. Import errors (8 files)

All of these were undefined-identifier or undefined-class errors. Each is a
missing `import` and nothing else.

| File | Added | For |
| --- | --- | --- |
| `lib/main.dart` | `package:flutter/services.dart` | `SystemChrome`, `DeviceOrientation` |
| `.../puck_gesture_recognizer.dart` | `package:flutter/foundation.dart` | `VoidCallback` |
| `.../puck_screen.dart` | `package:puck/src/providers.dart` | `settingsProvider`, `jokeRepositoryProvider` |
| `.../spring_offset.dart` | `package:flutter/gestures.dart` | `Velocity` |
| `.../widgets/context_card.dart` | `dart:ui` | `PointMode` |
| `.../widgets/sos_sheet.dart` | `.../repositories/settings_repository.dart` | `SettingsRepository` |
| `.../settings/settings_screen.dart` | `.../repositories/settings_repository.dart` | `SettingsRepository` |
| `lib/src/sync/puck_sync_client.dart` | `dart:typed_data` | `Uint8List` |

`puck_sync_client.dart` also had `import 'puck_crypto.dart';` (relative), which
trips `always_use_package_imports`. Converted to
`package:puck/src/sync/puck_crypto.dart`.

---

## 4. Type errors

### 4a. `location_service.dart` — `Future<Position?>` vs `FutureOr<Position>`

```
The argument type 'Future<Position?> Function()' can't be assigned to the
parameter type 'FutureOr<Position> Function()?'
```

`.timeout(timeout, onTimeout: lastKnown)` — `lastKnown()` returns `Position?`,
but the future being timed is `Future<Position>`.

**Change:** dropped the `onTimeout` callback. `.timeout(timeout)` throws
`TimeoutException`, which the very next line already catches and answers with
`lastKnown()`. Identical observable behaviour, one fallback path instead of two.

### 4b. `puck_crypto.dart` — `List<int>` vs `Uint8List`

`SecretKey.extractBytes()` returns `Future<List<int>>`; the method declares
`Future<Uint8List>`. Wrapped: `Uint8List.fromList(await key.extractBytes())`.

### 4c. `puck_gesture_recognizer.dart` — `onDragStart`

```
The parameter 'onDragStart' can't have a value of 'null' because of its type,
but the implicit default value is 'null'
```

The field is `final void Function(Offset) onDragStart` (non-nullable) but the
constructor parameter was optional.

**Change: added `required`.** This is the one edit to this file beyond an
import, and it is one keyword:

- Its three siblings (`onGesture`, `onDragUpdate`, `onDragEnd`) are all already
  `required`.
- Its only caller, `PuckBubble`, declares it `required` too, so every call site
  already supplies it.
- The alternative — making the field nullable — would have forced a null check
  into the drag path, i.e. an actual behaviour change.

No threshold, timing constant, or branch of the gesture state machine was
touched.

### 4d. `puck_screen.dart` — non-exhaustive switch

```
The type 'PanelKind' isn't exhaustively matched by the switch cases since it
doesn't match the pattern 'PanelKind.answer'
```

`PanelKind` has a fourth member, `answer`, with no case in `_panelFor`.

**Change: added `case PanelKind.answer: return _empty;`**

Justification for not rendering something new: `IntentBar` reads
`widget.controller.intent` and renders the answer itself, and the controller
never assigns `PanelKind.answer` (it only ever sets `none`, `context` and
`joke`). Building a second renderer for the same content would be new
behaviour, which is out of scope for a compile pass. The case is documented in
place.

---

## 5. Deprecated APIs

### 5a. `speech_service.dart` — `speech_to_text` 7.x

`listenFor`, `pauseFor` and `localeId` moved off `listen()` and onto
`SpeechListenOptions`. Separately, `SpeechListenOptions`'s constructor is
**not** `const`, so the existing `const SpeechListenOptions(...)` was
`const_with_non_const`.

Migrated all three into the options object and dropped `const`.

### 5b. `settings_screen.dart` — `activeColor`

Deprecated after v3.31.0-2.0.pre. `activeTrackColor` was already set
separately, so the deprecated parameter was unambiguously the thumb:
`activeColor` → `activeThumbColor`.

---

## 6. Lint warnings that were real bugs

Two `unawaited` findings were not style nits.

**`messaging_service.dart`** — `return launchUrl(...)` inside a `try`, without
`await`. A future returned from inside a `try` is *not* covered by that `try`'s
`catch`, so a `PlatformException` from the launch would have propagated instead
of being converted to the documented `false`. Added `await`.

**`puck_controller.dart`** — `_closeSos()` is `async` and was fired and
forgotten on the line before `return opened`, so SOS teardown raced the
caller. Added `await`.

### Remaining lints

`dart fix --apply` handled 33 mechanical fixes across 12 files
(`unnecessary_import`, `prefer_const_constructors`, `unnecessary_const`,
`unnecessary_lambdas`, `prefer_final_locals`, `directives_ordering`,
`require_trailing_commas`, `unused_import`). Two were done by hand:

- `expression.dart` — removed `_peek()`, which has zero call sites anywhere in
  `lib/` (there was no `test/` to reference it from either).
- `haptics.dart` — `enabled` was a getter/setter pair wrapping a field with no
  logic. Collapsed to a plain field; the public surface (`service.enabled`
  read and write) is unchanged.

---

## 7. `flutter build apk --debug`

Not yet green. Two real blockers were found and fixed, and a third is
environmental.

### Blocker 1 — the Android platform folder was mostly missing

```
Build failed due to use of deleted Android v1 embedding.
```

This message is misleading. `AndroidManifest.xml` already declares
`<meta-data android:name="flutterEmbedding" android:value="2" />`.

The real cause is in `flutter_tools/lib/src/project.dart:898`:

```dart
bool get isUsingGradle => hostAppGradleFile.existsSync();
```

`hostAppGradleFile` is the **root** `android/build.gradle(.kts)`, which did not
exist. With `isUsingGradle == false`, `appManifestFile` resolves to the
non-Gradle path `android/AndroidManifest.xml`, which also does not exist, and
`computeEmbeddingVersion()` falls through to its "no manifest" branch and
reports v1.

Missing: root `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`,
`gradle/wrapper/`, a `MainActivity`, and all of `res/`.

**Fix:** `flutter create --platforms=android --org dev.puck --project-name puck .`

Because `flutter create` regenerates the manifest, the three hand-written files
that carry design intent were backed up first and verified afterwards:

- `android/app/src/main/AndroidManifest.xml` — the `SYSTEM_ALERT_WINDOW`
  rationale and the per-permission comments survived (`flutter create` does not
  overwrite an existing manifest).
- `android/app/build.gradle.kts` — all comments intact.
- `android/app/proguard-rules.pro` — intact.

Also removed the stale `GeneratedPluginRegistrant.java`. It is a generated
build artifact and is listed in `.gitignore`
(`/android/**/GeneratedPluginRegistrant.java`); it referenced an old plugin
set. And the generated `MainActivity` landed at `dev/puck/puck`, which does
not match the declared `namespace` / `applicationId` of `dev.puck.app`, so it
was moved to `dev/puck/app` with `package dev.puck.app`.

### Blocker 2 — the Gradle heap

The template ships `org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G`. This
host has **2 GB total**, so the daemon was OOM-killed mid-build ("Gradle build
daemon disappeared unexpectedly"). Capped to `-Xmx900m`, set
`kotlin.compiler.execution.strategy=in-process` (no second JVM) and
`org.gradle.workers.max=1`.

### Blocker 3 — wall time

With a cold Gradle and Maven cache the build ran 29 minutes without
completing on this 2-core / 2 GB sandbox. The dependency cache is now warm
(1.6 GB), so a subsequent run should be substantially faster, but it has not
been observed to completion. **The APK build is unproven.**

---

## 8. `flutter build ios --debug --no-codesign`

**Not possible on this host, for two independent reasons.**

1. On Linux, Flutter 3.47.4 does not offer an `ios` build subcommand at all:

   ```
   Available subcommands: aar, apk, appbundle, bundle, linux, web
   ```

   Both `--debug` and `--no-codesign` are rejected as unknown options
   (`Could not find an option named "--no-codesign"`, exit 64).

2. There is no Xcode, and there cannot be one on Linux.

This needs a macOS runner. **The iOS build is unproven.**

---

## 9. Tests

There was **no `test/` directory** — `flutter test` exited 1 with
`Test directory "test" not found.` There was no suite to make green.

Added `test/core/expression_test.dart` and `test/core/format_test.dart`:
**29 tests** over the two modules that are pure Dart with no plugin surface, so
they need no mocks and no new dependencies.

- `expression.dart` — operator precedence, parentheses, unary minus,
  right-associative `^`, modulo, whitespace, division/modulo-by-zero, trailing
  junk, `tryEvaluate`, `looksLikeMaths`.
- `format.dart` — `clock` (including 12 AM / 12 PM), `countdown` unit
  selection, `relativeDay` (calendar-day comparison, not 24-hour windows),
  coordinate formatting, accuracy, `clamp`.

These assert behaviour that already existed; no product code was changed to
make them pass. They do **not** cover anything with a plugin dependency — the
widget and controller layers remain untested, and `puck_controller.dart` in
particular is the file most worth a real test suite next.

---

## 10. What is still unverified

| Area | Status |
| --- | --- |
| Static analysis | **Clean** |
| Pure-Dart unit tests | **29/29** |
| Android APK build | Unproven — timed out on a 2 GB box |
| iOS build | Impossible on Linux |
| Plugin behaviour at runtime | Untested on any device |
| `torch_light` 2.0.0 | Compiles; not exercised — the brief's `EnableTorchException` is worth a try/catch review at the `TorchService` call site |
| `geolocator`, `device_calendar`, `battery_plus`, `vibration` | All compiled without error, so no breaking-change migration was actually required |
