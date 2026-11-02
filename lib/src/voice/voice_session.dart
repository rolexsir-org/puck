import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:puck/src/voice/transcriber.dart';

/// Why a voice session ended without producing a sentence.
enum VoiceProblem {
  /// Already listening; a second start is a no-op, not a second microphone.
  busy,

  /// The microphone permission was refused.
  permissionDenied,

  /// The offline models are not installed.
  needsModels,

  /// The device cannot do this at all.
  unsupported,

  /// The engine started and then failed.
  engine,

  /// It listened and heard nothing.
  silent,

  /// It heard something and never got a transcript.
  timeout,
}

enum VoicePhase { idle, preparing, listening, transcribing, failed }

/// The state machine around one press of the microphone button.
///
/// # What it guarantees
///
///   * **One session at a time.** [listen] while a session is live returns null
///     and records [VoiceProblem.busy]. Two overlapping sessions would open two
///     recorders, and on Android the second one wins and the first one's audio
///     is silently truncated.
///   * **Every session ends.** A maximum utterance length and a transcript
///     timeout mean a socket-shaped hang in the native layer cannot leave the
///     UI stuck on "listening" forever.
///   * **Every exit is reported.** The future returned by [listen] resolves with
///     the transcript, or null plus a [problem] the UI can explain. It does not
///     throw into a gesture handler.
///   * **Cancel means cancel.** [cancel] drops the utterance; a transcript that
///     arrives afterwards is ignored rather than running a command the user
///     already changed their mind about.
class VoiceSessionController extends ChangeNotifier {
  VoiceSessionController({
    required Transcriber transcriber,
    this.maxUtterance = const Duration(seconds: 15),
    this.finalTimeout = const Duration(seconds: 12),
  }) : _transcriber = transcriber;

  final Transcriber _transcriber;

  /// Hard stop for an utterance. Long enough for a sentence, short enough that
  /// a stuck recorder cannot hold the microphone for a minute.
  final Duration maxUtterance;

  /// How long to wait for a transcript after the utterance closed.
  final Duration finalTimeout;

  VoicePhase _phase = VoicePhase.idle;
  VoiceProblem? _problem;
  String _detail = '';
  double _level = 0;

  bool _live = false;

  /// True once this session has been cancelled or has already delivered its
  /// transcript: late events must not be acted on.
  bool _settled = false;

  Completer<String?>? _result;
  StreamSubscription<VocalEvent>? _subscription;
  Timer? _maxTimer;
  Timer? _finalTimer;

  VoicePhase get phase => _phase;
  VoiceProblem? get problem => _problem;
  String get detail => _detail;

  /// 0-1 input level, for the listening indicator.
  double get level => _level;

  bool get isListening => _phase == VoicePhase.listening;
  bool get isActive =>
      _phase == VoicePhase.preparing ||
      _phase == VoicePhase.listening ||
      _phase == VoicePhase.transcribing;

  /// Which engine answered: "sherpa-onnx moonshine-tiny-en" or the platform
  /// recogniser. Shown in diagnostics, because "why is it using the network"
  /// deserves an answer.
  String get source => _transcriber.sourceLabel;

  /// Runs one session to completion.
  ///
  /// The future resolves when the transcript arrives, the speaker goes silent,
  /// the session is stopped or cancelled, or something fails. It never hangs
  /// past [maxUtterance] + [finalTimeout].
  Future<String?> listen() async {
    if (isActive) {
      _problem = VoiceProblem.busy;
      _detail = 'a voice session is already running';
      notifyListeners();
      return null;
    }

    _publish(phase: VoicePhase.preparing, problem: null, detail: '');
    _live = true;
    _settled = false;
    _level = 0;
    final Completer<String?> result = Completer<String?>();
    _result = result;

    final VoiceAvailability availability;
    try {
      availability = await _transcriber.prepare();
    } on Object catch (error) {
      // Prepare touches the microphone permission and, for the offline engine,
      // two model files. If it throws rather than reporting, the session still
      // has to end: the future in the caller's hand must never be left open.
      return _finish(null, VoiceProblem.engine, '$error');
    }
    if (!_live) return _finish(null, VoiceProblem.busy, 'cancelled');

    switch (availability) {
      case VoiceAvailability.ready:
        break;
      case VoiceAvailability.needsModels:
        return _finish(null, VoiceProblem.needsModels,
            _transcriber.lastError);
      case VoiceAvailability.permissionDenied:
        return _finish(null, VoiceProblem.permissionDenied,
            'microphone permission denied');
      case VoiceAvailability.unsupported:
        return _finish(null, VoiceProblem.unsupported, _transcriber.lastError);
      case VoiceAvailability.error:
        return _finish(null, VoiceProblem.engine, _transcriber.lastError);
    }

    _subscription = _transcriber.events.listen(_onEvent);

    try {
      await _transcriber.start();
    } on TranscriberException catch (error) {
      return _finish(null, VoiceProblem.engine, error.message);
    } on Object catch (error) {
      return _finish(null, VoiceProblem.engine, '$error');
    }

    _publish(phase: VoicePhase.listening);
    _maxTimer = Timer(maxUtterance, () {
      // Out of time: cut the audio, decode what there is, and treat a late
      // answer as the answer.
      unawaited(stopListening());
    });

    return result.future;
  }

