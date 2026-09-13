/// A tiny recursive-descent arithmetic evaluator.
///
/// Supports: + - * / % ^ ( ) unary minus, and decimal literals.
///
/// Written by hand rather than pulled from a package because the entire
/// grammar is 70 lines and any expression library would drag in more than
/// that in transitive dependencies. Also: no `dart:math` eval, no codegen.
class ExpressionError implements Exception {
  const ExpressionError(this.message);
  final String message;

  @override
  String toString() => 'ExpressionError: $message';
}

class ExpressionEvaluator {
  const ExpressionEvaluator._();

  static double evaluate(String source) {
    final _Parser p = _Parser(source);
    final double value = p.parseExpression();
    p.skipWhitespace();
    if (!p.isAtEnd) {
      throw const ExpressionError('unexpected trailing input');
    }
    return value;
  }

  /// Returns null instead of throwing -- used for "is this even maths?" probes.
  static double? tryEvaluate(String source) {
    try {
      return evaluate(source);
    } on ExpressionError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static bool looksLikeMaths(String source) {
    final String s = source.trim();
    if (s.isEmpty) return false;
    if (!RegExp(r'[0-9]').hasMatch(s)) return false;
    return RegExp(r'^[0-9\.\s\+\-\*\/\%\^\(\)]+$').hasMatch(s);
  }
}

class _Parser {
  _Parser(this._src);

  final String _src;
  int _pos = 0;

  bool get isAtEnd => _pos >= _src.length;

  void skipWhitespace() {
    while (!isAtEnd && (_src[_pos] == ' ' || _src[_pos] == '\t')) {
      _pos++;
    }
  }

  bool _take(String ch) {
    skipWhitespace();
    if (isAtEnd || _src[_pos] != ch) return false;
    _pos++;
    return true;
  }

  double parseExpression() {
    double value = parseTerm();
    for (;;) {
      if (_take('+')) {
        value += parseTerm();
      } else if (_take('-')) {
        value -= parseTerm();
      } else {
        return value;
      }
    }
  }

  double parseTerm() {
    double value = parsePower();
    for (;;) {
      if (_take('*')) {
        value *= parsePower();
      } else if (_take('/')) {
        final double d = parsePower();
        if (d == 0) throw const ExpressionError('division by zero');
        value /= d;
      } else if (_take('%')) {
        final double d = parsePower();
        if (d == 0) throw const ExpressionError('modulo by zero');
        value %= d;
      } else {
        return value;
      }
    }
  }

  double parsePower() {
    final double base = parseUnary();
    if (_take('^')) {
      final double exp = parsePower(); // right-associative
      return _pow(base, exp);
    }
    return base;
  }

  double parseUnary() {
    skipWhitespace();
    if (_take('-')) return -parseUnary();
    if (_take('+')) return parseUnary();
    return parsePrimary();
  }

  double parsePrimary() {
    skipWhitespace();
    if (isAtEnd) throw const ExpressionError('unexpected end');

    if (_take('(')) {
      final double value = parseExpression();
      if (!_take(')')) throw const ExpressionError('missing closing paren');
      return value;
    }

    final int start = _pos;
    while (!isAtEnd &&
        ((_src.codeUnitAt(_pos) >= 48 && _src.codeUnitAt(_pos) <= 57) ||
            _src[_pos] == '.')) {
      _pos++;
    }
    if (start == _pos) {
      throw ExpressionError('unexpected "${_src[_pos]}"');
    }
    final double? value = double.tryParse(_src.substring(start, _pos));
    if (value == null) {
      throw const ExpressionError('bad number');
    }
    return value;
  }

  static double _pow(double base, double exp) {
    if (exp == exp.roundToDouble() && exp.abs() < 1e9) {
      final int n = exp.toInt();
      if (n >= 0) {
        double r = 1;
        for (int i = 0; i < n; i++) {
          r *= base;
        }
        return r;
      }
      double r = 1;
      for (int i = 0; i < -n; i++) {
        r *= base;
      }
      return 1 / r;
    }
    throw const ExpressionError('unsupported exponent');
  }
}
