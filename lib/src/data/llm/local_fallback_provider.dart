import 'dart:math' as math;
import 'dart:ui' show Locale;

import 'package:intl/intl.dart';
import 'package:puck/src/core/expression.dart';
import 'package:puck/src/l10n/puck_strings.dart';

/// A deterministic, offline intent resolver.
///
/// Two jobs:
///   1. Answer the things that do not need a language model at all, and that
///      a language model is actively bad at -- coin flips should be uniformly
///      random and arithmetic should be correct, not plausible.
///   2. Keep Puck usable with no API key and no network. A build with no key
///      still answers "flip a coin" instantly instead of showing a blank.
///
/// Returns null when it has no opinion, letting the router escalate to the
/// LLM.
///
/// # Language
///
/// The patterns are per-language, and a language with no pattern set gets an
/// empty one -- which means an unanswered question rather than a wrong answer.
/// That direction of failure is the whole design: a Spanish speaker asking
/// "¿cara o cruz?" gets a real coin flip, and a Spanish speaker asking
/// something this class does not understand falls through to the model or to
/// the offline line instead of matching an English keyword by accident.
class LocalIntentResolver {
  LocalIntentResolver({math.Random? random, Locale? locale})
      : _rng = random ?? math.Random(),
        _locale = locale ?? const Locale('en');

  final math.Random _rng;
  Locale _locale;

  /// The UI sets this from `Localizations.localeOf` on the first frame; the
  /// resolver is app-scoped and outlives any widget.
  void setLocale(Locale locale) => _locale = locale;

  PuckStrings get _strings => PuckStrings.forLocale(_locale);

  /// The one honest sentence for "I cannot answer this without the network".
  /// Never an error dialog, never an apology tour -- one line, then the
  /// things that still work.
  ///
  /// English is kept as a static so that code with no locale (tests, the
  /// router's own fallback) has a single canonical value.
  static const String offlineLine = 'Offline. Try coin, dice, or maths.';

  String? tryResolve(String raw) {
    final String q = raw.trim().toLowerCase();
    if (q.isEmpty) return null;

    final String? coin = _coin(q);
    if (coin != null) return coin;

    final String? dice = _dice(q);
    if (dice != null) return dice;

    final String? rand = _randomNumber(q);
    if (rand != null) return rand;

    final String? maths = _maths(q);
    if (maths != null) return maths;

    final String? clock = _timeDate(q);
    if (clock != null) return clock;

    final String? pick = _pickOne(q);
    if (pick != null) return pick;

    return null;
  }

  String offline() => _strings.offlineLine;

  /// The one cloud failure the user can act on: their own key was refused.
  String keyRejected() => _strings.answerKeyRejected;

  /// The fixed line for a crisis question. Never model output, never
  /// rephrased -- see PuckSafety for why this category gets no improvisation.
  String safety() => _strings.safetyLine;

  // -- Handlers ------------------------------------------------------------

  String? _coin(String q) {
    final List<String> patterns = _patterns('coin');
    for (final String p in patterns) {
      if (RegExp(p).hasMatch(q)) {
        return _rng.nextBool() ? _strings.coinHeads : _strings.coinTails;
      }
    }
    return null;
  }

  /// Per-language pattern sets. A language that is not listed matches
  /// nothing, which is the honest failure.
  ///
  /// Note what this is *not*: a fallback to English. Returning the English
  /// patterns here would mean a phone whose UI is in a language Puck does not
  /// ship gets an answer to an English phrase it never asked in -- the wrong
  /// answer, delivered confidently, which is the failure mode this resolver
  /// exists to avoid. (That is a real bug this method used to have: it ended
  /// `return table['en']`, contradicting this comment. `test/core/
  /// local_resolver_test.dart` now pins both directions.)
  ///
  /// The common path is unaffected: `app.dart`'s `localeResolutionCallback`
  /// maps an unshipped phone language to `en` before the app ever asks, so a
  /// German phone that types English gets English answers through an explicit
  /// `'en'` lookup rather than through this guard.
  List<String> _patterns(String kind) {
    final Map<String, List<String>>? table = _patternTable[kind];
    if (table == null) return const <String>[];
    return table[_locale.languageCode] ?? const <String>[];
  }

