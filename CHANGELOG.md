# Changelog

All notable changes to Puck. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/), versions follow
`pubspec.yaml`, and every entry says what changed *and why* -- an entry that
only says "fixes" is an entry nobody can act on later.

## [Unreleased]

### Added

* **A string table, in two languages.** Every visible string now lives in
  `lib/src/l10n/`, with English and Spanish complete, ARB files for
  translators (`lib/l10n/`), and a generator (`tools/gen_arb.py`). A locale
  that is not shipped falls back to English *key by key*, visibly.
* **The emergency path.** Regional emergency numbers with an honest fallback
  (`emergency_numbers.dart`), a dialer handoff that never places a call
  (`tel:`/ACTION_DIAL, no permission), and a durable SOS send that survives a
  GPS fix that never arrives.
* **The privacy screen** (`/privacy`): what is sent, in plain language; what is
  never sent; attribution for Open-Meteo and Groq; one switch that stops all
  cloud features; one action that erases everything local; and a feedback mail
  that carries the real version and nothing personal.
* **Accessibility surfaces.** One labelled semantics node on the bubble with
  the three gestures a screen reader cannot express as actions, a full action
  list shown only while assistive technology is active, localized action names,
  a settings screen with 48dp targets, and reduce-motion support.
* **The shared answer service** (`worker/` + `data/llm/proxy_provider.dart`): a
  Cloudflare Worker that holds one Groq key so no phone has to, with a kill
  switch, a per-device hourly limit, a global daily ceiling, server-side
  sampling parameters and a prompt-marker check that keeps it from being a free
  general-purpose LLM. Fourteen tests run with `node --test
  worker/test/*.test.mjs` and pass. **Not deployed, and off in every build**
  unless someone compiles in `--dart-define=PUCK_PROXY_URL=...`: running it
  spends the maintainer's money (FINDINGS.md §4.1).
* **A crisis interception** (`domain/safety.dart`): first-person crisis
  phrasing is answered on the device with one fixed, localized line and never
  reaches the model.
* **Cost control for cloud answers**: a polish is skipped when the local line
  is already short, at most one per 20 seconds, and reused from a bounded cache
  for 10 minutes.
* **Tests**: 101 cases across 13 files, including the SOS failure states, the
  string-table contract, contrast arithmetic, the safety phrases, and the
  resolver's behaviour in a language it does not know.

### Changed

* **The privacy switch is real.** `cloudEnabled` is enforced in
  `GatedLlmProvider` (answers) and `ContextRepository` (weather). Before this it
  was a switch nothing read.
* **`textMuted` is `#828282`, not `#666666`.** The old value was 3.66:1 on
  black and 3.29:1 on the card; 13px captions need 4.5:1. Buttons on the
  emergency fill now draw their label in black (5.92:1, versus white's 3.55:1).
* **The SOS message and the card are written in the user's language.** The
  recipient of an SOS may not read English either.
* **Settings shows the real version** from `package_info_plus` instead of the
  hardcoded "Version 1.0".
* **The hold length is adjustable (1-3s).** The 3s default is unchanged: it is
  the constant the pocket-safety argument rests on. The control exists because
  a three-second precision hold excludes people with a tremor.

### Fixed

* **The emergency SMS read `sosMessage / sosMessageNoLocation`.** Two keys were
  asked for and never defined, and `text()` falls back to the key itself. The
  keys exist now, and a test parses the class source so a missing key is a red
  test rather than a message that arrives as gibberish.
* **The SOS countdown could end in complete silence.** The composer opened only
  when the message body existed, the body existed only once the GPS returned,
  and the countdown (3s) was shorter than the GPS timeout (8s): on a cold fix
  nothing happened -- no message, no retry, no error. The send is now owed and
  delivered when the fix lands or fails.
* **An untitled calendar event was shown as the English word "Busy"** in every
  language, because the data layer chose the word. The ranker now supplies the
  localized one.
* **A late GPS fix overwrote "no contact" with "location found"** -- true, and
  useless to someone with nobody to text.
* **Four TalkBack action labels were hardcoded English**, and were the only
  description of those actions a screen reader user got.
* **A rejected API key produced a raw English provider message on the card.**
  It has its own localized line now; every other failure gets the one honest
  offline line.
* **`dart:math` was seeded non-deterministically in tests**, error messages used
  `!` on nullable values, and `ref.onDispose` was missing on two providers.
  (Fixed in `15a35e6` and this change.)

## [1.1.0+2] — previous

The version that was in `pubspec.yaml` before this change: the four gestures,
the tap card, the joke bag, the offline resolver, the Groq SSE client, and the
first SOS sheet -- see the git history up to `2fa7254`.
