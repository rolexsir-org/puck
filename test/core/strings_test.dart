import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:puck/src/l10n/puck_strings.dart';

/// The contract `flutter gen-l10n` would have enforced, enforced for real.
///
/// Puck does not generate code from ARB (see the note in `puck_strings.dart`),
/// so the ARB files under `lib/l10n/` and the maps in `lib/src/l10n/` are two
/// representations of the same thing. This test is what keeps them honest:
///
///   * every ARB file exists for a shipped locale, and no ARB file exists for a
///     locale that is not shipped,
///   * the key sets are identical in both directions, so a string can neither
///     be added to the UI without a translator seeing it nor be removed from
///     the UI while lingering in the translation,
///   * `%1`, `%2` placeholders survive translation -- a dropped placeholder is
///     a card that renders "in %1" to a real person,
///   * and no shipped locale is silently falling back to English for most of
///     its strings.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  Map<String, String> arb(String code) {
    final File file = File('lib/l10n/app_$code.arb');
    expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
    final Map<String, dynamic> json =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json.map<String, String>((String k, dynamic v) {
      if (k == '@@locale') return MapEntry<String, String>(k, '$v');
      return MapEntry<String, String>(k, '$v');
    });
  }

  Set<String> placeholders(String value) =>
      RegExp(r'%(\d)').allMatches(value).map((Match m) => m.group(1)!).toSet();

  test('every shipped locale has an ARB file, and nothing else does', () {
    final Set<String> shipped = PuckStrings.supportedLocales
        .map((Locale l) => l.languageCode)
        .toSet();

    final Set<String> onDisk = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where(
          (String name) => name.startsWith('app_') && name.endsWith('.arb'),
        )
        .map((String name) => name.substring(4, name.length - 4))
        .toSet();

    expect(onDisk, shipped);
  });

  for (final Locale locale in PuckStrings.supportedLocales) {
    final String code = locale.languageCode;

    test('$code: the ARB keys and the source strings agree', () {
      final Map<String, String> files = arb(code);
      final Map<String, String> source = code == 'en'
          ? PuckStrings.englishSource()
          : PuckStrings.translationsFor(code);

      final Set<String> arbKeys = files.keys.toSet()..remove('@@locale');
      final Set<String> dartKeys = source.keys.toSet();

      expect(
        dartKeys.difference(arbKeys),
        isEmpty,
        reason: 'in the app but not in the ARB file: translators cannot see '
            'these',
      );
      expect(
        arbKeys.difference(dartKeys),
        isEmpty,
        reason: 'in the ARB file but not in the app: these are dead strings',
      );
    });

    test('$code: every string matches its ARB value exactly', () {
      final Map<String, String> files = arb(code);
      final Map<String, String> source = code == 'en'
          ? PuckStrings.englishSource()
          : PuckStrings.translationsFor(code);

      for (final MapEntry<String, String> entry in source.entries) {
        expect(
          files[entry.key],
          entry.value,
          reason: 'lib/l10n/app_$code.arb has a stale value for ${entry.key}',
        );
      }
    });

    test('$code: no translation drops a placeholder', () {
      final Map<String, String> files = arb(code);
      final Map<String, String> source = code == 'en'
          ? PuckStrings.englishSource()
          : PuckStrings.translationsFor(code);

      for (final MapEntry<String, String> entry in source.entries) {
        expect(
          placeholders(files[entry.key] ?? ''),
          placeholders(entry.value),
          reason: '${entry.key} lost a placeholder in $code',
        );
      }
    });
  }

  test('English is complete, and the fallback is visible rather than silent',
      () {
    final PuckStrings en = PuckStrings.forLocale(const Locale('en'));
    expect(en.untranslatedKeys(), isEmpty);
    expect(en.isTranslated('bubbleLabel'), isTrue);

    // A language that is not shipped reads English, key by key: never a blank,
    // never a crash, and every key reported as untranslated.
    final PuckStrings de = PuckStrings.forLocale(const Locale('de'));
    expect(de.text('bubbleLabel'), en.text('bubbleLabel'));
    expect(de.isTranslated('bubbleLabel'), isFalse);
    expect(de.untranslatedKeys().length, PuckStrings.englishSource().length);
  });

  test('every key the code asks for exists in the map', () {
    // This is the test that would have caught the worst bug in this file's
    // history: `MessagingService` asked for `text('sosMessage')` and
    // `text('sosMessageNoLocation')` while neither key existed in the map, so
    // `text()` fell through to its last resort -- the key itself -- and the
    // emergency SMS went out reading "sosMessage / sosMessageNoLocation".
    //
    // The ARB parity test above cannot catch that: a key that is missing from
    // the map is missing from the ARB file too, and parity is satisfied. So
    // this test reads the class's own source and checks every literal key it
    // references against the English map.
    final String source = File('lib/src/l10n/puck_strings.dart')
        .readAsStringSync()
        // Comments mention keys (`text('...')` appears in the class doc), and a
        // scan that reads its own documentation as code reports a failure that
        // is not there. Only code lines are scanned.
        .split('\n')
        .where((String line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final Set<String> english = PuckStrings.englishSource().keys.toSet();

    final RegExp reference = RegExp(r"(?:text|format)\('([a-z][A-Za-z0-9]*)'");
    final Set<String> referenced = reference
        .allMatches(source)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();

    expect(referenced, isNotEmpty, reason: 'the scan found no keys at all -- '
        'the pattern or the file path changed, and this test is now blind');

    final List<String> missing = referenced
        .where((String key) => !english.contains(key))
        .toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'these keys are asked for but never defined, so the UI would '
          'show the raw key text',
    );
  });

  test('no value is empty, and no value is just its own key', () {
    for (final MapEntry<String, String> entry
        in PuckStrings.englishSource().entries) {
      expect(entry.value.trim(), isNotEmpty, reason: '${entry.key} is blank');
      expect(entry.value.trim(), isNot(entry.key), reason: entry.key);
    }
    for (final Locale locale in PuckStrings.supportedLocales) {
      for (final MapEntry<String, String> entry
          in PuckStrings.translationsFor(locale.languageCode).entries) {
        expect(entry.value.trim(), isNotEmpty,
            reason: '${entry.key} is blank in ${locale.languageCode}');
      }
    }
  });

  test('no shipped translation is mostly English', () {
    for (final Locale locale in PuckStrings.supportedLocales) {
      if (locale.languageCode == 'en') continue;
      final PuckStrings strings = PuckStrings.forLocale(locale);
      expect(
        strings.untranslatedKeys(),
        isEmpty,
        reason: 'a locale that ships with gaps shows a mix of two languages',
      );
    }
  });

  test('the numbers in a card follow the locale, not the source language', () {
    final PuckStrings en = PuckStrings.forLocale(const Locale('en'));
    final PuckStrings es = PuckStrings.forLocale(const Locale('es'));

    expect(es.countdown(const Duration(minutes: 12)),
        isNot(en.countdown(const Duration(minutes: 12))));
    expect(es.clock(DateTime(2026, 1, 15, 15, 14)), isNot('3:14 PM'));
    expect(
      es.stamp(DateTime(2026, 1, 15, 15, 14)),
      isNot(en.stamp(DateTime(2026, 1, 15, 15, 14))),
    );
  });
}
