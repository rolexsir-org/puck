import 'package:puck/src/core/format.dart';

/// Everything Puck knows about "right now", gathered in one pass.
///
/// Every field is nullable and every reader is allowed to fail: a locked-down
/// calendar or a denied location permission degrades Puck, it does not break it.
class ContextSnapshot {
  const ContextSnapshot({
    required this.now,
    this.battery,
    this.nextEvent,
    this.weather,
  });

  final DateTime now;
  final BatterySnapshot? battery;
  final CalendarEvent? nextEvent;
  final WeatherSnapshot? weather;
}

class BatterySnapshot {
  const BatterySnapshot({required this.level, required this.charging});

  /// 0..100
  final int level;
  final bool charging;
}

class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.start,
    this.end,
    this.location,
    this.allDay = false,
  });

  final String title;
  final DateTime start;
  final DateTime? end;
  final String? location;
  final bool allDay;

  bool isInProgress(DateTime now) => !start.isAfter(now);

  Duration until(DateTime now) => start.difference(now);

  /// Where or what -- trimmed to something that fits on one line.
  String? get subtitle {
    final String? loc = location?.trim();
    if (loc == null || loc.isEmpty) return null;
    return loc.length > 42 ? '${loc.substring(0, 41)}…' : loc;
  }
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.code,
    required this.hourly,
    required this.fetchedAt,
  });

  final double temperatureC;
  final int code;
  final List<HourlyPoint> hourly;
  final DateTime fetchedAt;

  /// First hour within [window] where rain is actually likely.
  ///
  /// "Likely" is >= 40% -- below that, telling someone to carry an umbrella is
  /// noise, not signal.
  HourlyPoint? rainStartingWithin(Duration window, {int threshold = 40}) {
    for (final HourlyPoint h in hourly) {
      if (h.time.isBefore(fetchedAt)) continue;
      if (h.time.difference(fetchedAt) > window) break;
      if (WeatherCodes.rain.contains(h.code) &&
          h.precipProbability >= threshold) {
        return h;
      }
    }
    return null;
  }
}

class HourlyPoint {
  const HourlyPoint({
    required this.time,
    required this.code,
    required this.precipProbability,
  });

  final DateTime time;
  final int code;
  final int precipProbability;
}

/// The single thing Puck decides to tell you.
class ContextItem {
  const ContextItem({
    required this.kind,
    required this.label,
    required this.headline,
    this.detail,
  });

  final ContextKind kind;
  final String label;
  final String headline;
  final String? detail;

  @override
  String toString() => '$label · $headline';
}

/// Drives the tiny glyph shown at the left of a context card.
enum ContextKind { calendar, battery, weather, time }
