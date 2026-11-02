# Voice

Puck listens, turns speech into text on the phone, and — for a fixed set of
phone commands — acts on it. This document is the design and the honest state of
the implementation: what is built, what was inspected in sherpa-onnx, what has
actually been executed, and what has only been written.

The short version: **nothing in this document has been compiled or run on a
device yet.** This checkout has no Flutter, Dart, Java or Android SDK, so
`flutter analyze`, `flutter test` and `flutter build` have not been executed, and
no model has been downloaded. The sections that claim something is verified say
exactly what was verified and by what.

## 1. The pipeline

```
 mic (16 kHz mono PCM16)
   │  record:      AudioRecorder.startStream  → Uint8List frames
   ▼
 pcm16 → Float32   (value / 32768.0)          lib/src/voice/transcriber.dart
   ▼
 VAD isolate       sherpa-onnx VoiceActivityDetector + Silero VAD
   │              512-sample windows, speech start/stop, segment end on silence
   ▼
 ASR isolate       sherpa-onnx OfflineRecognizer (Moonshine tiny / Whisper tiny)
   │              one decode per segment, `getResult(stream).text`
   ▼
 CommandRouter     CommandParser → CommandIntent  (deterministic, no model)
   │
   ├─ recognised command → CommandExecutor → platform ports → CommandNarrator
   │                                                            │
   │                                                            ├─ card on screen
   │                                                            └─ spoken answer
   └─ not a command → existing IntentRouter (LLM, unchanged) → spoken answer
```

Two isolates, not one, and both are spawned once and reused. Model loading is
the slow part (a 30 MB ONNX graph, a second or two on a mid-range phone), so it
happens when the mic is first pressed, not per utterance. `reset()` clears the
VAD's circular buffer between utterances; nothing is reloaded.

`sherpa_onnx` keeps its FFI binding state per isolate, so **each isolate calls
`initBindingsAsync()` itself**. That is stated in the package's own docs
(`flutter/sherpa_onnx/lib/sherpa_onnx.dart:41`) and is the most common way a
sherpa integration fails at the first decode.

Work stays off the UI isolate throughout: VAD, ASR and TTS each run in a worker,
and TTS synthesis uses a third isolate for the optional bundled voice.

### Why not streaming ASR

Streaming (online) recognition trades accuracy for partial results. Puck's
commands are one short sentence, and the VAD already decides when the sentence
ended — the user waits for silence + decode, typically a few hundred
milliseconds, and gets a correct transcript instead of a growing guess. Partial
text would also invite acting on a sentence that is still being spoken.
`sherpa-onnx`'s `streaming_asr` example was read and deliberately not used.

### Why VAD at all

Without it the recorder either runs to a fixed timeout (worse latency, wasted
decode) or hands the ASR model a buffer padded with room noise, which produces
hallucinated words on Moonshine and Whisper alike. Silero VAD is 643,854 bytes
and turns "when did they stop talking" into a measurement.

## 2. The sherpa-onnx reference

- Repository: <https://github.com/k2-fsa/sherpa-onnx>
- Commit cloned: `935e5ded3d949a8b557ac44ef4dad03a7d2038e7` (shallow, 2026-10-29)
- Location: `reference/sherpa-onnx/` — inside the workspace, **outside** the app
  source tree, and listed in `.gitignore`. It is not in the APK, not in the
  repository, and not committed.
- Use: the published package `sherpa_onnx: 2.0.1` from pub.dev is the dependency.
  No C++, CMake, JNI or Gradle integration was copied, and no source file from
  the reference tree was copied into `lib/` or `android/`.

### Examples actually read in this checkout

| Example | What was taken from it |
| --- | --- |
| `flutter-examples/vad-non-streaming-asr-from-microphone` | the shape of the pipeline: recorder → VAD worker → ASR worker, and the `initBindingsAsync()`-per-isolate requirement |
| `flutter-examples/vad-non-streaming-asr-from-file` | `model_config.dart` — the exact model ids, archive URLs and the per-family `OfflineRecognizerConfig` (Moonshine wants `mergedDecoder`, Whisper wants `modelType: 'whisper'` + its own tokens file) |
| `flutter-examples/streaming_asr` (read, not used) | confirmed partial-result streaming exists and why it is not the right trade here |
| `flutter-examples/tts` | `OfflineTts(OfflineTtsConfig(...))`, `generate(text:, speed:)`, `GeneratedAudio.samples` |
| `dart-api-examples/keyword-spotter` (the Flutter examples contain no KWS example) | `KeywordSpotter`, `KeywordSpotterConfig`, the `keywords.txt` file it reads, and `result.keyword` — see §5 |
| `flutter/sherpa_onnx` (the package) | the actual API surface used below, read from source rather than from a README |
| `flutter-examples/.../generate-asset-list.py`, `scripts/apk/*.sh` | how the examples provision models at build time — which is exactly what Puck does **not** do (models are runtime downloads) |

