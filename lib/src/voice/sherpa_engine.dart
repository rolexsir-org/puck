import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Which recogniser architecture the installed model is. The two default
/// models have different constructors; everything else about the pipeline is
/// identical.
enum AsrFamily { moonshine, whisper }

/// Everything the engine needs to start, resolved to absolute paths.
class SpeechEngineConfig {
  const SpeechEngineConfig({
    required this.vadModelPath,
    required this.asrModelDir,
    required this.asrFamily,
    this.numThreads = 2,
    this.vadThreshold = 0.5,
    this.minSilenceSeconds = 0.6,
    this.minSpeechSeconds = 0.2,
    this.maxSpeechSeconds = 12,
  });

  final String vadModelPath;
  final String asrModelDir;
  final AsrFamily asrFamily;
  final int numThreads;

  /// Silero VAD speech probability above which a frame counts as speech.
  final double vadThreshold;

  /// Silence that ends an utterance. 0.6s is long enough for a person to
  /// breathe mid-sentence and short enough that a command feels finished when
  /// they stop talking.
  final double minSilenceSeconds;

  /// Shorter than this and a cough is ignored rather than transcribed.
  final double minSpeechSeconds;

  /// Hard cap. A 12-second cap bounds the worst-case wait for a transcript on
  /// a slow phone, and no phone command is longer than that.
  final double maxSpeechSeconds;
}

/// What the engine reports while it runs.
sealed class SpeechEvent {
  const SpeechEvent();
}

final class EngineReady extends SpeechEvent {
  const EngineReady();
}

final class SpeechStarted extends SpeechEvent {
  const SpeechStarted();
}

final class SpeechStopped extends SpeechEvent {
  const SpeechStopped();
}

/// A complete utterance was isolated from the audio stream; transcription is
/// running.
final class SegmentDetected extends SpeechEvent {
  const SegmentDetected({
    required this.index,
    required this.startSeconds,
    required this.endSeconds,
  });

  final int index;
  final double startSeconds;
  final double endSeconds;
}

final class Transcript extends SpeechEvent {
  const Transcript({
    required this.index,
    required this.text,
    required this.audioSeconds,
    required this.decodeSeconds,
  });

  final int index;
  final String text;
  final double audioSeconds;
  final double decodeSeconds;

  /// Decoding time over audio time. Below 1.0 means faster than real time,
  /// which is the only figure that says whether a phone can keep up.
  double get realTimeFactor =>
      audioSeconds <= 0 ? 0 : decodeSeconds / audioSeconds;
}

final class EngineFailure extends SpeechEvent {
  const EngineFailure(this.message);

  final String message;

  @override
  String toString() => 'EngineFailure: $message';
}

class SpeechEngineException implements Exception {
  const SpeechEngineException(this.message);

  final String message;

  @override
  String toString() => 'SpeechEngineException: $message';
}

enum _EngineState { idle, starting, ready, failed }

/// Microphone audio in, transcripts out, with voice activity detection in
/// between.
///
/// # Two isolates, and why
///
/// The VAD and the recogniser are native, blocking, and CPU-hungry. Running
/// either one on the UI isolate would freeze the bubble mid-gesture. So this
/// is the shape [sherpa-onnx's own Flutter example] uses:
///
/// ```
///  UI isolate ──audio chunks──▶ VAD isolate ──segment──▶ ASR isolate
///       ▲                            │                        │
///       └──── speech state ──────────┴──── transcript ────────┘
/// ```
///
/// The two workers are spawned once and reused across utterances, because
/// loading a 30 MB model per press is a two-second stall. `reset()` clears the
/// VAD's circular buffer between utterances; nothing else is reloaded.
///
/// Each isolate calls `initBindingsAsync()` itself. sherpa-onnx keeps its FFI
/// binding state per isolate, so a binding loaded in the UI isolate is not
/// visible in a worker -- the single most common way a sherpa integration
/// crashes at the first decode.
///
/// [sherpa-onnx's own Flutter example]:
/// https://github.com/k2-fsa/sherpa-onnx/tree/master/flutter-examples/vad-non-streaming-asr-from-microphone
class SherpaSpeechEngine {
  SherpaSpeechEngine(this.config);

  final SpeechEngineConfig config;

