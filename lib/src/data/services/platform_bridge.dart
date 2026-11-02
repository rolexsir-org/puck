import 'dart:typed_data';

import 'package:flutter/services.dart';

/// The one bridge to the Android code that has no Dart equivalent: the media
/// stream, the launcher, the clock app, and audio output.
///
/// Everything here answers rather than throws. On a platform without the
/// channel (an iOS build, a widget test) `MissingPluginException` becomes
/// null/false, and the command layer reports "this phone would not do that"
/// instead of a red screen. That is the difference between a feature that
/// degrades and a feature that crashes.
///
/// The Kotlin side is `android/app/src/main/kotlin/com/rolexsir/puck/
/// PuckPlatform.kt`.
class PlatformBridge {
  PlatformBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.rolexsir.puck/platform';

  final MethodChannel _channel;

  // -- Media volume ---------------------------------------------------------

  /// 0-100, or null when the platform cannot answer.
  Future<int?> mediaVolumePercent() => _invoke<int>('volume.get');

  Future<bool> setMediaVolumePercent(int percent) async {
    final int level = percent < 0 ? 0 : (percent > 100 ? 100 : percent);
    final bool? ok = await _invoke<bool>(
      'volume.set',
      <String, Object?>{'percent': level},
    );
    return ok ?? false;
  }

  Future<bool> adjustMediaVolume(int steps) async {
    final bool? ok = await _invoke<bool>(
      'volume.adjust',
      <String, Object?>{'steps': steps},
    );
    return ok ?? false;
  }

  Future<bool> setMediaMuted(bool muted) async {
    final bool? ok = await _invoke<bool>(
      'volume.mute',
      <String, Object?>{'muted': muted},
    );
    return ok ?? false;
  }

  /// Null when the device does not report mute state (many do not).
  Future<bool?> isMediaMuted() => _invoke<bool>('volume.isMuted');

  // -- Apps -----------------------------------------------------------------

  /// Opens the installed app best matching [spokenName], returning its label.
  /// Null when nothing matched; throws [PlatformException] when a match was
  /// found and launching it failed.
  Future<String?> openApp(String spokenName) async {
    try {
      return await _channel.invokeMethod<String>(
        'apps.open',
        <String, Object?>{'name': spokenName},
      );
    } on MissingPluginException {
      return null;
    }
  }

  // -- Clock ----------------------------------------------------------------

  Future<bool> startTimer(Duration duration) async {
    final bool? ok = await _invoke<bool>(
      'clock.timer',
      <String, Object?>{'seconds': duration.inSeconds},
    );
    return ok ?? false;
  }

  Future<bool> setAlarm({required int hour, required int minute}) async {
    final bool? ok = await _invoke<bool>(
      'clock.alarm',
      <String, Object?>{'hour': hour, 'minute': minute},
    );
    return ok ?? false;
  }

  // -- Audio out ------------------------------------------------------------

  /// Speak through the device's own text-to-speech engine. Offline on any phone
  /// with its language data installed, which is the default.
  Future<bool> speak(String text) async {
    final bool? ok = await _invoke<bool>(
      'tts.speak',
      <String, Object?>{'text': text},
    );
    return ok ?? false;
  }

  Future<void> stopSpeaking() async {
    await _invoke<bool>('tts.stop');
  }

  Future<bool> isSpeaking() async =>
      await _invoke<bool>('tts.isSpeaking') ?? false;

  /// Play mono float samples through an `AudioTrack`. Used by the optional
  /// sherpa-onnx voice; the system engine has its own path.
  Future<bool> playPcm(Float32List samples, int sampleRate) async {
    final bool? ok = await _invoke<bool>(
      'pcm.play',
      <String, Object?>{'samples': samples, 'sampleRate': sampleRate},
    );
    return ok ?? false;
  }

  Future<void> stopPlayback() async {
    await _invoke<bool>('pcm.stop');
  }

  // -- Internals ------------------------------------------------------------

  /// One place where the three ways a channel call can fail are handled.
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      // No Android side (widget tests, an iOS build): report "unavailable"
      // rather than throwing into a gesture handler.
      return null;
    } on PlatformException {
      // Android said no: no torch, no clock app, an OEM that blocks the
      // intent. The command layer turns this into an honest sentence.
      return null;
    }
  }
}
