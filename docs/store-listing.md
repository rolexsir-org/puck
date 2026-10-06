# Store listing, and the answers the stores ask for

Draft copy for the Play Store and App Store listings, plus the Data Safety /
App Privacy answers that have to match the code. Written to be *true* rather
than persuasive: a listing that overpromises is the same defect as a comment
that lies, just with a bigger audience. **[needs owner input]** marks the
places where a decision, a hostname or a legal review is required before
anything is published.

The version to publish is whatever `pubspec.yaml` says; Settings shows the real
one (`package_info_plus`), so support questions can be answered without asking
the user to guess.

---

## Play Store

### App name (30 characters max)

`Puck — one button, four gestures`

### Short description (80 characters max)

English: `One button. Four gestures. No menus, no setup, works offline.`
Spanish: `Un botón. Cuatro gestos. Sin menús, sin configurar, sin conexión.`

### Full description

English:

> Puck is one button. Tap it for the one thing worth knowing right now. Double
> tap for a joke. Hold it for an emergency. Swipe up to ask anything.
>
> There is no home screen, no feed, no account and no onboarding. It works the
> moment it is installed, with no setup and no network: the tap card, the joke,
> the dice, the coin, arithmetic and the whole emergency path are all on the
> device.
>
> **It tells you the truth when it cannot help.** No spinner that will never
> finish, no invented answer. When something is unavailable, Puck says so in one
> line and points at what still works.
>
> **Nothing leaves your phone unless you ask.** No analytics, no ads, no crash
> reporting, no account. One switch stops every cloud feature; one action erases
> everything Puck has stored. The screen that lists exactly what is sent —
> and what is never sent — is one tap from the top of Settings.
>
> **Emergency, without the dangerous parts.** Hold for three seconds and the
> sheet counts down; lift your finger at any point and nothing happens. Holding
> through turns on the torch and opens a message with your location, ready to
> send — Puck never sends it for you. With nobody configured to text, it offers
> your region's emergency number, shows it in words, and opens the dialer: it
> never places a call.
>
> **For everyone, as literally as possible.** It ships in English and Spanish,
> every control is at least 48dp, everything is labelled for TalkBack, the
> palette meets WCAG AA, reduce-motion is honoured, and there is an action list
> for anyone who cannot perform a gesture — a three-second hold is a physical
> demand, and the hold length is adjustable down to one second.
>
> Free, no ads, no account. Optional: paste your own API key to make open-ended
> questions work.

Spanish: **[needs owner input: a native speaker should review this copy before
it is published, as with every other Spanish string.]**

### Screenshots (the honest script)

1. The bubble on black, resting — "One button."
2. The tap card — "Tap: the one thing worth knowing."
3. The joke card — "Double tap: a joke."
4. The SOS sheet mid-countdown with the cancel button visible — "Hold: emergency. Lift your finger and nothing happens."
5. The intent bar with a typed question — "Swipe up: ask anything."
6. The privacy screen — "Everything Puck sends, in plain words."
7. Settings with the cloud switch off — "One switch stops all of it."
8. The tap card in Spanish — this is a product that ships in two languages.

Feature graphic: the bubble and the four gesture words, on black. No phone
mock-ups, no hands, no stock photography.

### Data Safety answers

| Question | Answer | Where that comes from |
| -------- | ------ | --------------------- |
| Does your app collect or share user data? | **Yes**, but only when the user asks a question, and only as described below | §"What leaves your phone" in `docs/privacy.md` |
| Data types collected | *Personal info → Other* (the question text) and *Location → Approximate location* | `proxy_provider.dart`, `weather_service.dart` |
| Is the data shared with third parties? | Yes: Groq (answers) and Open-Meteo (weather). **[needs owner input: the shared-service hostname if it is deployed]** | `docs/privacy.md` |
| Is the data encrypted in transit? | Yes — HTTPS only, no cleartext traffic configured | Android manifest / iOS ATS |
| Can users request deletion? | Yes, in-app: Settings → Erase local data. Server side there is nothing to delete: the shared service stores expiring counters only | `settings_repository.dart`, `worker/src/index.js` |
| Is data collected for advertising or tracking? | No | There is no such SDK in `pubspec.yaml` |
| Are accounts required? | No | There is no account code |
| Data retention by the developer | None, other than automatically expiring counters at the shared service | `worker/README.md` |

Play also asks for a **privacy policy URL**: publish `docs/privacy.md` at a
stable address and use that. **[needs owner input: the address.]**

### Content rating

Puck has no user-generated content, no social features, no advertising, no
in-app purchases, and no content of its own beyond a bag of 100 dry jokes with
no profanity, no exclamation marks and no targets — see
`test/core/jokes_test.dart` for the enforced contract. It can display text
produced by a language model in response to what the user typed, which is the
one fact a reviewer should be told rather than asked about.

**[needs owner input: the questionnaire itself, and whether to disclose the
model-produced text as "user-generated content" to be safe.]**

## App Store

Same copy, plus App Privacy answers that mirror the table above (data linked to
the user: none; tracking: no). The App Store listing cannot ship until iOS
actually builds — see `FINDINGS.md` §4.3 and the README line that says so.

## What the listing must not say

* Anything about a "shared answer service" being available, until it is
  deployed and the app points at it. Today a new user gets the offline
  resolver, and the listing must not imply otherwise.
* "Works on iOS" until it does.
* "No data ever leaves your device" — false: a question is sent when you ask
  one. The true sentence is "nothing leaves your phone unless you ask".
* Anything about a specific number of languages beyond English and Spanish.
* Any claim about reaction time, reliability or "saves lives" in the emergency
  path. It opens a composer and a dialer; it does not call for help by itself,
  and the listing must not imply it does.
