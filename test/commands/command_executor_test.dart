import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/commands/command_executor.dart';
import 'package:puck/src/commands/command_intent.dart';
import 'package:puck/src/commands/command_outcome.dart';
import 'package:puck/src/commands/units.dart';

/// The executor, against fake ports.
///
/// No device, no plugins, no microphone: every Android capability is a five
/// method interface, so the interesting behaviour -- what the assistant says
/// when the phone refuses, when it cannot report a number, or when a launcher
/// throws -- can be tested on a laptop in milliseconds.
///
/// The rule these tests exist to protect is in the first group: **never claim
/// success that did not happen.** A false "done" is the one bug in an assistant
/// that people never forgive.

class _FakeVolume implements VolumePort {
  _FakeVolume({
    this.accept = true,
    this.level = 50,
    this.levelAfterChange,
    this.reportLevel = true,
    this.muted = false,
    this.throwOnSet = false,
  });

  /// What the platform says to a change request.
  bool accept;

  /// What `percent()` reports before a change (and after, unless
  /// [levelAfterChange] is set).
  int? level;
  int? levelAfterChange;
  bool reportLevel;
  bool? muted;
  bool throwOnSet;

  int? lastSet;
  int? lastAdjust;
  bool? lastMute;

  @override
  Future<int?> percent() async {
    if (!reportLevel) return null;
    return level;
  }

  @override
  Future<bool> setPercent(int percent) async {
    if (throwOnSet) throw StateError('audio service died');
    lastSet = percent;
    if (accept && levelAfterChange != null) level = levelAfterChange;
    return accept;
  }

  @override
  Future<bool> adjust(int steps) async {
    if (throwOnSet) throw StateError('audio service died');
    lastAdjust = steps;
    if (accept && levelAfterChange != null) level = levelAfterChange;
    return accept;
  }

  @override
  Future<bool> setMuted(bool muted) async {
    lastMute = muted;
    if (accept) this.muted = muted;
    return accept;
  }

  @override
  Future<bool?> isMuted() async => muted;
}

class _FakeApps implements AppLauncherPort {
  _FakeApps({this.label, this.throws = false});

  String? label;
  bool throws;

  @override
  Future<String?> open(String spokenName) async {
    if (throws) throw AppLaunchException('Calculator');
    return label;
  }
}

class _FakeClock implements ClockPort {
  _FakeClock({this.accept = true});

  bool accept;
  Duration? timer;
  DateTime? alarm;

  @override
  Future<bool> startTimer(Duration duration) async {
    timer = duration;
    return accept;
  }

  @override
  Future<bool> setAlarm(DateTime at) async {
    alarm = at;
    return accept;
  }
}

class _FakeTorch implements TorchPort {
  _FakeTorch({this.available = true, this.accept = true});

  bool available;
  bool accept;
  bool? lastSet;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> setOn(bool on) async {
    lastSet = on;
    return accept;
  }
}

class _FakeBattery implements BatteryPort {
  _FakeBattery({this.percent, this.charging = false});

  int? percent;
  bool charging;

  @override
  Future<({int percent, bool charging})?> read() async {
    final int? level = percent;
    if (level == null) return null;
    return (percent: level, charging: charging);
  }
}

