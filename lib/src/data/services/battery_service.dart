import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:puck/src/data/models/context.dart';

class BatteryService {
  BatteryService({Battery? battery}) : _battery = battery ?? Battery();

  final Battery _battery;

  Future<BatterySnapshot?> read() async {
    try {
      final int level = await _battery.batteryLevel;
      final BatteryState state = await _battery.batteryState;
      return BatterySnapshot(
        level: level.clamp(0, 100),
        charging: state == BatteryState.charging || state == BatteryState.full,
      );
    } catch (_) {
      // Battery reporting is unavailable on some desktop/embedded targets.
      return null;
    }
  }
}
