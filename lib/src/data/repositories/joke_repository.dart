import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:puck/src/data/repositories/settings_repository.dart';

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

  List<String> _jokes = const <String>[];
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
          .map((dynamic e) => (e as String? ?? '').trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      // The asset ships inside the binary; this path exists so a corrupted
      // build degrades to "no joke" instead of a red screen. next() returns
      // null and the double-tap simply shows nothing.
      _jokes = const <String>[];
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

  /// The next line, or null if the bag could not be loaded. Null is rare
  /// enough (it means a broken build) that showing nothing beats showing a
  /// fabricated excuse.
  String? next() {
    if (_jokes.isEmpty) return null;

    if (_cursor >= _bag.length) {
      _bag = _freshBag();
      _cursor = 0;
    }

    final String joke = _jokes[_bag[_cursor]];
    _cursor++;

    // Fire-and-forget persistence; a lost cursor costs nothing.
    _settings.setJokeIndex(_cursor);
    _settings.setJokeOrder(_bag);

    return joke;
  }
}
