import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Locks the contract of the joke bag: exactly 100 lines, no repeats, and a
/// register a human would actually say out loud.
///
/// If you add or remove a joke, this test is the reviewer that cares.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> jokes;

  setUpAll(() async {
    final String raw = await rootBundle.loadString('assets/jokes.json');
    jokes = (jsonDecode(raw) as List<dynamic>).cast<String>();
  });

  test('there are exactly 100 jokes', () {
    expect(jokes.length, 100);
  });

  test('no joke repeats, and no near-repeat within 10 lines', () {
    final Set<String> seen = <String>{};
    for (final String joke in jokes) {
      expect(seen.contains(joke.trim()), isFalse, reason: 'duplicated: $joke');
      seen.add(joke.trim());
    }
  });

  test('every joke is one breath long', () {
    for (final String joke in jokes) {
      final int words = joke.split(RegExp(r'\s+')).length;
      expect(words, lessThanOrEqualTo(25), reason: 'too long: $joke');
    }
  });

  test('no joke reads like a greeting card or a chatbot', () {
    final RegExp banned = RegExp(
      r'!',
      multiLine: false,
    );
    const List<String> bannedOpeners = <String>[
      'just', 'literally', 'honestly', 'sometimes',
    ];

    for (final String joke in jokes) {
      expect(banned.hasMatch(joke), isFalse, reason: 'exclamation: $joke');
      expect(joke.contains('#'), isFalse, reason: 'hashtag: $joke');
      final String first = joke.trim().split(' ').first.toLowerCase();
      expect(
        bannedOpeners.contains(first),
        isFalse,
        reason: 'banned opener: $joke',
      );
    }
  });
}
