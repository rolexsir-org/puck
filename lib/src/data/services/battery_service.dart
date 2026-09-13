import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:puck/src/core/constants.dart';
import 'package:puck/src/data/models/context.dart';

/// Battery state, cached for [PuckConstants.snapshotCacheTtl].
///
/// The platform call is cheap, but it is a channel round-trip -- and the tap
/// that reads it is the highest-frequency gesture in the app. Within the TTL
/// a tap answers from memory; past it, one fresh read refreshes the cache.
class BatteryService {
  BatteryService({Battery? battery}) : _battery = battery ?? Battery();

  final Battery _battery;

  BatterySnapshot? _cache;
  DateTime _cacheAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<BatterySnapshot?> read() async {
    final DateTime now = DateTime.now();
    if (_cache != null &&
        now.difference(_cacheAt) < PuckConstants.snapshotCacheTtl) {
      return _cache;
    }

    try {
      final int level = await _battery.batteryLevel;
      final BatteryState state = await _battery.batteryState;
      final BatterySnapshot snap = BatterySnapshot(
        level: level.clamp(0, 100),
        charging: state == BatteryState.charging || state == BatteryState.full,
      );
      _cache = snap;
      _cacheAt = now;
      return snap;
    } catch (_) {
      // Battery reporting is unavailable on some desktop/embedded targets.
      return _cache;
    }
  }
}