  final StreamController<SpeechEvent> _events =
      StreamController<SpeechEvent>.broadcast();

  /// Events from both workers. Broadcast: the session controller and the
  /// diagnostics line can both listen.
  Stream<SpeechEvent> get events => _events.stream;

  _EngineState _state = _EngineState.idle;
  bool _disposed = false;

  Isolate? _vadIsolate;
  Isolate? _asrIsolate;
  SendPort? _vadSendPort;
  ReceivePort? _vadReceivePort;
  ReceivePort? _asrReadyPort;

  /// Leftover samples that do not yet fill a VAD window.
  final List<double> _buffer = <double>[];
  late final int _windowSize;

  /// 16 kHz mono, the only rate Silero VAD and both bundled ASR models accept.
  static const int sampleRate = 16000;

  /// Silero VAD v4/v5 works on 512-sample windows at 16 kHz.
  static const int defaultWindowSize = 512;

  bool get isReady => _state == _EngineState.ready;
  bool get isBusy => _state == _EngineState.starting;

  /// Loads both models, in workers. Safe to call twice; the second call is a
  /// no-op.
  Future<void> start() async {
    if (_state == _EngineState.ready) return;
    if (_state == _EngineState.starting) {
      throw const SpeechEngineException('already starting');
    }
    if (_disposed) throw const SpeechEngineException('disposed');
    _state = _EngineState.starting;

    _windowSize = defaultWindowSize;

    try {
      _asrReadyPort = ReceivePort();
      _vadReceivePort = ReceivePort();
      _vadReceivePort!.listen(_onVadMessage);

      _asrIsolate = await Isolate.spawn(
        _asrEntry,
        _AsrInit(
          readyPort: _asrReadyPort!.sendPort,
          resultPort: _vadReceivePort!.sendPort,
          modelDir: config.asrModelDir,
          family: config.asrFamily,
          numThreads: config.numThreads,
        ),
        onError: _vadReceivePort!.sendPort,
        errorsAreFatal: false,
      );

      final Object? handshake = await _asrReadyPort!.first.timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw const SpeechEngineException(
          'the recogniser did not start (timeout)',
        ),
      );
      if (handshake is! SendPort) {
        throw SpeechEngineException('recogniser failed: $handshake');
      }

      // Registered before the spawn, so a VAD isolate that wins the race
      // cannot complete a completer that does not exist yet.
      final Completer<void> vadReady = Completer<void>();
      _handshake = vadReady;

      _vadIsolate = await Isolate.spawn(
        _vadEntry,
        _VadInit(
          asrSegmentPort: handshake,
          uiPort: _vadReceivePort!.sendPort,
          config: config,
          windowSize: _windowSize,
        ),
        onError: _vadReceivePort!.sendPort,
        errorsAreFatal: false,
      );

      // The VAD isolate answers with its own SendPort once its model is loaded.
      await vadReady.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw const SpeechEngineException(
          'voice activity detection did not start (timeout)',
        ),
      );
      _state = _EngineState.ready;
      _emit(const EngineReady());
    } on Object catch (error) {
      _state = _EngineState.failed;
      _disposeWorkers();
      if (error is SpeechEngineException) rethrow;
      throw SpeechEngineException('$error');
    }
  }

  Completer<void>? _handshake;

  /// Feed raw 16 kHz mono samples. Chunks smaller than a VAD window are
  /// buffered; [flush] discards any remainder.
  void acceptWaveform(Float32List samples) {
    if (_state != _EngineState.ready || _disposed) return;
    final SendPort? port = _vadSendPort;
    if (port == null) return;

    for (int i = 0; i < samples.length; i++) {
      _buffer.add(samples[i]);
    }
    while (_buffer.length >= _windowSize) {
      final Float32List chunk =
          Float32List.fromList(_buffer.sublist(0, _windowSize));
      _buffer.removeRange(0, _windowSize);
      port.send(_AudioChunk(chunk));
    }
  }

  /// End the current utterance even if the speaker went quiet without a pause
  /// long enough for the VAD. Sends whatever it has to the VAD, which flushes
  /// its own buffer and emits a final segment.
  void flush() {
    _buffer.clear();
    _vadSendPort?.send(const _Flush());
  }

  /// Prepare for a new utterance: drop buffered audio and clear the VAD's
  /// circular buffer and segment counter. The models stay loaded.
  void reset() {
    _buffer.clear();
    _vadSendPort?.send(const _Reset());
  }

  void _onVadMessage(Object? message) {
    if (_disposed) return;
    switch (message) {
      case final SendPort port:
        _vadSendPort = port;
        _handshake?.complete();
        _handshake = null;
      case final SegmentDetected event:
        _emit(event);
      case final SpeechStarted event:
        _emit(event);
      case final SpeechStopped event:
        _emit(event);
      case final Transcript event:
        _emit(event);
      case final EngineFailure event:
        debugPrint('$event');
        // A failure before the handshake is why the engine never became ready;
        // propagate it instead of waiting out the timeout.
        final Completer<void>? pending = _handshake;
        if (pending != null && !pending.isCompleted) {
          pending.completeError(SpeechEngineException(event.message));
        }
        _handshake = null;
        _emit(event);
      case final List<Object?> error:
        // `Isolate.spawn(onError:)` delivers a two-element list.
        final String text = error.isEmpty ? 'isolate error' : '${error.first}';
        _emit(EngineFailure(text));
      default:
        debugPrint('sherpa engine: unknown message $message');
    }
  }

  void _emit(SpeechEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _disposeWorkers() {
    _vadIsolate?.kill(priority: Isolate.immediate);
    _asrIsolate?.kill(priority: Isolate.immediate);
    _vadIsolate = null;
    _asrIsolate = null;
    _vadSendPort = null;
  }

  /// Tears everything down. Called when the voice session ends for good (the
  /// assistant is done, the screen is gone); a plain [reset] is enough between
  /// utterances.
  void dispose() {
    _disposed = true;
    _state = _EngineState.idle;
    _disposeWorkers();
    _vadReceivePort?.close();
    _vadReceivePort = null;
    _asrReadyPort?.close();
    _asrReadyPort = null;
    unawaited(_events.close());
  }
}

