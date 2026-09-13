import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech-to-text wrapper.
///
/// Initialisation is deferred until the intent bar is actually opened --
/// spinning up the recogniser at app start costs a visible hitch and, on
/// Android, downloads a language model.
///
/// This is the single heaviest dependency in the project (see README for the
/// bundle-size note and how to drop it).
class SpeechService {
  SpeechService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  bool _initialised = false;
  bool _initialising = false;
  bool _listening = false;

  bool get isListening => _listening;
  bool get isAvailable => _initialised;

  void Function(String text, bool partial)? onText;
  void Function()? onDone;
  void Function(String error)? onError;

  Future<bool> init() async {
    if (_initialised) return true;
    if (_initialising) return false;
    _initialising = true;
    try {
      _initialised = await _speech.initialize(
        onError: (SpeechRecognitionError e) {
          _listening = false;
          onError?.call(e.errorMsg);
          onDone?.call();
        },
        onStatus: (String status) {
          if (status == 'done' || status == 'notListening') {
            _listening = false;
            onDone?.call();
          }
        },
      );
    } catch (_) {
      _initialised = false;
    }
    _initialising = false;
    return _initialised;
  }

  Future<bool> start() async {
    if (!await init()) return false;
    try {
      _listening = true;
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) {
          onText?.call(r.recognizedWords, !r.finalResult);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          // v7 moved these three off `listen` and onto the options object.
          // The constructor is not const, hence no `const` here.
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          localeId: null, // device locale
          // Dictation mode tolerates pauses better than search mode.
          listenMode: ListenMode.dictation,
        ),
      );
      return true;
    } catch (_) {
      _listening = false;
      return false;
    }
  }

  Future<void> stop() async {
    if (!_listening) return;
    _listening = false;
    try {
      await _speech.stop();
    } catch (_) {
      // Stopping a session that already ended throws on some engines. There is
      // nothing to recover and nothing to report: the state we asked for --
      // not listening -- is the state we are already in.
    }
  }

  Future<void> cancel() async {
    _listening = false;
    try {
      await _speech.cancel();
    } catch (_) {
      // Cancelling a session that never started throws. Same reasoning as
      // above, and swallowing it is what lets callers cancel unconditionally
      // without first tracking whether a session is live.
    }
  }
}
