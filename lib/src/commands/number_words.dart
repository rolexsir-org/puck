/// Spoken numbers, durations and clock times -- the three things a command
/// parser needs from speech and a text field never has.
///
/// Recognition output is not what people typed. "Set the volume to forty" and
/// "volume 40%" are the same request, "half an hour" and "thirty minutes" are
/// the same timer, and an ASR engine has no idea which one it heard. So the
/// parser converts both shapes to numbers *before* it tries to understand the
/// sentence, rather than carrying two regexes for every command.
///
/// Deliberately not a full natural-number grammar: no "three point five
/// million", no "a couple of", no ordinals beyond the ones the commands use.
/// Every rule here is one the parser actually calls, because a number grammar
/// that is guessing is worse than one that returns null and lets the caller
/// say "I did not understand that".
library;

/// Words that mean a number, 0-20, then the tens and the scale words.
const Map<String, int> _smallNumbers = <String, int>{
  'zero': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fourty': 40, // a common recogniser spelling of a word people say as "fourty"
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};

const Map<String, int> _scaleWords = <String, int>{
  'hundred': 100,
  'thousand': 1000,
};

/// Every word [parseSpokenNumber] will consume, for the duration parser's own
/// regex. Kept in sync by construction rather than by hand.
Iterable<String> get spokenNumberWords => <String>[
      ..._smallNumbers.keys,
      ..._scaleWords.keys,
    ];

/// A number read out loud, as a `double`.
///
/// Handles digits ("40", "3.5"), words ("forty", "twenty five", "one hundred
/// and twenty"), and "three point five". Returns null when there is no number
/// in [text], which is how the parser tells "set the volume to forty" from
/// "set the volume to something".
double? parseSpokenNumber(String text) {
  final String cleaned = text
      .trim()
      .toLowerCase()
      // "twenty-five" and "twenty five" are the same number; the recogniser
      // picks either.
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\band\b'), ' ')
      .trim();
  if (cleaned.isEmpty) return null;

  final RegExpMatch? digits = RegExp(
    r'^(\d+(?:\.\d+)?)$',
  ).firstMatch(cleaned);
  if (digits != null) return double.tryParse(digits.group(1)!);

  // "three point five" -> 3.5
  final RegExpMatch? point = RegExp(
    r'^(.+?)\s+point\s+(.+)$',
  ).firstMatch(cleaned);
  if (point != null) {
    final double? whole = parseSpokenNumber(point.group(1)!);
    final double? fraction = _digitsOfWords(point.group(2)!);
    if (whole == null || fraction == null) return null;
    return whole + fraction;
  }

  final int? value = parseSpokenInt(cleaned);
  return value?.toDouble();
}

/// The integer part of [parseSpokenNumber], for callers that need an int
/// (a volume percentage, a minute count).
int? parseSpokenInt(String text) {
  final String cleaned = text
      .trim()
      .toLowerCase()
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\band\b'), ' ')
      .trim();
  if (cleaned.isEmpty) return null;

  final RegExpMatch? digits = RegExp(r'^(\d+)$').firstMatch(cleaned);
  if (digits != null) return int.tryParse(digits.group(1)!);

  final List<String> words = cleaned
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList(growable: false);

  int total = 0;
  int current = 0;
  bool matched = false;

  for (final String word in words) {
    final int? small = _smallNumbers[word];
    if (small != null) {
      // "twenty five" is 25, but "hundred" between them resets the frame:
      // after a scale word the next small number is a new group.
      current += small;
      matched = true;
      continue;
    }
    final int? scale = _scaleWords[word];
    if (scale != null) {
      matched = true;
      if (scale == 100) {
        current = (current == 0 ? 1 : current) * 100;
      } else {
        total += (current == 0 ? 1 : current) * scale;
        current = 0;
      }
      continue;
    }
    // An unknown word ends the number: "volume forty please" parses the forty
    // and leaves "please" to the caller's own patterns.
    break;
  }

  if (!matched) return null;
  return total + current;
}

/// "five" -> 5, "twenty five" -> 25, used for the fractional part of
/// "three point five". Digits after the point are read one at a time, so
/// "three point five zero" is 3.50, not 3.05.
double? _digitsOfWords(String text) {
  final String cleaned = text.trim().toLowerCase();
  final RegExpMatch? digits = RegExp(r'^(\d+)$').firstMatch(cleaned);
  if (digits != null) return double.tryParse('0.${digits.group(1)!}');

  final StringBuffer buffer = StringBuffer();
  for (final String word in cleaned.split(RegExp(r'\s+'))) {
    final int? small = _smallNumbers[word];
    if (small == null || small > 9) return null;
    buffer.write(small);
  }
  if (buffer.isEmpty) return null;
  return double.tryParse('0.$buffer');
}

