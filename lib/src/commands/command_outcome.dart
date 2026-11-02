import 'package:puck/src/commands/command_intent.dart';
import 'package:puck/src/commands/units.dart';

/// What actually happened, as data.
///
/// The executor never builds a sentence and never touches a widget. It reports
/// an outcome; `CommandNarrator` turns that into the one line the card shows and
/// the same line spoken aloud, in the user's language. Keeping those two apart
/// is what lets the whole command layer be tested without a screen, and what
/// stops a localization change from being able to alter behaviour.
///
/// Note the shape of the unsupported cases: [VolumeUnavailable],
/// [TorchUnavailable], [AppNotFound], [AppLaunchFailed], [TimerUnavailable],
/// [AlarmUnavailable]. They exist because "the phone said no" is a real,
/// frequent answer -- no torch, no clock app, a launcher that refused the
/// intent -- and an assistant that reports success it did not achieve is worse
/// than one that says it cannot.
sealed class CommandOutcome {
  const CommandOutcome();
}

// -- Volume -----------------------------------------------------------------

final class VolumeChanged extends CommandOutcome {
  const VolumeChanged({required this.percent, this.steps});

  /// 0-100, as reported by the device after the change.
  final int percent;

  /// Present for a relative change ("louder" -> 1 step).
  final int? steps;
}

/// A relative change where the device would not report the resulting level.
/// The direction is known, the number is not, and the narrator says only what
/// is true.
final class VolumeAdjusted extends CommandOutcome {
  const VolumeAdjusted(this.steps);

  final int steps;
}

final class VolumeMuted extends CommandOutcome {
  const VolumeMuted({required this.muted});

  final bool muted;
}

final class VolumeUnavailable extends CommandOutcome {
  const VolumeUnavailable();
}

// -- Flashlight -------------------------------------------------------------

final class FlashlightChanged extends CommandOutcome {
  const FlashlightChanged({required this.on});

  final bool on;
}

final class TorchUnavailable extends CommandOutcome {
  const TorchUnavailable();
}

// -- Apps -------------------------------------------------------------------

final class AppOpened extends CommandOutcome {
  const AppOpened(this.label);

  /// The installed app's own name ("Calculator"), not what the user said.
  final String label;
}

final class AppNotFound extends CommandOutcome {
  const AppNotFound(this.spokenName);

  final String spokenName;
}

final class AppLaunchFailed extends CommandOutcome {
  const AppLaunchFailed(this.label);

  final String label;
}

// -- Information ------------------------------------------------------------

final class BatteryReported extends CommandOutcome {
  const BatteryReported({required this.percent, required this.charging});

  final int percent;
  final bool charging;
}

final class BatteryUnavailable extends CommandOutcome {
  const BatteryUnavailable();
}

final class TimeReported extends CommandOutcome {
  const TimeReported(this.now);

  final DateTime now;
}

final class DateReported extends CommandOutcome {
  const DateReported(this.now);

  final DateTime now;
}

final class Calculated extends CommandOutcome {
  const Calculated({required this.expression, required this.value});

  final String expression;
  final double value;
}

final class Converted extends CommandOutcome {
  const Converted({
    required this.value,
    required this.from,
    required this.to,
    required this.result,
  });

  final double value;
  final Unit from;
  final Unit to;
  final double result;
}

/// "5 kilograms in miles" -- two units of different kinds. Reported, not
/// silently forced into a number.
final class ConversionImpossible extends CommandOutcome {
  const ConversionImpossible({required this.from, required this.to});

  final Unit from;
  final Unit to;
}

// -- Clock ------------------------------------------------------------------

final class TimerStarted extends CommandOutcome {
  const TimerStarted(this.duration);

  final Duration duration;
}

final class TimerUnavailable extends CommandOutcome {
  const TimerUnavailable();
}

final class AlarmSet extends CommandOutcome {
  const AlarmSet(this.at);

  final DateTime at;
}

final class AlarmUnavailable extends CommandOutcome {
  const AlarmUnavailable();
}

// -- Conversation -----------------------------------------------------------

final class HelpShown extends CommandOutcome {
  const HelpShown();
}

final class Cancelled extends CommandOutcome {
  const Cancelled();
}

/// An action Puck will not take from voice, by design. See docs/voice.md §4.
final class RefusedConsequential extends CommandOutcome {
  const RefusedConsequential({required this.kind, required this.detail});

  final ConsequentialKind kind;
  final String detail;
}

/// Something failed that is not a capability gap: a channel error, a timeout.
final class CommandFailed extends CommandOutcome {
  const CommandFailed(this.reason);

  final String reason;
}
