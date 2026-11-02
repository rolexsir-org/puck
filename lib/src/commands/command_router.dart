import 'package:puck/src/commands/command_executor.dart';
import 'package:puck/src/commands/command_intent.dart';
import 'package:puck/src/commands/command_outcome.dart';
import 'package:puck/src/commands/command_parser.dart';

/// The result of offering an utterance to the command layer.
sealed class CommandDispatch {
  const CommandDispatch();
}

/// A command was recognised and executed.
final class CommandHandled extends CommandDispatch {
  const CommandHandled({required this.intent, required this.outcome});

  final CommandIntent intent;
  final CommandOutcome outcome;
}

/// The same utterance arrived twice inside the duplicate window, so the second
/// one did nothing.
///
/// This is not paranoia. A voice session can deliver the same final transcript
/// from two paths (a VAD segment that ended on silence, and a stop button that
/// ended the same capture), and a double "mute" or a double "torch off" is a
/// user-visible bug. Worse, a doubled *torch on* cancels itself out.
final class CommandDuplicate extends CommandDispatch {
  const CommandDuplicate(this.intent);

  final CommandIntent intent;
}

/// Parse, then execute -- with two guards around the execution.
///
/// Deliberately tiny. The intelligence is in [CommandParser] (what did they
/// mean) and [CommandExecutor] (do it and report honestly); this class only
/// decides whether to run at all.
class CommandRouter {
  CommandRouter({
    required CommandParser parser,
    required CommandExecutor executor,
    DateTime Function()? now,
    this.duplicateWindow = const Duration(milliseconds: 1500),
  })  : _parser = parser,
        _executor = executor,
        _now = now ?? DateTime.now;

  final CommandParser _parser;
  final CommandExecutor _executor;
  final DateTime Function() _now;

  /// How long an identical utterance is treated as the same request.
  final Duration duplicateWindow;

  String? _lastSignature;
  DateTime? _lastAt;
  bool _running = false;

  CommandParser get parser => _parser;

  /// Returns null when the utterance is not a Puck command, which is the
  /// caller's signal to answer it instead of executing it.
  Future<CommandDispatch?> route(String utterance) async {
    final CommandIntent? intent = _parser.parse(utterance);
    if (intent == null) return null;

    final String signature = _parser.normalize(utterance);
    final DateTime now = _now();
    final DateTime? last = _lastAt;
    final bool duplicate = _running ||
        (last != null &&
            signature == _lastSignature &&
            now.difference(last) < duplicateWindow);

    if (duplicate) return CommandDuplicate(intent);

    _lastSignature = signature;
    _lastAt = now;
    _running = true;
    try {
      final CommandOutcome outcome = await _executor.execute(intent);
      return CommandHandled(intent: intent, outcome: outcome);
    } finally {
      _running = false;
    }
  }

  /// Forgets the duplicate window. Called when a new voice session starts, so
  /// "louder" said twice on purpose, a minute apart, is two commands.
  void reset() {
    _lastSignature = null;
    _lastAt = null;
  }
}
