import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:puck/src/data/services/speech_service.dart';
import 'package:puck/src/voice/model_store.dart';
import 'package:puck/src/voice/on_device_engine.dart';
import 'package:puck/src/voice/voice_model.dart';
import 'package:record/record.dart';

/// Whether speech input can run right now.
enum VoiceAvailability {
  /// Ready to listen.
  ready,

  /// The offline models are not installed yet. The UI offers the download.
  needsModels,

  /// The microphone permission was refused or revoked.
  permissionDenied,

  /// This build/platform cannot do offline speech at all.
  unsupported,

  /// Something else went wrong; [Transcriber.lastError] says what.
  error,
}

sealed class VocalEvent {
  const VocalEvent();
}

final class VocalSpeechStarted extends VocalEvent {
  const VocalSpeechStarted();
}

final class VocalSpeechEnded extends VocalEvent {
  const VocalSpeechEnded();
}

/// Input amplitude, 0-1, for the listening indicator. Cheap and smoothed:
/// it exists so a person can see that the mic is actually hearing them.
final class VocalLevel extends VocalEvent {
  const VocalLevel(this.level);

  final double level;
}

/// The utterance's text. Emitted once per utterance.
final class VocalFinal extends VocalEvent {
  const VocalFinal(this.text);

  final String text;
}

final class VocalFailure extends VocalEvent {
  const VocalFailure(this.message);

  final String message;
}

/// One microphone, one recogniser, one utterance at a time.
///
/// The controller above this owns the session state machine; this interface is
/// the seam that lets that machine be tested with a scripted fake instead of a
/// microphone. Two implementations: [OnDeviceTranscriber] (offline, VAD + ASR in
/// isolates) and [PlatformTranscriber] (Android's own recogniser, which needs a
/// network on many phones but needs no download).
abstract interface class Transcriber {
  VoiceAvailability get availability;

  String get lastError;

  /// Where the audio is coming from, for the diagnostics line.
  String get sourceLabel;

  /// Does whatever preparation is needed (permission, models, native init).
  Future<VoiceAvailability> prepare();

  /// Begin listening. Throws [TranscriberException] when the microphone or the
  /// engine refuses to start.
  Future<void> start();

  /// Stop capturing and let the engine finish the utterance.
  Future<void> stop();

  /// Stop and throw away the utterance.
  Future<void> cancel();

  Stream<VocalEvent> get events;

  void dispose();
}

class TranscriberException implements Exception {
  const TranscriberException(this.message);

  final String message;

  @override
  String toString() => 'TranscriberException: $message';
}

/// Offline: `record` for 16 kHz mono PCM, the on-device engine for VAD and ASR.
///
/// # The audio contract
///
/// Silero VAD and both bundled ASR models take 16 kHz mono float samples in
/// [-1, 1]. Android will not always give you 16 kHz -- some devices resample,
/// some fail to open the stream at that rate -- so the recorder is asked for
/// 16 kHz explicitly and `record` throws if the device cannot, which is a
/// `VocalFailure` rather than silently feeding 44.1 kHz into a 16 kHz model
/// (that produces confident nonsense: the pitch is wrong by 2.75x).
class OnDeviceTranscriber implements Transcriber {
  OnDeviceTranscriber({
    required this.store,
    this.asrModel = VoiceModels.moonshineTinyEn,
    this.vadModel = VoiceModels.sileroVad,
    AudioRecorder? recorder,
    OnDeviceSpeechEngine? engine,
  })  : _recorder = recorder ?? AudioRecorder(),
        _injectedEngine = engine;

  final VoiceModelStore store;
  final VoiceModel asrModel;
  final VoiceModel vadModel;
  final AudioRecorder _recorder;
  final OnDeviceSpeechEngine? _injectedEngine;

  OnDeviceSpeechEngine? _engine;
  StreamSubscription<Uint8List>? _micSubscription;
  StreamSubscription<SpeechEvent>? _engineSubscription;
  final StreamController<VocalEvent> _events =
      StreamController<VocalEvent>.broadcast();

  VoiceAvailability _availability = VoiceAvailability.needsModels;
  String _lastError = '';
  bool _listening = false;

