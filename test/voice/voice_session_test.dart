import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:puck/src/voice/transcriber.dart';
import 'package:puck/src/voice/voice_session.dart';

/// The session state machine, with a scripted transcriber.
///
/// No microphone and no models: [Transcriber] is six methods and a stream, so
/// the whole of "what happens when permission is refused / the engine dies / the
/// user changes their mind / nobody says anything" can be exercised on a laptop.
/// These are the cases that used to leave the mic button spinning forever.

class _ScriptedTranscriber implements Transcriber {
  _ScriptedTranscriber({
    this.prepareWith = VoiceAvailability.ready,
    this.startError,
    this.finalDelay = const Duration(milliseconds: 10),
    this.finalText,
    this.emitEnded = true,
  });

  VoiceAvailability prepareWith;
  String? startError;

  /// How long after [start] the scripted utterance closes.
  Duration finalDelay;

  /// The transcript to deliver. Null means "the person said nothing".
  String? finalText;

  /// Whether a `VocalSpeechEnded` precedes the transcript.
  bool emitEnded;

  final StreamController<VocalEvent> _events =
      StreamController<VocalEvent>.broadcast();

  int prepares = 0;
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  int disposes = 0;

  Timer? _timer;

  @override
  VoiceAvailability get availability => prepareWith;

  @override
  String get lastError => 'scripted';

  @override
  String get sourceLabel => 'scripted transcriber';

  @override
  Stream<VocalEvent> get events => _events.stream;

  @override
  Future<VoiceAvailability> prepare() async {
    prepares++;
    return prepareWith;
  }

  @override
  Future<void> start() async {
    starts++;
    final String? error = startError;
    if (error != null) throw TranscriberException(error);

    _timer?.cancel();
    _timer = Timer(finalDelay, () {
      if (emitEnded) _emit(const VocalSpeechEnded());
      final String? text = finalText;
      if (text != null) _emit(VocalFinal(text));
    });
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _timer?.cancel();
  }

  /// Test hook: inject an event at an arbitrary moment.
  void emit(VocalEvent event) => _emit(event);

