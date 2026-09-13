import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Haptics, centralised.
///
/// Two engines, used for different jobs:
///   * [HapticFeedback] -- the standard iOS/Android taps. Always available,
///     respects the system "haptics" setting, costs nothing.
///   * [Vibration] -- long custom patterns. Used only by SOS, which needs a
///     pattern the user can feel through a jacket pocket.
///
/// Every call is wrapped: a haptic failure must never break a gesture.
class HapticsService {
  HapticsService({this.enabled = true});

  bool enabled;
  bool _patternProbed = false;
  bool _hasVibrator = false;

  /// The tick of a UI element responding -- bubble press, panel appear.
  Future<void> tick() => _fire(HapticFeedback.selectionClick);

  Future<void> light() => _fire(HapticFeedback.lightImpact);

  Future<void> medium() => _fire(HapticFeedback.mediumImpact);

  Future<void> heavy() => _fire(HapticFeedback.heavyImpact);

  /// The SOS signature: three long escalating pulses. Deliberately
  /// distinguishable from any notification the phone could otherwise produce.
  Future<void> sosAlarm() async {
    if (!enabled) return;
    try {
      if (!_patternProbed) {
        _patternProbed = true;
        _hasVibrator = (await Vibration.hasVibrator()) ?? false;
      }
    } catch (_) {
      _hasVibrator = false;
    }
    if (!_hasVibrator) return;

    try {
      // wait, vibrate, wait, vibrate ... amplitudes 0..255
      await Vibration.vibrate(
        pattern: <int>[0, 700, 180, 700, 180, 900],
        intensities: <int>[0, 255, 0, 200, 0, 255],
      );
    } catch (_) {
      // Fall back to repeated heavy impacts.
      for (int i = 0; i < 3; i++) {
        await heavy();
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
  }

  /// Single confirmation pulse when SOS is disarmed.
  Future<void> sosCancel() async {
    if (!enabled) return;
    try {
      await Vibration.vibrate(duration: 90, amplitude: 90);
    } catch (_) {
      await light();
    }
  }

  Future<void> _fire(Future<void> Function() call) async {
    if (!enabled) return;
    try {
      await call();
    } catch (_) {
      // Some OEM builds throw on unsupported engines. Swallow.
    }
  }
}