  /// Guards against a second final for the same utterance: the VAD can emit two
  /// segments if the speaker pauses, and the second one must not run the
  /// command again.
  bool _finalDelivered = false;

  /// Smoothing for the level meter: raw RMS on 20 ms of speech jumps around
  /// enough to look like a fault.
  double _level = 0;

  @override
  VoiceAvailability get availability => _availability;

  @override
  String get lastError => _lastError;

  @override
  String get sourceLabel => 'on-device ${asrModel.id}';

  @override
  Stream<VocalEvent> get events => _events.stream;

  @override
  Future<VoiceAvailability> prepare() async {
    if (_availability == VoiceAvailability.ready && _engine?.isReady == true) {
      return _availability;
    }

    if (!await store.isInstalled(vadModel) || !await store.isInstalled(asrModel)) {
      _availability = VoiceAvailability.needsModels;
      return _availability;
    }

    bool permitted;
    try {
      permitted = await _recorder.hasPermission();
    } on Object catch (error) {
      _lastError = '$error';
      _availability = VoiceAvailability.unsupported;
      return _availability;
    }
    if (!permitted) {
      _availability = VoiceAvailability.permissionDenied;
      return _availability;
    }

    final OnDeviceSpeechEngine engine = _injectedEngine ??
        OnDeviceSpeechEngine(
          SpeechEngineConfig(
            vadModelPath: _path(vadModel, vadModel.files.first),
            asrModelDir: store.directoryOf(asrModel),
            asrFamily: asrModel.id == VoiceModels.whisperTinyEn.id
                ? AsrFamily.whisper
                : AsrFamily.moonshine,
          ),
        );

    // Retrying after a failure builds a new engine, and a subscription to the
    // old one would keep listening to a dead stream: every event of the new
    // engine would be dropped and the session would end in a timeout with no
    // explanation. So the subscription follows the engine -- exactly one, for
    // whichever engine is current, because two would deliver every transcript
    // twice and the second "torch on" would turn the torch back off.
    final OnDeviceSpeechEngine? previous = _engine;
    if (previous != null && !identical(previous, engine)) previous.dispose();
    await _engineSubscription?.cancel();
    _engineSubscription = engine.events.listen(_onEngineEvent);

    try {
      await engine.start();
      _engine = engine;
      _availability = VoiceAvailability.ready;
      _lastError = '';
    } on SpeechEngineException catch (error) {
      _lastError = error.message;
      _availability = VoiceAvailability.error;
    } on Object catch (error) {
      _lastError = '$error';
      _availability = VoiceAvailability.error;
    }
    return _availability;
  }

  String _path(VoiceModel model, String file) =>
      '${store.directoryOf(model)}/$file';

