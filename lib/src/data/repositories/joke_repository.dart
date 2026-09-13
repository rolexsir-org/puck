import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:puck/src/data/repositories/settings_repository.dart';

enum JokeKind { joke, quote }

class Joke {
  const Joke({required this.text, required this.kind});

  final String text;
  final JokeKind kind;

  factory Joke.fromJson(Map<String, dynamic> json) => Joke(
        text: (json['text'] as String? ?? '').trim(),
        kind: (json['kind'] as String?) == 'quote'
            ? JokeKind.quote
            : JokeKind.joke,
      );
}

/// Serves jokes from a shuffle bag rather than `random()`.
///
/// Plain randomness gives users the same line twice in a row about 1% of the
/// time, which reads as broken. A shuffle bag guarantees you see every joke
/// before any repeat, and the bag order is persisted across sessions.
class JokeRepository {
  JokeRepository(this._settings, {math.Random? random})
      : _rng = random ?? math.Random();

  static const String _asset = 'assets/jokes.json';

  final SettingsRepository _settings;
  final math.Random _rng;

  List<Joke> _jokes = const <Joke>[];
  List<int> _bag = const <int>[];
  int _cursor = 0;

  bool get isLoaded => _jokes.isNotEmpty;
  int get count => _jokes.length;

  Future<void> load() async {
    if (_jokes.isNotEmpty) return;
    try {
      final String raw = await rootBundle.loadString(_asset);
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      _jokes = decoded
          .whereType<Map<String, dynamic>>()
          .map(Joke.fromJson)
          .where((Joke j) => j.text.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      _jokes = _builtInFallback;
    }

    _bag = _settings.jokeOrder ?? _freshBag();
    if (_bag.length != _jokes.length) _bag = _freshBag();
    _cursor = _settings.jokeIndex.clamp(0, math.max(0, _bag.length - 1));
  }

  List<int> _freshBag() {
    final List<int> bag = List<int>.generate(_jokes.length, (int i) => i);
    bag.shuffle(_rng);
    return bag;
  }

  Joke next() {
    if (_jokes.isEmpty) {
      return const Joke(text: 'Out of jokes. Imagine one instead.', kind: JokeKind.joke);
    }

    if (_cursor >= _bag.length) {
      _bag = _freshBag();
      _cursor = 0;
    }

    final Joke joke = _jokes[_bag[_cursor]];
    _cursor++;

    // Fire-and-forget persistence; a lost cursor costs nothing.
    _settings.setJokeIndex(_cursor);
    _settings.setJokeOrder(_bag);

    return joke;
  }

  static const List<Joke> _builtInFallback = <Joke>[
    Joke(text: 'My humour module failed to load. The irony is noted.', kind: JokeKind.joke),
    Joke(text: 'Do one thing every day that scares you. Mine is the electricity bill.', kind: JokeKind.quote),
  ];
}