  static const Map<String, Map<String, List<String>>> _patternTable =
      <String, Map<String, List<String>>>{
    'coin': <String, List<String>>{
      'en': <String>[r'\b(coin|flip|heads|tails|toss)\b'],
      'es': <String>[
        r'\b(moneda|monedas|cara o cruz|cruz o cara|lanza|lanzo|'
        r'echar a suertes|suerte)\b',
      ],
    },
    'diceWords': <String, List<String>>{
      'en': <String>[r'\b(dice|die|roll)\b'],
      'es': <String>[r'\b(dado|dados|tira|tiro|lance)\b'],
    },
    'time': <String, List<String>>{
      'en': <String>[
        r'^(the\s+)?(time|clock)$',
        r"\bwhat(?:'s| is|s)?\s+(?:the\s+)?(?:time|clock)\b",
        r'\bwhat time is it\b',
      ],
      'es': <String>[
        r'^(la\s+)?(hora)$',
        r'\bqu[eé] horas? (?:es|son)\b',
        r'\bla hora\b',
      ],
    },
    'date': <String, List<String>>{
      'en': <String>[
        r'^(the\s+)?(date|day|today)$',
        r"\bwhat(?:'s| is|s)?\s+(?:the\s+)?(?:date|today'?s date)\b",
        r'\bwhat day (?:is it|is today|are we)\b',
        r"\btoday'?s (?:date|day)\b",
      ],
      'es': <String>[
        r'^(la\s+)?(fecha|d[ií]a|hoy)$',
        r'\bqu[eé] (?:fecha|d[ií]a) (?:es|es hoy)\b',
        r'\bfecha de hoy\b',
      ],
    },
  };

  String? _dice(String q) {
    final RegExpMatch? dnd =
        RegExp(r'(\d*)\s*d\s*(\d+)').firstMatch(q.replaceAll(' ', ''));
    if (dnd != null) {
      final int count =
          int.tryParse(dnd.group(1) ?? '')?.clamp(1, 20).toInt() ?? 1;
      final int sides = int.tryParse(dnd.group(2) ?? '')?.clamp(2, 100) ?? 6;
      int total = 0;
      for (int i = 0; i < count; i++) {
        total += _rng.nextInt(sides) + 1;
      }
      return count == 1 ? '$total.' : '${count}d$sides = $total.';
    }

    for (final String pattern in _patterns('diceWords')) {
      if (RegExp(pattern).hasMatch(q)) {
        return '${_rng.nextInt(6) + 1}.';
      }
    }
    return null;
  }

  String? _randomNumber(String q) {
    final RegExpMatch? m =
        RegExp(r'random (?:number )?(?:between )?(\d+)\s*(?:and|to|-)\s*(\d+)')
            .firstMatch(q);
    if (m == null) return null;
    final int lo = int.parse(m.group(1)!);
    final int hi = int.parse(m.group(2)!);
    if (hi <= lo) return '$lo.';
    return '${lo + _rng.nextInt(hi - lo + 1)}.';
  }

