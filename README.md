# Puck

Puck is one button. Four gestures. No menus, no onboarding, no configuration. It tells you the one thing you need to know, tells you a joke, calls for help, or answers any question. It works offline. It never sends automatically.

![Puck — one button, four gestures](docs/hero.png)

Flutter · Dart 3 · Android 7+ / iOS 13+

---

## Try it

```bash
flutter pub get
flutter run
```

The app runs fully offline on first launch with no configuration. To enable open-ended answers on swipe-up, open **Settings**, paste a free key from [console.groq.com/keys](https://console.groq.com/keys), done.

A browser-runnable port of the surface lives at `preview/puck_preview.html` — open it in any browser to feel the gestures without a device.

## The four gestures

**Tap** — the one thing worth knowing, ranked by actionability: an event starting within the hour, a battery about to die, rain inside four hours, or just the time and a quiet line. The time card paints on the same frame as the touch; the snapshot only ever upgrades it.

**Double tap** — one dry line from a bag of 100. The bag is shuffled and persisted, so you see every joke before any repeat.

**Hold 3 seconds** — SOS. The sheet counts down for three more seconds; lifting your finger at any point in that countdown cancels everything (a pocket can hold a button by accident, but it can't hold it for six seconds). Holding through the end turns on the torch and opens Messages with your location pre-filled. Puck never sends anything itself.

**Swipe up** — ask anything. Coin, dice, arithmetic and dates answer instantly, offline, exactly. Everything else streams a one-sentence answer when a key is set, or one honest line when it isn't.

## Where the intelligence lives

Deliberate split. Things that must be correct or instant — arithmetic, coin flips, the time, the guaranteed tap card — are computed on device with no network. Things that must be open-ended go to one model (Groq, `gpt-oss-20b`) through a single seam: `LlmProvider` in, a stream of text out. The model can only ever *sharpen* a line the device already chose; it is never allowed to originate facts. Every output passes a client-side validator before it is allowed on screen, so a bad model day degrades to the deterministic answer, never to garbage.

## Architecture

```
lib/
├── main.dart, app.dart          entry, routes, theme application
└── src/
    ├── core/                    constants (the tuning surface), theme, format, haptics, expression evaluator
    ├── data/
    │   ├── models/              ContextSnapshot — every field nullable, every reader failure-tolerant
    │   ├── services/            battery, calendar, location, weather, torch, messaging, speech
    │   ├── repositories/        settings (secure key storage), jokes (shuffle bag), context (parallel gather)
    │   └── llm/                 Groq SSE client, hardened prompt, deterministic local resolver
    ├── domain/                  context ranker (the priority list), intent router (device vs cloud)
    └── features/
        ├── puck/                controller, custom gesture recogniser, spring physics, bubble, cards, intent bar, SOS sheet
        └── settings/            the one configuration screen
```

One custom gesture recogniser (`puck_gestureRecognizer.dart`) owns the bubble. Flutter's stock recognisers put tap, double-tap, long-press and vertical-drag in the same arena, and vertical drag wins the moment a finger travels — which kills swipe-up. One recogniser, one pointer, a small state machine classifies every press by distance, time and velocity instead.

Motion is one spring (stiffness 400, damping ratio 0.63) and one easing curve (240ms easeOutCubic). The bubble's drag is a real physics simulation — it decelerates into the edge with the velocity your finger had, which a fixed curve cannot express.

## Permissions

Requested lazily, at the moment a gesture needs them, never at launch: calendar on first tap, location on first weather check or SOS, microphone on first mic press. Deny any of them and Puck degrades — it never nags, and it never breaks. The SOS SMS is handed to the native composer unsent; that extra tap is the feature that makes a pocket-SOS recoverable.

## Verification

```bash
flutter analyze   # no issues found
flutter test      # unit + widget suites
```

The test suite locks the things a hackathon demo cannot afford to regress: the arithmetic evaluator, the SMS body format, the local resolver's exact answers ("what's 47 times 83" → `3901.`), the joke bag's contract (exactly 100, no repeats, no exclamation marks), and a widget smoke test of the launch → tap → double-tap → settings path.

## Demo video

`docs/demo.mp4` — 90 seconds, one take, no cuts, no voiceover. The script, in order: launch → tap (time card) → wait → double tap (joke) → swipe up → "flip a coin" → swipe up → "what's 47 times 83" → swipe up → "why is the sky blue" (offline line) → hold 3s → release early (auto-cancel) → hold again, let it fire.
