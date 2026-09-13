import 'package:puck/src/core/format.dart';
import 'package:puck/src/data/models/context.dart';

/// The things Puck asks a model to do.
///
/// The mode is never inferred -- it is decided by the gesture before the
/// request is built (tap = context, double-tap = giggle, swipe-up = intent)
/// and injected into the prompt. Asking a model to classify its own mode
/// costs accuracy on every call and lets a swipe-up query drift into GIGGLE.
///
/// EMERGENCY is deliberately absent from this enum. The long press is served
/// locally: an SOS must be byte-identical every time, must not wait on a
/// network round trip, and must not be improvised by a language model. See
/// `emergencyOutput()` in puck-universal and `sos_sheet.dart` in this app --
/// neither one asks a model for anything.
enum PuckMode { giggle, context, intent }

/// Everything the model needs, assembled once per request.
class LlmRequest {
  const LlmRequest({
    required this.mode,
    this.query = '',
    this.contextEnvelope,
    this.recentJokes = const <String>[],
  });

  final PuckMode mode;

  /// The user's text. Empty for GIGGLE (there is nothing to answer).
  final String query;

  /// Serialised device state. Required for CONTEXT, ignored otherwise.
  final String? contextEnvelope;

  /// Lines already shown, so GIGGLE does not converge on its own favourites.
  final List<String> recentJokes;
}

/// The hardened system prompt.
///
/// Every block here exists because the obvious version failed in a specific
/// way. The comments record the failure, not just the rule.
abstract final class PuckPrompt {
  // -- Budgets --------------------------------------------------------------

  /// Output caps, enforced at the API as well as in the prompt. A prompt that
  /// says "be brief" is a request; `max_completion_tokens` is a guarantee.
  /// Derived from the word limit rather than hand-tuned per mode, so the
  /// token cap and the word clamp can never disagree. A model allowed 80
  /// tokens into a 15-word budget spends latency writing text we will throw
  /// away, then gets rejected by [isAcceptable] for its trouble.
  static int maxTokensFor(PuckMode mode) => 16 + (wordLimitFor(mode) * 1.6).round();

  /// Stop sequences.
  ///
  /// Note the asymmetry: CONTEXT and GIGGLE stop at the first newline because
  /// they are single-line outputs. INTENT is allowed two sentences, so it
  /// stops on a *blank* line -- stopping on '\n' would silently amputate the
  /// second sentence mid-stream.
  static List<String> stopFor(PuckMode mode) => switch (mode) {
        PuckMode.context => <String>['\n'],
        PuckMode.giggle => <String>['\n\n'],
        PuckMode.intent => <String>['\n\n'],
      };

  /// Per-mode temperature.
  ///
  /// One global temperature is wrong for all three jobs: GIGGLE needs entropy
  /// or it tells the same twelve lines forever, while CONTEXT is a
  /// compression task where drift means contradicting the local ranker.
  static double temperatureFor(PuckMode mode) => switch (mode) {
        PuckMode.giggle => 1.0,
        PuckMode.context => 0.2,
        PuckMode.intent => 0.3,
      };

  /// The phone's share of the universal word contract:
  /// watch/buds 8, phone/car 15, pc/tv/ar 25.
  ///
  /// Mirrors `DEVICE_WORD_BUDGET` in puck-universal/shared/src/protocol.ts.
  /// Change both or neither -- a phone that renders 40 words is a different
  /// product from a watch that renders 8, which is the thing Puck exists to
  /// avoid.
  static const int phoneWordBudget = 15;

  /// Per-mode ceiling, clamped to the device budget.
  ///
  /// A mode may ask for less than the device allows (CONTEXT is a compression
  /// task and wants 10), never more.
  static int wordLimitFor(PuckMode mode) {
    final int perMode = switch (mode) {
      PuckMode.context => 10,
      PuckMode.giggle => 30,
      PuckMode.intent => 40,
    };
    return perMode < phoneWordBudget ? perMode : phoneWordBudget;
  }

  // -- Prompt assembly ------------------------------------------------------

  static String system(
    LlmRequest request, {
    bool actionsSupported = false,
  }) {
    return <String>[
      _preamble,
      _universalRules,
      _modeBlock(request.mode, actionsSupported: actionsSupported),
    ].join('\n\n');
  }

