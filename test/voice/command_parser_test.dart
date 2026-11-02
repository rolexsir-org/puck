import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/commands/command_intent.dart';
import 'package:puck/src/commands/command_parser.dart';
import 'package:puck/src/commands/units.dart';

/// What a person says, and what Puck does about it.
///
/// These are the acceptance tests for the command layer: every phrase here is
/// one a real person would speak, and the expectation is the intent that must
/// come out -- or, just as importantly, `null`, so the sentence goes to the
/// answer path instead of doing something to the phone.
void main() {
  final CommandParser parser = CommandParser(assistantName: 'Puck');

  group('normalisation', () {
    test('strips the wake phrase, filler and punctuation', () {
      expect(parser.normalize('Hey Puck, turn the torch on.'), 'turn the torch on');
      expect(parser.normalize('OKAY PUCK  volume up!'), 'volume up');
      expect(parser.normalize('Puck, hey, what time is it?'), 'hey what time is it');
      expect(parser.normalize('Please turn it up'), 'turn it up');
    });

    test('expands contractions so one pattern covers both spellings', () {
      expect(parser.normalize("What's the time"), 'what is the time');
      expect(parser.normalize('whats the time'), 'what is the time');
    });

    test('keeps decimal points and maths operators', () {
      expect(parser.normalize('what is 2.5 + 2'), 'what is 2.5 + 2');
    });

    test('the duplicate guard sees the same string twice', () {
      expect(parser.normalize('Volume up!'), parser.normalize('volume  up'));
    });
  });

  group('volume', () {
    test('set by number', () {
      expect(
        parser.parse('set the volume to 40'),
        isA<SetVolumeIntent>().having((SetVolumeIntent i) => i.percent, 'percent', 40),
      );
      expect(
        parser.parse('volume 15 percent'),
        isA<SetVolumeIntent>().having((SetVolumeIntent i) => i.percent, 'percent', 15),
      );
    });

    test('set by spoken number', () {
      expect(
        parser.parse('set volume to forty two'),
        isA<SetVolumeIntent>().having((SetVolumeIntent i) => i.percent, 'percent', 42),
      );
      expect(
        parser.parse('volume twenty five'),
        isA<SetVolumeIntent>().having((SetVolumeIntent i) => i.percent, 'percent', 25),
      );
    });

    test('max and min', () {
      expect(
        parser.parse('volume max'),
        isA<SetVolumeIntent>().having((SetVolumeIntent i) => i.percent, 'percent', 100),
      );
      expect(
        parser.parse('set the volume to minimum'),
        isA<SetVolumeIntent>().having((SetVolumeIntent i) => i.percent, 'percent', 0),
      );
    });

    test('up and down, in natural variations', () {
      for (final String phrase in <String>[
        'volume up',
        'turn it up',
        'louder',
        'raise the volume',
        'increase the volume',
        'a bit louder',
        'turn up the music',
      ]) {
        expect(
          parser.parse(phrase),
          isA<AdjustVolumeIntent>()
              .having((AdjustVolumeIntent i) => i.steps, 'steps', 1),
          reason: phrase,
        );
      }
      for (final String phrase in <String>[
        'volume down',
        'turn it down',
        'quieter',
        'lower the volume',
        'reduce the volume',
      ]) {
        expect(
          parser.parse(phrase),
          isA<AdjustVolumeIntent>()
              .having((AdjustVolumeIntent i) => i.steps, 'steps', -1),
          reason: phrase,
        );
      }
    });

    test('by a number of steps', () {
      expect(
        parser.parse('turn it up by three steps'),
        isA<AdjustVolumeIntent>()
            .having((AdjustVolumeIntent i) => i.steps, 'steps', 3),
      );
      expect(
        parser.parse('volume down two notches'),
        isA<AdjustVolumeIntent>()
            .having((AdjustVolumeIntent i) => i.steps, 'steps', -2),
      );
    });

    test('mute and unmute', () {
      for (final String phrase in <String>[
        'mute',
        'mute it',
        'silence',
        'be quiet',
        'sound off',
        'turn the sound off',
      ]) {
        expect(
          parser.parse(phrase),
          isA<MuteIntent>().having((MuteIntent i) => i.muted, 'muted', true),
          reason: phrase,
        );
      }
      expect(
        parser.parse('unmute'),
        isA<MuteIntent>().having((MuteIntent i) => i.muted, 'muted', false),
      );
      expect(
        parser.parse('sound on'),
        isA<MuteIntent>().having((MuteIntent i) => i.muted, 'muted', false),
      );
    });

    test('a volume that is not a volume is not a command', () {
      // 150% does not exist; guessing would set it to maximum and be wrong.
      expect(parser.parse('volume 150'), isNull);
      // "the volume is too loud" is a statement, not a request.
      expect(parser.parse('the volume is too loud'), isNull);
    });
  });

  group('flashlight', () {
    test('on', () {
      for (final String phrase in <String>[
        'turn on the flashlight',
        'torch on',
        'switch on the light',
        'turn the lamp on',
      ]) {
        expect(
          parser.parse(phrase),
          isA<FlashlightIntent>().having((FlashlightIntent i) => i.on, 'on', true),
          reason: phrase,
        );
      }
    });

    test('off', () {
      for (final String phrase in <String>[
        'turn off the torch',
        'flashlight off',
        'switch the light off',
      ]) {
        expect(
          parser.parse(phrase),
          isA<FlashlightIntent>().having((FlashlightIntent i) => i.on, 'on', false),
          reason: phrase,
        );
      }
    });
  });

  group('apps', () {
    test('open an app by name', () {
      expect(
        parser.parse('open calculator'),
        isA<OpenAppIntent>()
            .having((OpenAppIntent i) => i.spokenName, 'name', 'calculator'),
      );
      expect(
        parser.parse('launch the camera app'),
        isA<OpenAppIntent>()
            .having((OpenAppIntent i) => i.spokenName, 'name', 'camera'),
      );
    });
  });

  group('information', () {
    test('battery', () {
      expect(parser.parse('battery'), isA<BatteryIntent>());
      expect(parser.parse('how much battery do i have'), isA<BatteryIntent>());
      expect(parser.parse('battery level'), isA<BatteryIntent>());
    });

    test('time and date', () {
      expect(parser.parse('what time is it'), isA<TimeIntent>());
      expect(parser.parse("what's the time"), isA<TimeIntent>());
      expect(parser.parse('current time'), isA<TimeIntent>());
      expect(parser.parse('what is the date'), isA<DateIntent>());
      expect(parser.parse('what day is it'), isA<DateIntent>());
    });

    test('arithmetic, spoken and symbolic', () {
      expect(
        parser.parse('what is 12 times 8'),
        isA<CalculateIntent>()
            .having((CalculateIntent i) => i.value, 'value', 96.0),
      );
      expect(
        parser.parse('5 plus 3'),
        isA<CalculateIntent>()
            .having((CalculateIntent i) => i.value, 'value', 8.0),
      );
      expect(
        parser.parse('twenty five divided by five'),
        isA<CalculateIntent>()
            .having((CalculateIntent i) => i.value, 'value', 5.0),
      );
      expect(
        parser.parse('15 percent of 240'),
        isA<CalculateIntent>()
            .having((CalculateIntent i) => i.value, 'value', 36.0),
      );
      expect(
        parser.parse('2 + 2 * 3'),
        isA<CalculateIntent>()
            .having((CalculateIntent i) => i.value, 'value', 8.0),
      );
    });

    test('a bare number is a question, not a calculation', () {
      expect(parser.parse('what is 5'), isNull);
    });

    test('unit conversion, three ways', () {
      final CommandIntent? convert = parser.parse('convert 10 km to miles');
      expect(convert, isA<ConvertIntent>());
      final ConvertIntent c = convert! as ConvertIntent;
      expect(c.value, 10);
      expect(c.from.id, 'km');
      expect(c.to.id, 'mi');

      expect(
        parser.parse('how many pounds in 5 kg'),
        isA<ConvertIntent>()
            .having((ConvertIntent i) => i.from.id, 'from', 'kg')
            .having((ConvertIntent i) => i.to.id, 'to', 'lb'),
      );
      expect(
        parser.parse('72 f to c'),
        isA<ConvertIntent>()
            .having((ConvertIntent i) => i.from.id, 'from', 'f')
            .having((ConvertIntent i) => i.to.id, 'to', 'c'),
      );
    });
  });

  group('clock', () {
    test('timers', () {
      expect(
        parser.parse('set a timer for 5 minutes'),
        isA<SetTimerIntent>()
            .having((SetTimerIntent i) => i.duration, 'duration',
                const Duration(minutes: 5)),
      );
      expect(
        parser.parse('timer 90 seconds'),
        isA<SetTimerIntent>()
            .having((SetTimerIntent i) => i.duration, 'duration',
                const Duration(seconds: 90)),
      );
      expect(
        parser.parse('set a timer for half an hour'),
        isA<SetTimerIntent>()
            .having((SetTimerIntent i) => i.duration, 'duration',
                const Duration(minutes: 30)),
      );
      expect(
        parser.parse('remind me in one hour and a half'),
        isA<SetTimerIntent>()
            .having((SetTimerIntent i) => i.duration, 'duration',
                const Duration(minutes: 90)),
      );
    });

    test('an alarm with a time', () {
      final CommandIntent? intent = parser.parse('set an alarm for 7:30 am');
      expect(intent, isA<SetAlarmIntent>());
      final SetAlarmIntent alarm = intent! as SetAlarmIntent;
      expect(alarm.hour, 7);
      expect(alarm.minute, 30);
      expect(alarm.explicitMeridiem, isTrue);
    });

    test('an evening alarm', () {
      final CommandIntent? intent = parser.parse('wake me up at 6 pm');
      expect(intent, isA<SetAlarmIntent>());
      final SetAlarmIntent alarm = intent! as SetAlarmIntent;
      expect(alarm.hour, 18);
      expect(alarm.explicitMeridiem, isTrue);
    });

    test('an alarm with no am/pm is marked ambiguous', () {
      final CommandIntent? intent = parser.parse('set an alarm for 7');
      expect(intent, isA<SetAlarmIntent>());
      expect((intent! as SetAlarmIntent).explicitMeridiem, isFalse);
    });

    test('wake me in twenty minutes is a timer, not an alarm', () {
      expect(
        parser.parse('wake me in 20 minutes'),
        isA<SetTimerIntent>()
            .having((SetTimerIntent i) => i.duration, 'duration',
                const Duration(minutes: 20)),
      );
    });
  });

  group('safety', () {
    test('consequential requests are recognised so they can be refused', () {
      expect(
        parser.parse('call mom'),
        isA<ConsequentialIntent>()
            .having((ConsequentialIntent i) => i.kind, 'kind',
                ConsequentialKind.call),
      );
      expect(
        parser.parse('send a message to sam'),
        isA<ConsequentialIntent>()
            .having((ConsequentialIntent i) => i.kind, 'kind',
                ConsequentialKind.message),
      );
      expect(
        parser.parse('text sam that i am late'),
        isA<ConsequentialIntent>()
            .having((ConsequentialIntent i) => i.kind, 'kind',
                ConsequentialKind.message),
      );
      expect(
        parser.parse('delete all my data'),
        isA<ConsequentialIntent>()
            .having((ConsequentialIntent i) => i.kind, 'kind',
                ConsequentialKind.deleteData),
      );
      expect(
        parser.parse('share my location'),
        isA<ConsequentialIntent>()
            .having((ConsequentialIntent i) => i.kind, 'kind',
                ConsequentialKind.shareLocation),
      );
    });

    test('an unsupported sentence is not a command at all', () {
      // This is the case that must never reach an executor: the answer path is
      // where open-ended sentences belong.
      for (final String phrase in <String>[
        'what is the weather like',
        'tell me a joke',
        'who won the match yesterday',
        'i am hungry',
        'что это',
      ]) {
        expect(parser.parse(phrase), isNull, reason: phrase);
      }
    });
  });

  group('conversation', () {
    test('help and cancel', () {
      expect(parser.parse('what can you do'), isA<HelpIntent>());
      expect(parser.parse('help'), isA<HelpIntent>());
      expect(parser.parse('stop'), isA<CancelIntent>());
      expect(parser.parse('never mind'), isA<CancelIntent>());
    });

    test('the assistant name is configurable, and only strips the prefix', () {
      final CommandParser jarvis = CommandParser(assistantName: 'Jarvis');
      expect(jarvis.normalize('Hey Jarvis, volume up'), 'volume up');
      expect(jarvis.parse('jarvis torch on'), isA<FlashlightIntent>());
      // Renaming does not remove the default word from unrelated sentences.
      expect(jarvis.parse('puck is a game'), isNull);
    });
  });

  group('the unit table', () {
    test('converts within a kind', () {
      expect(Units.convert(10, Units.kilometre, Units.mile)!.closeTo(6.2137, 0.001),
          isTrue);
      expect(Units.convert(5, Units.kilogram, Units.pound)!.closeTo(11.023, 0.01),
          isTrue);
      expect(Units.convert(100, Units.celsius, Units.fahrenheit)!, 212);
      expect(Units.convert(72, Units.fahrenheit, Units.celsius)!.closeTo(22.22, 0.01),
          isTrue);
    });

    test('refuses across kinds', () {
      expect(Units.convert(5, Units.kilogram, Units.mile), isNull);
    });

    test('resolves spoken aliases', () {
      expect(Units.resolve('kilometres')?.id, 'km');
      expect(Units.resolve('pounds')?.id, 'lb');
      expect(Units.resolve('degrees fahrenheit')?.id, 'f');
      expect(Units.resolve('banana'), isNull);
    });
  });

  group('phrases that only look like commands', () {
    test('"volume of a sphere" is not a volume level', () {
      // The setter must not read its own trailing words as a percentage. A
      // misparse here would set the media volume to 0 while claiming success.
      expect(parser.parse('volume of a sphere with radius three'), isNull);
      expect(parser.parse('volume down two notches'), isA<AdjustVolumeIntent>());
      expect(parser.parse('turn the volume down'), isA<AdjustVolumeIntent>());
    });

    test('both word orders for the torch', () {
      expect(parser.parse('turn on the torch'), isA<FlashlightIntent>());
      expect(parser.parse('turn the torch on'), isA<FlashlightIntent>());
      expect(parser.parse('turn the lights off'), isA<FlashlightIntent>());
      expect(parser.parse('switch off the lamp'), isA<FlashlightIntent>());
    });

    test('a bare hour after "alarm for" is an alarm, not a duration', () {
      final CommandIntent? seven = parser.parse('set an alarm for seven');
      expect(seven, isA<SetAlarmIntent>());
      expect((seven! as SetAlarmIntent).hour, 7);

      // Digits with no am/pm: parseClockTime wants a colon or a meridiem, so
      // this case is why the alarm branch has its own bare-hour fallback.
      final CommandIntent? digits = parser.parse('set an alarm for 7');
      expect(digits, isA<SetAlarmIntent>());
      expect((digits! as SetAlarmIntent).hour, 7);

      // The timer grammar owns "for five minutes"; it must not become 05:00.
      expect(parser.parse('set a timer for five minutes'), isA<SetTimerIntent>());
    });
  });
}