API names used in `lib/src/voice/sherpa_engine.dart` and `speech_output.dart`
were checked against the package sources at this commit, class by class:
`VoiceActivityDetector`, `VadModelConfig`, `SileroVadModelConfig`,
`VoiceActivityDetector.acceptWaveform/isDetected/isEmpty/front/pop/flush/reset`,
`SpeechSegment.samples/start`, `OfflineRecognizer`, `OfflineRecognizerConfig`,
`OfflineModelConfig`, `OfflineMoonshineModelConfig.mergedDecoder`,
`OfflineWhisperModelConfig`, `OfflineStream.acceptWaveform(samples:, sampleRate:)`,
`decode`, `getResult`, `OfflineTts`, `OfflineTtsConfig`,
`OfflineTtsVitsModelConfig(lexicon:)`, `GeneratedAudio`.

Licences:

| Component | Licence |
| --- | --- |
| sherpa-onnx (library, and the `sherpa_onnx` package) | Apache-2.0 |
| Silero VAD weights | MIT |
| Moonshine tiny | MIT (Useful Sensors) |
| Whisper tiny | MIT (OpenAI) — note the *model* is MIT; the repository licence differs |
| Piper / VITS voice `en_US-amy-low` | Piper is MIT; the voice model card states its dataset terms — **verify before redistributing the voice** (it is downloaded, never bundled) |
| `record`, `archive`, `path_provider` | MIT / BSD-style; see pub.dev |

Nothing here is GPL or otherwise incompatible with Puck's own licence, but the
Piper item is the one still worth a second look before any redistribution.

## 3. Models

Sizes measured from the publishing release on 2026-11-02 (GitHub asset byte
counts), not estimated. Nothing is bundled in the APK: a model download changes
what the app is, and has to be a choice with the size on the button.

| id | kind | size | default | licence |
| --- | --- | --- | --- | --- |
| `silero-vad` | VAD | 0.6 MB | required | MIT |
| `moonshine-tiny-en` | ASR | 29.9 MB | yes | MIT |
| `whisper-tiny-en` | ASR | 118.1 MB | no | MIT |
| `piper-amy-low` | TTS | 67.1 MB + 6.3 MB lexicon | no | Piper MIT / card |

Moonshine tiny is the default because the commands are short and English, and
29.9 MB is a download a person will accept on a phone where Whisper's 118 MB is
not. Whisper stays in the catalogue for accents and longer sentences; both
configurations were read out of the reference `model_config.dart` rather than
guessed.

Install invariants (`lib/src/voice/model_store.dart`), because a half-installed
model is worse than no model:

1. bytes go to `<id>.download.part`, never to the model directory;
2. the byte count is compared with the published size before anything else uses
   the file;
3. bzip2 blocks are CRC-checked by the decoder (the bzip2 container carries a
   CRC per block, and the decoder verifies it);
4. extraction lands in `<id>.installing`, every declared file must exist and be
   non-empty, and only then is the directory renamed into place;
5. cancellation stops at the next chunk and deletes the partial files;
6. download and extraction run off the UI isolate (`Isolate.run`);
7. the Silero graph is a single `.onnx` file, not a tarball — it is downloaded
   directly (`extraFiles`), never fed to the bzip2 decoder.

No silent downloads: `VoiceModelStore.install` is only reachable from a pressed
row on **Settings → Voice models**, with current storage and the download size
shown per model.

## 4. Commands

The parser is hand-written and deterministic (`lib/src/commands/`), and no
language model is involved in deciding what a phone command means. The LLM is
still there for questions; it never sees a sentence and then changes the
volume.

Order matters: `cancel → help → consequential → mute → setVolume →
adjustVolume → flashlight → openApp → battery → clock → date → timer → alarm →
convert → calculate`. `null` from the parser is a real answer: it means "not one
of mine", and the sentence goes to the answer path.

