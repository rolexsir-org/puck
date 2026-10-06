import 'package:puck/src/core/format.dart';
import 'package:puck/src/data/models/context.dart';

/// The things Puck asks a model to do.
///
/// The mode is never inferred -- it is decided by the gesture before the
/// request is built (tap = context, swipe-up = intent) and injected into the
/// prompt. Asking a model to classify its own mode costs accuracy on every
/// call and lets a swipe-up query drift.
///
/// EMERGENCY is deliberately absent from this enum. The long press is served
/// locally: an SOS must be byte-identical every time, must not wait on a
/// network round trip, and must not be improvised by a language model.
enum PuckMode { context, intent }

/// Everything the model needs, assembled once per request.
class LlmRequest {
  const LlmRequest({
    required this.mode,
    this.query = '',
    this.contextEnvelope,
  });

  final PuckMode mode;

  /// The user's text. Empty for CONTEXT.
  final String query;

  /// Serialised device state. Required for CONTEXT, ignored otherwise.
  final String? contextEnvelope;
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
  /// token cap and the word clamp can never disagree.
  /// Reasoning tokens are drawn from the same budget as visible tokens, so a
  /// cap sized for the words alone can starve the answer and truncate it
  /// mid-sentence. Three tokens per word plus a floor is generous for the
  /// visible text and leaves the model room to think.
  static int maxTokensFor(PuckMode mode) => 24 + (wordLimitFor(mode) * 3);

  /// Stop sequences.
  ///
  /// Note the asymmetry: CONTEXT stops at the first newline because it is a
  /// single-line output. INTENT is allowed two sentences, so it stops on a
  /// *blank* line -- stopping on '\n' would silently amputate the second
  /// sentence mid-stream.
  static List<String> stopFor(PuckMode mode) => switch (mode) {
        PuckMode.context => <String>['\n'],
        PuckMode.intent => <String>['\n\n'],
      };

  /// Per-mode temperature.
  ///
  /// One global temperature is wrong for both jobs: CONTEXT is a compression
  /// task where drift means contradicting the local ranker.
  static double temperatureFor(PuckMode mode) => switch (mode) {
        PuckMode.context => 0.2,
        PuckMode.intent => 0.3,
      };

  /// The phone's word budget. Answers render on one small card; forty words
  /// is already a paragraph on a phone held in one hand.
  ///
  /// This is the *one* number. The prompt stub, the clamp below and the
  /// validator used to disagree (the prompt said 40, the clamp said 15, the
  /// validator allowed 17), which meant the model was being told one thing,
  /// allowed another and judged against a third. Every one of them now derives
  /// from here.
  static const int phoneWordBudget = 15;

  /// How much a mode may overshoot before the answer is rejected. Two words is
  /// the difference between "Rain starting in 20 minutes" and the same
  /// sentence with a stray "today"; it is not a licence to write paragraphs.
  static const int validationTolerance = 2;

  /// A hard ceiling on answer length, independent of word count -- a single
  /// 600-character "word" is impossible by the numbers and entirely possible
  /// from a model.
  static const int maxAnswerChars = 400;

  /// Per-mode ceiling, clamped to the device budget.
  ///
  /// A mode may ask for less than the device allows (CONTEXT is a compression
  /// task and wants 10), never more.
  static int wordLimitFor(PuckMode mode) {
    final int perMode = switch (mode) {
      PuckMode.context => 10,
      PuckMode.intent => phoneWordBudget,
    };
    return perMode < phoneWordBudget ? perMode : phoneWordBudget;
  }

  // -- Prompt assembly ------------------------------------------------------

  static String system(LlmRequest request) {
    return <String>[
      _preamble,
      _universalRules,
      _modeBlock(request.mode),
    ].join('\n\n');
  }

  static String user(LlmRequest request) => switch (request.mode) {
        PuckMode.context => request.contextEnvelope ?? '',
        PuckMode.intent => request.query,
      };

  static const String _preamble =
      'You are the intelligence engine inside Puck, a zero-friction personal '
      'utility that lives in a single floating button on a phone. Your output '
      'is rendered on one small card for a few seconds. Brevity is not a '
      'style preference, it is the format.';

  static const String _universalRules = '''
RULES THAT OVERRIDE EVERYTHING
1. MODE IS GIVEN, NEVER GUESSED. The MODE line below is authoritative. Do not infer it from the request, do not switch modes, never output the word MODE, and never repeat the mode name back.
2. No preamble, no agreement, no filler. Banned openers: Sure, Certainly, Of course, Absolutely, Great question, Here is, Here's your, I hope this helps, Let me know, As an AI, Got it, Sure thing.
3. No markdown, no bullet points, no emoji, no exclamation marks, no quotation marks around your own answer, no trailing offer to help.
4. Answer in the same language as the request.
5. If the request is empty, MODE alone determines what to produce.''';

