# Puck

**One floating button. Four gestures. Zero menus.**

Puck is a single 72px disc on a black screen. It tells you the one thing you
actually need right now, tells you a joke when you ask twice, calls for help
when you hold it, and answers anything when you flick it upward. There is no
navigation, no onboarding flow, and no settings screen you are expected to
open more than once.

Flutter · Dart 3 · Android 7+ / iOS 13+

---

## Quick start

```bash
flutter pub get
flutter run
```

The app runs fully offline on first launch with no configuration. To enable the
swipe-up assistant, open **Settings** and paste a free key from
[console.groq.com/keys](https://console.groq.com/keys).

Without a key, Puck still does single tap, double tap, SOS, and — for coin
flips, dice, arithmetic, dates and "this or that" — the swipe-up bar too.

---

## The four gestures

| Gesture | Behaviour | Dismissal |
| --- | --- | --- |
| **Tap** | One piece of context, chosen by urgency | 4s |
| **Double tap** | A dry joke or fake motivational quote | 4s |
| **Hold 3s** | SOS: haptics + torch + pre-filled SMS | Manual |
| **Swipe up** | Ask anything, one-sentence answer | 7s |

### 1. Tap — context

Reads time, battery, the next calendar event, and local weather in one parallel
pass, then says **one** thing. Ranking is by *actionability*: would knowing this
change what you do in the next hour?

1. An event starting within 60 minutes, or one already running
2. Battery at or below 20%, or finished charging
3. Rain within 4 hours, or genuinely extreme temperatures
4. Otherwise, the time and a moment of reassurance

Weather comes from [Open-Meteo](https://open-meteo.com) — free, no API key — so
the app is useful before you configure anything.

The card paints immediately with a neutral state and refines when the snapshot
lands (~100–400ms). A tap that shows nothing for half a second feels broken.

### 2. Double tap — the daily giggle

100 bundled one-to-two-liners, served from a **shuffle bag**: you see every
joke before any repeat, and the bag order persists across sessions. Plain
`random()` hands you the same line twice in a row often enough to read as a bug.

### 3. Hold 3 seconds — SOS

In order:

- A three-pulse vibration pattern you can feel through a winter coat
- The torch at full brightness, strobed in **Morse SOS** (··· ——— ···) twice,
  then held steady
- A GPS fix, and a pre-filled SMS with coordinates, accuracy and a Google Maps
  link

**Puck does not send the message.** It hands a pre-filled body to the native SMS
composer. Sending requires a deliberate tap. Rationale: a pocket is a hostile
input device, an accidental emergency text has real costs, and `SEND_SMS` is a
Play-Store-restricted permission that would sink a four-gesture app. Torch and
haptics — harmless, attention-getting, and useful on their own — start instantly.

The whole sequence powers down after 30 seconds even if the sheet is never
dismissed, so a phone in a pocket does not cook itself.

### 4. Swipe up — ask anything

One line of input, one line of output. Queries are streamed over SSE and
rendered token by token.

Some queries never leave the device. Coin flips, dice, random numbers,
arithmetic, the time and the date resolve locally in microseconds — an LLM is
both slower and *worse* at them, since a model will answer "heads" with a
bias it cannot perceive.

---

## Architecture

```
lib/
├── main.dart                      startup: prefs, orientation, system chrome
├── app.dart                       MaterialApp + two routes
└── src/
    ├── core/
    │   ├── constants.dart         every tunable number, in one place
    │   ├── theme.dart             six greys, one red, the whole type scale
    │   ├── format.dart            hand-rolled date/time/coord formatters
    │   ├── haptics.dart           HapticFeedback + long vibration patterns
    │   └── expression.dart        70-line arithmetic evaluator
    ├── data/
    │   ├── models/context.dart    the snapshot Puck takes of "now"
    │   ├── llm/
    │   │   ├── llm_provider.dart  the seam: in a Request, out a Stream<String>
    │   │   ├── prompt.dart        the hardened system prompt, per-mode
    │   │   ├── groq_provider.dart SSE streaming + per-mode sampling
    │   │   └── local_fallback_provider.dart
    │   ├── repositories/          context, jokes, settings
    │   └── services/              battery, calendar, location, weather,
    │                              torch, messaging, speech
    ├── domain/
    │   ├── context_ranker.dart    THE PRODUCT: picks the one thing to say
    │   └── intent_router.dart     device or cloud?
    ├── features/
    │   ├── puck/
    │   │   ├── puck_gesture_recognizer.dart
    │   │   ├── spring_offset.dart
    │   │   ├── puck_controller.dart
    │   │   ├── puck_screen.dart
    │   │   └── widgets/           bubble, cards, intent bar, SOS sheet
    │   └── settings/
    └── providers.dart             the entire DI graph
```

### Why a custom gesture recogniser

This was the one genuinely hard part, and the reason there is no
`GestureDetector` in the codebase.

A stock `GestureDetector` with tap + doubleTap + longPress + verticalDrag puts
**four** recognisers into the gesture arena. The vertical-drag recogniser wins
the moment your finger clears touch slop — which destroys swipe-up, because a
swipe-up *is* vertical travel. Stacking a raw `Listener` underneath means
reimplementing slop, timing and velocity by hand anyway.

`PuckGestureRecognizer` is one recogniser, one pointer, one small state machine.
It claims the arena on pointer down and classifies the press:

```
travel up ≥ 56px and vertical-dominant  → swipe up    (fires mid-gesture)
travel > 18px in any direction          → drag
held 3s without leaving the slop        → long press
released inside slop                    → tap, unless a second tap
                                           lands within 260ms → double tap
```

Two details worth stealing:

- **Swipe-up fires mid-gesture**, while the finger is still moving. Waiting for
  pointer-up makes the "ultra-fast" bar feel like a normal one.
- **Tap resolves on a 260ms delay** rather than at pointer-up. Firing instantly
  would flash the context card before every single joke.

### Why physics, not curves

Edge-snapping uses two real spring simulations (`AnimationController.animateWith`)
rather than a `Curves.easeOut` tween, because a curve cannot express "the user
flicked it *this* hard". The snap target is chosen from a velocity projection,
so a leftward flick commits to the left edge even if released on the right half
of the screen. Damping ratio is ~0.63 — snappy, with a whisper of overshoot.

---

## Dependency budget

Twelve direct dependencies. Every one is either pure Dart or a thin plugin over
a platform API Dart cannot reach.

| Package | Why it is here | Cost |
| --- | --- | --- |
| `flutter_riverpod` | DI + observation | pure Dart |
| `http` | Groq, Open-Meteo | pure Dart |
| `shared_preferences` | settings | tiny |
| `flutter_secure_storage` | API key → Keychain / Keystore | small |
| `battery_plus` | battery level | tiny |
| `device_calendar` | next event | tiny |
| `geolocator` | GPS for SOS + weather | tiny |
| `torch_light` | flashlight, on/off only | tiny |
| `vibration` | long SOS patterns | tiny |
| `url_launcher` | pre-filled SMS | tiny |
| `speech_to_text` | the mic button | **heavy — see below** |
| `flutter_lints` | dev only | — |

Deliberately **not** included:

- **`intl`** — ~250KB of ICU tables for four formatters. `core/format.dart` is
  80 lines and zero dependencies.
- **Font packages** — a type family costs 300KB+ and buys nothing at 19px.
- **Icon packs** — the four context glyphs and the bubble are `CustomPaint`,
  smaller than the icon font would be.
- **Codegen / build_runner** — nothing in Puck is worth a build step.

### The one heavy dependency

`speech_to_text` is the only large thing here: on Android it pulls in Google ML
Kit and downloads a language model on first use. It is loaded **lazily** — the
recogniser is not initialised at startup, only when you press the mic.

If you would rather ship without it, three edits:

1. Delete `speech_to_text` from `pubspec.yaml`
2. Delete `lib/src/data/services/speech_service.dart`
3. In `intent_bar.dart`, remove the mic button and the two `_toggleMic` call
   sites (marked with `// SPEECH` comments)

Nothing else references it. Expect roughly 15MB off the Android build.

---

## Permissions

| Permission | Platform | Requested when |
| --- | --- | --- |
| Calendar read | both | first tap |
| Location (when in use) | both | first SOS, or first weather check |
| Camera | both | first SOS — the torch lives behind `AVCaptureDevice` / Camera2 |
| Microphone + speech | both | first press of the mic button |
| Vibrate | Android | automatically, on SOS |

Nothing is requested at launch. Puck boots to a black screen and asks for
nothing until a gesture needs it. Every permission is optional: denial degrades
one feature, never the app.

---

## Honest limitations

Worth reading before you demo this to anyone.

1. **No system-wide overlay, and iOS cannot have one.** Android permits
   draw-over-apps via `SYSTEM_ALERT_WINDOW`; **iOS has no equivalent API at
   any permission level**, and no workaround (a keyboard extension or a Live
   Activity is a different product). Puck is therefore a normal app whose
   entire UI *is* the bubble — which is why it looks identical on both
   platforms. On Android you *can* add an overlay service later without
   touching any of the feature code; the controller has no dependency on the
   surface it lives in.

2. **"Maximum brightness" is whatever the OS allows.** Dart has no
   cross-platform torch-level API. `enableTorch()` gives the platform default
   full level (AVCaptureDevice level 1.0 on iOS, the single torch mode on
   Android). Fine control needs a platform channel.

3. **The AI takes no actions, and no longer claims to.** Earlier drafts of the
   prompt told the model to answer device requests in the past tense, so
   "wake me at 7" produced a cheerful, confident "Alarm set for 7:00 AM" about
   something that had not happened. That rule is gone: Puck now answers "not
   connected" in under eight words until a real action registry exists. Flip
   `GroqLlmProvider.deviceActionsSupported` when you wire one up, and the
   past-tense confirmation comes back.

4. **SOS is one-way.** There is no "I'm safe" reply path, no location sharing
   link that updates, no fallback contact if the first one does not answer.
   All of that is real work, not scaffolding.

5. **Emergency features are not a substitute for a real emergency system.**
   This is an MVP. Do not ship it to people who depend on it.

6. **Not compiled in this environment.** The sandbox that produced this code
   had no Flutter/Dart SDK, so `flutter analyze` and `flutter test` have never
   been run against it. The code is written to be correct and is heavily
   commented, but expect to fix a few import paths and API-name details on
   first `flutter pub get`. Plugin APIs shift between majors; the ones most
   likely to need a nudge are `device_calendar` (event result types) and
   `speech_to_text` (`SpeechListenOptions` moved to a named parameter in v7).

---

## Extending

**Swap the model.** Implement `LlmProvider` (`in: String`, `out: Stream<String>`)
and change one line in `providers.dart`. `local_fallback_provider.dart` is a
working example with no network at all.

**Add a context source.** Add a service, add a field to `ContextSnapshot`, add
a candidate function to `ContextRanker.rank()`. The ranking is a flat priority
list at the top of that file — put yours in the right slot.

**Add real actions.** Give the model a tool schema, parse the JSON in
`groq_provider.dart`, and dispatch through a registry in `intent_router.dart`.
The UI already renders whatever single sentence comes back, so no changes are
needed downstream.

**Tune the feel.** Everything is in `core/constants.dart`: long-press duration,
double-tap window, swipe distance, spring stiffness, dismiss delays, Morse
timings.

---

## The intelligence layer

Three modes, and one rule that matters more than the rest: **the mode is
never inferred.** The gesture decides it before the request is built.

| Gesture | Mode | Budget | Temperature |
| --- | --- | --- | --- |
| Tap | `CONTEXT` | 10 words | 0.2 |
| Double tap | `GIGGLE` | 30 words | 1.0 |
| Swipe up | `INTENT` | 40 words | 0.3 |

Length is enforced twice — in the prompt *and* by `max_completion_tokens` —
because a prompt that says "be brief" is a request, while a token cap is a
guarantee. Temperature is per-mode because one global value is wrong for all
three jobs: GIGGLE at low temperature tells the same twelve lines forever,
while CONTEXT at high temperature drifts away from the line it was asked to
compress.

### Single tap is hybrid

The local `ContextRanker` picks the answer — deterministic, offline, ~0ms. The
model is then asked to **sharpen that line**, not to choose one from raw
state. That single decision prevents two failures at once:

- *Fabrication.* Given a snapshot with a null calendar field, a model will
  invent a plausible event. Given a committed local line, it can only
  compress a fact that already exists.
- *Noise.* Asked to "produce an actionable observation" from a full snapshot,
  the model narrates the least interesting true thing available — "It is
  3:14 PM in Srinagar."

The rewrite is bounded at 900ms and validated on arrival: empty, too long,
opening with filler, or echoing the mode header all get discarded. The
deterministic line is already on screen, so **the network can only improve the
card, never break it.** Same shape for GIGGLE, which is opt-in and behind the
bundled shuffle bag by default.

`stop` is `['\n']` for CONTEXT and `['\n\n']` for INTENT — stopping INTENT on a
single newline silently amputates its second sentence mid-stream.

## Tests worth writing first

The logic that is actually testable without a device, in the order it will pay
off:

- `context_ranker_test.dart` — the product's core decision, pure function
- `local_fallback_provider_test.dart` — coin/dice/maths determinism
- `expression_test.dart` — precedence, parens, divide by zero
- `puck_gesture_recognizer_test.dart` — gesture classification via
  `TestWidgetsFlutterBinding` and synthetic pointer events
- `groq_provider_test.dart` — SSE frame parsing against a fake `http.Client`
- `prompt_test.dart` — `isAcceptable` rejects filler, mode echoes and
  over-length output; `buildEnvelope` omits absent fields