| What you can say | What happens | Android API / permission |
| --- | --- | --- |
| "volume up", "louder", "volume down two steps" | media stream adjusted, capped at 10 steps | `AudioManager.setStreamVolume`, no permission |
| "set volume to 40", "volume 40 percent", "volume max" | percentage of the stream's own maximum; the level is read back and reported | `AudioManager`, no permission |
| "mute", "unmute", "sound on" | stream muted / restored | `AudioManager.adjustStreamVolume(…, FLAG_SHOW_UI?)` — flags `0`, no beep |
| "torch on", "turn the flashlight off" | torch, confirmed by reading the plugin's state back | `torch_light` plugin, camera feature; no runtime permission on the devices Puck targets |
| "open calculator", "open the metro app" | exact → prefix → contains match over launcher labels, ties to the shorter label | `queryIntentActivities` + `<queries>` in the manifest, `startActivity` |
| "battery", "how much charge" | the same cached `battery_plus` read the tap card uses | `BatteryManager`, no permission |
| "what time is it", "what's the date" | local clock | — |
| "what's 15% of 240", "5 km in miles" | `expression.dart` / `units.dart` | — |
| "set a timer for 10 minutes" | system timer | `AlarmClock.ACTION_SET_TIMER`, no permission |
| "set an alarm for seven" | system alarm; a bare hour means the nearer half of the day | `AlarmClock.ACTION_SET_ALARM`; with `SET_ALARM` granted, `EXTRA_SKIP_UI`; without it the clock app asks for confirmation (deliberate) |

Refused by design — Puck narrates the refusal, it does not attempt these from
voice: sending a message, placing a call, deleting data, sharing location. The
parser recognises them so the refusal is explicit rather than a mystery, and
nothing in the command layer can reach `SmsManager`, `ACTION_CALL` or the
location permission.

Failure is data, not a sentence: the executor returns `VolumeUnavailable`,
`TorchUnavailable`, `AppNotFound`, `AppLaunchFailed`, `TimerUnavailable`,
`AlarmUnavailable`, `BatteryUnavailable`, `CommandFailed`. The narrator turns
those into one line on the card and the same line spoken. There is no code path
that reports success without reading the platform's answer back.

Duplicate protection: `CommandRouter` drops an identical normalised utterance
inside a 1500 ms window, and refuses to start a second execution while one is
running. Both exist because a voice session can legitimately deliver the same
final transcript twice (a VAD segment that ended on silence, plus a stop button
that closed the same capture) — and a doubled "torch on" is a torch off.

## 5. Wake word

**Not implemented, and not configurable.** Tap the mic.

What the reference shows (`dart-api-examples/keyword-spotter/bin/zipformer-transducer.dart`):
`KeywordSpotter` takes a `KeywordSpotterConfig(model: OnlineModelConfig(transducer: …),
keywordsFile: …)`, streams audio, and reports matches through `result.keyword`.
The keyword list is a plain text file of BPE-tokenised phrases, one per line,
built from the model's own `tokens.txt`; a phrase the model's token set cannot
spell is not spot-able. Changing the wake phrase therefore is not a string in
settings — it is a trained acoustic model plus an encoding step.

The example model, `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`
(17.6 MB, recorded in `voice_model.dart` but not in the catalogue), is a
transducer trained on GigaSpeech. Nothing in this checkout has been trained or
tested with it, so claiming "say anything you like" would be false.

The assistant *name* in settings is honoured differently and honestly: it is the
name accepted as a phrase prefix ("Puck, torch on" / "Jarvis, torch on"), which
is what `CommandParser.normalize` strips. That works in foreground,
press-to-talk flow. It is not a wake word.

Enabling a real wake word later needs, in this order: a foreground service with
`FOREGROUND_SERVICE_MICROPHONE`, a persistent notification, a KWS model shipped
or downloaded with its licence verified, a battery measurement over a real day,
and a user switch that is off by default. The settings screen says this in one
line rather than offering a toggle that does nothing.

## 6. Permissions, lifecycle, cleanup

- `RECORD_AUDIO` is requested by the `record` plugin at `hasPermission()`.
  Denied or revoked → `VoiceAvailability.permissionDenied` → the card says so.
  **There is no fallback to the network recogniser on denial**: falling back to
  a cloud path after a local permission refusal would be exactly the behaviour
  people do not expect from a privacy-shaped app.
- `MODIFY_AUDIO_SETTINGS` for stream volume. `SET_ALARM` (normal permission,
  granted at install) only to skip the clock app's confirmation dialog.
- `<queries>` entries for launcher apps, `SET_ALARM`, `SET_TIMER` and
  `TTS_SERVICE`, so Android 11+ visibility rules do not silently make the
  command layer blind.
- One session at a time, enforced in `VoiceSessionController`: a second press
  returns `busy` instead of opening a second recorder.
- Every session ends: a 15 s maximum utterance and a 12 s transcript timeout, so
  a stuck native call surfaces as `timeout` rather than a spinner forever.
