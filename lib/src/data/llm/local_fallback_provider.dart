import 'dart:math' as math;

import 'package:puck/src/core/expression.dart';
import 'package:puck/src/core/format.dart';

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
class LocalIntentResolver {
  LocalIntentResolver({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;

  /// The one honest sentence for "I cannot answer this without the network".
  /// Never an error dialog, never an apology tour -- one line, then the
  /// things that still work.
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

  String offline() => offlineLine;

  // -- Handlers ------------------------------------------------------------

  String? _coin(String q) {
    if (!RegExp(r'\b(coin|flip|heads|tails|toss)\b').hasMatch(q)) return null;
    return _rng.nextBool() ? 'Heads.' : 'Tails.';
  }

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

    if (RegExp(r'\b(dice|die|roll)\b').hasMatch(q)) {
      return '${_rng.nextInt(6) + 1}.';
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
    final String normalised = q
        .replaceAll(RegExp(r"^(what'?s|what is|whats|calculate|compute)\s+"), '')
        .replaceAll('?', '')
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll(RegExp(r'\btimes\b'), '*')
        .replaceAll(RegExp(r'\bmultiplied by\b'), '*')
        .replaceAll(RegExp(r'\bplus\b'), '+')
        .replaceAll(RegExp(r'\bminus\b'), '-')
        .replaceAll(RegExp(r'\bdivided by\b'), '/')
        .replaceAll('x', '*')
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

    final bool asksTime = RegExp(r'^(the\s+)?(time|clock)$').hasMatch(q) ||
        RegExp(r"\bwhat(?:'s| is|s)?\s+(?:the\s+)?(?:time|clock)\b")
            .hasMatch(q) ||
        RegExp(r'\bwhat time is it\b').hasMatch(q);

    final bool asksDate = RegExp(r'^(the\s+)?(date|day|today)$').hasMatch(q) ||
        RegExp(r"\bwhat(?:'s| is|s)?\s+(?:the\s+)?(?:date|today'?s date)\b")
            .hasMatch(q) ||
        RegExp(r"\bwhat day (?:is it|is today|are we)\b").hasMatch(q) ||
        RegExp(r"\btoday'?s (?:date|day)\b").hasMatch(q);

    if (asksTime) return '${PuckFormat.clock(now)}.';
    if (asksDate) {
      const List<String> days = <String>[
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
        'Friday', 'Saturday', 'Sunday',
      ];
      return '${days[now.weekday - 1]}, ${PuckFormat.stamp(now)}.';
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
        .replaceAll(
          RegExp(r'^(?:should i (?:pick|choose|get|have|take)|'
              r'which (?:one|is better)[,:]?|pick|choose|either)\s+'),
          '',
        )
        .replaceAll(RegExp(r'[?!.,\s]+$'), '')
        .trim();

    final List<String> parts = s.split(RegExp(r'\s+or\s+'));
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
