import 'package:puck/src/commands/command_intent.dart';
import 'package:puck/src/commands/command_outcome.dart';
import 'package:puck/src/commands/units.dart';
import 'package:puck/src/l10n/puck_strings.dart';

/// One line as it appears on the card, and as it is spoken.
///
/// They are not the same string on purpose. A card can say "12 * 8 = 96" with
/// symbols that read perfectly on a screen and are rubble in a speech
/// synthesiser; the spoken form has to say "That is 96." Both are localized.
class Narration {
  const Narration({
    required this.display,
    required this.spoken,
    this.dismiss = false,
  });

  /// What the answer card shows.
  final String display;

  /// What the device says. Empty when nothing should be said.
  final String spoken;

  /// True for "cancel": the bar closes and no card is left behind.
  final bool dismiss;
}

/// Turns a [CommandOutcome] into the words a person reads and hears.
///
/// The only Flutter-dependent piece of the command layer -- it needs
/// [PuckStrings] for the locale -- which is why it is a separate class from the
/// executor. Everything above this line is pure Dart and tested as such.
class CommandNarrator {
  const CommandNarrator(this.strings);

  final PuckStrings strings;

  Narration narrate(CommandOutcome outcome) {
    switch (outcome) {
      case VolumeChanged(:final int percent):
        // A relative change still reports the resulting level, because "one
        // step up" tells nobody where they now are.
        return _say(strings.cmdVolumeLevel(percent));
      case VolumeAdjusted(:final int steps):
        return _say(steps >= 0 ? strings.cmdVolumeUp : strings.cmdVolumeDown);
      case VolumeMuted(:final bool muted):
        return _say(muted ? strings.cmdMuted : strings.cmdUnmuted);
      case VolumeUnavailable():
        return _say(strings.cmdVolumeUnavailable);
      case FlashlightChanged(:final bool on):
        return _say(on ? strings.cmdTorchOn : strings.cmdTorchOff);
      case TorchUnavailable():
        return _say(strings.cmdTorchUnavailable);
      case AppOpened(:final String label):
        return _say(strings.cmdOpening(label));
      case AppNotFound(:final String spokenName):
        return _say(strings.cmdAppNotFound(spokenName));
      case AppLaunchFailed(:final String label):
        return _say(strings.cmdAppFailed(label));
      case BatteryReported(:final int percent, :final bool charging):
        return _say(strings.cmdBattery(percent, charging));
      case BatteryUnavailable():
        return _say(strings.cmdBatteryUnavailable);
      case TimeReported(:final DateTime now):
        return _say(strings.cmdTimeLine(now));
      case DateReported(:final DateTime now):
        return _say(strings.cmdDateLine(now));
      case Calculated(:final String expression, :final double value):
        final String number = formatNumber(value);
        return Narration(
          display: strings.cmdAnswerCard(expression, number),
          spoken: strings.cmdAnswerSpoken(number),
        );
      case Converted(
          :final double value,
          :final Unit from,
          :final Unit to,
          :final double result,
        ):
        final String input = formatNumber(value);
        final String output = formatNumber(result);
        return Narration(
          display: strings.cmdConvertCard(input, from.id, output, to.id),
          spoken: strings.cmdConvertSpoken(
            input,
            from.pronounce,
            output,
            to.pronounce,
          ),
        );
      case ConversionImpossible(:final Unit from, :final Unit to):
        return _say(strings.cmdConvertImpossible(from.pronounce, to.pronounce));
      case TimerStarted(:final Duration duration):
        final String spoken = strings.spokenDuration(duration);
        return Narration(
          display: strings.cmdTimerCard(spoken),
          spoken: strings.cmdTimerSpoken(spoken),
        );
      case TimerUnavailable():
        return _say(strings.cmdTimerUnavailable);
      case AlarmSet(:final DateTime at):
        final String clock = strings.clock(at);
        return Narration(
          display: strings.cmdAlarmCard(clock),
          spoken: strings.cmdAlarmSpoken(clock),
        );
      case AlarmUnavailable():
        return _say(strings.cmdAlarmUnavailable);
      case HelpShown():
        return _say(strings.cmdHelp);
      case Cancelled():
        return const Narration(display: '', spoken: '', dismiss: true);
      case RefusedConsequential(:final ConsequentialKind kind):
        return _say(switch (kind) {
          ConsequentialKind.call => strings.cmdRefusedCall,
          ConsequentialKind.message => strings.cmdRefusedMessage,
          ConsequentialKind.deleteData => strings.cmdRefusedDelete,
          ConsequentialKind.shareLocation => strings.cmdRefusedShare,
        });
      case CommandFailed():
        return _say(strings.cmdFailed);
    }
  }

  Narration _say(String line) => Narration(display: line, spoken: line);

  /// "96" not "96.0", "6.21" not "6.210000001".
  ///
  /// One rule for the card and for speech, so the two can never disagree about
  /// the answer -- the bug where the screen says 6.2 and the voice says
  /// 6.2137 is exactly the kind of thing a person notices and never forgives.
  static String formatNumber(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    final String fixed = value.toStringAsFixed(4);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
