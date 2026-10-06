import 'package:puck/src/data/models/context.dart';
import 'package:puck/src/l10n/puck_strings.dart';

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

  /// [strings] carries the user's language: the card is the highest-frequency
  /// surface in the app, so a headline that only exists in English is a
  /// headline most of the world reads in a language it did not choose.
  static ContextItem rank(ContextSnapshot snap, PuckStrings strings) {
    final DateTime now = snap.now;
    final ContextItem? item = _calendar(snap, now, strings) ??
        _battery(snap, strings) ??
        _weather(snap, now, strings);
    return item ?? timeOfDay(now, strings);
  }

  // -- Candidates, in descending order of urgency --------------------------

  static ContextItem? _calendar(
    ContextSnapshot snap,
    DateTime now,
    PuckStrings strings,
  ) {
    final CalendarEvent? e = snap.nextEvent;
    if (e == null) return null;

    // All-day entries are handled before anything measures a duration,
    // because a duration is the wrong unit for them. An all-day "Birthday"
    // that began at midnight is not "started 9h ago", and a three-day trip is
    // not "started 2d ago" -- both read as bugs, and both used to happen here
    // because the `until <= 0` branch ran first and an all-day event always
    // has `until <= 0` for most of its own day.
    if (e.allDay) return _allDay(e, now, strings);

    final Duration until = e.until(now);

    // Already started: tell them, briefly, then get out of the way.
    if (until <= Duration.zero) {
      final String late = strings.countdown(until.abs());
      return ContextItem(
        kind: ContextKind.calendar,
        label: strings.labelHappeningNow,
        headline: strings.startedAgo(_name(e, strings), late),
        detail: e.subtitle,
      );
    }

    if (until > meetingWindow) return null;

    return ContextItem(
      kind: ContextKind.calendar,
      label: strings.labelNextUp,
      headline: strings.nextUp(_name(e, strings), strings.countdown(until)),
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
  static ContextItem? _allDay(
    CalendarEvent e,
    DateTime now,
    PuckStrings strings,
  ) {
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
      label: strings.labelToday,
      headline: _name(e, strings),
      detail: strings.allDay,
    );
  }

  static ContextItem? _battery(ContextSnapshot snap, PuckStrings strings) {
    final BatterySnapshot? b = snap.battery;
    if (b == null) return null;

    if (!b.charging && b.level <= lowBatteryThreshold) {
      return ContextItem(
        kind: ContextKind.battery,
        label: strings.labelBattery,
        headline: b.level <= 8
            ? strings.batteryCritical(b.level)
            : strings.batteryLow(b.level),
      );
    }

    if (b.charging && b.level >= 95) {
      return ContextItem(
        kind: ContextKind.battery,
        label: strings.labelBattery,
        headline: strings.chargedTo(b.level),
      );
    }

    return null;
  }

  static ContextItem? _weather(
    ContextSnapshot snap,
    DateTime now,
    PuckStrings strings,
  ) {
    final WeatherSnapshot? w = snap.weather;
    if (w == null) return null;

    final HourlyPoint? rain = w.rainStartingWithin(rainWindow);
    if (rain != null) {
      final Duration until = rain.time.difference(w.fetchedAt);
      return ContextItem(
        kind: ContextKind.weather,
        label: strings.labelWeather,
        headline: until < const Duration(minutes: 45)
            ? strings.rainStarting(strings.countdown(until))
            : strings.rainAt(strings.clock(rain.time)),
        detail: strings.condition(
          strings.weatherDescription(w.code),
          '${w.temperatureC.round()}°',
        ),
      );
    }

    // Cold enough that leaving without a layer was a mistake.
    if (w.temperatureC <= 3) {
      return ContextItem(
        kind: ContextKind.weather,
        label: strings.labelWeather,
        headline: strings.coldOutside('${w.temperatureC.round()}'),
        detail: strings.weatherDescription(w.code),
      );
    }

    if (w.temperatureC >= 38) {
      return ContextItem(
        kind: ContextKind.weather,
        label: strings.labelWeather,
        headline: strings.hotOutside('${w.temperatureC.round()}'),
        detail: strings.weatherDescription(w.code),
      );
    }

    return null;
  }

  // -- Fallback ------------------------------------------------------------

  /// No urgent signal. The guaranteed answer to a tap: the time, and a line
  /// that reads like a person wrote it. This paints before any await runs,
  /// so a tap is never answered with a spinner.
  static ContextItem timeOfDay(DateTime now, PuckStrings strings) {
    final int h = now.hour;
    final String clock = strings.clock(now);

    if (h < 5) {
      return ContextItem(
        kind: ContextKind.time,
        label: clock,
        headline: strings.nothingUrgentNight,
      );
    }

    if (h < 11) {
      return ContextItem(
        kind: ContextKind.time,
        label: strings.labelGoodMorning,
        headline: strings.timeOfDay(clock, strings.clearAhead),
      );
    }

    if (h < 17) {
      return ContextItem(
        kind: ContextKind.time,
        label: strings.labelGoodAfternoon,
        headline: strings.timeOfDay(clock, strings.nothingUrgent),
      );
    }

    if (h < 22) {
      return ContextItem(
        kind: ContextKind.time,
        label: strings.labelGoodEvening,
        headline: strings.timeOfDay(clock, strings.nothingUrgent),
      );
    }

    return ContextItem(
      kind: ContextKind.time,
      label: clock,
      headline: strings.nothingUrgentLate,
    );
  }

  /// The event's name, or the localized word for an untitled one.
  static String _name(CalendarEvent e, PuckStrings strings) =>
      e.title.trim().isEmpty ? strings.busyLabel : e.title;
}
