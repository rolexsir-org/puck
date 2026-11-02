import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:puck/src/data/services/platform_bridge.dart';
import 'package:puck/src/voice/model_store.dart';
import 'package:puck/src/voice/voice_model.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as onnx;

/// Spoken answers.
///
/// Recognition does not produce speech: an ASR model gives text and nothing
/// else. Something has to say the answer, and there are two honest options:
///
///   * **The phone's own engine** (Android `TextToSpeech`). Already installed,
///     already offline for most languages, better sounding than anything Puck
///     could ship, and zero download. This is the default.
///   * **A bundled neural voice** (VITS, Piper). Self-contained: works on a
///     phone whose speech engine is missing, silenced, or set to a language the
///     user does not want. 67 MB, downloaded only if asked for.
///
/// [SpeechRouter] uses the second when it is installed and the first otherwise,
/// and never silently downloads anything.
abstract interface class SpeechOutput {
  /// For the diagnostics line: which engine would speak.
  String get sourceLabel;

  Future<bool> isAvailable();

  /// Speaks [text], interrupting anything already being said. A reply that
  /// queues behind the last one is worse than a reply that replaces it.
  Future<void> speak(String text);

  Future<void> stop();

  void dispose();
}

/// Android's `TextToSpeech`, over the platform channel.
class SystemSpeechOutput implements SpeechOutput {
  SystemSpeechOutput({PlatformBridge? bridge})
      : _bridge = bridge ?? PlatformBridge();

  final PlatformBridge _bridge;

  @override
  String get sourceLabel => 'system speech engine';

  @override
  Future<bool> isAvailable() async {
    // There is no cheap "is it installed" query that does not spin the engine
    // up; a speak attempt that returns false is the honest test, and the router
    // then reports that nothing was spoken.
    return true;
  }

  @override
  Future<void> speak(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final bool ok = await _bridge.speak(trimmed);
    if (!ok) debugPrint('system TTS refused: $trimmed');
  }

  @override
  Future<void> stop() => _bridge.stopSpeaking();

  @override
  void dispose() {
    unawaited(_bridge.stopSpeaking());
  }
}

/// A bundled VITS voice, generated on the phone and played through `AudioTrack`.
///
/// Synthesis runs in its own isolate, exactly like recognition: a 67 MB VITS
/// model takes a few hundred milliseconds per sentence, and on the UI isolate
/// that is a visible freeze just as the answer appears.
class OnDeviceSpeechOutput implements SpeechOutput {
  OnDeviceSpeechOutput({
    required VoiceModelStore Function() store,
    this.model = VoiceModels.piperAmyLow,
    PlatformBridge? bridge,
  })  : _store = store,
        _bridge = bridge ?? PlatformBridge();

  /// Resolved on use, not on construction.
  ///
  /// The Puck voice is the *optional* engine: the default one is the phone's
  /// own, which needs no files and no directory. Making the model store a hard
  /// construction-time dependency would mean an app started without one (a
  /// widget test, a future entry point) cannot speak at all -- a wiring detail
  /// silently disabling a feature that does not depend on it.
  final VoiceModelStore Function() _store;
  final VoiceModel model;
  final PlatformBridge _bridge;

  /// Null when no model directory is configured. The Puck voice is then simply
  /// unavailable, and the router falls back to the system engine.
  VoiceModelStore? _resolveStore() {
    try {
      return _store();
    } on StateError {
      return null;
    }
  }

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool _starting = false;

  @override
  String get sourceLabel => 'bundled voice (${model.id})';

  @override
  Future<bool> isAvailable() async {
    final VoiceModelStore? store = _resolveStore();
    if (store == null) return false;
    return store.isInstalled(model);
  }