  /// Accepts both typed arithmetic ("47*83") and spoken arithmetic
  /// ("what's 47 times 83"). The spoken forms are normalised to operators
  /// and handed to the same evaluator, so both paths share one grammar.
  String? _maths(String q) {
    // Spoken arithmetic, in the languages Puck ships. The operator words are
    // replaced rather than the question being pattern-matched, so both
    // languages share one grammar and one evaluator.
    // Punctuation comes off *first*. It used to come off after the prefix was
    // stripped, so "¿cuánto es 12 más 4?" never lost its opening inverted
    // question mark, never matched the prefix, kept the letters, and fell
    // through to the model -- a Spanish arithmetic question that the device
    // can answer exactly, handed to a language model that will guess.
    final String normalised = q
        .replaceAll('¿', '')
        .replaceAll('?', '')
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll(
          RegExp(
            r"^(?:what'?s|what is|whats|calculate|compute|"
            r"cu[aá]nto es|cu[aá]nto son|calcula)\s+",
          ),
          '',
        )
        .replaceAll(RegExp(r'\btimes\b'), '*')
        .replaceAll(RegExp(r'\bmultiplied by\b'), '*')
        .replaceAll(RegExp(r'\bplus\b'), '+')
        .replaceAll(RegExp(r'\bminus\b'), '-')
        .replaceAll(RegExp(r'\bdivided by\b'), '/')
        .replaceAll(RegExp(r'\bm[aá]s\b'), '+')
        .replaceAll(RegExp(r'\bmenos\b'), '-')
        // "dividido por", "dividido entre" and "entre" are all how Spanish
        // is actually written and spoken. One rule, because two rules turned
        // "100 dividido entre 8" into "100 //8" -- which is not arithmetic.
        .replaceAll(
          RegExp(r'\b(?:dividido|entre)(?:\s+entre)?\s+(?:por\s+)?'),
          '/',
        )
        .replaceAll(RegExp(r'\bmultiplicado por\b'), '*')
        .replaceAll(RegExp(r'\bpor\b'), '*')
        .replaceAll(RegExp(r'\bequisdividido\b'), '/')
        .replaceAll('x', '*')
        // Collapse the spaces the replacements leave behind, so the evaluator
        // and any error message see "100 / 8" rather than "100 / 8" with
        // an extra gap.
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (!ExpressionEvaluator.looksLikeMaths(normalised)) return null;
    final double? value = ExpressionEvaluator.tryEvaluate(normalised);
    if (value == null) return null;
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return '${value.toStringAsFixed(0)}.';
    }
    return '${_trimDouble(value)}.';
  }

  /// "what's the time", "what day is it" -- free, exact, no network.
  ///
  /// The patterns ask a *question*; they do not look for keywords. The
  /// keyword version of this method matched a bare `day` anywhere in the
  /// string, so "when is my birthday" confidently answered with today's date.
  /// A wrong answer delivered without hesitation is the worst thing a tool
  /// built on honesty can do, so the cost of missing a phrasing is the right
  /// side to fail on: an unmatched question falls through to the model or to
  /// the offline line, both of which are honest.
  String? _timeDate(String q) {
    final DateTime now = DateTime.now();
    final bool asksTime =
        _patterns('time').any((String p) => RegExp(p).hasMatch(q));
    final bool asksDate =
        _patterns('date').any((String p) => RegExp(p).hasMatch(q));

    if (asksTime) return '${_strings.clock(now)}.';
    if (asksDate) {
      // The day name comes from the locale's own tables rather than a
      // hand-written English list, so the answer is in the language it was
      // asked in.
      final String day = DateFormat.EEEE(_strings.localeName).format(now);
      return '$day, ${_strings.stamp(now)}.';
    }
    return null;
  }

  /// "tea or coffee" -- decide, as instructed.
  ///
  /// Only for an actual either/or. The previous pattern matched *any* " or "
  /// anywhere in a sentence, so "tea or coffee or tea" was answered with
  /// "coffee or tea." -- a confident reply to a question that was never asked.
  /// Splitting on every " or " and requiring exactly two clean, word-like
  /// options keeps the joke ("tea or coffee" is a real question) and drops the
  /// nonsense.
  String? _pickOne(String q) {
    final String s = q
        .replaceAll(RegExp(r'^[¿\s]*'), '')
        .replaceAll(
          RegExp(
            r'^(?:should i (?:pick|choose|get|have|take)|'
            r'which (?:one|is better)[,:]?|pick|choose|either|'
            r'deber[ií]a (?:elegir|escoger|tomar)|'
            r'(?:elijo|elige|escoge|prefiero|quiero))\s+',
          ),
          '',
        )
        .replaceAll(RegExp(r'[?!.,\s]+$'), '')
        .trim();

    // The conjunction is a word in the language, not a symbol: Spanish asks
    // "té o café" (and "siete u ocho", where "o" becomes "u" before an
    // o- sound), English asks "tea or coffee". Splitting only on `or` meant
    // every Spanish either/or fell through to the model -- or to the offline
    // line, which is a worse answer to a question the device can decide.
    final String conjunction =
        _locale.languageCode == 'es' ? r'\s+(?:o|u)\s+' : r'\s+or\s+';
    final List<String> parts = s.split(RegExp(conjunction));
    if (parts.length != 2) return null;

    final String a = parts[0].trim();
    final String b = parts[1].trim();
    if (a.isEmpty || b.isEmpty) return null;
    if (a.length > 28 || b.length > 28) return null;
    if (RegExp(r'\d').hasMatch('$a$b')) return null; // probably maths

    // Options are *things*, and few words of them: "tea or coffee", "cats or
    // dogs". "I could take the bus or I could walk" is a deliberation, not a
    // coin to flip, and answering it with one of the two clauses is exactly
    // the kind of confident nonsense this resolver must not produce.
    final RegExp words = RegExp(r"^[\p{L}\p{M}\s\-'&]+$", unicode: true);
    if (!words.hasMatch(a) || !words.hasMatch(b)) return null;
    if (_wordCount(a) > 3 || _wordCount(b) > 3) return null;

    return _rng.nextBool() ? '$a.' : '$b.';
  }

  static int _wordCount(String text) => text
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .length;

  static String _trimDouble(double v) {
    final String s = v.toStringAsFixed(6);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
