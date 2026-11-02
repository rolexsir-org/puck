import 'package:puck/src/commands/command_intent.dart';
import 'package:puck/src/commands/command_outcome.dart';
import 'package:puck/src/commands/units.dart';

/// The phone, as the command layer sees it.
///
/// Five narrow ports rather than one fat "platform service", because each one
/// maps to a different Android API with a different permission story, and
/// because a test that fakes volume control should not have to implement
/// torch control. In production they are all backed by
/// `PuckPlatformChannel` (see `data/services/platform_bridge.dart`) except the
/// torch and the battery, which already had working plugins in Puck and reuse
/// them.
abstract interface class VolumePort {
  /// Current media volume as 0-100, or null when the device cannot report it.
  Future<int?> percent();

  /// Set the media stream to [percent] of its own maximum. Returns true when
  /// the platform accepted the change.
  Future<bool> setPercent(int percent);

  /// Move by [steps] of the platform's own step size (negative is quieter).
  Future<bool> adjust(int steps);

  /// Mute or unmute the media stream.
  Future<bool> setMuted(bool muted);

  /// Whether the media stream is muted right now, or null when unknown.
  Future<bool?> isMuted();
}

/// A matched installed app that Android refused to launch.
class AppLaunchException implements Exception {
  const AppLaunchException(this.label);

  final String label;
}

abstract interface class AppLauncherPort {
  /// Open the installed app whose name best matches [spokenName].
  ///
  /// Returns the app's own label when it opened. Returns null when nothing
  /// matched -- which is a normal answer, not an error: half of what people say
  /// ("open the metro app") is simply not installed on that phone.
  Future<String?> open(String spokenName);
}

abstract interface class ClockPort {
  /// Start the system timer. False when the device has no clock app that
  /// accepts the intent.
  Future<bool> startTimer(Duration duration);

  /// Create an alarm for [at].
  Future<bool> setAlarm(DateTime at);
}

abstract interface class TorchPort {
  Future<bool> isAvailable();

  /// Turn the torch on or off. False when the platform refused (some cameras
  /// are in use by another app, and the torch cannot be shared).
  Future<bool> setOn(bool on);
}

abstract interface class BatteryPort {
  /// Null when the platform cannot answer.
  Future<({int percent, bool charging})?> read();
}

/// Runs one [CommandIntent] against the ports and reports what happened.
///
/// Every branch is a straight line -- resolve, call, report -- because the
/// interesting decisions (what did they mean? is this allowed?) were made
/// before execution started. The one policy left here is alarm time
/// resolution, which needs a clock.
class CommandExecutor {
  CommandExecutor({
    required VolumePort volume,
    required AppLauncherPort apps,
    required ClockPort clock,
    required TorchPort torch,
    required BatteryPort battery,
    DateTime Function()? now,
  })  : _volume = volume,
        _apps = apps,
        _clock = clock,
        _torch = torch,
        _battery = battery,
        _now = now ?? DateTime.now;

  final VolumePort _volume;
  final AppLauncherPort _apps;
  final ClockPort _clock;
  final TorchPort _torch;
  final BatteryPort _battery;
  final DateTime Function() _now;

  Future<CommandOutcome> execute(CommandIntent intent) async {
    // A statement switch, not an expression: the branches return futures and
    // plain values, and Dart's exhaustiveness check covers this one too.
    switch (intent) {
      case SetVolumeIntent(:final int percent):
        return _setVolume(percent);
      case AdjustVolumeIntent(:final int steps):
        return _adjustVolume(steps);
      case MuteIntent(:final bool muted):
        return _mute(muted);
      case FlashlightIntent(:final bool on):
        return _flashlight(on);
      case OpenAppIntent(:final String spokenName):
        return _openApp(spokenName);
      case BatteryIntent():
        return _batteryLevel();
      case TimeIntent():
        return TimeReported(_now());
      case DateIntent():
        return DateReported(_now());
      case CalculateIntent(:final double value, :final String expression):
        return Calculated(expression: expression, value: value);
      case ConvertIntent():
        return _convert(intent);
      case SetTimerIntent(:final Duration duration):
        return _timer(duration);
      case SetAlarmIntent():
        return _alarm(intent);
      case HelpIntent():
        return const HelpShown();
      case CancelIntent():
        return const Cancelled();
      case ConsequentialIntent(
          :final ConsequentialKind kind,
          :final String detail,
        ):
        return RefusedConsequential(kind: kind, detail: detail);
    }
  }