  Future<bool> _ensureStarted() async {
    if (_sendPort != null) return true;
    if (_starting) return false;
    final VoiceModelStore? store = _resolveStore();
    if (store == null) return false;
    if (!store.isInstalled(model)) return false;
    _starting = true;

    try {
      final ReceivePort port = ReceivePort();
      final Completer<SendPort> ready = Completer<SendPort>();

      port.listen((Object? message) {
        switch (message) {
          case final SendPort sendPort:
            if (!ready.isCompleted) ready.complete(sendPort);
          case final _TtsAudio audio:
            unawaited(_play(audio));
          case final _EnginePortFailure failure:
            if (!ready.isCompleted) {
              ready.completeError(StateError(failure.message));
            } else {
              debugPrint('tts: ${failure.message}');
            }
          default:
            debugPrint('tts: unexpected $message');
        }
      });

      _isolate = await Isolate.spawn(
        _ttsEntry,
        _TtsInit(
          uiPort: port.sendPort,
          modelPath: '${store.directoryOf(model)}/en_US-amy-low.onnx',
          tokensPath: '${store.directoryOf(model)}/tokens.txt',
          lexiconPath: '${store.directoryOf(model)}/lexicon-en-us.txt',
        ),
      );

      _sendPort = await ready.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw StateError('tts init timeout'),
      );
      _receivePort = port;
      return true;
    } on Object catch (error) {
      debugPrint('tts start failed: $error');
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _sendPort = null;
      return false;
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> speak(String text) async {
    await speakChecked(text);
  }

  /// Same work as [speak], but reports whether the sentence reached the
  /// synthesiser -- so the router can fall back instead of leaving the answer
  /// unspoken.
  Future<bool> speakChecked(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    await stop();
    if (!await _ensureStarted()) return false;
    final SendPort? port = _sendPort;
    if (port == null) return false;
    port.send(_TtsSpeak(trimmed));
    return true;
  }

  Future<void> _play(_TtsAudio audio) async {
    if (audio.samples.isEmpty) return;
    await _bridge.playPcm(audio.samples, audio.sampleRate);
  }

  @override
  Future<void> stop() => _bridge.stopPlayback();

  @override
  void dispose() {
    _sendPort?.send(const _TtsShutdown());
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;
  }
}

/// Chooses at speak time, so installing or deleting the Puck voice takes effect
/// without restarting the app.
class SpeechRouter implements SpeechOutput {
  SpeechRouter({required this.system, required this.onDevice});

  final SystemSpeechOutput system;
  final OnDeviceSpeechOutput onDevice;

  SpeechOutput? _last;

  @override
  String get sourceLabel => _last?.sourceLabel ?? system.sourceLabel;

  @override
  Future<bool> isAvailable() async =>
      await onDevice.isAvailable() || await system.isAvailable();

  @override
  Future<void> speak(String text) async {
    if (await onDevice.isAvailable()) {
      _last = onDevice;
      // A refused synthesis must not become silence: the phone's own engine is
      // one call away and always there.
      if (await onDevice.speakChecked(text)) return;
    }
    _last = system;
    await system.speak(text);
  }

  @override
  Future<void> stop() async {
    await onDevice.stop();
    await system.stop();
  }

  @override
  void dispose() {
    onDevice.dispose();
    system.dispose();
  }
}

/// Says nothing. Used by widget tests and by the "answers on screen only"
/// configuration.
class SilentSpeechOutput implements SpeechOutput {
  @override
  String get sourceLabel => 'silent';

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}

// -- TTS isolate -------------------------------------------------------------

class _TtsInit {
  const _TtsInit({
    required this.uiPort,
    required this.modelPath,
    required this.tokensPath,
    required this.lexiconPath,
  });

  final SendPort uiPort;
  final String modelPath;
  final String tokensPath;
  final String lexiconPath;
}

class _TtsSpeak {
  const _TtsSpeak(this.text);

  final String text;
}

class _TtsShutdown {
  const _TtsShutdown();
}

class _TtsAudio {
  const _TtsAudio(this.samples, this.sampleRate);

  final Float32List samples;
  final int sampleRate;
}

class _EnginePortFailure {
  const _EnginePortFailure(this.message);

  final String message;
}

Future<void> _ttsEntry(_TtsInit init) async {
  try {
    await onnx.initBindingsAsync();

    final onnx.OfflineTts tts = onnx.OfflineTts(
      onnx.OfflineTtsConfig(
        model: onnx.OfflineTtsModelConfig(
          vits: onnx.OfflineTtsVitsModelConfig(
            model: init.modelPath,
            tokens: init.tokensPath,
            // The lexicon frontend instead of the phonemiser: one extra 6.3 MB
            // file, no extra native component, and plain English replies come
            // out right.
            lexicon: init.lexiconPath,
          ),
          numThreads: 2,
          debug: false,
        ),
        maxNumSentences: 1,
      ),
    );

    final ReceivePort receivePort = ReceivePort();
    init.uiPort.send(receivePort.sendPort);

    receivePort.listen((Object? message) {
      if (message is _TtsShutdown) {
        tts.free();
        receivePort.close();
        return;
      }
      if (message is! _TtsSpeak) return;
      try {
        final onnx.GeneratedAudio audio =
            tts.generate(text: message.text, speed: 1.0);
        init.uiPort.send(_TtsAudio(audio.samples, audio.sampleRate));
      } on Object catch (error) {
        init.uiPort.send(_EnginePortFailure('tts generate: $error'));
      }
    });
  } on Object catch (error) {
    init.uiPort.send(_EnginePortFailure('tts init: $error'));
  }
}