  void _emit(VocalEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  void dispose() {
    disposes++;
    _timer?.cancel();
    unawaited(_events.close());
  }
}

void main() {
  late _ScriptedTranscriber transcriber;
  late VoiceSessionController session;

  setUp(() {
    transcriber = _ScriptedTranscriber();
    session = VoiceSessionController(
      transcriber: transcriber,
      maxUtterance: const Duration(milliseconds: 200),
      finalTimeout: const Duration(milliseconds: 40),
    );
  });

  tearDown(() {
    session.dispose();
    transcriber.dispose();
  });

  group('happy path', () {
    test('one press, one transcript, idle afterwards', () async {
      transcriber
        ..finalText = 'turn the torch on'
        ..finalDelay = const Duration(milliseconds: 5);

      final String? text = await session.listen();

      expect(text, 'turn the torch on');
      expect(transcriber.starts, 1);
      expect(session.phase, VoicePhase.idle);
      expect(session.problem, isNull);
      expect(session.isActive, isFalse);
    });

    test('the level reaches the indicator while listening', () async {
      transcriber.finalText = null;
      transcriber.emitEnded = false;
      transcriber.finalDelay = const Duration(milliseconds: 100);

      final Future<String?> pending = session.listen();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      transcribeLevel(transcriber, 0.8);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(session.level, closeTo(0.8, 0.001));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(await pending, isNull);
    });
  });

  group('refusals', () {
    test('permission denied is reported, and nothing starts', () async {
      transcriber.prepareWith = VoiceAvailability.permissionDenied;

      final String? text = await session.listen();

      expect(text, isNull);
      expect(session.problem, VoiceProblem.permissionDenied);
      expect(session.phase, VoicePhase.failed);
      expect(transcriber.starts, 0);
    });

    test('models missing is a different message than permission', () async {
      transcriber.prepareWith = VoiceAvailability.needsModels;

      expect(await session.listen(), isNull);
      expect(session.problem, VoiceProblem.needsModels);
    });

    test('an unsupported device says so instead of hanging', () async {
      transcriber.prepareWith = VoiceAvailability.unsupported;

      expect(await session.listen(), isNull);
      expect(session.problem, VoiceProblem.unsupported);
    });

    test('an engine that will not start fails the session', () async {
      transcriber.startError = 'the voice engine is not ready';

      expect(await session.listen(), isNull);
      expect(session.problem, VoiceProblem.engine);
      expect(session.detail, contains('not ready'));
    });

    test('the failure is cleared on the next press', () async {
      transcriber.prepareWith = VoiceAvailability.permissionDenied;
      await session.listen();
      expect(session.problem, VoiceProblem.permissionDenied);

      session.acknowledge();
      expect(session.problem, isNull);
      expect(session.phase, VoicePhase.idle);
    });
  });

  group('silence and timeouts', () {
    test('a session that hears nothing ends as a timeout, not a hang', () async {
      transcriber
        ..finalText = null
        ..emitEnded = false
        ..finalDelay = const Duration(seconds: 5);

      // The max-utterance timer closes the capture, then the transcript never
      // arrives.
      final String? text = await session.listen();

      expect(text, isNull);
      expect(session.problem, VoiceProblem.timeout);
      expect(transcriber.stops, 1);
    });

    test('speech that produced no transcript times out', () async {
      transcriber
        ..finalText = null
        ..finalDelay = const Duration(milliseconds: 5);

      expect(await session.listen(), isNull);
      expect(session.problem, VoiceProblem.timeout);
    });
  });

  group('one session at a time', () {
    test('a second press while listening is refused', () async {
      transcriber
        ..emitEnded = false
        ..finalDelay = const Duration(milliseconds: 60);

      final Future<String?> first = session.listen();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final String? second = await session.listen();

      expect(second, isNull);
      expect(session.problem, VoiceProblem.busy);
      expect(transcriber.starts, 1);

      await session.cancel();
      await first;
    });

    test('repeated start and stop leaves no listener behind', () async {
      for (int i = 0; i < 3; i++) {
        transcriber
          ..finalText = 'volume up'
          ..finalDelay = const Duration(milliseconds: 5);
        expect(await session.listen(), 'volume up');
      }

      expect(transcriber.starts, 3);
      expect(session.phase, VoicePhase.idle);
    });
  });

  group('cancel', () {
    test('cancelling resolves with nothing and stops the microphone', () async {
      transcriber
        ..emitEnded = false
        ..finalDelay = const Duration(seconds: 5);

      final Future<String?> pending = session.listen();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await session.cancel();

      expect(await pending, isNull);
      expect(transcriber.cancels, 1);
      expect(session.phase, VoicePhase.idle);
    });

    test('a transcript that arrives after cancel is ignored', () async {
      transcriber.emitEnded = false;
      transcriber.finalText = null;

      final Future<String?> pending = session.listen();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await session.cancel();

      transcriber.emit(const VocalFinal('open calculator'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(await pending, isNull);
    });

    test('the same transcript twice still yields one answer', () async {
      transcriber
        ..emitEnded = false
        ..finalDelay = const Duration(seconds: 5);

      final Future<String?> pending = session.listen();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // This is the double-delivery the router's guard also defends against:
      // a VAD segment ending on silence and a stop button closing the same
      // capture. The session must resolve once.
      transcriber.emit(const VocalFinal('volume up'));
      transcriber.emit(const VocalFinal('volume up'));

      expect(await pending, 'volume up');
    });
  });

  group('engine failure while listening', () {
    test('a failure with no transcript ends the session', () async {
      transcriber
        ..emitEnded = false
        ..finalDelay = const Duration(seconds: 5);

      final Future<String?> pending = session.listen();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      transcriber.emit(const VocalFailure('microphone disconnected'));

      // The reason survives: the session ends because the engine failed, and
      // the message says which part failed, not just "no transcript".
      expect(await pending, isNull);
      expect(session.problem, VoiceProblem.engine);
      expect(session.detail, contains('disconnected'));
    });
  });
}

/// Pushes a level through the scripted transcriber's stream.
void transcribeLevel(_ScriptedTranscriber transcriber, double level) {
  transcriber.emit(VocalLevel(level));
}