  Future<CommandOutcome> _setVolume(int percent) async {
    try {
      final bool accepted = await _volume.setPercent(percent);
      if (!accepted) return const VolumeUnavailable();
      // Read back rather than echo the request: Android rounds a percentage
      // onto its own step grid, and the number the user hears should be the one
      // the phone is actually at.
      final int? actual = await _volume.percent();
      return VolumeChanged(percent: actual ?? percent);
    } catch (Object error) {
      return CommandFailed('$error');
    }
  }

  Future<CommandOutcome> _adjustVolume(int steps) async {
    try {
      final bool accepted = await _volume.adjust(steps);
      if (!accepted) return const VolumeUnavailable();
      final int? actual = await _volume.percent();
      if (actual == null) {
        // The change happened; we just cannot say to what. Better to confirm
        // the direction than to invent a number.
        return VolumeAdjusted(steps);
      }
      return VolumeChanged(percent: actual, steps: steps);
    } catch (Object error) {
      return CommandFailed('$error');
    }
  }

  Future<CommandOutcome> _mute(bool muted) async {
    try {
      final bool accepted = await _volume.setMuted(muted);
      if (!accepted) return const VolumeUnavailable();
      final bool? actual = await _volume.isMuted();
      return VolumeMuted(muted: actual ?? muted);
    } catch (Object error) {
      return CommandFailed('$error');
    }
  }

  Future<CommandOutcome> _flashlight(bool on) async {
    try {
      if (!await _torch.isAvailable()) return const TorchUnavailable();
      if (!await _torch.setOn(on)) return const TorchUnavailable();
      return FlashlightChanged(on: on);
    } catch (Object error) {
      return CommandFailed('$error');
    }
  }

  Future<CommandOutcome> _openApp(String spokenName) async {
    try {
      final String? label = await _apps.open(spokenName);
      if (label == null) return AppNotFound(spokenName);
      return AppOpened(label);
    } on AppLaunchException catch (e) {
      return AppLaunchFailed(e.label);
    } catch (Object error) {
      return CommandFailed('$error');
    }
  }

  Future<CommandOutcome> _batteryLevel() async {
    try {
      final ({int percent, bool charging})? reading = await _battery.read();
      if (reading == null) return const BatteryUnavailable();
      return BatteryReported(
        percent: reading.percent,
        charging: reading.charging,
      );
    } catch (Object error) {
      return CommandFailed('$error');
    }
  }

  CommandOutcome _convert(ConvertIntent intent) {
    // Units.convert is a pure function; the table has its own tests.
    final double? result = Units.convert(intent.value, intent.from, intent.to);
    if (result == null) {
      return ConversionImpossible(from: intent.from, to: intent.to);
    }
    return Converted(
      value: intent.value,
      from: intent.from,
      to: intent.to,
      result: result,
    );
  }

  Future<CommandOutcome> _timer(Duration duration) async {
    try {
      final bool accepted = await _clock.startTimer(duration);
      if (!accepted) return const TimerUnavailable();
      return TimerStarted(duration);
    } catch (Object error) {
      return CommandFailed('$error');
    }
  }

  Future<CommandOutcome> _alarm(SetAlarmIntent intent) async {
    try {
      final DateTime at = resolveAlarm(
        now: _now(),
        hour: intent.hour,
        minute: intent.minute,
        explicitMeridiem: intent.explicitMeridiem,
      );
      final bool accepted = await _clock.setAlarm(at);
      if (!accepted) return const AlarmUnavailable();
      return AlarmSet(at);
    } catch (Object error) {
      return CommandFailed('$error');
    }
  }

  /// The next time the clock reads [hour]:[minute].
  ///
  /// "An alarm for seven" said at 3pm means 7pm, not 7am tomorrow: with no
  /// am/pm, the nearer of the two candidates wins. With am/pm given, the hour
  /// is already unambiguous (the parser resolved it) and only the day can roll.
  static DateTime resolveAlarm({
    required DateTime now,
    required int hour,
    required int minute,
    required bool explicitMeridiem,
  }) {
    DateTime at = DateTime(now.year, now.month, now.day, hour, minute);
    if (explicitMeridiem || hour >= 12) {
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      return at;
    }

    final DateTime evening =
        DateTime(now.year, now.month, now.day, hour + 12, minute);
    DateTime morning = at;
    if (!morning.isAfter(now)) {
      morning = morning.add(const Duration(days: 1));
    }
    final DateTime eveningNext =
        evening.isAfter(now) ? evening : evening.add(const Duration(days: 1));
    return morning.isBefore(eveningNext) ? morning : eveningNext;
  }
}