  /// Ends the utterance now. Safe to call at any point: from the stop button, a
  /// lifecycle pause, or the max-utterance timer.
  Future<void> stopListening() async {
    if (!_live) return;
    _maxTimer?.cancel();
    _maxTimer = null;
    if (_phase == VoicePhase.listening) {
      _publish(phase: VoicePhase.transcribing);
    }
    try {
      await _transcriber.stop();
    } on Object catch (error) {
      unawaited(_settle(null, VoiceProblem.engine, '$error'));
      return;
    }

    if (_result?.isCompleted ?? true) return;
    _finalTimer?.cancel();
    _finalTimer = Timer(finalTimeout, () {
      // An engine that already failed is not "no transcript": keep its reason
      // rather than replacing it with the generic one.
      final VoiceProblem problem = _problem == VoiceProblem.engine
          ? VoiceProblem.engine
          : VoiceProblem.timeout;
      unawaited(_settle(
        null,
        problem,
        _detail.isEmpty ? 'no transcript' : _detail,
      ));
    });
  }

  /// Drops the utterance. Any transcript that arrives afterwards is ignored.
  Future<void> cancel() async {
    if (!_live) return;
    _live = false;
    _settled = true;
    _cancelTimers();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _transcriber.cancel();
    } on Object catch (error) {
      debugPrint('voice cancel: $error');
    }
    _publish(phase: VoicePhase.idle, problem: null, detail: '');
    final Completer<String?>? result = _result;
    _result = null;
    if (result != null && !result.isCompleted) result.complete(null);
  }

  void _onEvent(VocalEvent event) {
    if (!_live || _settled) return;
    switch (event) {
      case VocalSpeechStarted():
        _level = _level < 0.1 ? 0.1 : _level;
        if (_phase != VoicePhase.listening) {
          _publish(phase: VoicePhase.listening);
        } else {
          notifyListeners();
        }
      case VocalSpeechEnded():
        if (_phase == VoicePhase.listening) {
          _publish(phase: VoicePhase.transcribing);
        }
      case VocalLevel(:final double level):
        _level = level;
        notifyListeners();
      case VocalFinal(:final String text):
        _cancelTimers();
        unawaited(_settle(text, null, ''));
      case VocalFailure(:final String message):
        // A failure after speech was captured is only fatal if no transcript
        // can still arrive; let the timeout decide, but surface the reason.
        _detail = message;
        _problem = VoiceProblem.engine;
        notifyListeners();
    }
  }

  Future<String?> _settle(
    String? text,
    VoiceProblem? problem,
    String detail,
  ) async {
    if (_settled) return null;

    final String trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) {
      return _finish(
        null,
        problem ?? VoiceProblem.silent,
        detail.isEmpty ? 'heard nothing' : detail,
      );
    }
    return _finish(trimmed, null, '');
  }

  /// Ends the session: cleans up, publishes the terminal phase, and resolves the
  /// pending future. Idempotent, because a timeout and a late transcript can
  /// race here and only the first one may win.
  String? _finish(String? text, VoiceProblem? problem, String detail) {
    if (_settled) {
      // Already ended. Returning the caller's own text again is correct; the
      // future is long resolved and nothing else may be published.
      return text;
    }
    _settled = true;
    _live = false;
    _cancelTimers();
    // Without this, the next session subscribes a second listener to the same
    // broadcast stream and every event arrives twice -- two transcripts for one
    // utterance, which is two commands.
    unawaited(_subscription?.cancel());
    _subscription = null;

    _problem = problem;
    _detail = detail;
    if (problem == null) {
      _publish(phase: VoicePhase.idle, problem: null, detail: '');
    } else {
      _publish(phase: VoicePhase.failed, problem: problem, detail: detail);
    }
    final Completer<String?>? result = _result;
    _result = null;
    if (result != null && !result.isCompleted) result.complete(text);
    return text;
  }

  void _cancelTimers() {
    _maxTimer?.cancel();
    _maxTimer = null;
    _finalTimer?.cancel();
    _finalTimer = null;
  }

  void _publish({
    required VoicePhase phase,
    VoiceProblem? problem,
    String? detail,
  }) {
    _phase = phase;
    if (problem != null || phase != VoicePhase.failed) _problem = problem;
    if (detail != null) _detail = detail;
    notifyListeners();
  }

  /// Forgets the last failure, so the next press starts from a clean state.
  void acknowledge() {
    if (_phase == VoicePhase.failed) {
      _publish(phase: VoicePhase.idle, problem: null, detail: '');
      _level = 0;
    }
  }

  @override
  void dispose() {
    _live = false;
    _settled = true;
    _cancelTimers();
    unawaited(_subscription?.cancel());
    _subscription = null;
    // The transcriber is not disposed here: it is created and disposed by
    // `transcriberProvider`, and a session that came and went must not tear
    // down the engine the next session is going to use.
    super.dispose();
  }
}