// -- Messages (must stay plain data: they cross isolate boundaries) ----------

class _AudioChunk {
  const _AudioChunk(this.samples);

  final Float32List samples;
}

class _Reset {
  const _Reset();
}

class _Flush {
  const _Flush();
}

class _AsrSegmentRequest {
  const _AsrSegmentRequest({
    required this.index,
    required this.samples,
    required this.startSeconds,
    required this.endSeconds,
  });

  final int index;
  final Float32List samples;
  final double startSeconds;
  final double endSeconds;
}

// -- VAD isolate -------------------------------------------------------------

class _VadInit {
  const _VadInit({
    required this.asrSegmentPort,
    required this.uiPort,
    required this.config,
    required this.windowSize,
  });

  final SendPort asrSegmentPort;
  final SendPort uiPort;
  final SpeechEngineConfig config;
  final int windowSize;
}

Future<void> _vadEntry(_VadInit init) async {
  final SendPort ui = init.uiPort;
  try {
    // Each isolate has its own FFI binding state (see the class dartdoc).
    await sherpa_onnx.initBindingsAsync();

    final sherpa_onnx.VoiceActivityDetector vad =
        sherpa_onnx.VoiceActivityDetector(
      config: sherpa_onnx.VadModelConfig(
        sileroVad: sherpa_onnx.SileroVadModelConfig(
          model: init.config.vadModelPath,
          threshold: init.config.vadThreshold,
          minSilenceDuration: init.config.minSilenceSeconds,
          minSpeechDuration: init.config.minSpeechSeconds,
          maxSpeechDuration: init.config.maxSpeechSeconds,
          windowSize: init.windowSize,
        ),
        numThreads: 1,
        debug: false,
      ),
      // Five minutes of audio. A command never comes close; the ring is sized
      // to hold the audio *while* a segment is being decoded.
      bufferSizeInSeconds: 300,
    );

    final ReceivePort receivePort = ReceivePort();
    int nextIndex = 0;

    void drainSegments() {
      while (!vad.isEmpty()) {
        final sherpa_onnx.SpeechSegment segment = vad.front();
        final double startSeconds = segment.start / SherpaSpeechEngine.sampleRate;
        final double endSeconds =
            startSeconds + segment.samples.length / SherpaSpeechEngine.sampleRate;
        final int index = nextIndex++;

        ui.send(SegmentDetected(
          index: index,
          startSeconds: startSeconds,
          endSeconds: endSeconds,
        ));
        init.asrSegmentPort.send(
          _AsrSegmentRequest(
            index: index,
            samples: segment.samples,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
          ),
        );
        vad.pop();
      }
    }

    bool lastSpeech = false;

    receivePort.listen((Object? message) {
      try {
        switch (message) {
          case _AudioChunk(:final Float32List samples):
            vad.acceptWaveform(samples);
            final bool speech = vad.isDetected();
            if (speech != lastSpeech) {
              lastSpeech = speech;
              ui.send(speech ? const SpeechStarted() : const SpeechStopped());
            }
            drainSegments();
          case _Flush():
            vad.flush();
            if (lastSpeech) {
              lastSpeech = false;
              ui.send(const SpeechStopped());
            }
            drainSegments();
          case _Reset():
            vad.reset();
            nextIndex = 0;
            lastSpeech = false;
          default:
            break;
        }
      } on Object catch (error) {
        ui.send(EngineFailure('vad: $error'));
      }
    });

    ui.send(receivePort.sendPort);
  } on Object catch (error) {
    ui.send(EngineFailure('vad init: $error'));
  }
}