  static String user(LlmRequest request) => switch (request.mode) {
        PuckMode.giggle => _giggleUser(request),
        PuckMode.context => request.contextEnvelope ?? '',
        PuckMode.intent => request.query,
      };

  static const String _preamble =
      'You are the intelligence engine inside Puck, a zero-friction personal '
      'utility that lives in a single floating button on a phone. Your output '
      'is rendered on one small card for four seconds, or read aloud. Brevity '
      'is not a style preference, it is the format.';

  static const String _universalRules = '''
RULES THAT OVERRIDE EVERYTHING
1. MODE IS GIVEN, NEVER GUESSED. The MODE line below is authoritative. Do not infer it from the request, do not switch modes, never output the word MODE, and never repeat the mode name back.
2. No preamble, no agreement, no filler. Banned openers: Sure, Certainly, Of course, Absolutely, Great question, Here is, Here's your, I hope this helps, Let me know, As an AI, Got it, Sure thing.
3. No markdown, no bullet points, no emoji, no exclamation marks, no quotation marks around your own answer, no trailing offer to help.
4. Answer in the same language as the request.
5. If the request is empty, MODE alone determines what to produce.''';

  static String _modeBlock(PuckMode mode, {required bool actionsSupported}) {
    return switch (mode) {
      PuckMode.giggle => _giggleBlock,
      PuckMode.context => _contextBlock,
      PuckMode.intent => _intentBlock(actionsSupported),
    };
  }

  // -- GIGGLE ---------------------------------------------------------------

  /// The register is defined positively, not just by what to avoid.
  ///
  /// "Deadpan, absurd, witty, never corny" tells a small model what to exclude
  /// but not what to aim at, so it falls back to the highest-probability
  /// humour register it knows -- which is wordplay, i.e. exactly the dad joke
  /// the prompt just banned. Naming the target register (understatement,
  /// misdirection, bureaucratic absurdity, anti-joke) is what actually
  /// changes the output distribution.
  static const String _giggleBlock = '''
MODE: GIGGLE
Output ONE deadpan line. Two sentences only if the second is the punchline.

Register -- aim at one of these:
  - Understatement: something enormous described as a minor inconvenience.
  - Misdirection: the setup promises one thing, the payoff is literal.
  - Bureaucratic absurdity: cosmic or mundane events as admin procedure.
  - Anti-joke: a setup that pointedly refuses to pay off.

BANNED: puns, wordplay, question-and-answer setups ("Why did the..."), knock-knock, animal jokes, anything a greeting card would print, and any line that would be at home on a workplace poster.
NEVER repeat or closely paraphrase a line in the exclusion list.
Length: 30 words maximum.''';

  static String _giggleUser(LlmRequest request) {
    if (request.recentJokes.isEmpty) return 'Give me one line.';
    final StringBuffer b = StringBuffer()
      ..writeln('Already told. Do not repeat or closely paraphrase any of these:');
    for (final String line in request.recentJokes.take(8)) {
      b.writeln('- $line');
    }
    b.writeln('Give me one new line.');
    return b.toString();
  }

  // -- CONTEXT --------------------------------------------------------------

  /// The model sharpens a line the device already produced; it does not
  /// choose one from raw state.
  ///
  /// Two failure modes this prevents. First, fabrication: given a snapshot
  /// with a null calendar field, a model will invent a plausible event. Here
  /// it can only compress a fact that a deterministic ranker already
  /// committed to. Second, noise: asked to "produce an actionable
  /// observation" from a full snapshot, the model narrates the least
  /// interesting true thing available -- "It is 3:14 PM in Srinagar."
  static const String _contextBlock = '''
MODE: CONTEXT
A deterministic ranker on the device has already chosen the single most actionable fact from the user's state. It is given to you as LOCAL LINE.

Your job: sharpen LOCAL LINE to under 10 words. Preserve its meaning and its urgency. If it is already under 10 words and clear, return it unchanged.

You may add ONE concrete detail from the snapshot -- a room, a percentage, a time -- if it makes the line more actionable.
Use only fields present in the snapshot. If a field is absent, ignore it entirely. Never invent an event, a place, a number, or a time.
Never narrate the time of day back to the user, and never open with the word "It".
Length: 10 words maximum. No trailing period needed.''';

