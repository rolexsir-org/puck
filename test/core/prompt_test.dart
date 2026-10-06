import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/data/llm/prompt.dart';

/// Three numbers used to disagree about how long an answer may be: the prompt
/// told the model 40 words, the clamp allowed 15, and the validator accepted
/// 17. These tests exist so they cannot drift apart again.
void main() {
  String words(int n) => List<String>.generate(n, (int i) => 'word').join(' ');

  group('one budget, three places', () {
    test('the prompt states the same limit the clamp enforces', () {
      final String intentPrompt =
          PuckPrompt.system(const LlmRequest(mode: PuckMode.intent));

      expect(PuckPrompt.wordLimitFor(PuckMode.intent), 15);
      expect(intentPrompt, contains('15 words maximum'));
      expect(intentPrompt, isNot(contains('40 words')));
    });

    test('the token cap follows the word budget rather than contradicting it',
        () {
      expect(PuckPrompt.maxTokensFor(PuckMode.intent),
          greaterThan(PuckPrompt.maxTokensFor(PuckMode.context)));
      expect(PuckPrompt.maxTokensFor(PuckMode.context), greaterThan(0));
    });

    test('the validator allows the budget plus a tolerance, no more', () {
      expect(
        PuckPrompt.isAcceptable(PuckMode.intent, words(15)),
        isTrue,
      );
      expect(
        PuckPrompt.isAcceptable(
          PuckMode.intent,
          words(15 + PuckPrompt.validationTolerance),
        ),
        isTrue,
      );
      expect(
        PuckPrompt.isAcceptable(
          PuckMode.intent,
          words(15 + PuckPrompt.validationTolerance + 1),
        ),
        isFalse,
      );
    });

    test('length is also bounded in characters, because one word can be huge',
        () {
      expect(
        PuckPrompt.isAcceptable(
          PuckMode.intent,
          'a' * (PuckPrompt.maxAnswerChars + 1),
        ),
        isFalse,
      );
    });
  });

  group('filler openers', () {
    test('are caught as complete words', () {
      expect(PuckPrompt.hasBannedOpening('Sure, the sky is blue'), isTrue);
      expect(PuckPrompt.hasBannedOpening('Certainly.'), isTrue);
      expect(PuckPrompt.hasBannedOpening("Here's the answer"), isTrue);
      expect(PuckPrompt.hasBannedOpening('Mode: INTENT'), isTrue);
    });

    test('do not swallow words that merely start the same way', () {
      expect(PuckPrompt.hasBannedOpening('Surely the sky is blue'), isFalse);
      expect(PuckPrompt.hasBannedOpening('Sufficiently warm'), isFalse);
      expect(PuckPrompt.hasBannedOpening('Hereford is in England'), isFalse);
    });

    test('a clean answer is acceptable and an empty one is not', () {
      expect(PuckPrompt.isAcceptable(PuckMode.intent, 'Blue light scatters.'),
          isTrue);
      expect(PuckPrompt.isAcceptable(PuckMode.intent, '   '), isFalse);
      expect(PuckPrompt.isAcceptable(PuckMode.intent, 'Sure, blue.'), isFalse);
    });
  });
}
