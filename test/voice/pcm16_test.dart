import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/voice/transcriber.dart';

/// PCM16 to float, byte for byte.
///
/// This is three lines of arithmetic that the entire recogniser depends on: the
/// models were trained on samples in [-1, 1], and a conversion that keeps the
/// wrong scale, the wrong endianness or the wrong sign does not fail loudly --
/// it produces a confident transcription of nothing. Which is why it is pinned
/// here rather than only exercised through a microphone.
void main() {
  Uint8List pcm(List<int> shorts) {
    final ByteData data = ByteData(shorts.length * 2);
    for (int i = 0; i < shorts.length; i++) {
      data.setInt16(i * 2, shorts[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  group('scale', () {
    test('silence is zero', () {
      expect(pcm16ToFloat32(pcm(<int>[0, 0, 0])), Float32List(3));
    });

    test('full positive scale is just under one', () {
      final Float32List samples = pcm16ToFloat32(pcm(<int>[32767]));
      expect(samples.single, closeTo(0.99997, 0.00001));
      expect(samples.single, lessThan(1.0));
    });

    test('full negative scale is exactly minus one', () {
      // -32768 / 32768 is the only case that reaches the rail. Dividing by
      // 32767 instead would make this clip and would put silence half a step
      // off centre.
      expect(pcm16ToFloat32(pcm(<int>[-32768])).single, -1.0);
    });

    test('half scale is half', () {
      expect(pcm16ToFloat32(pcm(<int>[16384])).single, 0.5);
      expect(pcm16ToFloat32(pcm(<int>[-16384])).single, -0.5);
    });
  });

  group('byte order', () {
    test('reads little endian, low byte first', () {
      // 0x0100 little-endian is 1; big-endian would read it as 256.
      expect(pcm16ToFloat32(Uint8List.fromList(<int>[0x01, 0x00])).single,
          closeTo(1 / 32768, 1e-9));
      expect(pcm16ToFloat32(Uint8List.fromList(<int>[0x00, 0x01])).single,
          closeTo(256 / 32768, 1e-9));
    });

    test('a negative value keeps its sign across both bytes', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0xFF, 0xFF]);
      expect(pcm16ToFloat32(bytes).single, closeTo(-1 / 32768, 1e-9));
    });
  });

  group('shape', () {
    test('one float per pair of bytes', () {
      expect(pcm16ToFloat32(pcm(<int>[1, 2, 3, 4])).length, 4);
      expect(pcm16ToFloat32(Uint8List(0)), isEmpty);
    });

    test('a dangling byte is ignored rather than read as silence', () {
      // Recorders hand over whole frames, but a stream can end mid-frame; the
      // conversion must not invent a sample from one byte.
      final Uint8List odd = Uint8List.fromList(<int>[0x00, 0x40, 0x7F]);
      final Float32List samples = pcm16ToFloat32(odd);
      expect(samples.length, 1);
      expect(samples.single, 0.5);
    });

    test('the result is contiguous and in order', () {
      final Float32List samples =
          pcm16ToFloat32(pcm(<int>[0, 32767, -32768, 16384]));
      expect(samples[0], 0);
      expect(samples[1], greaterThan(samples[0]));
      expect(samples[2], -1.0);
      expect(samples[3], 0.5);
    });
  });

  group('events', () {
    test('a debug description never leaks the audio payload', () {
      // The level event carries a double and nothing else; the description
      // exists so a log line cannot accidentally print samples.
      expect(describeVocalEvent(const VocalLevel(0.42)), contains('level'));
      expect(describeVocalEvent(const VocalSpeechStarted()),
          contains('speech'));
      expect(describeVocalEvent(const VocalSpeechEnded()), isNotEmpty);
      expect(describeVocalEvent(const VocalFinal('volume up')),
          contains('volume up'));
    });
  });
}
