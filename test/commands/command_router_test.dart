import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/commands/command_executor.dart';
import 'package:puck/src/commands/command_intent.dart';
import 'package:puck/src/commands/command_outcome.dart';
import 'package:puck/src/commands/command_parser.dart';
import 'package:puck/src/commands/command_router.dart';

/// The router: parse, guard against double execution, execute.
///
/// Two things are being tested here and they are both about *not* acting: an
/// utterance that is not a command must return null so the answer path gets it,
/// and an utterance that arrives twice must act once. A doubled "torch on" is
/// not a harmless repeat -- the second one turns the torch off.

class _CountingVolume implements VolumePort {
  int sets = 0;
  int adjusts = 0;
  int level = 30;

  /// Set to make the executor's call hang, so a second route overlaps it.
  bool hold = false;

  @override
  Future<int?> percent() async => level;

  @override
  Future<bool> setPercent(int percent) async {
    sets++;
    if (hold) await Future<void>.delayed(const Duration(milliseconds: 30));
    level = percent;
    return true;
  }

  @override
  Future<bool> adjust(int steps) async {
    adjusts++;
    if (hold) await Future<void>.delayed(const Duration(milliseconds: 30));
    return true;
  }

  @override
  Future<bool> setMuted(bool muted) async => true;

  @override
  Future<bool?> isMuted() async => false;
}

class _NullApps implements AppLauncherPort {
  @override
  Future<String?> open(String spokenName) async => null;
}

class _DeadClock implements ClockPort {
  @override
  Future<bool> startTimer(Duration duration) async => false;

  @override
  Future<bool> setAlarm(DateTime at) async => false;
}

class _DarkTorch implements TorchPort {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> setOn(bool on) async => false;
}

class _NoBattery implements BatteryPort {
  @override
  Future<({int percent, bool charging})?> read() async => null;
}

void main() {
  late _CountingVolume volume;
  late DateTime clockNow;
  late CommandRouter router;

  setUp(() {
    volume = _CountingVolume();
    clockNow = DateTime(2026, 11, 2, 12);
    router = CommandRouter(
      parser: CommandParser(assistantName: 'Puck'),
      executor: CommandExecutor(
        volume: volume,
        apps: _NullApps(),
        clock: _DeadClock(),
        torch: _DarkTorch(),
        battery: _NoBattery(),
        now: () => clockNow,
      ),
      now: () => clockNow,
      duplicateWindow: const Duration(milliseconds: 1500),
    );
  });

  group('not a command', () {
    test('a question is left for the answer path', () async {
      expect(await router.route('what is the capital of France'), isNull);
      expect(await router.route('tell me a joke'), isNull);
      expect(volume.sets, 0);
      expect(volume.adjusts, 0);
    });

    test('empty input does nothing at all', () async {
      expect(await router.route('   '), isNull);
    });

    test('a phrase that starts like a command but is not', () async {
      // The dictionary has no entry for this pairing; it must not be executed
      // as a volume change just because it contains the word "volume".
      expect(await router.route('volume of a sphere with radius three'), isNull);
    });
  });

  group('execution', () {
    test('a command comes back handled, with its outcome', () async {
      final CommandDispatch? dispatch = await router.route('volume up');

      expect(dispatch, isA<CommandHandled>());
      final CommandHandled handled = dispatch! as CommandHandled;
      expect(handled.intent, isA<AdjustVolumeIntent>());
      expect(handled.outcome, isA<CommandOutcome>());
      expect(volume.adjusts, 1);
    });

    test('the parser is reachable for diagnostics', () {
      expect(router.parser.normalize('Hey Puck, mute.'), 'mute');
    });
  });

  group('duplicate protection', () {
    test('the same utterance twice inside the window runs once', () async {
      final CommandDispatch? first = await router.route('volume up');
      final CommandDispatch? second = await router.route('volume up');

      expect(first, isA<CommandHandled>());
      expect(second, isA<CommandDuplicate>());
      expect(volume.adjusts, 1);
    });

    test('punctuation and spacing do not defeat the guard', () async {
      await router.route('Volume up!');
      expect(await router.route('volume   up'), isA<CommandDuplicate>());
      expect(volume.adjusts, 1);
    });

    test('the same words after the window really do run again', () async {
      await router.route('volume up');
      clockNow = clockNow.add(const Duration(seconds: 2));
      expect(await router.route('volume up'), isA<CommandHandled>());
      expect(volume.adjusts, 2);
    });

    test('an overlapping command is dropped, not queued', () async {
      volume.hold = true;
      final Future<CommandDispatch?> first = router.route('volume up');
      final CommandDispatch? overlapping = await router.route('volume up');
      await first;

      expect(overlapping, isA<CommandDuplicate>());
      expect(volume.adjusts, 1);
    });

    test('a different command during a slow one is not a duplicate', () async {
      volume.hold = true;
      final Future<CommandDispatch?> first = router.route('volume up');
      // _running still guards this one: one action at a time, whatever it is.
      final CommandDispatch? other = await router.route('set volume to 10');
      await first;

      expect(other, isA<CommandDuplicate>());
      expect(volume.sets, 0);
    });

    test('reset clears the window for a new session', () async {
      await router.route('volume up');
      router.reset();
      expect(await router.route('volume up'), isA<CommandHandled>());
      expect(volume.adjusts, 2);
    });
  });

  group('honest failure', () {
    test('a refused timer still comes back handled, with a refusal', () async {
      final CommandDispatch? dispatch = await router.route('set a timer for 5 minutes');

      expect(dispatch, isA<CommandHandled>());
      expect((dispatch! as CommandHandled).outcome, isA<TimerUnavailable>());
    });

    test('a missing torch is reported, and the command still counts as handled', () async {
      final CommandDispatch? dispatch = await router.route('turn the torch on');

      expect(
        (dispatch! as CommandHandled).outcome,
        isA<TorchUnavailable>(),
      );
    });
  });
}
