import 'package:puck/src/commands/command_intent.dart';
import 'package:puck/src/commands/number_words.dart';
import 'package:puck/src/commands/units.dart';
import 'package:puck/src/core/expression.dart';

/// Speech (or typing) in, a [CommandIntent] out. Or null, which is an answer
/// in itself: it means "this is not one of my commands", and the caller sends
/// the sentence to the ordinary answer path.
///
/// # Why a hand-written parser and not a model
///
/// Every command here is deterministic and must work with the radio off. "Turn
/// the torch on" is a lookup, not an inference, and a language model in front of
/// it would add latency, a download and a way to be wrong -- for a sentence
/// whose meaning has one spelling. The model still exists in Puck; it answers
/// questions. It does not drive the phone.
///
/// # Shape of the thing
///
/// Recognition output is dirty: no punctuation, inconsistent casing, numbers as
/// words about half the time, and a wake phrase glued to the front. So parsing
/// is three passes, in this order:
///
///   1. [normalize] -- one canonical string (case, contractions, wake word,
///      punctuation, filler).
///   2. recognise -- a battery of anchored patterns, ordered from the most
///      specific phrasing to the least. Whichever fires first wins, which is
///      why "set a timer for 5 minutes" cannot be read as an alarm.
///   3. extract -- numbers, durations, clock times and units, each through one
///      shared helper, so "40", "forty" and "forty percent" are one number.
///
/// Failure is always "no intent" rather than a guess. A parser that guesses is
/// a parser that mutes a phone when somebody said "the volume is too loud".
class CommandParser {
  CommandParser({String assistantName = 'puck'})
      : _assistantName = _cleanName(assistantName);

  /// The name the user gave the assistant. Used for one thing only: stripping a
  /// wake phrase off the front of an utterance ("hey puck, turn the light on").
  /// It is *not* an acoustic model -- see docs/voice.md §5.
  final String _assistantName;

  static String _cleanName(String name) {
    final String cleaned = name.trim().toLowerCase();
    return cleaned.isEmpty ? 'puck' : cleaned;
  }

