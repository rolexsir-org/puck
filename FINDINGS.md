# Findings

What was built, what was proven, what was only reasoned about, and what the
owner of this repository has to decide. Written to be read by someone who has
to *act* on it: every claim below is either a command with its output, or it is
labelled as reasoning.

The one rule for this whole document: **do not claim a fix works if you did not
run it.** Where that rule bites, it says so in bold.

---

## 1. The definition of done, honestly

The release gate for this work is:

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze          # No issues found!
flutter test             # green, materially more tests
flutter build apk --debug
flutter build appbundle --release
```

**None of the six commands can run in the environment this change was authored
in, and therefore none of them were run.** There is no Flutter or Dart SDK on
the machine, and none can be obtained: `pub.dev`, `dl.google.com` and
`storage.googleapis.com` are all unreachable from the sandbox, and no npm, PyPI
or GitHub-release route publishes a Linux Flutter/Dart toolchain. There is also
no `flutter` on `PATH`:

```
$ which flutter dart
(no output, exit status 1)
```

So: **no output from those six commands is pasted anywhere in this repository,
because pasting fabricated output is the one thing worse than pasting none.**
Everything below in §2 is what *was* run.

### What actually was run

| Command | Output | What it proves |
| ------- | ------ | -------------- |
| `node /tmp/tscheck/check.js /home/user/puck` | `59 dart files parsed, 0 with syntax errors` | Every Dart file parses. Catches syntax errors, stray quotes, unbalanced braces. It is **not** an analyzer: it says nothing about types, imports or lints. |
| `python3 tools/gen_arb.py` | `lib/l10n/app_en.arb: 152 keys` / `lib/l10n/app_es.arb: 152 keys` | The ARB files the translator sees are regenerated from the Dart maps, and both locales are complete (the script refuses to write a locale with missing or extra keys). |
| ARB ↔ map comparison, both directions | `en 152 / es 152, missing [], extra []` | The same thing, checked independently of the generator. |
| Key-reference scan (`text('…')` / `format('…')` in `puck_strings.dart` vs the map) | `referenced 150, missing []` | Every key the code asks for exists. **This found a real bug** (§3.1). |
| The safety phrase list, ported to Python and run against 18 crisis phrases + 13 ordinary queries | `patterns found: 53`, `unmatched crisis phrases: []`, `false positives: []` | The phrase list in `PuckSafety` matches what it says it matches and nothing else among ordinary queries. Python's regex engine and Dart's agree on this subset. |
| WCAG contrast arithmetic, in Python, then asserted in `test/core/contrast_math_test.dart` | see §3.2 | The palette ratios in the code comment are the actual ratios. |
| `node --test worker/test/*.test.mjs` | `tests 14 / pass 14 / fail 0` | **The shared answer service's rules, executed.** Kill switch, per-device hourly limit, global daily ceiling, request-shape validation, refusal to forward a non-Puck prompt, no upstream-body leakage, and "the only keys written are counters". This is the one part of the tree where "it passes" is an honest sentence. |
| `grep`/`sed` over the tree | various | The contradictions in §3. |
| `git log`, `git status` | 5 commits, clean tree | The work is committed in area-scoped commits. |

The tree-sitter gate is a real parser (web-tree-sitter + the Dart grammar), not
a regex pass, and it was re-run after every edit in this session. It has already
earned its place: it caught a truncated `RegExp` string and a `library;`
directive that the grammar in this repo's CI would reject.

### What was *not* run, and what that means

* **`flutter analyze` — not run.** Type errors, unresolved imports, and every
  lint in the strict `analysis_options.yaml` are unverified. I hand-checked the
  things the lints care about in the files I touched (trailing commas, package
  imports and their ordering, `unawaited`, `prefer_final_locals`, unused
  imports), and I fixed what I found, but **hand-checking is not analyzing.**
* **`flutter test` — not run.** 101 test cases across 13 files exist. Several
  are new this session and are the only regression protection for the fixes in
  §3. **They have never executed.** Expect to have to fix some of them on first
  run — a fake that does not quite satisfy an interface, or a `pump` duration
  that needs adjusting. Nothing in this document claims a test passes.
* **`dart format` — not run.** `dart format --set-exit-if-changed .` **will
  fail**: 42 lines in `lib/` and `test/` exceed 80 columns, most of them
  pre-existing (long string literals in `prompt.dart` and `format_test.dart`,
  the `clamp` expressions in `puck_controller.dart`). Some are string literals
  the formatter cannot split; others it will reflow. Run `dart format .` once
  and commit the result as a mechanical commit before wiring CI to
  `--set-exit-if-changed`, or the first CI run will be red for a reason that
  looks like a style argument.
* **`flutter build apk --debug` / `appbundle --release` — not run.** No SDK, no
  Android SDK, no keystore. `COMPILE_NOTES.md` records the two compile passes
  that *were* possible earlier (a Gradle configuration that fits in 2 GB), and
  that the release keystore does not exist yet. The app has never been built in
  this environment, so **no claim is made that it compiles**, let alone runs.
* **TalkBack, VoiceOver, dynamic type, a real 2 GB device, airplane mode, a
  phone with no SIM — not run.** There is no device and no emulator. See §5.

---

## 2. Dependency-budget reversal (and what was deliberately *not* added)

The original budget banned `intl` and `flutter_localizations` to keep the app
thin and English-only. That decision was wrong, and the reversal is recorded in
`pubspec.yaml` and here.

**Added:**

| Package | Why | Size | Alternative considered |
| ------- | --- | ---- | ---------------------- |
| `flutter_localizations` (SDK) | Localizes the framework's own strings (text selection menus, the `Switch` announcement, "Back" semantics) and is what makes the locale's text direction flow into the tree. Without it, an Arabic user gets an English framework and a hardcoded LTR. | SDK | Hand-writing delegates for every framework string. Rejected: unbounded maintenance for a worse result. |
| `intl` (`any`) | `DateFormat`/`NumberFormat`: a 24-hour clock where that is the norm, locale month and day names, the region's date order. `PuckFormat` (hand-rolled English) stays as the English path so the tested path and the shipped path are the same code. `any` on purpose: `flutter_localizations` pins an exact version and a range here is the classic version-solving failure. | pure Dart, ~200 KB before tree-shaking | Hand-rolled tables for 12-hour/24-hour, month names, date order, RTL digits. Rejected: that *is* `intl`, written badly. |
| `package_info_plus` | The settings screen and the feedback mail must state the real version. The app previously displayed the hardcoded string "Version 1.0" while `pubspec.yaml` said `1.1.0+2`, so every bug report would have carried a wrong version. | tiny plugin | Reading `pubspec.yaml` at build time via `--dart-define`. Rejected: it puts the version in two places, which is the bug being fixed. |

**Not added, deliberately:**

* **No accessibility/semantics helper package.** The budget allowed one. It was
  not needed: `Semantics`, `MergeSemantics`, `ExcludeSemantics`,
  `CustomSemanticsAction`, `SemanticsService.announce` and
  `MediaQuery.disableAnimations` are all in the framework, and the two
  third-party candidates (`flutter_semantics`-style wrappers and
  `announce`-style helpers) add a dependency to save a handful of lines. The
  budget stays unspent, which is the best outcome for a budget.
* **No state-management codegen, fonts, icon packs, analytics or crash
  reporting.** Unchanged from the original ban.

---

## 3. Contradictions found between the documentation and the code

Each of these was a place where a comment, a README line or a doc reference
said something the code did not do. The failure mode is not "the docs are
stale": it is that a reader trusts the sentence and stops looking.

### 3.1 The emergency SMS would have gone out reading `sosMessage`

`MessagingService.buildSosBody()` asked the string table for
`strings.sosMessage` and `strings.sosMessageNoLocation`. Neither key existed in
the map, and `PuckStrings.text()` falls back to the *key itself* when a lookup
fails. The most important message in the app -- the one that leaves the phone
during an emergency -- would have read:

```
sosMessage
sosMessageNoLocation
3:14 PM · Thu Jan 15
```

Found by the key-reference scan in §1, not by the analyzer, because a missing
string key is not a compile error in a map-based string table. Fixed by adding
both keys in both languages, and **made impossible to repeat** by
`test/core/strings_test.dart`, which parses the class source and fails if any
`text('…')` key is missing from the map.

This is the strongest argument in the whole change for the ARB parity test
existing: an ARB-vs-map comparison cannot catch it, because a key missing from
the map is missing from the ARB file too, and the two agree.

### 3.2 The palette failed WCAG AA while the comment implied it was fine

`textMuted` was `#666666` -- **3.66:1** on black and **3.29:1** on the card.
It is used for 13px captions and provenance labels, where AA requires 4.5:1. So
every quiet label in the app was below the floor while the design notes implied
the palette was the carefully chosen, final answer. Now `#828282`
(**5.46:1** / **4.91:1**), which is still visibly the quietest text. Related:
white on `emergency` red is **3.55:1** and fails AA at 17px, so buttons with
that fill draw their label in black (**5.92:1**). The ratios now live in the
palette doc comment *and* in `test/core/contrast_math_test.dart`, so the
comment and the code cannot drift apart again.

### 3.3 An English word chosen in a layer that has no language

`CalendarService` replaced an untitled calendar event with the literal string
`'Busy'`. That string then travelled into `ContextRanker` and onto the card, so
a Spanish user with an untitled appointment got an English word in a Spanish
sentence. The substitution now happens in the ranker, which is handed the
user's language (`strings.busyLabel`).

### 3.4 The privacy switch was not connected to anything

The privacy screen said "Off means no question, and nothing else, ever leaves
your phone". Nothing read `settings.cloudEnabled`: the router always used the
Groq provider and every tap fetched weather from Open-Meteo. The promise is now
enforced at the seams -- `GatedLlmProvider` (cloud answers) and
`ContextRepository` (weather) -- which is the only way that promise stays true
when a feature is added later.

### 3.5 Four accessibility labels were hardcoded English

`CustomSemanticsAction(label: 'Joke' / 'Ask a question' / 'Emergency' / 'Show
all actions')` are read aloud. In a Spanish UI they were the *only* description
of those actions. Now localized (`strings.actionJoke`, `actionAsk`, `actionSos`,
`actionsOpen`).

### 3.6 A doc reference to a class that did not exist

`puck_strings.dart` said the crisis line "is never improvised by the model --
see `PuckSafety`". There was no `PuckSafety`, no crisis interception, and no
crisis rule in the prompt: a user typing "I want to kill myself" was sent to a
20B-parameter model. `lib/src/domain/safety.dart` now exists (§4.4), the
reference is real, and `safety_test.dart` proves the question never leaves the
phone. **The line is a fixed, localized sentence, and it deliberately names no
hotline** -- naming one is a decision for the owner (§4.4).

### 3.7 The ARB files were truncated, one string at a time

The first ARB generation used a line-based extractor, and Dart values are
routinely written as adjacent string literals across lines. The result: 22
English and 20 Spanish strings in the translator-facing files were cut at the
first line -- e.g. `holdNote` ended at "…Shorten it only ". The generator is now
a real parser (`tools/gen_arb.py`) and refuses to write a locale whose keys do
not match English exactly. Nothing had shipped to a translator yet; had it,
they would have translated half-sentences.

### 3.8 README claims that outrun the code

* **"Android 7+ / iOS 13+"** — the repository contains a partial `ios/` directory
  and no iOS build has ever been produced (it is impossible on this Linux
  machine: no Xcode). The README now says so instead of implying parity. Whether
  iOS is a real target is a decision for the owner (§4.3).
* **"Every output passes a client-side validator"** — this became true in
  `15a35e6` for the streaming INTENT path; the README sentence now names where
  the validator is (`PuckPrompt.isAcceptable` plus the streaming guard) rather
  than asserting a property of "everything".
* **"Version 1.0"** — see §2, `package_info_plus`.
* The architecture section was missing `l10n/`, `privacy/`, `emergency_numbers`,
  `feedback_service`, `gated_provider`, `motion`, `safety` and `tools/`; it now
  lists them.

### 3.9 The controller's locale was never set

The controller owns the SOS status lines and the emergency message body. The
only place with a `Localizations` scope is `PuckHome.build`; nothing called
`controller.setLocale(...)`. It does now, on every build, alongside
`setReducedMotion(...)`.

---

## 4. Decisions that are not mine to make

### 4.1 Running the shared answer proxy, and its ceiling

**Written, tested, and switched off.** The code exists on both sides:

* `worker/` — a Cloudflare Worker that holds the Groq key as a secret. It
  validates the request shape, requires Puck's prompt marker (so it is not a
  free general-purpose LLM), sets the sampling parameters itself (so a modified
  app cannot buy a longer answer), enforces a per-device hourly limit and a
  global daily ceiling, has a one-variable kill switch, and stores nothing but
  counters. `worker/test/handler.test.mjs` runs with `node --test` and **14 of
  14 pass — actually executed** (§1).
* `lib/src/data/llm/proxy_provider.dart` — the client half, behind the
  unchanged `LlmProvider.complete`. The URL comes from
  `--dart-define=PUCK_PROXY_URL=...`; with no define (the default build)
  `isConfigured` is false and the app sends nothing. The device UUID from
  settings is the only identity it sends, and there is no key anywhere in the
  repository.
* `providers.dart` picks the path: **a key the user pasted wins over the shared
  service** (the privacy screen promises exactly that, and their key is their
  bill, not the project's), otherwise the shared service when configured,
  otherwise the offline resolver.

**Not switched on.** Nobody has deployed the Worker and no build defines the
URL, because deploying it spends the owner's money and there is no Cloudflare
account (or permission) here. The recommendation is that this is the right
shape — it keeps the key off every phone, and it is the only design in which
"ask anything" works on a fresh install with no setup, which is the product's
first principle and the one thing a new user still cannot get today.

**Decide:** (a) deploy it, or delete it and keep the pasted-key path as the
only cloud route; (b) the global daily ceiling (`DAILY_CEILING`, default
20000 requests/day in `wrangler.toml`); (c) the per-device limit
(`DEVICE_HOURLY_LIMIT`, default 60 — a guess that fits one person with a
habit); (d) what happens at 50/90/100% of the ceiling. The plan assumes
degrade to the offline resolver with one honest line and never a paywall in
the middle of a question after someone has typed it; `worker/README.md`
records that response.

### 4.2 Which languages ship next

**English and Spanish ship, complete.** Two languages done properly beat twelve
done badly, and Spanish is the highest-value single target for a small app
(Spain + Latin America, ~500M speakers) that also exercises gendered word order,
a 24-hour clock and a different date order. Arabic, Hindi, Portuguese, French,
German and Indonesian are all *translation-only* follow-ups: the RTL mirroring
(`AlignmentDirectional`, `EdgeInsetsDirectional`) is already in the tree, the
resolver refuses to match English keywords in a non-English UI (an unanswered
question rather than a wrong answer), and adding a language is one map plus one
ARB file. Machine translation is not used for any shipped string.

**Decide:** the order, and whether any language should be a community
contribution with a named maintainer (recommended, given that a bad translation
of an emergency screen is worse than English).

### 4.3 iOS: build it or drop the claim

The README said "iOS 13+" and the repository cannot build iOS. Either iOS
becomes a real target with a real build (needs a Mac, Xcode, a signing identity,
and someone to test it) or the README drops the claim and the App Store
workstream is closed honestly. This cannot be decided from Linux, and shipping
an iOS claim that has never been compiled is exactly the kind of confident
untruth the rest of this work removed.

### 4.4 The assistant safety boundary

Implemented narrowly: a fixed, localized line for first-person, immediate
crisis phrasing, decided **on the device, before the network**, in both shipped
languages, with the phrases checked regardless of the UI locale (someone typing
Spanish into an English phone is ordinary, and a missed crisis costs more than
a false positive). See `lib/src/domain/safety.dart` and `test/core/safety_test.dart`.

**Not decided here, and needs the owner (with a clinician or a lawyer):**
where the boundary actually sits. Specifically: (a) whether the app should name
a crisis line, and if so, whose per-region, kept-current list it may legally
and safely rely on -- today it deliberately names none and points at the
emergency number instead; (b) whether medical *emergencies* ("chest pain", "I
can't breathe") belong in the same list as self-harm (they are in it now);
(c) what the fixed line must say in jurisdictions with mandatory-reporting
nuances; (d) whether any question about self-harm that is *not* first-person
("how do crisis lines work?") should also be intercepted -- today it is not.
The phrase list is deliberately conservative and will miss subtle phrasing.
**It is a seatbelt, not a safety system, and the code says so.**

### 4.5 The joke bag

The 100 jokes are English wordplay. A non-English UI now gets one honest
sentence (`jokeFallback`: "The jokes only work in English so far. The button
does not.") instead of English puns the user cannot read. **Decide:** whether
that is acceptable long-term, or whether each language needs its own bag of
100 lines written by a human (recommended over machine translation, which
would produce 100 lines that are funny in neither language). Until then the
double-tap still does something, and the settings screen is not a lie.

---

## 5. Everything that cannot be verified without hardware or humans

**Please do not read any of this as "done".** Each line names a claim and the
observation that would settle it.

| Claim | Status | Settled by |
| ----- | ------ | ---------- |
| The app compiles and runs | **unverified** -- no SDK, never built | `flutter pub get && flutter analyze && flutter build apk --debug` |
| The 101 test cases pass | **unverified** -- never executed | `flutter test` |
| Code is `dart format` clean | **known false** -- 42 lines over 80 columns | `dart format .` then a mechanical commit |
| Four gestures work with TalkBack, unaided, at 2.0× type | **by construction only** | A person with a device, screen reader on, text scale 2.0 |
| Nothing is clipped at 2.0× scale | **by construction only** | Screenshots at 1.0/1.3/1.6/2.0 on 320×568, 412×915, 600×960 |
| The SOS path works with no SIM / airplane mode / GPS off | **unit-tested for the Dart halves**, not on a modem | A real phone in airplane mode |
| Cold start under 2 s, no dropped frames, steady memory over 50 cycles | **unmeasured** | A 2 GB device with a profiler |
| The RTL mirroring is correct | **by construction only** | A device with an Arabic or Hebrew locale |
| The SMS composer opens pre-filled on every OEM | **unverified** -- `sms:` URI handling differs per vendor | 3-5 real phones from different OEMs |
| "No contact" flows are understood by a stranger | **unverified** | Five first-time users (§6) |
| The Spanish reads naturally to a native speaker | **unverified** -- written by a non-native | A native speaker's review, and one who speaks a Latin American variety |

---

## 6. Test with real humans

Five first-time users. Not colleagues, not developers, not people who have seen
this repository. Watch their hands, not their words -- what people *say* about
an app is a courtesy, and what they *do* is data.

Setup for each: a phone with Puck installed, no explanation, no demo, the
screen recording on. Start the clock.

The three questions, asked in this order, and nothing else:

1. **"What does this do?"** (after 30 seconds, without touching it) -- tests
   whether the bubble's resting state communicates anything at all, and whether
   the ring reads as "hold me".
2. **"Show me how you'd get it to tell you something."** -- tests
   discoverability of tap and swipe-up. If they cannot find the swipe, the
   swipe is the problem, not the user. Then: **"and the joke?"** and **"and the
   emergency, if something happened right now?"** Watch how long each takes, and
   whether they look for a menu (they will, if the gestures failed).
3. **"What would you expect to leave your phone, and where would you check?"**
   -- tests the trust story. Then open the privacy screen and ask them to turn
   answers off, and back on. If they cannot find it in ten seconds, the switch
   is in the wrong place.

What to record for each person, per gesture: found it (y/n), how long, whether
it was found by accident, and whether anything was misunderstood afterwards.
Two people failing the same gesture is a design failure, not a sample of two
clumsy people. Two people *succeeding* tells you nothing -- the fifth person is
the one who finds the thing that breaks it.

Also worth one session each, if the people exist: someone who uses a screen
reader daily (gestures + SOS, unaided), and someone over 70 with no smartphone
habit (tap and hold only).

---

## 7. Where the workstreams actually stand

| # | Workstream | State |
| - | ---------- | ----- |
| 0 | `EVERYONE.md` | **Done.** 14 rows, each with a test and an honest verification column. |
| 1 | Zero-setup intelligence | **Code complete, switched off.** The Worker, its 14 executed tests, the client provider, the device UUID, the ceilings, the kill switch and the client-side cost policy are all in the tree; the URL is not compiled in and nothing is deployed, because that is the owner's cost decision -- §4.1. The direct-key path still works and is still off by default. |
| 2 | Emergency path | **Done in the code.** Durable send, dialer (never a call, no permission), regional number with an honest fallback, accessible SOS surface, tests for the failure states. Not run on a device. |
| 3 | Discoverability | **Done in the code.** One-time gesture card after the first served tap; the hold ring that disappears once the hold has been found; a full action list for assistive technology; no tutorial, no onboarding. |
| 4 | Accessibility | **Done in the code** except the parts that need a device: semantics on everything, 48dp targets, dynamic-type audit documented but unmeasured, contrast fixed and tested, reduce-motion honoured, nothing carried by colour or vibration alone. |
| 5 | Localization | **Done for en + es.** The string table, the ARB files, the parity test, RTL-ready layout, locale-aware clock/date/countdown, localized resolver patterns with honest fallthrough. Next languages: §4.2. |
| 6 | Any device | **Not done.** No device, no profiler. The plans (2 GB budget, layout matrix, per-ABI size) are described, nothing is measured. |
| 7 | Trust | **Done in the code** -- the privacy screen, the cloud switch (now real), one-action erase, diagnostics with no personal data, feedback with the real version, attribution, the crisis line, the fixed offline line. The store-facing half is drafted: `docs/privacy.md` (written from the code, with the file names that back each claim, marked for review) and `docs/store-listing.md` (listing copy plus the Data Safety answers). Both need the owner's decisions before publication, and the privacy policy needs a stable URL. |
| 8 | Distribution | **Drafted, not done.** Listing copy, screenshots script and Data Safety answers are in `docs/store-listing.md`; the version now comes from the app rather than a hardcoded string. Still missing: a keystore and a signed build (never attempted here), CI (see below), localized metadata, the feature graphic, and the staged rollout. |
| 9 | Phase 1 carry-overs | **Done** in `15a35e6` and this change. |

### The two documents that need a decision before they are published

`docs/privacy.md` and `docs/store-listing.md` are written to match the code, and
both contain `[needs owner input]` markers where matching the code is not
enough: the shared service's hostname, a stable privacy-policy URL, the Play
content-rating questionnaire, and a native speaker's review of the Spanish
listing copy. Neither is published anywhere.

### CI

`.github/workflows/ci.yml` **cannot be pushed from this environment**: the
GitHub App token available here lacks the `workflows` permission, and every
attempt is rejected with *"refusing to allow a GitHub App to create or update
workflow files without `workflows` permission"*. The file is not in the tree
(adding it would make every subsequent push to the branch fail). It has to be
added by the repository owner; `.github/workflows/` is the only thing that has
to be, and the checks it should run are exactly the six commands in §1.
