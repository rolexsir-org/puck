import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/data/llm/local_fallback_provider.dart';

void main() {
  final LocalIntentResolver resolver = LocalIntentResolver();

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
      expect(resolver.tryResolve('I could take the bus or I could walk'), isNull);
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
    expect(LocalIntentResolver.offlineLine, 'Offline. Try coin, dice, or maths.');
    expect(resolver.offline(), LocalIntentResolver.offlineLine);
  });
}
