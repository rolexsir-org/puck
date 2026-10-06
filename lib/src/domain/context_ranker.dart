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

    // All-day entries are handled before anything measures a duration,
    // because a duration is the wrong unit for them. An all-day "Birthday"
    // that began at midnight is not "started 9h ago", and a three-day trip is
    // not "started 2d ago" -- both read as bugs, and both used to happen here
    // because the `until <= 0` branch ran first and an all-day event always
    // has `until <= 0` for most of its own day.
    if (e.allDay) return _allDay(e, now);

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

    return ContextItem(
      kind: ContextKind.calendar,
      label: 'NEXT UP',
      headline: '${e.title} ${PuckFormat.countdown(until)}',
      detail: e.subtitle,
    );
  }

  /// An all-day entry is a *state*, not an appointment: it is true for the
  /// whole day and there is no useful countdown to it.
  ///
  /// It is also only worth interrupting someone for while it is happening.
  /// Tomorrow's all-day entry is not "next up" -- the tap card exists for the
  /// next hour, and a birthday three days out is the kind of trivia that makes
  /// people stop trusting the button.
  static ContextItem? _allDay(CalendarEvent e, DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime startDay =
        DateTime(e.start.year, e.start.month, e.start.day);
    if (startDay.isAfter(today)) return null;

    // DTEND is exclusive in iCalendar ("1 day" = ends the next midnight), but
    // some providers hand back an inclusive end instead. Subtracting a day
    // from the exclusive form and clamping at the start day makes both shapes
    // mean the same thing: the last day the entry is live.
    DateTime lastDay = startDay;
    final DateTime? rawEnd = e.end;
    if (rawEnd != null) {
      lastDay = DateTime(rawEnd.year, rawEnd.month, rawEnd.day)
          .subtract(const Duration(days: 1));
      if (lastDay.isBefore(startDay)) lastDay = startDay;
    }
    if (lastDay.isBefore(today)) return null; // already over

    return ContextItem(
      kind: ContextKind.calendar,
      label: 'TODAY',
      headline: e.title,
      detail: 'All day',
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
