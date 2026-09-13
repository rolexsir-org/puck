import 'dart:math' as math;

/// Hand-rolled formatters.
///
/// `intl` would pull in ~250KB of ICU tables for four functions. Not worth it.
abstract final class PuckFormat {
  /// "3 PM", "3:07 PM", "12 AM"
  static String clock(DateTime t) {
    final int hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final String suffix = t.hour < 12 ? 'AM' : 'PM';
    if (t.minute == 0) return '$hour $suffix';
    return '$hour:${t.minute.toString().padLeft(2, '0')} $suffix';
  }

  /// "now", "in 12m", "in 1h 5m", "in 2d"
  static String countdown(Duration d) {
    if (d <= Duration.zero) return 'now';
    if (d.inMinutes < 1) return 'in ${d.inSeconds}s';
    if (d.inHours < 1) return 'in ${d.inMinutes}m';
    if (d.inDays < 1) {
      final int m = d.inMinutes.remainder(60);
      return m == 0 ? 'in ${d.inHours}h' : 'in ${d.inHours}h ${m}m';
    }
    return 'in ${d.inDays}d';
  }

  /// "today", "tomorrow", "in 3d", "yesterday"
  static String relativeDay(DateTime day, DateTime now) {
    final int days = DateTime(day.year, day.month, day.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    switch (days) {
      case 0:
        return 'today';
      case 1:
        return 'tomorrow';
      case -1:
        return 'yesterday';
      default:
        return days > 0 ? 'in ${days}d' : '${-days}d ago';
    }
  }

  /// "34.0522°N, 118.2437°W" -- the human-readable form used in the SMS body.
  static String coordsDegrees(double lat, double lng) {
    final String ns = lat >= 0 ? 'N' : 'S';
    final String ew = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}°$ns, '
        '${lng.abs().toStringAsFixed(4)}°$ew';
  }

  /// "maps.google.com/?q=34.0522,-118.2437" -- no scheme; every SMS client
  /// auto-links it and the body stays short.
  static String coordsUrl(double lat, double lng) {
    return 'maps.google.com/?q='
        '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
  }

  /// "±12m"
  static String accuracy(double metres) {
    if (metres < 0) return '';
    if (metres >= 1000) return '±${(metres / 1000).toStringAsFixed(1)}km';
    return '±${metres.round()}m';
  }

  /// "3:14 PM · Wed Jan 15"
  static String stamp(DateTime t) {
    const List<String> days = <String>[
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', //
    ];
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${clock(t)} · ${days[t.weekday - 1]} '
        '${months[t.month - 1]} ${t.day}';
  }

  static double clamp(double v, double lo, double hi) {
    return math.min(hi, math.max(lo, v));
  }
}

/// WMO 4677 weather codes -> plain language.
/// https://open-meteo.com/en/docs  (weather_code)
abstract final class WeatherCodes {
  static const Set<int> rain = <int>{
    51, 53, 55, 56, 57, // drizzle
    61, 63, 65, 66, 67, // rain
    80, 81, 82, // showers
    95, 96, 99, // thunderstorm
  };

  static const Set<int> snow = <int>{
    71, 73, 75, 77, 85, 86, //
  };

  static String describe(int code) {
    if (code == 0) return 'Clear';
    if (code <= 3) return 'Partly cloudy';
    if (code == 45 || code == 48) return 'Fog';
    if (code <= 57) return 'Drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 82) return 'Showers';
    if (code <= 86) return 'Snow showers';
    return 'Thunderstorm';
  }
}
