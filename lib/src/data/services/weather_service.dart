import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/data/models/context.dart';

/// Weather via Open-Meteo.
///
/// Chosen over the usual providers for one reason: no API key. Puck must work
/// the instant it is installed, and a signup wall in a "zero setup" app is a
/// contradiction.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  static const String _endpoint = 'https://api.open-meteo.com/v1/forecast';

  final http.Client _client;

  Position? _lastPosition;
  DateTime? _fetchedAt;
  WeatherSnapshot? _cache;

  /// Returns null on any failure -- weather is an enhancement, never a blocker.
  Future<WeatherSnapshot?> read(Position position) async {
    final DateTime now = DateTime.now();

    // Serve cache when the device has barely moved and the TTL holds.
    if (_cache != null &&
        _fetchedAt != null &&
        now.difference(_fetchedAt!) < PuckConstants.weatherCacheTtl &&
        _lastPosition != null &&
        _distanceMetres(_lastPosition!, position) < 5000) {
      return _cache;
    }

    try {
      final Uri uri = Uri.parse(_endpoint).replace(
        queryParameters: <String, String>{
          'latitude': position.latitude.toStringAsFixed(3),
          'longitude': position.longitude.toStringAsFixed(3),
          'current': 'temperature_2m,weather_code',
          'hourly': 'precipitation_probability,weather_code',
          'forecast_days': '1',
          'timezone': 'auto',
        },
      );

      final http.Response res = await _client
          .get(uri)
          .timeout(PuckConstants.weatherTimeout);

      if (res.statusCode != 200) return _cache;

      final Map<String, dynamic> json =
          jsonDecode(res.body) as Map<String, dynamic>;

      final Map<String, dynamic> current =
          json['current'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final Map<String, dynamic> hourly =
          json['hourly'] as Map<String, dynamic>? ?? <String, dynamic>{};

      final List<dynamic> times = hourly['time'] as List<dynamic>? ?? const [];
      final List<dynamic> probs =
          hourly['precipitation_probability'] as List<dynamic>? ?? const [];
      final List<dynamic> codes =
          hourly['weather_code'] as List<dynamic>? ?? const [];

      final List<HourlyPoint> points = <HourlyPoint>[];
      for (int i = 0; i < times.length; i++) {
        final DateTime? t = DateTime.tryParse(times[i] as String? ?? '');
        if (t == null) continue;
        points.add(
          HourlyPoint(
            time: t,
            code: i < codes.length ? (codes[i] as num?)?.toInt() ?? 0 : 0,
            precipProbability:
                i < probs.length ? (probs[i] as num?)?.toInt() ?? 0 : 0,
          ),
        );
      }

      final WeatherSnapshot snap = WeatherSnapshot(
        temperatureC: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
        code: (current['weather_code'] as num?)?.toInt() ?? 0,
        hourly: points,
        fetchedAt: now,
      );

      _cache = snap;
      _fetchedAt = now;
      _lastPosition = position;
      return snap;
    } catch (_) {
      return _cache;
    }
  }

  void dispose() => _client.close();

  /// Equirectangular approximation -- plenty accurate at 5km.
  static double _distanceMetres(Position a, Position b) {
    const double mPerDeg = 111320;
    final double dx = (a.latitude - b.latitude) * mPerDeg;
    final double dy =
        (a.longitude - b.longitude) * mPerDeg * _cosDeg(a.latitude);
    return _sqrt(dx * dx + dy * dy);
  }

  static double _cosDeg(double deg) {
    // Small local series is fine: we need ~1% accuracy for a cache radius.
    final double x = deg * 3.141592653589793 / 180;
    return 1 - (x * x) / 2 + (x * x * x * x) / 24;
  }

  static double _sqrt(double v) {
    if (v <= 0) return 0;
    double x = v;
    for (int i = 0; i < 12; i++) {
      x = (x + v / x) / 2;
    }
    return x;
  }
}
