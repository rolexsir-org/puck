import 'package:flutter/services.dart';
import 'package:puck/src/commands/command_executor.dart';
import 'package:puck/src/data/services/battery_service.dart';
import 'package:puck/src/data/services/platform_bridge.dart';
import 'package:puck/src/data/services/torch_service.dart';

/// The production implementations of the five ports the command layer needs.
///
/// Thin by design: each class is a translation of one Dart interface onto one
/// Android capability, so the tests can substitute a fake without a device and
/// the device code has no branching of its own to get wrong.
///
/// Two of them reuse services Puck already had. The torch is the `torch_light`
/// plugin that already strobes SOS, and the battery is the same cached read that
/// paints the tap card -- keeping them means the voice command and the card can
/// never disagree about the battery level.

class BridgedVolumePort implements VolumePort {
  BridgedVolumePort(this._bridge);

  final PlatformBridge _bridge;

  @override
  Future<int?> percent() => _bridge.mediaVolumePercent();

  @override
  Future<bool> setPercent(int percent) => _bridge.setMediaVolumePercent(percent);

  @override
  Future<bool> adjust(int steps) => _bridge.adjustMediaVolume(steps);

  @override
  Future<bool> setMuted(bool muted) => _bridge.setMediaMuted(muted);

  @override
  Future<bool?> isMuted() => _bridge.isMediaMuted();
}

class BridgedAppLauncher implements AppLauncherPort {
  BridgedAppLauncher(this._bridge);

  final PlatformBridge _bridge;

  @override
  Future<String?> open(String spokenName) async {
    try {
      return await _bridge.openApp(spokenName);
    } on PlatformException catch (error) {
      // The Android side distinguishes "no such app" (null) from "found it and
      // could not launch it" (an exception carrying the label). Collapsing both
      // into "not found" would tell the user to install something they already
      // have.
      throw AppLaunchException(error.message ?? spokenName);
    }
  }
}

class BridgedClock implements ClockPort {
  BridgedClock(this._bridge);

  final PlatformBridge _bridge;

  @override
  Future<bool> startTimer(Duration duration) => _bridge.startTimer(duration);

  @override
  Future<bool> setAlarm(DateTime at) =>
      _bridge.setAlarm(hour: at.hour, minute: at.minute);
}

class PluginTorch implements TorchPort {
  PluginTorch({TorchService? torch}) : _torch = torch ?? TorchService();

  final TorchService _torch;

  @override
  Future<bool> isAvailable() => _torch.isAvailable;

  @override
  Future<bool> setOn(bool on) async {
    if (on) {
      await _torch.enable();
    } else {
      await _torch.disable();
    }
    // The plugin swallows platform errors, so read the service's own belief
    // back. It is the only signal available, and a torch that did not come on
    // must not be reported as on.
    return _torch.isOn == on;
  }
}

class ServiceBattery implements BatteryPort {
  ServiceBattery({BatteryService? battery}) : _battery = battery ?? BatteryService();

  final BatteryService _battery;

  @override
  Future<({int percent, bool charging})?> read() async {
    final BatterySnapshot? snapshot = await _battery.read();
    if (snapshot == null) return null;
    return (percent: snapshot.level, charging: snapshot.charging);
  }
}
