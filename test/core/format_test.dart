import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/core/format.dart';

void main() {
  group('PuckFormat.clock', () {
    test('drops :00 and uses 12-hour time', () {
      expect(PuckFormat.clock(DateTime(2026, 1, 1, 15)), '3 PM');
      expect(PuckFormat.clock(DateTime(2026, 1, 1, 9)), '9 AM');
    });

    test('pads minutes', () {
      expect(PuckFormat.clock(DateTime(2026, 1, 1, 15, 7)), '3:07 PM');
    });

    test('midnight and noon are 12, not 0', () {
      expect(PuckFormat.clock(DateTime(2026, 1, 1, 0)), '12 AM');
      expect(PuckFormat.clock(DateTime(2026, 1, 1, 12)), '12 PM');
    });
  });

  group('PuckFormat.countdown', () {
    test('zero and negative are "now"', () {
      expect(PuckFormat.countdown(Duration.zero), 'now');
      expect(PuckFormat.countdown(const Duration(seconds: -30)), 'now');
    });

    test('picks the coarsest useful unit', () {
      expect(PuckFormat.countdown(const Duration(seconds: 45)), 'in 45s');
      expect(PuckFormat.countdown(const Duration(minutes: 12)), 'in 12m');
      expect(PuckFormat.countdown(const Duration(days: 3)), 'in 3d');
    });

    test('combines hours and minutes only when minutes remain', () {
      expect(
        PuckFormat.countdown(const Duration(hours: 1, minutes: 5)),
        'in 1h 5m',
      );
      expect(PuckFormat.countdown(const Duration(hours: 2)), 'in 2h');
    });
  });

  group('PuckFormat.relativeDay', () {
    // Anchored on 13 Sep 2026.
    final DateTime now = DateTime(2026, 9, 13, 18, 42);

    test('names today, tomorrow and yesterday', () {
      expect(PuckFormat.relativeDay(DateTime(2026, 9, 13, 1), now), 'today');
      expect(
        PuckFormat.relativeDay(DateTime(2026, 9, 14, 23), now),
        'tomorrow',
      );
      expect(
        PuckFormat.relativeDay(DateTime(2026, 9, 12, 23), now),
        'yesterday',
      );
    });

    test('counts beyond that', () {
      expect(PuckFormat.relativeDay(DateTime(2026, 9, 16), now), 'in 3d');
      expect(PuckFormat.relativeDay(DateTime(2026, 9, 10), now), '3d ago');
    });

    test('compares calendar days, not 24-hour windows', () {
      // 23:59 today is still "today"; 00:01 tomorrow is "tomorrow".
      expect(
        PuckFormat.relativeDay(DateTime(2026, 9, 13, 23, 59), now),
        'today',
      );
      expect(
        PuckFormat.relativeDay(DateTime(2026, 9, 14, 0, 1), now),
        'tomorrow',
      );
    });
  });

  group('the emergency SMS body parts', () {
    test('coordinates read like a person reads them out loud', () {
      expect(
        PuckFormat.coordsDegrees(34.052234, -118.243685),
        '34.0522°N, 118.2437°W',
      );
      expect(
        PuckFormat.coordsDegrees(-33.8674, 151.2078),
        '33.8674°S, 151.2078°E',
      );
    });

    test('the map link is short and schemeless', () {
      expect(
        PuckFormat.coordsUrl(34.052234, -118.243685),
        'maps.google.com/?q=34.0522,-118.2437',
      );
    });

    test('accuracy is a delta, not a number', () {
      expect(PuckFormat.accuracy(-1), '');
      expect(PuckFormat.accuracy(12.4), '±12m');
      expect(PuckFormat.accuracy(1500), '±1.5km');
    });

    test('the stamp reads like a text message, not a log line', () {
      // Thursday 15 Jan 2026, 3:14 PM.
      expect(
        PuckFormat.stamp(DateTime(2026, 1, 15, 15, 14)),
        '3:14 PM · Thu Jan 15',
      );
    });
  });

  group('PuckFormat.clamp', () {
    test('bounds on both sides', () {
      expect(PuckFormat.clamp(5, 0, 10), 5.0);
      expect(PuckFormat.clamp(-1, 0, 10), 0.0);
      expect(PuckFormat.clamp(11, 0, 10), 10.0);
    });
  });
}
