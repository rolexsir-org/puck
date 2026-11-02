import 'package:puck/src/commands/units.dart';

/// What a spoken sentence was understood to *mean*.
///
/// The parser's entire output is one of these, and nothing here can execute
/// anything: a [CommandIntent] is data. Execution is
/// `CommandExecutor`'s job, over an injected platform, which is what keeps
/// "recognised text" and "did something to the phone" two separate steps.
///
/// Sealed so a new intent cannot be added without every `switch` that acts on
/// intents failing to compile -- the alternative is a dispatcher with a
/// `default:` branch that silently swallows a command somebody thought they
/// shipped.
sealed class CommandIntent {
  const CommandIntent();
}

/// Set the media volume to a percentage of the stream's maximum.
final class SetVolumeIntent extends CommandIntent {
  const SetVolumeIntent(this.percent);

  final int percent;
}

/// Nudge the media volume by [steps] (negative is quieter).
final class AdjustVolumeIntent extends CommandIntent {
  const AdjustVolumeIntent(this.steps);

  final int steps;
}

/// Mute or unmute the media stream.
final class MuteIntent extends CommandIntent {
  const MuteIntent({required this.muted});

  final bool muted;
}

/// Flashlight / torch.
final class FlashlightIntent extends CommandIntent {
  const FlashlightIntent({required this.on});

  final bool on;
}

/// Launch an installed app by the name the user said.
final class OpenAppIntent extends CommandIntent {
  const OpenAppIntent(this.spokenName);

  final String spokenName;
}

final class BatteryIntent extends CommandIntent {
  const BatteryIntent();
}

final class TimeIntent extends CommandIntent {
  const TimeIntent();
}

final class DateIntent extends CommandIntent {
  const DateIntent();
}

/// Arithmetic that has already been evaluated at parse time.
///
/// Evaluating in the parser rather than the executor is deliberate: "is this
/// even arithmetic?" is a *parse* question, and an expression that does not
/// parse must fall through to the ordinary answer path instead of producing a
/// command that fails later.
final class CalculateIntent extends CommandIntent {
  const CalculateIntent({required this.value, required this.expression});

  final double value;

  /// The expression in symbols, for the card: "12 * 8".
  final String expression;
}

final class ConvertIntent extends CommandIntent {
  const ConvertIntent({
    required this.value,
    required this.from,
    required this.to,
  });

  final double value;
  final Unit from;
  final Unit to;
}

final class SetTimerIntent extends CommandIntent {
  const SetTimerIntent(this.duration);

  final Duration duration;
}

final class SetAlarmIntent extends CommandIntent {
  const SetAlarmIntent({
    required this.hour,
    required this.minute,
    this.explicitMeridiem = true,
  });

  /// 24-hour clock.
  final int hour;
  final int minute;

  /// False when the utterance gave no am/pm ("an alarm for seven"), which
  /// makes the time ambiguous by 12 hours. The executor picks whichever of the
  /// two is next, because that is what "seven" means at 3pm.
  final bool explicitMeridiem;
}

/// What Puck can do, said out loud.
final class HelpIntent extends CommandIntent {
  const HelpIntent();
}

/// "Stop" / "cancel" / "never mind".
final class CancelIntent extends CommandIntent {
  const CancelIntent();
}

/// The categories of action a voice interface must not take on its own.
///
/// They are recognised rather than ignored: silence would read as "Puck did
/// not hear you", and a person's next move would be to try again louder. The
/// honest answer -- "I will not send messages from voice" -- is the feature.
enum ConsequentialKind { call, message, deleteData, shareLocation }

final class ConsequentialIntent extends CommandIntent {
  const ConsequentialIntent({
    required this.kind,
    required this.detail,
  });

  final ConsequentialKind kind;

  /// What was asked for, so the answer can be specific ("I cannot call Sam
  /// from here") rather than generic.
  final String detail;
}