// -- ASR isolate -------------------------------------------------------------

class _AsrInit {
  const _AsrInit({
    required this.readyPort,
    required this.resultPort,
    required this.modelDir,
    required this.family,
    required this.numThreads,
  });

  final SendPort readyPort;
  final SendPort resultPort;
  final String modelDir;
  final AsrFamily family;
  final int numThreads;
}

Future<void> _asrEntry(_AsrInit init) async {
  try {
    await sherpa_onnx.initBindingsAsync();

    final String dir = init.modelDir;
    final sherpa_onnx.OfflineRecognizerConfig recognizerConfig =
        sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        moonshine: init.family == AsrFamily.moonshine
            ? sherpa_onnx.OfflineMoonshineModelConfig(
                encoder: '$dir/encoder_model.ort',
                mergedDecoder: '$dir/decoder_model_merged.ort',
              )
            : const sherpa_onnx.OfflineMoonshineModelConfig(),
        whisper: init.family == AsrFamily.whisper
            ? sherpa_onnx.OfflineWhisperModelConfig(
                encoder: '$dir/tiny.en-encoder.int8.onnx',
                decoder: '$dir/tiny.en-decoder.int8.onnx',
              )
            : const sherpa_onnx.OfflineWhisperModelConfig(),
        tokens: init.family == AsrFamily.whisper
            ? '$dir/tiny.en-tokens.txt'
            : '$dir/tokens.txt',
        modelType: init.family == AsrFamily.whisper ? 'whisper' : '',
        numThreads: init.numThreads,
        debug: false,
      ),
    );

    final sherpa_onnx.OfflineRecognizer recognizer =
        sherpa_onnx.OfflineRecognizer(recognizerConfig);

    final ReceivePort receivePort = ReceivePort();
    receivePort.listen((Object? message) {
      if (message is! _AsrSegmentRequest) return;
      final Stopwatch stopwatch = Stopwatch()..start();
      try {
        final sherpa_onnx.OfflineStream stream = recognizer.createStream();
        try {
          stream.acceptWaveform(
            samples: message.samples,
            sampleRate: SherpaSpeechEngine.sampleRate,
          );
          recognizer.decode(stream);
          final sherpa_onnx.OfflineRecognitionResult result =
              recognizer.getResult(stream);
          stopwatch.stop();
          init.resultPort.send(
            Transcript(
              index: message.index,
              text: result.text.trim(),
              audioSeconds: message.endSeconds - message.startSeconds,
              decodeSeconds: stopwatch.elapsedMicroseconds / 1000000,
            ),
          );
        } finally {
          // A leaked stream leaks a decoder state the size of the model's
          // memory; one per command adds up to a crash on a cheap phone.
          stream.free();
        }
      } on Object catch (error) {
        init.resultPort.send(EngineFailure('decode: $error'));
      }
    });

    init.readyPort.send(receivePort.sendPort);
  } on Object catch (error) {
    init.readyPort.send(EngineFailure('recogniser init: $error').toString());
  }
}
