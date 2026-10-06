import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/data/llm/llm_provider.dart';
import 'package:puck/src/data/llm/local_fallback_provider.dart';
import 'package:puck/src/data/llm/prompt.dart';
import 'package:puck/src/domain/intent_router.dart';
import 'package:puck/src/domain/safety.dart';
import 'package:puck/src/l10n/puck_strings.dart';

// The assistant safety boundary, such as it is.
//
// The claim this file tests is narrow and checkable: a person who says they
// want to die gets one fixed, localized line instead of a language model's
// improvisation, and the question never reaches the network. It is
// deliberately not a claim to detect distress in general -- see `PuckSafety`
// and the FINDINGS.md entry on where this boundary was drawn and who has to
// move it next. (The paragraph above is prose about the file, not a doc
// comment on the fake below it.)

/// A provider that fails the test if it is called at all. "The question
/// never left the phone" is the actual requirement, so it is the assertion.
final class _Tripwire implements LlmProvider {
  bool called = false;

  @override
  String get id => 'tripwire';

  @override
  bool get isConfigured => true;

  @override
  Stream<String> complete(LlmRequest request) {
    called = true;
    return Stream<String>.value('Sure! Here is a helpful answer.');
  }
}

void main() {
  final PuckStrings en = PuckStrings.forLocale(const Locale('en'));
  final PuckStrings es = PuckStrings.forLocale(const Locale('es'));

  group('the phrases that are caught', () {
    const List<String> englishCrises = <String>[
      'I want to kill myself',
      'i want to die',
      'thinking about suicide',
      'I am having chest pain',
      "I can't breathe",
      'someone is following me',
    ];
    const List<String> spanishCrises = <String>[
      'quiero morir',
      'quiero matarme',
      'me duele el pecho, dolor en el pecho',
      'no puedo respirar',
      'me estan siguiendo',
      'me está atacando',
    ];

    for (final String phrase in <String>[...englishCrises, ...spanishCrises]) {
      test('"$phrase" is caught', () {
        expect(PuckSafety.isCrisis(phrase), isTrue);
      });
    }

    test('both languages are caught whatever the UI locale is', () {
      // Someone typing Spanish into an English phone is not a rare user; they
      // are a common one. The check does not trust the UI language.
      for (final String phrase in spanishCrises) {
        expect(PuckSafety.isCrisis(phrase, locale: const Locale('en')), isTrue);
      }
      for (final String phrase in englishCrises) {
        expect(PuckSafety.isCrisis(phrase, locale: const Locale('es')), isTrue);
      }
    });
  });

  group('the questions that are not', () {
    const List<String> ordinary = <String>[
      'flip a coin',
      'what is 47 times 83',
      'how do crisis lines work',
      'what time is it',
      'should I take an umbrella',
      'cuánto es 47 por 83',
      'lanza una moneda',
      'cómo funcionan las líneas de crisis',
    ];

    for (final String phrase in ordinary) {
      test('"$phrase" is left alone', () {
        expect(PuckSafety.isCrisis(phrase), isFalse);
      });
    }

    test('an empty or whitespace query is not a crisis', () {
      expect(PuckSafety.isCrisis(''), isFalse);
      expect(PuckSafety.isCrisis('   '), isFalse);
    });
  });

  group('the router', () {
    IntentRouter routerFor(_Tripwire tripwire, LocalIntentResolver local) =>
        IntentRouter(llm: tripwire, local: local);

    test('answers a crisis with the fixed line, and never asks the model',
        () async {
      final _Tripwire tripwire = _Tripwire();
      final LocalIntentResolver local = LocalIntentResolver();
      final IntentRouter router = routerFor(tripwire, local);

      final String answer =
          await router.resolve('I want to kill myself').join();

      expect(answer, en.safetyLine);
      expect(tripwire.called, isFalse,
          reason: 'the question must not leave the phone');
      // And the line is not a paraphrase: it is the string table's, verbatim.
      expect(answer.contains('I cannot help with this'), isTrue);
    });

    test('answers in the user\'s language', () async {
      final _Tripwire tripwire = _Tripwire();
      final LocalIntentResolver local =
          LocalIntentResolver(locale: const Locale('es'));
      final IntentRouter router = routerFor(tripwire, local);

      final String answer = await router.resolve('quiero morir').join();

      expect(answer, es.safetyLine);
      expect(answer, isNot(en.safetyLine));
      expect(tripwire.called, isFalse);
    });

    test('an ordinary question still reaches the resolver, then the model',
        () async {
      // The guard must not become a blanket "no". Coin and arithmetic keep
      // answering instantly and offline.
      final _Tripwire tripwire = _Tripwire();
      final IntentRouter router =
          routerFor(tripwire, LocalIntentResolver(locale: const Locale('en')));

      final String answer = await router.resolve('flip a coin').join();
      expect(<String>['Heads.', 'Tails.'], contains(answer));
      expect(tripwire.called, isFalse);
    });
  });
}
