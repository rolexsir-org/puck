import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/data/models/context.dart';
import 'package:puck/src/domain/context_ranker.dart';

/// The tap card is deterministic and it is the highest-frequency surface in
/// the app, so its edge cases are worth locking down: an all-day entry is a
/// state, not an appointment with a countdown.
void main() {
  final DateTime now = DateTime(2026, 1, 15, 9);

  ContextItem rankWith(CalendarEvent? event) => ContextRanker.rank(
        ContextSnapshot(now: now, nextEvent: event),
      );

  CalendarEvent allDay({
    required String title,
    required DateTime start,
    required DateTime? end,
  }) =>
      CalendarEvent(
        title: title,
        start: start,
        end: end,
        allDay: true,
      );

  group('all-day events are states, not countdowns', () {
    test('an all-day entry that started at midnight is TODAY, not "9h ago"',
        () {
      final ContextItem item = rankWith(
        allDay(
          title: 'Birthday',
          start: DateTime(2026, 1, 15),
          end: DateTime(2026, 1, 16),
        ),
      );

      expect(item.label, 'TODAY');
      expect(item.headline, 'Birthday');
      expect(item.detail, 'All day');
      expect(item.headline, isNot(contains('started')));
    });

    test('a multi-day entry mid-flight is TODAY, not "2d ago"', () {
      final ContextItem item = rankWith(
        allDay(
          title: 'Trip',
          start: DateTime(2026, 1, 13),
          end: DateTime(2026, 1, 17),
        ),
      );

      expect(item.label, 'TODAY');
      expect(item.headline, 'Trip');
    });

    test('an inclusive end (some providers report one) still means TODAY', () {
      final ContextItem item = rankWith(
        allDay(
          title: 'Birthday',
          start: DateTime(2026, 1, 15),
          end: DateTime(2026, 1, 15, 23, 59),
        ),
      );

      expect(item.label, 'TODAY');
    });

    test('a finished all-day entry falls through instead of being announced',
        () {
      final ContextItem item = rankWith(
        allDay(
          title: 'Yesterday',
          start: DateTime(2026, 1, 14),
          end: DateTime(2026, 1, 15),
        ),
      );

      expect(item.kind, ContextKind.time);
      expect(item.headline, isNot(contains('Yesterday')));
    });

    test('tomorrow\'s all-day entry is not an interruption', () {
      final ContextItem item = rankWith(
        allDay(
          title: 'Birthday',
          start: DateTime(2026, 1, 16),
          end: DateTime(2026, 1, 17),
        ),
      );

      expect(item.kind, ContextKind.time);
    });

    test('a timed event that already started keeps its HAPPENING NOW line',
        () {
      final ContextItem item = rankWith(
        CalendarEvent(
          title: 'Standup',
          start: now.subtract(const Duration(hours: 1)),
          end: now.add(const Duration(minutes: 30)),
        ),
      );

      expect(item.label, 'HAPPENING NOW');
      expect(item.headline, contains('started'));
    });
  });

  group('priority order', () {
    test('an imminent meeting outranks a low battery', () {
      final ContextItem item = ContextRanker.rank(
        ContextSnapshot(
          now: now,
          nextEvent: CalendarEvent(
            title: 'Standup',
            start: now.add(const Duration(minutes: 10)),
          ),
          battery: const BatterySnapshot(level: 4, charging: false),
        ),
      );

      expect(item.kind, ContextKind.calendar);
    });

    test('a low battery outranks rain', () {
      final ContextItem item = ContextRanker.rank(
        ContextSnapshot(
          now: now,
          battery: const BatterySnapshot(level: 9, charging: false),
          weather: WeatherSnapshot(
            temperatureC: 11,
            code: 61,
            fetchedAt: now,
            hourly: <HourlyPoint>[
              HourlyPoint(
                time: now.add(const Duration(minutes: 30)),
                code: 61,
                precipProbability: 80,
              ),
            ],
          ),
        ),
      );

      expect(item.kind, ContextKind.battery);
    });
  });
}