  @override
  Future<void> start() async {
    final OnDeviceSpeechEngine? engine = _engine;
    if (engine == null || !engine.isReady) {
      throw const TranscriberException('the voice engine is not ready');
    }
    if (_listening) {
      throw const TranscriberException('already listening');
    }

    final bool supported =
        await _recorder.isEncoderSupported(AudioEncoder.pcm16bits);
    if (!supported) {
      throw const TranscriberException('this device cannot record PCM');
    }

    _finalDelivered = false;
    _level = 0;
    engine.reset();

    final Stream<Uint8List> mic = await _recorder.startStream(
      // 16 kHz mono PCM16 and nothing else. No device selector: the default
      // input is the one the user expects, and offering a choice is a settings
      // screen nobody asked for.
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _listening = true;

    _micSubscription = mic.listen(
      (Uint8List bytes) {
        if (!_listening) return;
        final Float32List samples = pcm16ToFloat32(bytes);
        _emitLevel(samples);
        engine.acceptWaveform(samples);
      },
      onError: (Object error) {
        _lastError = '$error';
        _emit(VocalFailure('microphone: $error'));
      },
      onDone: () {
        _listening = false;
      },
      cancelOnError: true,
    );
  }

  @override
  Future<void> stop() async {
    // Order matters: stop the capture first so no more audio is queued, then
    // ask the VAD to close the segment. Flushing first would leave the tail of
    // the utterance still arriving after the segment was cut.
    await _stopCapture();
    _engine?.flush();
  }

  @override
  Future<void> cancel() async {
    _finalDelivered = true;
    await _stopCapture();
    _engine?.reset();
  }

  Future<void> _stopCapture() async {
    _listening = false;
    final StreamSubscription<Uint8List>? sub = _micSubscription;
    _micSubscription = null;
    await sub?.cancel();
    try {
      await _recorder.stop();
    } on Object {
      // Stopping an already-stopped recorder throws on some devices; the state
      // we wanted is the state we are in.
    }
  }

  void _onEngineEvent(SpeechEvent event) {
    switch (event) {
      case SpeechStarted():
        _emit(const VocalSpeechStarted());
      case SpeechStopped():
        _emit(const VocalSpeechEnded());
      case SegmentDetected():
        // The utterance closed itself; stop the microphone so the phone stops
        // recording while the model decodes.
        unawaited(_stopCapture());
      case Transcript(:final String text):
        if (_finalDelivered) return;
        _finalDelivered = true;
        _emit(VocalFinal(text));
      case EngineFailure(:final String message):
        _lastError = message;
        _emit(VocalFailure(message));
      case EngineReady():
        break;
    }
  }

  void _emitLevel(Float32List samples) {
    if (samples.isEmpty) return;
    double sum = 0;
    for (int i = 0; i < samples.length; i++) {
      sum += samples[i] * samples[i];
    }
    final double rms = math.sqrt(sum / samples.length);
    // Smoothed with the previous value so the ring breathes instead of
    // flickering; clamped because a clipped shout is not 3x a normal voice.
    _level = _level * 0.7 + (rms * 6).clamp(0.0, 1.0) * 0.3;
    _emit(VocalLevel(_level));
  }

  void _emit(VocalEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  void dispose() {
    unawaited(_micSubscription?.cancel());
    _micSubscription = null;
    unawaited(_engineSubscription?.cancel());
    _engineSubscription = null;
    _engine?.dispose();
    _engine = null;
    unawaited(_recorder.dispose());
    unawaited(_events.close());
  }
}

/// Android's own recogniser, through the [SpeechService] Puck already had.
///
/// Kept because it is the only speech input that works before a 30 MB
/// download: on many phones it is offline too (Google's on-device recogniser),
/// and on the rest it is a fallback that beats "no voice" on first launch. It
/// is never the *preferred* engine -- the service itself documents why
/// (language model download, network dependence, no audio access).
class PlatformTranscriber implements Transcriber {
  PlatformTranscriber({SpeechService? speech})
      : _speech = speech ?? SpeechService();

  final SpeechService _speech;
  final StreamController<VocalEvent> _events =
      StreamController<VocalEvent>.broadcast();

  VoiceAvailability _availability = VoiceAvailability.unsupported;
  String _lastError = '';
  bool _listening = false;

  @override
  VoiceAvailability get availability => _availability;

  @override
  String get lastError => _lastError;

  @override
  String get sourceLabel => 'platform recogniser';

  @override
  Stream<VocalEvent> get events => _events.stream;

  @override
  Future<VoiceAvailability> prepare() async {
    final bool ok = await _speech.init();
    _availability = ok ? VoiceAvailability.ready : VoiceAvailability.unsupported;
    if (!ok) _lastError = 'no recogniser on this device';
    return _availability;
  }

  @override
  Future<void> start() async {
    _speech
      ..onText = (String text, bool partial) {
        if (text.trim().isEmpty) return;
        if (partial) {
          _emit(VocalLevel(0.6));
        } else {
          _emit(const VocalSpeechEnded());
          _emit(VocalFinal(text.trim()));
        }
      }
      ..onDone = () {
        _listening = false;
        _emit(const VocalSpeechEnded());
      }
      ..onError = (String error) {
        _lastError = error;
        _listening = false;
        _emit(VocalFailure(error));
      };

    final bool started = await _speech.start();
    if (!started) {
      throw const TranscriberException('the recogniser did not start');
    }
    _listening = true;
    _emit(const VocalSpeechStarted());
  }

  @override
  Future<void> stop() async {
    _listening = false;
    await _speech.stop();
  }

  @override
  Future<void> cancel() async {
    _listening = false;
    _speech
      ..onText = null
      ..onDone = null
      ..onError = null;
    await _speech.cancel();
  }

  void _emit(VocalEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  void dispose() {
    unawaited(_speech.cancel());
    unawaited(_events.close());
  }
}

/// Picks the best available engine at the moment the mic is pressed.
///
/// Offline first: if the models are installed and the engine starts, nothing
/// leaves the phone and the same sentence works in a tunnel. The platform
/// recogniser is the fallback, not the default, and the diagnostics line on the
/// settings screen says which one answered.
class PreferredTranscriber implements Transcriber {
  PreferredTranscriber({
    required this.offline,
    required this.platform,
  });

  final OnDeviceTranscriber offline;
  final PlatformTranscriber platform;

  Transcriber? _chosen;
  final StreamController<VocalEvent> _events =
      StreamController<VocalEvent>.broadcast();
  StreamSubscription<VocalEvent>? _subscription;
  VoiceAvailability _availability = VoiceAvailability.needsModels;
  String _lastError = '';

  @override
  VoiceAvailability get availability => _availability;

  @override
  String get lastError => _lastError;

  @override
  String get sourceLabel => _chosen?.sourceLabel ?? offline.sourceLabel;

  @override
  Stream<VocalEvent> get events => _events.stream;

  @override
  Future<VoiceAvailability> prepare() async {
    _lastError = '';
    final VoiceAvailability offlineState = await offline.prepare();
    if (offlineState == VoiceAvailability.ready) {
      return _select(offline, offlineState);
    }
    if (offlineState == VoiceAvailability.permissionDenied) {
      // Do not fall back: without the microphone permission nothing works, and
      // "the offline engine is unavailable" would be a misleading reason.
      return _select(offline, offlineState);
    }

    final VoiceAvailability platformState = await platform.prepare();
    if (platformState == VoiceAvailability.ready) {
      return _select(platform, platformState);
    }

    // Nothing is usable. Report the offline engine's reason, because that one
    // is actionable (download a model).
    _lastError = offline.lastError.isNotEmpty
        ? offline.lastError
        : platform.lastError;
    _chosen = null;
    _availability = offlineState;
    return _availability;
  }

  VoiceAvailability _select(Transcriber transcriber, VoiceAvailability state) {
    _chosen = transcriber;
    _availability = state;
    unawaited(_subscription?.cancel());
    _subscription = transcriber.events.listen((VocalEvent event) {
      if (event is VocalFailure) _lastError = event.message;
      _emit(event);
    });
    return state;
  }

  @override
  Future<void> start() async {
    final Transcriber? chosen = _chosen;
    if (chosen == null) {
      throw const TranscriberException('no speech engine is ready');
    }
    await chosen.start();
  }

  @override
  Future<void> stop() async => _chosen?.stop();

  @override
  Future<void> cancel() async => _chosen?.cancel();

  void _emit(VocalEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_events.close());
    offline.dispose();
    platform.dispose();
  }
}

/// 16-bit little-endian PCM to float samples in [-1, 1].
///
/// The same conversion the reference implementation uses, kept here as a pure
/// function so it can be tested with a known byte pattern rather than by
/// listening.
Float32List pcm16ToFloat32(Uint8List bytes) {
  final int count = bytes.length ~/ 2;
  final Float32List samples = Float32List(count);
  final ByteData view = ByteData.sublistView(bytes);
  for (int i = 0; i < count; i++) {
    // Signed 16-bit, little endian. Dividing by 32768 (not 32767) keeps the
    // range symmetric: -32768 maps to exactly -1.0 and +32767 to just under
    // +1.0, which is what the models were trained on.
    samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

/// Debug helper: prints an engine event's shape without the payload audio.
String describeVocalEvent(VocalEvent event) {
  switch (event) {
    case VocalSpeechStarted():
      return 'speech started';
    case VocalSpeechEnded():
      return 'speech ended';
    case VocalLevel(:final double level):
      return 'level ${level.toStringAsFixed(2)}';
    case VocalFinal(:final String text):
      return 'final "$text"';
    case VocalFailure(:final String message):
      debugPrint(message);
      return 'failure $message';
  }
}
