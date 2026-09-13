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