void main() {
  late _FakeVolume volume;
  late _FakeApps apps;
  late _FakeClock clock;
  late _FakeTorch torch;
  late _FakeBattery battery;

  /// 2026-11-02 15:30 local. Fixed so alarm arithmetic is deterministic.
  final DateTime now = DateTime(2026, 11, 2, 15, 30);

  CommandExecutor build() => CommandExecutor(
        volume: volume,
        apps: apps,
        clock: clock,
        torch: torch,
        battery: battery,
        now: () => now,
      );

  setUp(() {
    volume = _FakeVolume();
    apps = _FakeApps(label: 'Calculator');
    clock = _FakeClock();
    torch = _FakeTorch();
    battery = _FakeBattery(percent: 42, charging: true);
  });

  group('volume', () {
    test('reports the level the phone settled on, not the one asked for', () async {
      volume
        ..accept = true
        ..level = 50
        ..levelAfterChange = 40;

      final CommandOutcome outcome =
          await build().execute(const SetVolumeIntent(40));

      expect(volume.lastSet, 40);
      expect(outcome, isA<VolumeChanged>());
      expect((outcome as VolumeChanged).percent, 40);
      expect(outcome.steps, isNull);
    });

    test('a refused set is reported as unavailable, never as success', () async {
      volume.accept = false;

      final CommandOutcome outcome =
          await build().execute(const SetVolumeIntent(80));

      expect(outcome, isA<VolumeUnavailable>());
    });

    test('when the phone will not report a level, the request is echoed', () async {
      volume
        ..levelAfterChange = null
        ..reportLevel = false;

      final CommandOutcome outcome =
          await build().execute(const SetVolumeIntent(30));

      expect((outcome as VolumeChanged).percent, 30);
    });

    test('a relative change says the direction when the level is unknown', () async {
      volume
        ..reportLevel = false
        ..levelAfterChange = null;

      final CommandOutcome outcome =
          await build().execute(const AdjustVolumeIntent(2));

      expect(volume.lastAdjust, 2);
      expect(outcome, isA<VolumeAdjusted>());
      expect((outcome as VolumeAdjusted).steps, 2);
    });

    test('mute confirms against the device, not against the request', () async {
      volume
        ..accept = true
        ..muted = false;

      final CommandOutcome outcome =
          await build().execute(const MuteIntent(muted: true));

      expect(volume.lastMute, isTrue);
      expect((outcome as VolumeMuted).muted, isTrue);
    });

    test('an exception from the audio service becomes a failure, not a crash', () async {
      volume.throwOnSet = true;

      final CommandOutcome outcome =
          await build().execute(const SetVolumeIntent(60));

      expect(outcome, isA<CommandFailed>());
    });
  });

  group('flashlight', () {
    test('on and off reach the torch port', () async {
      expect(
        await build().execute(const FlashlightIntent(on: true)),
        isA<FlashlightChanged>(),
      );
      expect(torch.lastSet, isTrue);

      expect(
        await build().execute(const FlashlightIntent(on: false)),
        isA<FlashlightChanged>(),
      );
      expect(torch.lastSet, isFalse);
    });

    test('no torch on this device is said out loud', () async {
      torch.available = false;

      final CommandOutcome outcome =
          await build().execute(const FlashlightIntent(on: true));

      expect(outcome, isA<TorchUnavailable>());
      expect(torch.lastSet, isNull);
    });

    test('a torch the camera already holds is unavailable, not on', () async {
      torch.accept = false;

      expect(
        await build().execute(const FlashlightIntent(on: true)),
        isA<TorchUnavailable>(),
      );
    });
  });

  group('apps', () {
    test('reports the app own label', () async {
      apps.label = 'Calculator';

      final CommandOutcome outcome =
          await build().execute(const OpenAppIntent('calculator'));

      expect((outcome as AppOpened).label, 'Calculator');
    });

    test('nothing installed is a normal answer', () async {
      apps.label = null;

      final CommandOutcome outcome =
          await build().execute(const OpenAppIntent('metro'));

      expect(outcome, isA<AppNotFound>());
      expect((outcome as AppNotFound).spokenName, 'metro');
    });

    test('matched but refused keeps the label for an honest message', () async {
      apps.throws = true;

      final CommandOutcome outcome =
          await build().execute(const OpenAppIntent('calculator'));

      expect(outcome, isA<AppLaunchFailed>());
      expect((outcome as AppLaunchFailed).label, 'Calculator');
    });
  });

  group('information', () {
    test('battery reports the snapshot', () async {
      final CommandOutcome outcome =
          await build().execute(const BatteryIntent());

      expect(outcome, isA<BatteryReported>());
      expect((outcome as BatteryReported).percent, 42);
      expect(outcome.charging, isTrue);
    });

    test('battery unknown is said, not guessed', () async {
      battery.percent = null;

      expect(
        await build().execute(const BatteryIntent()),
        isA<BatteryUnavailable>(),
      );
    });

    test('time and date come from the injected clock', () async {
      final CommandOutcome time = await build().execute(const TimeIntent());
      expect((time as TimeReported).now, now);

      final CommandOutcome date = await build().execute(const DateIntent());
      expect((date as DateReported).now, now);
    });

    test('arithmetic is computed before it is narrated', () async {
      final CommandOutcome outcome = await build().execute(
        const CalculateIntent(value: 12.5, expression: '5 + 7.5'),
      );

      expect((outcome as Calculated).value, 12.5);
      expect(outcome.expression, '5 + 7.5');
    });
  });

  group('conversion', () {
    test('kilometres to miles', () async {
      final CommandOutcome outcome = await build().execute(
        const ConvertIntent(
          value: 5,
          from: Units.kilometre,
          to: Units.mile,
        ),
      );

      expect(outcome, isA<Converted>());
      expect((outcome as Converted).result, closeTo(3.1069, 0.001));
    });

    test('a pair with no conversion is impossible, not zero', () async {
      final CommandOutcome outcome = await build().execute(
        const ConvertIntent(
          value: 5,
          from: Units.kilogram,
          to: Units.second,
        ),
      );

      expect(outcome, isA<ConversionImpossible>());
    });
  });

  group('clock', () {
    test('timer passes the duration through', () async {
      final CommandOutcome outcome = await build()
          .execute(const SetTimerIntent(Duration(minutes: 5, seconds: 30)));

      expect(clock.timer, const Duration(minutes: 5, seconds: 30));
      expect((outcome as TimerStarted).duration,
          const Duration(minutes: 5, seconds: 30));
    });

    test('a timer the platform refused is not announced as started', () async {
      clock.accept = false;

      expect(
        await build().execute(const SetTimerIntent(Duration(minutes: 1))),
        isA<TimerUnavailable>(),
      );
    });

    test('alarm is resolved to a real date before the intent is sent', () async {
      await build().execute(
        const SetAlarmIntent(hour: 7, minute: 0, explicitMeridiem: false),
      );

      // 15:30 + "seven" -> tomorrow 07:00 is nearer than today's 07:00 has
      // passed; 19:00 today is nearer still.
      expect(clock.alarm, DateTime(2026, 11, 2, 19, 0));
    });

    test('an alarm the platform refused is not announced as set', () async {
      clock.accept = false;

      expect(
        await build().execute(
          const SetAlarmIntent(hour: 7, minute: 0, explicitMeridiem: true),
        ),
        isA<AlarmUnavailable>(),
      );
    });
  });

  group('alarm resolution', () {
    DateTime resolve({
      required DateTime at,
      required int hour,
      int minute = 0,
      bool explicitMeridiem = false,
    }) =>
        CommandExecutor.resolveAlarm(
          now: at,
          hour: hour,
          minute: minute,
          explicitMeridiem: explicitMeridiem,
        );

    test('a passed hour rolls to tomorrow', () {
      expect(
        resolve(at: DateTime(2026, 11, 2, 9), hour: 7, explicitMeridiem: true),
        DateTime(2026, 11, 3, 7),
      );
    });

    test('a bare hour picks the nearer half of the day', () {
      expect(resolve(at: DateTime(2026, 11, 2, 8), hour: 7),
          DateTime(2026, 11, 2, 19));
      expect(resolve(at: DateTime(2026, 11, 2, 20), hour: 7),
          DateTime(2026, 11, 3, 7));
    });

    test('an evening hour stays in the evening', () {
      expect(resolve(at: DateTime(2026, 11, 2, 15, 30), hour: 21),
          DateTime(2026, 11, 2, 21));
    });

    test('the same minute right now rolls forward rather than firing instantly', () {
      expect(
        resolve(
          at: DateTime(2026, 11, 2, 7),
          hour: 7,
          explicitMeridiem: true,
        ),
        DateTime(2026, 11, 3, 7),
      );
    });
  });

  group('refusals', () {
    test('a message is never sent, only declined', () async {
      final CommandOutcome outcome = await build().execute(
        const ConsequentialIntent(
          kind: ConsequentialKind.message,
          detail: 'text mom I am late',
        ),
      );

      expect(outcome, isA<RefusedConsequential>());
      expect(
        (outcome as RefusedConsequential).kind,
        ConsequentialKind.message,
      );
    });

    test('help and cancel are answered without touching the device', () async {
      expect(await build().execute(const HelpIntent()), isA<HelpShown>());
      expect(await build().execute(const CancelIntent()), isA<Cancelled>());
    });
  });
}