  static String _modeBlock(PuckMode mode) {
    return switch (mode) {
      PuckMode.context => _contextBlock,
      PuckMode.intent => _intentBlock,
    };
  }

  // -- CONTEXT ---------------------------------------------------------------

  /// The model sharpens a line the device already produced; it does not
  /// choose one from raw state.
  ///
  /// Two failure modes this prevents. First, fabrication: given a snapshot
  /// with a null calendar field, a model will invent a plausible event. Here
  /// it can only compress a fact that a deterministic ranker already
  /// committed to. Second, noise: asked to "produce an actionable
  /// observation" from a full snapshot, the model narrates the least
  /// interesting true thing available.
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

    lines.add(
      'time: ${PuckFormat.stamp(snapshot.now)} (device local time, already '
      'converted)',
    );

    final CalendarEvent? event = snapshot.nextEvent;
    if (event != null) {
      lines.add(
        'calendar_event: ${event.title} — '
        '${_when(event, snapshot.now)}'
        '${_at(event.location)}',
      );
    }

    final BatterySnapshot? battery = snapshot.battery;
    if (battery != null) {
      lines.add(
        'battery: ${battery.level}%${_charging(battery.charging)}',
      );
    }

    final WeatherSnapshot? weather = snapshot.weather;
    if (weather != null) {
      lines.add(
        'weather: ${weather.temperatureC.round()}C, '
        '${WeatherCodes.describe(weather.code)}',
      );
    }

    lines.add('LOCAL LINE: ${localLine.headline}');
    return lines.join('\n');
  }

  // -- INTENT ---------------------------------------------------------------

  static const String _intentBlock = '''
MODE: INTENT
Answer the request directly. One sentence; two only if the second is essential.

DECISIONS: when asked to choose or advise ("should I", "which one", "is it worth it"), be definitive. Anchor the verdict to one stated criterion so it is decisive rather than guessed -- "Buy it if you will use it weekly, otherwise no." Never answer with "it depends" alone.
FACTS: state the fact. No preamble, no hedging, no source disclaimers.
UNANSWERABLE: if the answer genuinely requires information you do not have, say so in under 8 words. Never invent a price, a name, a number, or a date.
DEVICE ACTIONS: you have no connection to any device capability. If asked to set an alarm, add a reminder, send a message, or open an app, say it is not connected in under 8 words. Never claim you performed an action.
Length: 15 words maximum. The answer is rendered on one small card for a few seconds: past fifteen words it is a paragraph nobody finishes.''';

  // -- Output validation ----------------------------------------------------

  static const List<String> _bannedOpeners = <String>[
    'sure', 'certainly', 'of course', 'absolutely', 'great question',
    'here is', "here's", 'i hope', 'let me know', 'as an ai', 'got it',
    'sure thing', 'no problem', 'happy to', 'mode:', 'mode ', 'context:',
    'intent:',
  ];

  /// True when the *start* of an answer is something we will not put on
  /// screen. Split out from [isAcceptable] because the streaming path has to
  /// judge an answer that is still arriving: filler can be caught from the
  /// first few words, length cannot.
  ///
  /// Word boundaries matter here. "Sure." is filler; "Surely" is a sentence,
  /// and the old `startsWith('sure')` test rejected both.
  static bool hasBannedOpening(String text) {
    final String lower = text.trimLeft().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.startsWith('mode') && lower.contains(':')) return true;
    for (final String opener in _bannedOpeners) {
      if (RegExp('^${RegExp.escape(opener)}(?![a-z])').hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

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
    if (trimmed.length > maxAnswerChars) return false;
    if (hasBannedOpening(trimmed)) return false;

    final int words =
        trimmed.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).length;
    // Tolerance, not generosity: a model that lands at 11 or 12 words against
    // a 10-word limit is fine, one that lands at 30 has ignored the
    // instruction entirely -- and it always gets a second chance, because the
    // deterministic line is already on screen behind it.
    return words <= wordLimitFor(mode) + validationTolerance;
  }

  /// "started 20m ago" / "starts in 20m", as one short clause.
  ///
  /// Split out of the envelope so the line stays inside the column limit and
  /// so the two directions of the verb are one expression rather than two
  /// almost-identical inline branches.
  static String _when(CalendarEvent event, DateTime now) {
    final Duration until = event.until(now);
    if (event.isInProgress(now)) {
      return 'started ${PuckFormat.countdown(until.abs())} ago';
    }
    return 'starts ${PuckFormat.countdown(until)}';
  }

  /// " @ The kitchen", or nothing at all.
  static String _at(String? location) =>
      location != null && location.isNotEmpty ? ' @ $location' : '';

  static String _charging(bool charging) =>
      charging ? ', charging' : ', not charging';
}