  /// Serialises a snapshot for the model.
  ///
  /// Only fields that are actually present are written. An absent field is
  /// left out rather than written as "unknown", because a listed field is a
  /// field the model will try to use.
  static String buildEnvelope({
    required ContextSnapshot snapshot,
    required ContextItem localLine,
  }) {
    final List<String> lines = <String>[];

    lines.add('time: ${PuckFormat.shortStamp(snapshot.now)} (device local time, already converted)');

    final CalendarEvent? event = snapshot.nextEvent;
    if (event != null) {
      lines.add(
        'calendar_event: ${event.title} — '
        '${event.isInProgress(snapshot.now) ? 'started ${PuckFormat.countdown(event.until(snapshot.now).abs())} ago' : 'starts ${PuckFormat.countdown(event.until(snapshot.now))}'}'
        '${event.location != null && event.location!.isNotEmpty ? ' @ ${event.location}' : ''}',
      );
    }

    final BatterySnapshot? battery = snapshot.battery;
    if (battery != null) {
      lines.add(
        'battery: ${battery.level}%${battery.charging ? ', charging' : ', not charging'}',
      );
    }

    final WeatherSnapshot? weather = snapshot.weather;
    if (weather != null) {
      lines.add(
        'weather: ${weather.temperatureC.round()}C, ${WeatherCodes.describe(weather.code)}',
      );
    }

    lines.add('LOCAL LINE: ${localLine.headline}');
    return lines.join('\n');
  }

  // -- INTENT ---------------------------------------------------------------

  static String _intentBlock(bool actionsSupported) => '''
MODE: INTENT
Answer the request directly. One sentence; two only if the second is essential.

DECISIONS: when asked to choose or advise ("should I", "which one", "is it worth it"), be definitive. Anchor the verdict to one stated criterion so it is decisive rather than guessed -- "Buy it if you will use it weekly, otherwise no." Never answer with "it depends" alone.
FACTS: state the fact. No preamble, no hedging, no source disclaimers.
UNANSWERABLE: if the answer genuinely requires information you do not have, say so in under 8 words. Never invent a price, a name, a number, or a date.
${actionsSupported ? _actionsOn : _actionsOff}
Length: 40 words maximum.''';

  /// Puck has no alarm, reminder, or messaging plugins. Without this rule the
  /// model answers "Alarm set for 7:00 AM" and the user believes something
  /// happened that did not. Flip this when a real action registry exists.
  static const String _actionsOff =
      'DEVICE ACTIONS: you have no connection to any device capability. If asked to set an alarm, add a reminder, send a message, or open an app, say it is not connected in under 8 words. Never claim you performed an action.';

  static const String _actionsOn =
      'DEVICE ACTIONS: reply as though the action succeeded, in the past tense, using the exact value given: "Alarm set for 7:00 AM." Only for actions you were told are supported.';

  // -- Output validation ----------------------------------------------------

  static const List<String> _bannedOpeners = <String>[
    'sure', 'certainly', 'of course', 'absolutely', 'great question',
    'here is', "here's", 'i hope', 'let me know', 'as an ai', 'got it',
    'sure thing', 'no problem', 'happy to', 'mode:', 'mode ', 'giggle:',
    'context:', 'intent:',
  ];

  /// Cheap client-side guard on model output.
  ///
  /// The prompt is a request, not a contract. This catches the four ways it
  /// actually misbehaves: empty, too long, opening with filler, or echoing
  /// the mode header back at us. A rejected result is discarded and the
  /// deterministic local line is kept instead -- the model never gets to make
  /// the surface worse.
  static bool isAcceptable(PuckMode mode, String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length > 400) return false;

    final String lower = trimmed.toLowerCase();
    for (final String opener in _bannedOpeners) {
      if (lower.startsWith(opener)) return false;
    }
    // Mode echo.
    if (lower.startsWith('mode') && lower.contains(':')) return false;

    final int words =
        trimmed.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).length;
    // +2 tolerance: a model that lands at 11 or 12 words is fine, one that
    // lands at 30 has ignored the instruction entirely.
    return words <= wordLimitFor(mode) + 2;
  }
}
