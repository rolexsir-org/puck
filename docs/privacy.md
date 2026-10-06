# Puck privacy policy

**Draft, written from the code, and awaiting the repository owner's review.**
Every claim below is checkable against the source, and the file names are given
so that a reader who does not trust this document can check it. It is not legal
advice, and it must be reviewed before it is published or used as a store's
privacy-policy URL. Sections marked **[needs owner input]** cannot be written
correctly without a decision that is not an author's to make.

Last updated: the date of the commit that added this file (see `git log`).

---

## The short version

Puck has no account, no analytics, no advertising and no crash reporting. It
sends data only when you ask it a question, and only what the question needs.
There is one switch that stops all of it. One action erases everything Puck has
stored on the phone.

## What Puck stores on your phone

| Stored | Why | Where |
| ------ | --- | ----- |
| Your emergency contact number | The SOS message goes to it | Android SharedPreferences / iOS UserDefaults |
| The optional Groq API key, if you paste one | To answer questions with your own account | Platform keystore (Android Keystore / iOS Keychain), never an ordinary file |
| A random device identifier | Rate limiting, if the shared answer service is enabled | Preferences. 16 random bytes, not derived from your device, resettable from Settings |
| A joke cursor, a counter of cancelled SOS attempts, your hold-length choice | So the joke bag does not repeat, and so Settings can show what Puck has done | Preferences |
| A flag that says the one-time gesture card was dismissed | So it never appears again | Preferences |

Nothing else is stored. There is no history of your questions, no log of your
location, and no record of what Puck answered. `lib/src/data/repositories/settings_repository.dart`
is the complete list of what is kept, and the "erase everything" action in
Settings removes every row above.

## What leaves your phone, and when

Nothing leaves the phone unless you ask a question or look at the tap card, and
nothing leaves it at all if the cloud switch is off.

**1. Your question (swipe up).** The text you type or dictate is sent to the
answer provider so it can be answered. It is not stored by Puck.

**2. Your context, when you tap the bubble *and* cloud answers are on.** The
single-tap card is computed on the device first and always works; Puck then
*optionally* asks the model to sharpen the line. That request contains the
local line plus:

* the title of your next calendar event, whether it has started, and how long
  until it does (`lib/src/data/llm/prompt.dart`, `buildEnvelope`) — never the
  rest of your calendar, and never your other events;
* your battery level and whether the phone is charging;
* the current temperature and weather code, if weather was already fetched;
* your local time as a string.

**3. Your approximate position, for weather.** When the tap card needs weather,
Puck asks Open-Meteo for the forecast at your position **rounded to three
decimal places — about 100 metres**, which is as much as a forecast needs
(`lib/src/data/services/weather_service.dart`). The exact coordinates never
leave the phone for weather. They *are* included in an SOS message, because
that is the entire point of an SOS message — and that message goes to your
contact through your own SMS app, and Puck never sends it.

**4. A random identifier, for the shared answer service (if it is enabled).**
One request header, `X-Puck-Device`, carrying the random UUID described above.
It exists so one phone cannot use the whole service. It is not an account and
it is not linked to anything else. Resetting it in Settings gives the next
request a new one.

## Who receives it

| Recipient | What it receives | When | Their policy |
| --------- | ---------------- | ---- | ------------ |
| **Groq** (`api.groq.com`) | Your question, or the context envelope above | When you ask, either with your own key or through the shared service | Groq's own privacy policy |
| **Open-Meteo** (`api.open-meteo.com`) | Your position rounded to ~100 m | When the tap card needs weather | Open-Meteo's own policy; no key, no account |
| **The shared answer service** (a Cloudflare Worker, if this build points at one) | Your question or envelope, and the random identifier | Same as Groq, and it forwards to Groq | [needs owner input: hostname, operator, retention wording] |
| Your SMS app and your contact | The SOS message you chose to send | Only when you press send | Your carrier |

There is no other recipient. There is no advertising, analytics, attribution or
crash-reporting SDK in this app: it has no dependency that reports anything.
The Android build requests no permission that can be used to read contacts,
messages or files.

**Server-side retention at the shared service.** It keeps numbers, not text:
one request counter per device per hour and one per day, both expiring
automatically (one hour and two days respectively). Prompts and answers are not
logged. See `worker/src/index.js` and `worker/README.md`.

## Your controls

* **One switch stops everything.** Settings → "Let Puck answer with the
  internet". Off means no question leaves the phone, and the weather lookup
  stops too. The tap card, the joke, the dice, the maths, the time and the
  whole emergency path keep working offline. The switch is enforced in one
  place in the code (`GatedLlmProvider`), not promised in each feature.
* **One action erases everything.** Settings → "Erase local data". It removes
  every row in the table above, including the API key and the identifier.
* **Your own key.** With your own Groq key, answers come from your account and
  the shared service is not used.
* **No key at all** is a complete configuration: coin, dice, arithmetic, dates,
  the joke, the tap card and the emergency path all work with no network.

## Children

Puck is a general-purpose utility with no age gate, no account and no content
of its own. It has nothing to sell and collects nothing to sell. **[needs
owner input: the store's age-rating answers.]**

## Changes

If this policy changes, the change appears in `CHANGELOG.md` and in the diff of
this file, and the app version in Settings is the version you are running.

## Contact

`puck@rolexsir.org` — the same address the in-app feedback button uses. The
feedback mail contains the app version and the short status block shown on the
privacy screen, and nothing else; you can read it before you send it, because
Puck opens your mail app with the message written and does not send it.
