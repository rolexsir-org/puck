import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:puck/src/data/llm/local_fallback_provider.dart';
import 'package:puck/src/l10n/puck_strings.dart';

void main() {
  // A resolver per language, because the patterns and the answers are both
  // per-language now. The first one is deliberately the default: a caller that
  // never sets a locale must still get English rather than nothing.
  final LocalIntentResolver resolver = LocalIntentResolver();
  final LocalIntentResolver es =
      LocalIntentResolver(locale: const Locale('es'));
  final PuckStrings esStrings = PuckStrings.forLocale(const Locale('es'));

  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('the same answers in Spanish', () {
    test('a coin flip answers in Spanish', () {
      // English patterns must not match for an es locale, and the answer text
      // must not be English either -- both halves are the assertion.
      for (int i = 0; i < 20; i++) {
        final String? out = es.tryResolve('lanza una moneda');
        expect(out, anyOf(esStrings.coinHeads, esStrings.coinTails));
      }
    });

    test('a die roll answers in Spanish', () {
      for (int i = 0; i < 20; i++) {
        expect(es.tryResolve('tira los dados'), matches(RegExp(r'^[1-6]\.$')));
      }
    });

    test('the time and the date answer in Spanish, from the locale tables',
        () {
      expect(es.tryResolve('qué hora es'), isNotNull);
      expect(es.tryResolve('¿qué hora es?'), isNotNull);
      expect(es.tryResolve('la hora'), isNotNull);

      final String? date = es.tryResolve('qué día es hoy');
      expect(date, isNotNull);
      // Shape, not an exact string: the answer is "jueves, 15:14 · jue, 15
      // ene", and asserting the clock would flake on a minute boundary.
      expect(date, matches(RegExp(r'^\S+, \d{1,2}:\d{2} · .+\.$')));
      // A Spanish date does not contain an English weekday or month name.
      for (final String english in <String>[
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ]) {
        expect(date, isNot(contains(english)), reason: english);
      }
      // And it is not the English path in disguise: the English answer is
      // built by `PuckFormat` and always ends its clock in " AM"/" PM",
      // while the Spanish one goes through `intl`'s 24-hour format. Checked
      // with the markers rather than by comparing substrings, which would
      // collide on a clock like 13:14.
      expect(date, isNot(contains(' AM')));
      expect(date, isNot(contains(' PM')));
    });

    test('spoken arithmetic works in Spanish, including the operator words',
        () {
      expect(es.tryResolve('cuánto es 47 por 83'), '3901.');
      expect(es.tryResolve('¿cuánto es 12 más 4?'), '16.');
      expect(es.tryResolve('20 menos 6'), '14.');
      expect(es.tryResolve('100 dividido por 8'), '12.5.');
      expect(es.tryResolve('100 entre 8'), '12.5.');
      expect(es.tryResolve('7 multiplicado por 6'), '42.');
      // Symbols are language-neutral, so these must work in every locale.
      expect(es.tryResolve('47*83'), '3901.');
    });

    test('this-or-that understands the Spanish conjunction', () {
      // "té o café" is the Spanish tea-or-coffee. Splitting only on `or` meant
      // every Spanish either/or was answered by the model or not at all.
      for (int i = 0; i < 20; i++) {
        final String? out = es.tryResolve('té o café');
        expect(out, anyOf('té.', 'café.'));
      }
      // "u" is Spanish's `or` before an o- sound.
      for (int i = 0; i < 20; i++) {
        final String? out = es.tryResolve('siete u ocho');
        expect(out, anyOf('siete.', 'ocho.'));
      }
    });

    test('a Spanish question the resolver does not know stays unanswered', () {
      // Not a wrong answer, not an English answer: no answer, so the router
      // can ask the model or say the one honest offline line.
      expect(es.tryResolve('por qué el cielo es azul'), isNull);
      expect(es.tryResolve('hola'), isNull);
    });
  });

  group('language fallthrough', () {
    test('a language Puck does not ship matches nothing', () {
      // The bug this pins: `_patterns` ended `return table['en']`, so a phone
      // whose locale was German got English pattern matching while the class
      // comment promised the opposite. Silent, confident, and wrong.
      final LocalIntentResolver de =
          LocalIntentResolver(locale: const Locale('de'));
      expect(de.tryResolve('flip a coin'), isNull);
      expect(de.tryResolve('what time is it'), isNull);
      expect(de.tryResolve('roll a dice'), isNull);
      // Symbols carry no language, so arithmetic still works.
      expect(de.tryResolve('47*83'), '3901.');
      // And the offline line is still a line, in the English fallback the UI
      // is using on that phone.
      expect(
        de.offline(),
        PuckStrings.forLocale(const Locale('de')).offlineLine,
      );
    });

    test('Spanish does not match English keywords', () {
      expect(es.tryResolve('flip a coin'), isNull);
      expect(es.tryResolve('what time is it'), isNull);
      expect(es.tryResolve('roll a dice'), isNull);
    });

    test('English does not match Spanish keywords', () {
      expect(resolver.tryResolve('lanza una moneda'), isNull);
      expect(resolver.tryResolve('qué hora es'), isNull);
      expect(es.tryResolve('tira los dados'), isNotNull);
    });

    test('setLocale changes both the patterns and the answers', () {
      final LocalIntentResolver r = LocalIntentResolver();
      expect(r.tryResolve('lanza una moneda'), isNull);

      r.setLocale(const Locale('es'));
      expect(r.tryResolve('lanza una moneda'), isNotNull);
      expect(r.tryResolve('flip a coin'), isNull);

      // The offline line follows the locale too: it is the one sentence a
      // user sees when nothing else can answer.
      expect(r.offline(), esStrings.offlineLine);
      expect(r.keyRejected(), esStrings.answerKeyRejected);
      expect(r.safety(), esStrings.safetyLine);
    });

    test('a regioned locale uses its language, not its region', () {
      final LocalIntentResolver mx =
          LocalIntentResolver(locale: const Locale('es', 'MX'));
      expect(mx.tryResolve('lanza una moneda'), isNotNull);
    });
  });

  group('deterministic local answers', () {
    test('a coin flip is Heads or Tails, with a full stop', () {
      for (int i = 0; i < 20; i++) {
        final String? out = resolver.tryResolve('flip a coin');
        expect(out, anyOf('Heads.', 'Tails.'));
      }
    });

    test('a die roll is 1 to 6', () {
      for (int i = 0; i < 20; i++) {
        final String? out = resolver.tryResolve('roll a dice');
        expect(out, matches(RegExp(r'^[1-6]\.$')));
      }
    });

    test('typed arithmetic is exact', () {
      expect(resolver.tryResolve('47*83'), '3901.');
      expect(resolver.tryResolve('12/4'), '3.');
      expect(resolver.tryResolve('2+3*4'), '14.');
    });

    test("spoken arithmetic is exact -- 'what's 47 times 83'", () {
      expect(resolver.tryResolve("what's 47 times 83"), '3901.');
      expect(resolver.tryResolve('what is 9 plus 10'), '19.');
      expect(resolver.tryResolve('15 minus 6'), '9.');
      expect(resolver.tryResolve('100 divided by 8'), '12.5.');
      expect(resolver.tryResolve('6x7'), '42.');
    });

    test('this-or-that picks one of the two options', () {
      for (int i = 0; i < 20; i++) {
        final String? out = resolver.tryResolve('tea or coffee');
        expect(out, anyOf('tea.', 'coffee.'));
      }
    });

    test('this-or-that declines anything that is not an either/or', () {
      // "tea or coffee or tea" used to be answered with "coffee or tea." --
      // a confident reply to a question nobody asked.
      expect(resolver.tryResolve('tea or coffee or tea'), isNull);
      expect(
        resolver.tryResolve('I could take the bus or I could walk'),
        isNull,
      );
      expect(resolver.tryResolve('3 or 4'), isNull);
    });

    test('this-or-that still answers the plain question', () {
      for (final String q in <String>[
        'tea or coffee',
        'should I get tea or coffee?',
        'pick cats or dogs',
      ]) {
        final String? out = resolver.tryResolve(q);
        expect(out, isNotNull, reason: q);
        expect(out, endsWith('.'));
      }
    });

    test('a keyword inside a question is not a request for the time or date',
        () {
      // "when is my birthday" matched a bare "day" and answered with today's
      // date. A wrong answer delivered without hesitation is the worst output
      // this app can produce.
      expect(resolver.tryResolve('when is my birthday'), isNull);
      expect(resolver.tryResolve('what day should I book'), isNull);
      expect(resolver.tryResolve('how is your day'), isNull);
      expect(resolver.tryResolve('time to sleep?'), isNull);
    });

    test('the actual time and date questions still answer', () {
      expect(resolver.tryResolve('what time is it'), isNotNull);
      expect(resolver.tryResolve("what's the time"), isNotNull);
      expect(resolver.tryResolve('what day is it'), isNotNull);
      expect(resolver.tryResolve('date'), isNotNull);
    });

    test('nothing to say stays null', () {
      expect(resolver.tryResolve('why is the sky blue'), isNull);
      expect(resolver.tryResolve('hello'), isNull);
      expect(resolver.tryResolve(''), isNull);
    });
  });

  test('the offline line is the offline line', () {
    expect(
      LocalIntentResolver.offlineLine,
      'Offline. Try coin, dice, or maths.',
    );
    expect(resolver.offline(), LocalIntentResolver.offlineLine);
  });
}
