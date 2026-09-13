import 'dart:async';

import 'package:puck/src/core/constants.dart';
import 'package:torch_light/torch_light.dart';

/// Flashlight control.
///
/// The platform only exposes on/off to Dart -- there is no cross-platform
/// "set brightness to max", so maximum brightness means the OS-default full
/// level (AVCaptureDevice level 1.0 on iOS, the single torch mode on Android).
/// Anything finer needs a platform channel, which this MVP does not carry.
///
/// Strobe duty cycle is deliberately kept low: a torch at 100% for minutes
/// gets genuinely hot and drains the battery when you may need it.
class TorchService {
  /// Bumped on every [stop] so in-flight sequences can bail out.
  int _generation = 0;
  bool _on = false;

  bool get isOn => _on;

  Future<bool> get isAvailable async {
    try {
      return await TorchLight.isTorchAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<void> enable() async {
    if (_on) return;
    try {
      await TorchLight.enableTorch();
      _on = true;
    } catch (_) {
      _on = false;
    }
  }

  Future<void> disable() async {
    // Deliberately attempted even when we believe the torch is already off:
    // the OS can reclaim it without telling us, and a stale `_on` here is how
    // a beacon stays lit after the emergency is over.
    try {
      await TorchLight.disableTorch();
    } catch (_) {
      // Torch already off, unsupported on this device, or reclaimed by the OS.
      // Every one of those ends in the outcome we asked for, so there is
      // nothing to recover and nothing to report.
    }
    _on = false;
  }

  /// Morse SOS (··· ——— ···) at full brightness, then hold steady on.
  ///
  /// Leaves the torch lit on exit so the device stays findable; callers are
  /// responsible for calling [stop].
  Future<void> startSos() async {
    final int token = ++_generation;
    if (!await isAvailable) return;

    const List<Duration> s = <Duration>[
      PuckConstants.morseDot, PuckConstants.morseDot, PuckConstants.morseDot,
    ];
    const List<Duration> o = <Duration>[
      PuckConstants.morseDash, PuckConstants.morseDash, PuckConstants.morseDash,
    ];

    try {
      for (int cycle = 0; cycle < PuckConstants.sosStrobeCycles; cycle++) {
        for (final List<Duration> word in <List<Duration>>[s, o, s]) {
          if (token != _generation) return;
          for (int i = 0; i < word.length; i++) {
            if (token != _generation) return;
            await enable();
            await Future<void>.delayed(word[i]);
            if (token != _generation) return;
            await disable();
            if (i < word.length - 1) {
              await Future<void>.delayed(PuckConstants.morseGap);
            }
          }
          await Future<void>.delayed(PuckConstants.morseLetterGap);
        }
        if (cycle < PuckConstants.sosStrobeCycles - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
      }
      // Steady beacon.
      if (token == _generation) await enable();
    } catch (_) {
      await disable();
    }
  }

  /// Cancels any running sequence and guarantees the torch is off.
  Future<void> stop() async {
    _generation++;
    await disable();
  }
}
