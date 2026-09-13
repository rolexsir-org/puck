import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/core/expression.dart';

void main() {
  group('ExpressionEvaluator.evaluate', () {
    test('handles the four basic operators', () {
      expect(ExpressionEvaluator.evaluate('2+3'), 5.0);
      expect(ExpressionEvaluator.evaluate('10-4'), 6.0);
      expect(ExpressionEvaluator.evaluate('3*4'), 12.0);
      expect(ExpressionEvaluator.evaluate('12/4'), 3.0);
    });

    test('respects precedence and parentheses', () {
      // Without precedence this would be 20.
      expect(ExpressionEvaluator.evaluate('2+3*4'), 14.0);
      expect(ExpressionEvaluator.evaluate('(2+3)*4'), 20.0);
    });

    test('handles unary minus', () {
      expect(ExpressionEvaluator.evaluate('-5+2'), -3.0);
      expect(ExpressionEvaluator.evaluate('-(2+3)'), -5.0);
      expect(ExpressionEvaluator.evaluate('+7'), 7.0);
    });

    test('power is right-associative', () {
      // 2^(3^2) = 512, not (2^3)^2 = 64.
      expect(ExpressionEvaluator.evaluate('2^3^2'), 512.0);
    });

    test('modulo', () {
      expect(ExpressionEvaluator.evaluate('7%3'), 1.0);
    });

    test('ignores whitespace', () {
      expect(ExpressionEvaluator.evaluate('  2 +  3 '), 5.0);
    });

    test('decimals', () {
      expect(ExpressionEvaluator.evaluate('1.5*2'), 3.0);
    });
  });

  group('error handling', () {
    test('division by zero throws ExpressionError', () {
      expect(
        () => ExpressionEvaluator.evaluate('1/0'),
        throwsA(isA<ExpressionError>()),
      );
    });

    test('modulo by zero throws ExpressionError', () {
      expect(
        () => ExpressionEvaluator.evaluate('1%0'),
        throwsA(isA<ExpressionError>()),
      );
    });

    test('unbalanced parentheses throw', () {
      expect(
        () => ExpressionEvaluator.evaluate('(2+3'),
        throwsA(isA<ExpressionError>()),
      );
    });

    test('trailing junk throws', () {
      expect(
        () => ExpressionEvaluator.evaluate('2+3)'),
        throwsA(isA<ExpressionError>()),
      );
    });

    test('non-numeric input throws', () {
      expect(
        () => ExpressionEvaluator.evaluate('abc'),
        throwsA(isA<ExpressionError>()),
      );
    });
  });

  group('tryEvaluate', () {
    test('returns a value for valid input', () {
      expect(ExpressionEvaluator.tryEvaluate('2+2'), 4.0);
    });

    test('returns null instead of throwing', () {
      expect(ExpressionEvaluator.tryEvaluate('1/0'), isNull);
      expect(ExpressionEvaluator.tryEvaluate('(2+3'), isNull);
      expect(ExpressionEvaluator.tryEvaluate('abc'), isNull);
    });
  });

  group('looksLikeMaths', () {
    test('accepts arithmetic', () {
      expect(ExpressionEvaluator.looksLikeMaths('2+2'), isTrue);
      expect(ExpressionEvaluator.looksLikeMaths('40 * (3 - 1)'), isTrue);
    });

    test('rejects prose, even prose containing digits', () {
      expect(ExpressionEvaluator.looksLikeMaths(''), isFalse);
      expect(ExpressionEvaluator.looksLikeMaths('hello'), isFalse);
      expect(ExpressionEvaluator.looksLikeMaths('what is 2+2'), isFalse);
    });
  });
}
