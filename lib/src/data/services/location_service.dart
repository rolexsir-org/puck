import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:puck/src/core/constants.dart';

/// GPS access, on demand only.
///
/// Two tiers, because they cost very differently:
///   * [lastKnown]  -- free. Cached fix, no radio wake. Used for weather.
///   * [current]    -- expensive. Fresh high-accuracy fix. Used only by SOS,
///                     where a stale position is worse than no position.
class LocationService {
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
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// A fresh fix, or null if the user has not granted access.
  ///
  /// Falls back to [lastKnown] on timeout: in an emergency a position from
  /// twenty minutes ago is better than a spinner.
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

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
        // Plugin-level guard, on top of the Dart-side timeout below. It
        // throws on expiry rather than supplying a value, so the catch below
        // is the single fallback path -- `lastKnown` returns Position?, which
        // `Future<Position>.timeout` cannot accept as its `onTimeout`.
      ).timeout(timeout);
    } on TimeoutException catch (_) {
      return lastKnown();
    } catch (_) {
      return lastKnown();
    }
  }
}
