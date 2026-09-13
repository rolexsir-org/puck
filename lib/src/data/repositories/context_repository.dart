import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:puck/src/data/models/context.dart';
import 'package:puck/src/data/services/battery_service.dart';
import 'package:puck/src/data/services/calendar_service.dart';
import 'package:puck/src/data/services/location_service.dart';
import 'package:puck/src/data/services/weather_service.dart';

/// Gathers device context in one parallel pass.
///
/// Latency budget: a tap should feel instant. Everything is fetched
/// concurrently, and weather is served from a 10-minute cache when possible --
/// the slowest source is the network, so it must never block the fast ones.
///
/// Every source is optional. If the calendar permission was denied, the ranker
/// simply sees a null event and falls through to the next candidate.
class ContextRepository {
  ContextRepository({
    required BatteryService battery,
    required CalendarService calendar,
    required LocationService location,
    required WeatherService weather,
  })  : _battery = battery,
        _calendar = calendar,
        _location = location,
        _weather = weather;

  final BatteryService _battery;
  final CalendarService _calendar;
  final LocationService _location;
  final WeatherService _weather;

  /// Total time we will wait for the slow sources before ranking anyway.
  static const Duration budget = Duration(milliseconds: 1500);

  Future<ContextSnapshot> snapshot() async {
    final DateTime now = DateTime.now();

    // Fast, local, always available -- kick all three off together.
    final Future<BatterySnapshot?> battery = _battery.read();
    final Future<CalendarEvent?> event = _calendar.nextEvent();

    // Weather needs a position first. Use the cached fix: weather does not
    // need metre accuracy, and waking the GPS on every tap is rude.
    final Future<WeatherSnapshot?> weather = _weatherForCachedPosition();

    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      battery,
      event,
      weather.timeout(budget, onTimeout: () => null),
    ]);

    return ContextSnapshot(
      now: now,
      battery: results[0] as BatterySnapshot?,
      nextEvent: results[1] as CalendarEvent?,
      weather: results[2] as WeatherSnapshot?,
    );
  }

  Future<WeatherSnapshot?> _weatherForCachedPosition() async {
    final Position? position = await _location.lastKnown();
    if (position == null) return null;
    return _weather.read(position);
  }
}