  /// One canonical form for an utterance.
  ///
  /// Public because the duplicate-execution guard fingerprints utterances with
  /// it: "Volume up" and "volume  up." must be the same string, or a repeated
  /// recognition triggers the same command twice.
  String normalize(String raw) {
    String s = raw.toLowerCase();

    // Typographic punctuation first: recognition apps and keyboards both emit
    // curly quotes, and an apostrophe table keyed on straight quotes silently
    // misses half of them.
    s = s
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        .replaceAll('\u201c', ' ')
        .replaceAll('\u201d', ' ');

    for (final MapEntry<String, String> e in _contractions.entries) {
      s = s.replaceAll(e.key, e.value);
    }

    // A wake phrase is glued to the front of the next command, not a sentence
    // of its own.
    final String name = RegExp.escape(_assistantName);
    s = s.replaceFirst(
      RegExp('^(?:hey|hi|ok|okay|yo|hello)?\\s*$name\\b\\s*[,:.!\\-]*\\s*'),
      '',
    );
    // And the reverse ordering, which people also use: "puck, hey".
    s = s.replaceFirst(RegExp('^$name\\s*,\\s*(?:hey|hi|okay)?\\s*'), '');

    // Keep the characters any command can use, drop the rest. ':' survives for
    // clock times and the arithmetic operators survive for "what is 12*8".
    s = s.replaceAll(RegExp(r"[^a-z0-9 %+*/^().:\-]"), ' ');
    // A full stop is punctuation at the end of a sentence and a decimal point
    // between digits; there is no third case worth supporting.
    s = s.replaceAll(RegExp(r'\.(?:[\s]|$)'), ' ');
    s = s.replaceAll(RegExp(r'(?:^|\s)\.'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    s = s.replaceAll(RegExp(r'^(?:please|kindly|can you|could you|would you)\s+'),
        '');
    s = s.replaceAll(RegExp(r'\s+(?:please|for me)$'), '');
    return s.trim();
  }

  /// The one entry point. Returns null when nothing matched.
  CommandIntent? parse(String raw) {
    if (raw.trim().isEmpty) return null;
    final String text = normalize(raw);
    if (text.isEmpty) return null;

    return _cancel(text) ??
        _help(text) ??
        _consequential(text) ??
        _mute(text) ??
        _setVolume(text) ??
        _adjustVolume(text) ??
        _flashlight(text) ??
        _openApp(text) ??
        _battery(text) ??
        _clock(text) ??
        _date(text) ??
        _timer(text) ??
        _alarm(text) ??
        _convert(text) ??
        _calculate(text);
  }

  // -- Device controls ------------------------------------------------------

  CommandIntent? _cancel(String text) {
    if (RegExp(r'^(?:stop|cancel|never ?mind|forget it|stop talking|shut up|'
            r'abort|that is all|nothing)$')
        .hasMatch(text)) {
      return const CancelIntent();
    }
    return null;
  }

  CommandIntent? _help(String text) {
    if (RegExp(r'^(?:help|commands?|list commands|what can you do|'
            r'what can i say|what can you do for me|help me)$')
        .hasMatch(text)) {
      return const HelpIntent();
    }
    return null;
  }

  /// Consequential requests are recognised so they can be refused by name.
  CommandIntent? _consequential(String text) {
    final RegExpMatch? call = RegExp(
      r'^(?:call|dial|phone|ring)\s+(.+)$',
    ).firstMatch(text);
    if (call != null) {
      return ConsequentialIntent(kind: ConsequentialKind.call, detail: call.group(1)!);
    }

    final RegExpMatch? message = RegExp(
      r'^(?:send|text|message|whatsapp|telegram|email|mail|tell)\s+(.+)$',
    ).firstMatch(text);
    if (message != null &&
        RegExp(r'\b(?:message|text|sms|whatsapp|email|mail|say|tell)\b')
            .hasMatch(message.group(1)!)) {
      return ConsequentialIntent(
        kind: ConsequentialKind.message,
        detail: message.group(1)!,
      );
    }
    // "text Sam that I am late" -- the verb form has no "message" noun.
    if (RegExp(r'^(?:send|text|email|whatsapp)\b').hasMatch(text)) {
      return ConsequentialIntent(kind: ConsequentialKind.message, detail: text);
    }

    if (RegExp(r'^(?:delete|erase|remove|wipe|format)\b').hasMatch(text)) {
      return ConsequentialIntent(
        kind: ConsequentialKind.deleteData,
        detail: text,
      );
    }

    if (RegExp(r'\b(?:share|send)\s+my\s+(?:location|position|whereabouts)\b')
            .hasMatch(text) ||
        RegExp(r'^where am i$').hasMatch(text)) {
      return ConsequentialIntent(
        kind: ConsequentialKind.shareLocation,
        detail: text,
      );
    }
    return null;
  }

  CommandIntent? _mute(String text) {
    if (RegExp(r'^(?:mute|mute it|mute the (?:volume|sound|audio|phone)|'
            r'silence|silence it|be quiet|sound off|'
            r'(?:turn|switch) (?:the )?(?:sound|audio|volume) off|'
            r'turn off the (?:sound|audio))$')
        .hasMatch(text)) {
      return const MuteIntent(muted: true);
    }
    if (RegExp(r'^(?:unmute|unmute it|unsilence|sound on|'
            r'(?:turn|switch) (?:the )?(?:sound|audio) on|'
            r'restore (?:the )?(?:volume|sound)|volume back on)$')
        .hasMatch(text)) {
      return const MuteIntent(muted: false);
    }
    return null;
  }

  /// "set the volume to 40", "volume 40 percent", "volume to max", "volume 0".
  ///
  /// The level is a percentage of the media stream's own maximum, because that
  /// is the only volume scale Android exposes consistently across devices.
  CommandIntent? _setVolume(String text) {
    final RegExpMatch? m = RegExp(
      r'\b(?:set|change|put|turn)?\s*(?:the\s+)?(?:media\s+|music\s+|sound\s+)?'
      r'volume\s*(?:up|down)?\s*(?:to|at|on|of)?\s*(.+)$',
    ).firstMatch(text);
    if (m == null) return null;

    final String tail = m.group(1)!
        .replaceAll(RegExp(r'\bout of 100\b|\bpercent\b|%'), '')
        .trim();
    if (tail.isEmpty) return null;

    if (RegExp(r'^(?:max|maximum|full|all the way up|highest|top)$')
        .hasMatch(tail)) {
      return const SetVolumeIntent(100);
    }
    if (RegExp(r'^(?:min|minimum|lowest|zero|silent)$').hasMatch(tail)) {
      return const SetVolumeIntent(0);
    }

    // The level must be a number and nothing else. Without this check
    // "volume down two notches" reads its own "two" as a level of 2%, which is
    // both wrong and destructive -- the phone would go nearly silent.
    if (!_isPureNumber(tail)) return null;
    final double? number = parseSpokenNumber(tail);
    if (number == null) return null;
    final int level = number.round();

    // A volume above 100 is not a volume. If someone says "volume 150" they
    // meant something else (a channel, a frequency), and clamping silently
    // would be a wrong answer delivered confidently.
    if (level < 0 || level > 100) return null;
    return SetVolumeIntent(level);
  }

  /// "volume up", "louder", "turn it up by two steps", "volume down a notch".
  CommandIntent? _adjustVolume(String text) {
    final RegExp up = RegExp(
      r'\b(?:volume (?:up|higher)|(?:turn|bring|put) (?:it|the volume) up|'
      r'turn up the (?:volume|sound|music)|'
      r'(?:a bit |a little )?(?:louder|more volume)|'
      r'raise (?:the )?volume|increase (?:the )?volume|'
      r'crank (?:it|the volume) up)\b',
    );
    final RegExp down = RegExp(
      r'\b(?:volume (?:down|lower)|(?:turn|bring|put) (?:it|the volume) down|'
      r'turn down the (?:volume|sound|music)|'
      r'(?:a bit |a little )?(?:quieter|less volume|softer)|'
      r'lower (?:the )?volume|decrease (?:the )?volume|reduce (?:the )?volume)\b',
    );

    final bool isUp = up.hasMatch(text);
    final bool isDown = down.hasMatch(text);
    if (!isUp && !isDown) return null;
    if (isUp && isDown) return null; // "turn it up, no, down" -- not a command

    final int steps = _steps(text);
    return AdjustVolumeIntent(isUp ? steps : -steps);
  }

  /// "by three steps", "two notches", "a step". Defaults to one step, which is
  /// what the volume rocker does and what people expect from "louder".
  int _steps(String text) {
    final RegExpMatch? m = RegExp(
      r'\b(?:by\s+)?([a-z0-9 ]+?)\s*(?:steps?|notches?|clicks?)\b',
    ).firstMatch(text);
    if (m != null) {
      final int? n = parseSpokenInt(m.group(1)!.trim());
      if (n != null && n > 0 && n <= 10) return n;
    }
    return 1;
  }

  /// True when [text] is only digits and spoken number words ("40",
  /// "twenty five", "3.5"). Used to stop a phrase's trailing words being read
  /// as a volume level.
  bool _isPureNumber(String text) {
    final List<String> words = text
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return false;
    for (final String word in words) {
      if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(word)) continue;
      if (word == 'point') continue;
      if (_numberWords.contains(word)) continue;
      return false;
    }
    return true;
  }

  static final Set<String> _numberWords = spokenNumberWords.toSet();

  CommandIntent? _flashlight(String text) {
    // Plurals included: "turn the lights off" is how people talk about a room.
    const String noun = r'(?:flashlights?|torches?|lights?|lamps?|flashes?)';
    const String op = r'(?:turn|switch|put|power|flip)';
    // Both word orders, because both are said: "turn on the torch" and
    // "turn the torch on". And both without a verb: "torch on".
    if (RegExp(
      '\\b$op\\s+(?:on|up)\\s+(?:the\\s+)?(?:my\\s+)?$noun\\b'
      '|\\b$op\\s+(?:the\\s+)?(?:my\\s+)?$noun\\s+(?:on|up)\\b'
      '|^$noun\\s+(?:on|up)\\b',
    ).hasMatch(text)) {
      return const FlashlightIntent(on: true);
    }
    if (RegExp(
      '\\b$op\\s+(?:off|down)\\s+(?:the\\s+)?(?:my\\s+)?$noun\\b'
      '|\\b$op\\s+(?:the\\s+)?(?:my\\s+)?$noun\\s+(?:off|down)\\b'
      '|^$noun\\s+(?:off|down)\\b',
    ).hasMatch(text)) {
      return const FlashlightIntent(on: false);
    }
    return null;
  }

  /// "open calculator", "launch the camera app".
  ///
  /// The app is resolved against what is *installed* at execution time, not
  /// against a hard-coded list: a fixed list would be wrong on most phones and
  /// would make "open the metro app" a supported command that lies.
  CommandIntent? _openApp(String text) {
    final RegExpMatch? m = RegExp(
      r'^(?:open|launch|start|run|load|bring up)\s+(?:the\s+|my\s+)?(.+?)'
      r'(?:\s+app)?$',
    ).firstMatch(text);
    if (m == null) return null;
    final String name = m.group(1)!.trim();
    if (name.isEmpty) return null;
    // "open the timer" / "start the alarm" are covered earlier, but a bare
    // "open volume settings" would land here and be opened as an app named
    // "volume settings", which is exactly the honest answer if no such app
    // exists.
    return OpenAppIntent(name);
  }

  CommandIntent? _battery(String text) {
    if (RegExp(r'\bbattery\b|\bcharge level\b|\bhow much (?:battery|charge|'
            r'power)\b|\bpower level\b|\bpercentage of (?:the )?battery\b')
        .hasMatch(text)) {
      return const BatteryIntent();
    }
    return null;
  }

  CommandIntent? _clock(String text) {
    if (RegExp(r'\b(?:what|whats|what s)(?: is| s)? the time\b|'
            r'\bwhat time is it\b|\bcurrent time\b|\btime is it\b|'
            r'\btell me the time\b|\bwhat is the time now\b')
        .hasMatch(text)) {
      return const TimeIntent();
    }
    return null;
  }

  CommandIntent? _date(String text) {
    if (RegExp(r'\b(?:what|whats|what s)(?: is| s)? the date\b|'
            r'\bwhat date is it\b|\bwhat day is (?:it|today)\b|'
            r'\btodays date\b|\bwhat is today\b|\btell me the date\b')
        .hasMatch(text)) {
      return const DateIntent();
    }
    return null;
  }

  CommandIntent? _timer(String text) {
    final bool asksForTimer = RegExp(
      r'\b(?:set\s+)?(?:a\s+|an\s+)?timer\b|\bremind me\b|'
      r'\bcountdown\b',
    ).hasMatch(text);
    if (!asksForTimer) return null;
    final Duration? duration = parseSpokenDuration(text);
    if (duration == null) return null;
    return SetTimerIntent(duration);
  }

  CommandIntent? _alarm(String text) {
    final bool asksForAlarm = RegExp(
      r'\bset\s+(?:an\s+|a\s+)?alarm\b|\bwake me(?:\s+up)?\b|'
      r'\balarm\s+(?:for|at)\b|\bset my alarm\b',
    ).hasMatch(text);
    if (!asksForAlarm) return null;

    // "wake me in 20 minutes" is a timer, and Android's own clock app agrees
    // (a timer survives being set for a duration; an alarm for one does not).
    final Duration? relative = parseSpokenDuration(text);
    if (relative != null && RegExp(r'\bin\s+\d|\bin\s+(?:a|an|one|two|three|'
            r'four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|'
            r'forty|fifty|ninety)\b')
        .hasMatch(text)) {
      return SetTimerIntent(relative);
    }

    final ({int hour, int minute, bool explicitMeridiem})? time =
        parseClockTime(text);
    if (time != null) {
      return SetAlarmIntent(
        hour: time.hour,
        minute: time.minute,
        explicitMeridiem: time.explicitMeridiem,
      );
    }

    // A bare hour: "set an alarm for seven" or "for 7". Only looked for here,
    // after a duration has already been ruled out -- otherwise "a timer for 5
    // minutes" would become an alarm at 05:00.
    final RegExpMatch? bare = RegExp(
      r'\b(?:at|for)\s+(\d{1,2})\b',
    ).firstMatch(text);
    if (bare != null) {
      final int hour = int.parse(bare.group(1)!);
      if (hour <= 23) {
        return SetAlarmIntent(hour: hour, minute: 0, explicitMeridiem: false);
      }
    }
    return null;
  }

  // -- Knowledge ------------------------------------------------------------

  /// "10 km in miles", "how many pounds in 5 kg", "72 f to c".
  ///
  /// Three phrasings, one result. Units are resolved by name; the conversion
  /// itself happens in the executor so a unit mismatch can be reported instead
  /// of crashing a conversion.
  CommandIntent? _convert(String text) {
    final List<RegExp> patterns = <RegExp>[
      RegExp(r'\bconvert\s+(-?\d+(?:\.\d+)?)\s*([a-z ]+?)\s+(?:to|into|in)\s+'
          r'([a-z ]+)$'),
      RegExp(r'\bhow many\s+([a-z ]+?)\s+(?:are\s+)?in\s+(-?\d+(?:\.\d+)?)\s*'
          r'([a-z ]+)$'),
      RegExp(r'^(-?\d+(?:\.\d+)?)\s*([a-z ]+?)\s+(?:to|in|into)\s+([a-z ]+)$'),
    ];

    for (int i = 0; i < patterns.length; i++) {
      final RegExpMatch? m = patterns[i].firstMatch(text);
      if (m == null) continue;

      final String numberText;
      final String fromText;
      final String toText;
      if (i == 1) {
        // "how many <to> in <number> <from>"
        toText = m.group(1)!;
        numberText = m.group(2)!;
        fromText = m.group(3)!;
      } else {
        numberText = m.group(1)!;
        fromText = m.group(2)!;
        toText = m.group(3)!;
      }

      final double? value = double.tryParse(numberText);
      final Unit? from = Units.resolve(fromText);
      final Unit? to = Units.resolve(toText);
      if (value == null || from == null || to == null) return null;
      return ConvertIntent(value: value, from: from, to: to);
    }
    return null;
  }

  /// Arithmetic, including the spoken operators and "15 percent of 240".
  CommandIntent? _calculate(String text) {
    // "what is 15 percent of 240" is a percentage question, not a sentence.
    final RegExpMatch? percent = RegExp(
      r'(-?\d+(?:\.\d+)?)\s*(?:percent|%)\s+of\s+(-?\d+(?:\.\d+)?)',
    ).firstMatch(text);
    if (percent != null) {
      final double p = double.parse(percent.group(1)!);
      final double whole = double.parse(percent.group(2)!);
      final double value = p / 100 * whole;
      return CalculateIntent(
        value: value,
        expression: '${_trim(p)}% of ${_trim(whole)}',
      );
    }

    final String symbolic = _mathToSymbols(text);
    if (!RegExp(r'^[\d\s.+\-*/%^()]+$').hasMatch(symbolic)) return null;
    if (!RegExp(r'\d').hasMatch(symbolic)) return null;
    // A single number is not a calculation ("what is 5" is a question).
    if (!RegExp(r'[+\-*/%^]').hasMatch(symbolic)) return null;

    final double? value = ExpressionEvaluator.tryEvaluate(symbolic);
    if (value == null || value.isNaN || value.isInfinite) return null;
    return CalculateIntent(value: value, expression: symbolic.trim());
  }

  /// "twelve times eight" -> "12 * 8", "5 plus 3" -> "5 + 3".
  String _mathToSymbols(String text) {
    String s = text
        .replaceAll(RegExp(r'^(?:what is|whats|what s|what|calculate|compute|'
            r'how much is|how much|tell me|equals?)\s+'), '')
        .replaceAll(RegExp(r'\b(?:multiplied by|times|multiply by|multiply)\b'),
            ' * ')
        .replaceAll(RegExp(r'\b(?:divided by|divide by|divide|over)\b'), ' / ')
        .replaceAll(RegExp(r'\b(?:plus|add)\b'), ' + ')
        .replaceAll(RegExp(r'\b(?:minus|take away|less)\b'), ' - ')
        .replaceAll(RegExp(r'\b(?:to the power of|power of|squared)\b'), ' ^ ')
        .replaceAll(RegExp(r'\b(?:x|into)\b'), ' * ')
        .replaceAll(RegExp(r'\bequals?\b'), ' ');

    // "one hundred and twenty" is one number, so the joiner is dropped before
    // the number-word run below sees it. ('and' was never mapped to '+' for
    // exactly this reason.)
    s = s.replaceAll(RegExp(r'\s+and\s+'), ' ');

    final List<String> tokens = s.split(RegExp(r'\s+'));
    final List<String> out = <String>[];
    final StringBuffer run = StringBuffer();

    void flushRun() {
      if (run.isEmpty) return;
      final int? n = parseSpokenInt(run.toString());
      out.add(n == null ? run.toString() : '$n');
      run.clear();
    }

    for (final String token in tokens) {
      if (token.isEmpty) continue;
      final bool isNumberWord = RegExp(
        r'^(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|'
        r'twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|'
        r'nineteen|twenty|thirty|forty|fourty|fifty|sixty|seventy|eighty|'
        r'ninety|hundred|thousand)$',
      ).hasMatch(token);
      if (isNumberWord) {
        if (run.isNotEmpty) run.write(' ');
        run.write(token);
        continue;
      }
      flushRun();
      out.add(token);
    }
    flushRun();
    return out.join(' ');
  }

  static String _trim(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  /// Contractions, expanded before anything else looks at the sentence, because
  /// "what's the time" and "what is the time" must reach the same pattern.
  static const Map<String, String> _contractions = <String, String>{
    "what's": 'what is',
    'whats': 'what is',
    "what’s": 'what is',
    "it's": 'it is',
    "that's": 'that is',
    "there's": 'there is',
    "i'm": 'i am',
    "i'd": 'i would',
    "i'll": 'i will',
    "let's": 'let us',
    "don't": 'do not',
    "doesn't": 'does not',
    "didn't": 'did not',
    "can't": 'can not',
    "cannot": 'can not',
    "won't": 'will not',
    "isn't": 'is not',
    "aren't": 'are not',
    "couldn't": 'could not',
    "wouldn't": 'would not',
    "you're": 'you are',
    "we're": 'we are',
    "they're": 'they are',
    "how's": 'how is',
    "where's": 'where is',
  };
}