/// A spoken duration: "5 minutes", "ninety seconds", "half an hour",
/// "an hour and a half", "1 hour 30 minutes".
///
/// Returns null when no unit word is present -- "set a timer for five" is not
/// a timer, it is a question about what unit was meant.
Duration? parseSpokenDuration(String text) {
  final String cleaned = text
      .trim()
      .toLowerCase()
      .replaceAll('-', ' ')
      // "half an hour" is the one duration English builds backwards: the
      // amount follows the unit. Normalising those idioms first means the
      // scanner below only ever sees "amount unit" pairs, instead of carrying
      // a second grammar for four phrases.
      .replaceAll(RegExp(r'\bhalf an hour\b'), '30 minutes')
      .replaceAll(RegExp(r'\bhalf hour\b'), '30 minutes')
      .replaceAll(RegExp(r'\bhalf a minute\b'), '30 seconds')
      .replaceAll(RegExp(r'\bhalf a day\b'), '12 hours')
      .replaceAll(RegExp(r'\bquarter of an hour\b'), '15 minutes')
      .replaceAll(RegExp(r'\bquarter hour\b'), '15 minutes')
      .replaceAll(RegExp(r'\b(?:an?|one) (?:hour|hr) and a half\b'), '90 minutes')
      .replaceAll(RegExp(r'\band\b'), ' ');

  Duration total = Duration.zero;
  bool matched = false;

  // Number-word alternatives, longest first so "twenty five" wins over
  // "twenty" followed by a stray "five".
  final List<String> words = spokenNumberWords.toList(growable: false)
    ..sort((String a, String b) => b.length.compareTo(a.length));
  final String numberWords = words.join('|');
  final RegExp part = RegExp(
    '(\\d+(?:\\.\\d+)?|a|an|half|quarter|(?:$numberWords)(?: (?:$numberWords))*)\\s*'
    '(second|seconds|sec|secs|minute|minutes|min|mins|hour|hours|hr|hrs)',
  );

  for (final RegExpMatch m in part.allMatches(cleaned)) {
    final String amountText = m.group(1)!;
    final String unit = m.group(2)!;
    matched = true;

    final double? amount = switch (amountText) {
      'a' || 'an' => 1,
      'half' => 0.5,
      'quarter' => 0.25,
      _ => parseSpokenNumber(amountText),
    };
    if (amount == null) continue;

    final double seconds = unit.startsWith('sec')
        ? 1
        : unit.startsWith('min')
            ? 60
            : 3600;
    total += Duration(milliseconds: (amount * seconds * 1000).round());
  }

  if (!matched || total <= Duration.zero) return null;
  return total;
}

/// A clock time: "7:30 am", "7 30 a m", "19:45", "seven thirty pm".
///
/// Returns 24-hour `hour` and `minute`. A time with no am/pm is read as the
/// 24-hour clock ("19:45") and, for 1-12, as the nearest *upcoming* hour by the
/// caller -- which is what someone means by "set an alarm for seven".
({int hour, int minute, bool explicitMeridiem})? parseClockTime(String text) {
  final String cleaned = text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\b([ap])\s*m\b'), r'$1m')
      .replaceAll('-', ' ')
      .replaceAll('.', ':');

  // Numeric: "7:30", "19:45", "7.30" (already normalised to ':').
  final RegExpMatch? numeric = RegExp(
    r'\b(\d{1,2})\s*:\s*(\d{1,2})\s*(am|pm)?\b',
  ).firstMatch(cleaned);
  if (numeric != null) {
    return _clock(
      int.parse(numeric.group(1)!),
      int.parse(numeric.group(2)!),
      numeric.group(3),
    );
  }

  // Numeric hour only: "at 7", "at 7 am", "at 19".
  final RegExpMatch? hourOnly = RegExp(
    r'\b(\d{1,2})\s*(am|pm)\b',
  ).firstMatch(cleaned);
  if (hourOnly != null) {
    return _clock(int.parse(hourOnly.group(1)!), 0, hourOnly.group(2));
  }

  // Spoken: "seven thirty pm", "seven pm", "six oh five am".
  final RegExpMatch? spoken = RegExp(
    r'\b('
    'one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve'
    r'|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty'
    r')(?:\s+(oh\s+)?('
    r'one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve'
    r'|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty'
    r'|thirty|forty|fifty))?\s*(am|pm)?\b',
  ).firstMatch(cleaned);
  if (spoken != null) {
    final int hour = _smallNumbers[spoken.group(1)!]!;
    final String? minuteWord = spoken.group(3);
    final int minute =
        minuteWord == null ? 0 : (_smallNumbers[minuteWord] ?? 0);
    return _clock(hour, minute, spoken.group(4));
  }

  return null;
}

({int hour, int minute, bool explicitMeridiem})? _clock(
  int hour,
  int minute,
  String? meridiem,
) {
  if (minute < 0 || minute > 59) return null;
  if (meridiem == null) {
    if (hour < 0 || hour > 23) return null;
    // "at 7" is ambiguous, and the caller needs to know it: with no am/pm the
    // alarm could be morning or evening, and only the executor (which owns the
    // clock) can decide which is nearer.
    return (hour: hour, minute: minute, explicitMeridiem: false);
  }
  if (hour < 1 || hour > 12) return null;
  final bool pm = meridiem == 'pm';
  final int h = hour == 12 ? (pm ? 12 : 0) : (pm ? hour + 12 : hour);
  return (hour: h, minute: minute, explicitMeridiem: true);
}
