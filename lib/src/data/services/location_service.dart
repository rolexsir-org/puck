import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:puck/src/core/constants.dart';

/// GPS access, on demand only.
///
/// Two tiers, because they cost very differently:
///   * [lastKnown]  -- free. Cached fix, no radio wake. Used for weather.
///   * [current]    -- expensive. Fresh high-accuracy fix. Used only by SOS,
///                     where a stale position is worse than no position.
///
/// [current] result is cached for the rest of the session: the weather tap
/// asks once, SOS refreshes it, and nothing wakes the GPS radio twice for
/// the same answer.
class LocationService {
  /// The last fresh fix this session, if any. Weather reads this directly so
  /// a single session never requests the radio twice.
  Position? sessionFix;

  Future<bool> get serviceEnabled => Geolocator.isLocationServiceEnabled();

  Future<LocationPermission> get permission => Geolocator.checkPermission();

  Future<bool> requestPermission() async {
    final LocationPermission p = await Geolocator.requestPermission();
    return p == LocationPermission.always ||
        p == LocationPermission.whileInUse;
  }

  /// Best cached position. May be null, may be old -- callers must tolerate
  /// both. Never throws.
  Future<Position?> lastKnown() async {
    if (sessionFix != null) return sessionFix;
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// A fresh fix, or null if the user has not granted access.
  ///
  /// Falls back to the session fix / last known on timeout: in an emergency a
  /// position from twenty minutes ago is better than a spinner.
  Future<Position?> current({
    Duration timeout = PuckConstants.locationTimeout,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
        // Plugin-level guard, on top of the Dart-side timeout below. It
        // throws on expiry rather than supplying a value, so the catch below
        // is the single fallback path.
      ).timeout(timeout);

      sessionFix = position;
      return position;
    } on TimeoutException catch (_) {
      return lastKnown();
    } catch (_) {
      return lastKnown();
    }
  }
}
