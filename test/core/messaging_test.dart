import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:puck/src/data/services/messaging_service.dart';
import 'package:puck/src/l10n/puck_strings.dart';

void main() {
  final PuckStrings en = PuckStrings.forLocale(const Locale('en'));

  // Non-English date formatting needs the ICU tables loaded; the app does this
  // in main(), the tests do it here.
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('the emergency SMS body', () {
    test('reads like a person, in the order a person asks', () {
      final String body = MessagingService.buildSosBody(
        latitude: 34.052234,
        longitude: -118.243685,
        accuracy: 12,
        at: DateTime(2026, 1, 15, 15, 14),
        strings: en,
      );

      expect(
        body,
        'I need help.\n'
        '34.0522°N, 118.2437°W (±12m)\n'
        'maps.google.com/?q=34.0522,-118.2437\n'
        '3:14 PM · Thu Jan 15',
      );
    });

    test('without a GPS fix, it says so instead of inventing coordinates', () {
      final String body = MessagingService.buildSosBody(
        latitude: null,
        longitude: null,
        accuracy: null,
        at: DateTime(2026, 1, 15, 15, 14),
        strings: en,
      );

      expect(body, startsWith('I need help.\nLocation unavailable'));
      expect(body.contains('maps.google.com'), isFalse);
      expect(body.endsWith('3:14 PM · Thu Jan 15'), isTrue);
    });

    test('is written in the sender\'s language, not the app\'s source', () {
      // The recipient of an SOS is very often not a reader of English either.
      // A message that arrives in a language the person on the other end
      // cannot read is a message that did not arrive.
      final PuckStrings es = PuckStrings.forLocale(const Locale('es'));
      final String body = MessagingService.buildSosBody(
        latitude: null,
        longitude: null,
        accuracy: null,
        at: DateTime(2026, 1, 15, 15, 14),
        strings: es,
      );

      expect(body, startsWith(es.sosMessage));
      expect(body, contains(es.sosMessageNoLocation));
      expect(body, isNot(contains('I need help')));
    });
  });
}