- Cancel drops the utterance and ignores a late transcript.
- `onDestroy` in `MainActivity` disposes the platform channel's `TextToSpeech`
  and stops any `AudioTrack`; the VAD and ASR isolates are killed when the
  engine is disposed, and the `record` recorder is disposed with the transcriber.
- A call arriving mid-utterance stops capture (Android takes the mic); the
  session then times out with `timeout`, which is reported, not hidden.

## 7. Speech output

Android's own `TextToSpeech` by default: already installed, offline for the
installed languages on most phones, and better sounding than a 67 MB VITS model.
The optional `piper-amy-low` voice is used when it has been downloaded, and the
router falls back to the system engine if synthesis refuses. Answers are spoken
only when **Speak answers** is on, and closing the answer card stops the audio.

## 8. Verification status

Executed in this workspace:

| Check | Result |
| --- | --- |
| `python3 tools/gen_arb.py` | 226 keys in `app_en.arb`, 226 in `app_es.arb` |
| `python3 tools/check_regexes.py` | 129 regex literals, 0 suspicious, 1 not machine-checkable (`local_fallback_provider.dart:317`, pre-existing, uses `\p{...}`) |
| model release asset sizes | read from the GitHub release API |
| sherpa-onnx API names | checked against the package source at the cloned commit |

**Not executed — no toolchain in this environment:**

- `flutter pub get` (the lock file has not been updated with the four new
  dependencies)
- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`
- `flutter build apk` / `flutter build appbundle`
- any download of a real model, and therefore any actual recognition
- anything on a physical device

Consequently: no APK or AAB exists, no latency was measured, no battery was
measured, and no phrase in §4 has been recognised by a real microphone.

Tests written, **not run**:

| File | What it pins down |
| --- | --- |
| `test/voice/command_parser_test.dart` | the phrases in §4, normalisation, and the `null` answers |
| `test/commands/command_executor_test.dart` | every outcome against fake ports: refusals, unknown levels, throws, alarm arithmetic |
| `test/commands/command_router_test.dart` | no LLM for commands, duplicate window, one execution at a time |
| `test/voice/voice_session_test.dart` | one session at a time, permission denial, timeouts, cancel, double delivery |
| `test/voice/pcm16_test.dart` | sample scale, endianness, odd-length buffers |
| `test/voice/model_store_test.dart` | install invariants against a real temp dir and a real `.tar.bz2` (embedded, built offline) |

## 9. Device checklist

Run each of these on a real phone before believing this feature works.

1. Fresh install → Settings → Voice models → download Silero VAD (0.6 MB) and
   Moonshine tiny (29.9 MB). Watch the progress and confirm the sizes.
2. Airplane mode on. Tap the mic, say "torch on". Expect the card and, if
   enabled, the spoken confirmation — and a lit torch. Repeat "torch off".
3. "Volume up" three times; confirm the media level rises and the reported
   number matches the system slider. "Set volume to 40" and check the slider.
4. "Set a timer for one minute" → the system timer starts; wait for it.
5. "Set an alarm for seven" → the clock app either sets 07:00/19:00 (the nearer)
   or asks to confirm.
6. "Open calculator" → the calculator opens. "Open metro" → "I could not find
   an app called metro", not a crash.
7. "What's my battery" → the same percentage the tap card shows.
8. "What's 15% of 240", "5 kilometres in miles", "what time is it".
9. "Text mom I'm late" → refused, explicitly, with nothing sent.
10. Deny the microphone permission → the card says the mic is blocked.
    Re-grant in system settings, press again, and confirm it works without an
    app restart.
11. Kill and reopen the app mid-download → the model is not listed as installed
    and the download restarts cleanly.
12. Press the mic twice quickly → one session, no second recorder.
13. Press the mic, say nothing → a timeout, not a spinner.
14. Start an utterance, then take a phone call → the session ends and the app
    recovers on return.
15. Rotate the device while the card is showing.
16. Turn on Speak answers, ask a question, then dismiss the card mid-answer →
    audio stops.

## 10. Known limitations

- No wake word (§5). Foreground, press-to-talk only.
- English only: both ASR models are English, and so is every command phrase.
- The offline engine has no partial results — the card shows the transcript only
  once the decode finishes.
- `sherpa_onnx` adds a prebuilt native library per ABI. `flutter build apk`
  without `--split-per-abi` produces one APK carrying all of them; Puck's build
  already splits.
- The optional Piper voice is 67 MB of download for a worse-sounding voice than
  the phone's own engine; it exists for phones that have none.
- Whether a given phone reports stream mute state varies; when it does not, the
  narrator confirms the direction rather than a number.
