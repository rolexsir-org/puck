# Everyone

Puck is one button. That is only a good idea if a stranger can use it. This file
names the people "everyone" actually means and the test that proves each of them
is served. Every workstream in this change references a row here; if a change
cannot be tied to a row, it does not belong.

**How to read this.** Each row has a *specific* acceptance test, written so it can
be run by someone who did not write the code. "Works for everyone" is not a test.
Where a row cannot be verified without hardware or a human, it says so — see the
"Verified how" column, which uses the same honest vocabulary as `FINDINGS.md`:
**ran** (executed in this environment), **by construction** (provable from the
code, not executed), **needs a device** (cannot be executed here at all).

| # | Person | Acceptance test | Verified how |
| - | ------ | --------------- | ------------ |
| 1 | **Never used Puck** | Installs, launches, and reaches all four behaviours — one fact, a joke, SOS, a question — without being told what they are. The first-run card names all four; the bubble's resting ring hints that it can be held; nothing requires a manual. | By construction + widget test (`first_run_test.dart`) |
| 2 | **Non-English speaker** | Completes every flow in their language: the tap card, the joke, the SOS sheet, the settings screen, **and the SOS message body** — the recipient may not read English either. Unshipped locales fall back to English visibly, never to an empty string. | By construction + unit tests (`strings_test.dart`, `messaging_test.dart`) |
| 3 | **Screen reader user** | With TalkBack or VoiceOver on, unaided: triggers all four gestures, opens settings, completes the SOS flow, and hears every phase change announced. | By construction + widget tests (`semantics_test.dart`); **needs a device** to confirm the audible result |
| 4 | **Low vision** | Every screen is readable and unclipped at 2.0× system font size, and every text/background pair meets WCAG AA (4.5:1 for body text, 3:1 for ≥18.66px bold or ≥24px). Verified with a contrast checker, not by eye. | Ran — contrast ratios computed in `contrast_test.dart`, scale audit documented in `FINDINGS.md` |
| 5 | **Tremor, arthritis, or one hand** | Can raise SOS without holding a button for three seconds: the hold length is adjustable down to one second, and the accessible action list triggers SOS with a single confirmed tap, with a visible cancel. | By construction + widget tests; **needs a device** for the real tremor case |
| 6 | **Deaf or hard of hearing** | Nothing important is carried by sound or vibration alone. The SOS torch is visible *and* the sheet states its status in words; cancellation is visible; the answer bar announces completion textually. | By construction + widget test |
| 7 | **Low-end device (2 GB RAM, old CPU)** | Cold start under 2s, no dropped frames while dragging and snapping the bubble, steady memory across 50 gesture cycles, install under 30 MB per ABI. | **Needs a device** — the budget and the measurement method are in `README.md`; nothing here was measured on real 2 GB hardware |
| 8 | **No account, no key, no network** | On a fresh install in airplane mode with no configuration at all: tap, double-tap, hold and swipe-up each produce something honest and useful — a fact, a joke, the SOS path, and an offline line that names what still works. | By construction + unit tests (`local_resolver_test.dart`); **needs a device** for the airplane-mode run |
| 9 | **Privacy-conscious** | Can read, in plain language, exactly what leaves the phone; can switch all cloud features off with one control and keep using Puck; can erase everything Puck stored with one action. | By construction + widget tests |
| 10 | **Nobody technical at all** | Never has to paste a key, create an account, or read documentation. First launch is useful within one second with no configuration and no network. The paid-key path exists but is demoted, off by default, and irrelevant to a new user. | By construction |
| 11 | **Uses the phone one-handed, in a hurry** | Reaches every action without a menu: the bubble is the whole surface, the accessible list is one gesture away, and no flow requires two simultaneous touches or a long press with a second hand. | By construction |
| 12 | **Someone in crisis** | Asking about self-harm, medical, legal or financial emergencies does not get a confident improvised answer. It gets a short, fixed, localized line pointing at real help — never model improvisation. | By construction + unit tests (`safety_test.dart`) |
| 13 | **Someone whose phone is unusual** | No torch, no GPS, no calendar, no SMS app, no vibration motor, no speech engine, no network — every one degrades to a visible, honest sentence rather than an error, a spinner or a silent no-op. | By construction + unit tests for the pure parts; **needs a device** per capability |
| 14 | **Right-to-left speaker** | Arabic and Hebrew reading order is correct: the bubble anchors to the side the user reads toward, cards mirror, and no custom-painted ring makes a direction assumption. | By construction; **needs a device** with an RTL locale to confirm visually |

## What this file decides

Three rules fall out of the table and are binding for every workstream:

1. **Additive, skippable, invisible after first use.** A first-time user sees one
   extra quiet card (row 1) and then nothing new. Nothing in this workstream adds
   a menu, a wizard, or chrome.
2. **Degrade, never break** (rows 8, 13). Every new network path has a local
   answer behind it; every new hardware dependency has a sentence for its
   absence.
3. **Nothing leaves the phone uninvited** (row 9). New cloud code ships behind a
   control that is readable, revocable, and off by nothing — the only thing sent
   by default is the thing the user just asked for.

## What would falsify this

The rows above are claims. These are the observations that would prove them
wrong, and they should be looked for deliberately:

- A user in row 1 discovers a behaviour by accident and *cannot* discover the
  other three.
- A row 2 user's SOS message arrives in English.
- A row 3 user reaches a dead end that only a sighted tap can escape.
- A row 4 user is clipped at 1.3× — the most common real system scale.
- A row 7 device takes more than two seconds to show the bubble.
- A row 9 user cannot find what the app sends.
