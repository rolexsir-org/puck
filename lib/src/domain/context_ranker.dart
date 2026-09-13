import 'package:puck/src/core/format.dart';
import 'package:puck/src/data/models/context.dart';

/// Decides the ONE thing worth saying.
///
/// This is the whole product, compressed into a priority list. A context card
/// that shows three facts is a dashboard; Puck shows one or says nothing.
///
/// Ranking is by *actionability* -- would knowing this change what you do in
/// the next hour?
abstract final class ContextRanker {
  /// An event inside this window is worth interrupting someone for.
  static const Duration meetingWindow = Duration(minutes: 60);

  /// ...but only warn about rain a few hours out. A 14-hour forecast is
  /// trivia.
  static const Duration rainWindow = Duration(hours: 4);

  static const int lowBatteryThreshold = 20;

  static ContextItem rank(ContextSnapshot snap) {
    final DateTime now = snap.now;
    final ContextItem? item = _calendar(snap, now) ?? //
        _battery(snap) ??
        _weather(snap, now);
    return item ?? timeOfDay(now);
  }

  // -- Candidates, in descending order of urgency --------------------------

  static ContextItem? _calendar(ContextSnapshot snap, DateTime now) {
    final CalendarEvent? e = snap.nextEvent;
    if (e == null) return null;

    final Duration until = e.until(now);

    // Already started: tell them, briefly, then get out of the way.
    if (until <= Duration.zero) {
      final String late = PuckFormat.countdown(until.abs());
      return ContextItem(
        kind: ContextKind.calendar,
        label: 'HAPPENING NOW',
        headline: '${e.title} started $late ago',
        detail: e.subtitle,
      );
    }

    if (until > meetingWindow) return null;

    if (e.allDay) {
      return ContextItem(
        kind: ContextKind.calendar,
        label: 'TODAY',
        headline: e.title,
        detail: 'All day',
      );
    }

    return ContextItem(
      kind: ContextKind.calendar,
      label: 'NEXT UP',
      headline: '${e.title} ${PuckFormat.countdown(until)}',
      detail: e.subtitle,
    );
  }

  static ContextItem? _battery(ContextSnapshot snap) {
    final BatterySnapshot? b = snap.battery;
    if (b == null) return null;

    if (!b.charging && b.level <= lowBatteryThreshold) {
      return ContextItem(
        kind: ContextKind.battery,
        label: 'BATTERY',
        headline: b.level <= 8
            ? '${b.level}% — find a cable now'
            : '${b.level}% — charge before you leave',
      );
    }

    if (b.charging && b.level >= 95) {
      return ContextItem(
        kind: ContextKind.battery,
        label: 'BATTERY',
        headline: 'Charged to ${b.level}%',
      );
    }

    return null;
  }

  static ContextItem? _weather(ContextSnapshot snap, DateTime now) {
    final WeatherSnapshot? w = snap.weather;
    if (w == null) return null;

    final HourlyPoint? rain = w.rainStartingWithin(rainWindow);
    if (rain != null) {
      final Duration until = rain.time.difference(w.fetchedAt);
      return ContextItem(
        kind: ContextKind.weather,
        label: 'WEATHER',
        headline: until < const Duration(minutes: 45)
            ? 'Rain starting ${PuckFormat.countdown(until)} — take an umbrella'
            : 'Rain at ${PuckFormat.clock(rain.time)} — take an umbrella',
        detail: '${WeatherCodes.describe(w.code)} · ${w.temperatureC.round()}°',
      );
    }

    // Cold enough that leaving without a layer was a mistake.
    if (w.temperatureC <= 3) {
      return ContextItem(
        kind: ContextKind.weather,
        label: 'WEATHER',
        headline: '${w.temperatureC.round()}° outside — wear a jacket',
        detail: WeatherCodes.describe(w.code),
      );
    }

    if (w.temperatureC >= 38) {
      return ContextItem(
        kind: ContextKind.weather,
        label: 'WEATHER',
        headline: '${w.temperatureC.round()}° outside — carry water',
        detail: WeatherCodes.describe(w.code),
      );
    }

    return null;
  }

  // -- Fallback ------------------------------------------------------------

  /// No urgent signal. The guaranteed answer to a tap: the time, and a line
  /// that reads like a person wrote it. This paints before any await runs,
  /// so a tap is never answered with a spinner.
  static ContextItem timeOfDay(DateTime now) {
    final int h = now.hour;
    final String clock = PuckFormat.clock(now);

    if (h < 5) {
      return ContextItem(
        kind: ContextKind.time,
        label: clock,
        headline: 'Nothing urgent. Sleep is also a plan.',
      );
    }

    if (h < 11) {
      return ContextItem(
        kind: ContextKind.time,
        label: 'GOOD MORNING',
        headline: '$clock — clear ahead.',
      );
    }

    if (h < 17) {
      return ContextItem(
        kind: ContextKind.time,
        label: 'GOOD AFTERNOON',
        headline: '$clock — nothing needs you right now.',
      );
    }

    if (h < 22) {
      return ContextItem(
        kind: ContextKind.time,
        label: 'GOOD EVENING',
        headline: '$clock — nothing needs you right now.',
      );
    }

    return ContextItem(
      kind: ContextKind.time,
      label: clock,
      headline: 'Nothing urgent. Tomorrow is already queueing.',
    );
  }
}
