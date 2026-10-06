import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User settings.
///
/// Split storage, on purpose:
///   * SharedPreferences -- preferences. Non-sensitive, cheap, synchronous.
///   * flutter_secure_storage -- the API key. It lands in the iOS Keychain /
///     Android Keystore, not in a world-readable XML file in /data/data.
///
/// There are exactly two things worth configuring: who the SOS message goes
/// to, and the key that pays for the answers. Everything else has a correct
/// default and no UI.
class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._prefs, {FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static const String _kContactPhone = 'sos.contact.phone';
  static const String _kApiKey = 'llm.groq.key';
  static const String _kJokeIndex = 'fun.joke.index';
  static const String _kJokeOrder = 'fun.joke.order';
  static const String _kReleaseCancels = 'sos.release.cancels';
  static const String _kSosHoldSeconds = 'sos.hold.seconds';

  // -- Hold length ----------------------------------------------------------

  /// How long the bubble must be held before SOS arms, in seconds.
  ///
  /// The design constant is 3s and stays the default. It is adjustable
  /// because a three-second precision hold is a physical demand that excludes
  /// people with tremor, arthritis, or one hand on a ladder -- and the people
  /// most likely to need SOS are the people least able to hold a button for
  /// exactly three seconds.
  static const int defaultSosHoldSeconds = 3;

  /// Shorter than this and a pocket can arm SOS by brushing against a phone.
  static const int minSosHoldSeconds = 1;
  static const int maxSosHoldSeconds = 3;

  int get sosHoldSeconds => (_prefs.getInt(_kSosHoldSeconds) ??
          defaultSosHoldSeconds)
      .clamp(minSosHoldSeconds, maxSosHoldSeconds);

  Duration get sosHold => Duration(seconds: sosHoldSeconds);

  Future<void> setSosHoldSeconds(int seconds) async {
    await _prefs.setInt(
      _kSosHoldSeconds,
      seconds.clamp(minSosHoldSeconds, maxSosHoldSeconds),
    );
    notifyListeners();
  }

  // -- Emergency contact ----------------------------------------------------

  String get contactPhone => _prefs.getString(_kContactPhone) ?? '';

  bool get hasEmergencyContact =>
      contactPhone.trim().isNotEmpty &&
      contactPhone.replaceAll(RegExp(r'\D'), '').length >= 6;

  Future<void> setContactPhone(String phone) async {
    await _prefs.setString(_kContactPhone, phone.trim());
    notifyListeners();
  }

  // -- API key (secure) -----------------------------------------------------

  String? _apiKeyCache;

  Future<String?> loadApiKey() async {
    if (_apiKeyCache != null) return _apiKeyCache;
    try {
      _apiKeyCache = await _secure.read(key: _kApiKey);
    } catch (_) {
      _apiKeyCache = null;
    }
    return _apiKeyCache;
  }

  /// Read synchronously from the cache; call [loadApiKey] once at startup.
  String? get groqApiKey => _apiKeyCache;

  Future<void> setGroqApiKey(String key) async {
    final String trimmed = key.trim();
    try {
      if (trimmed.isEmpty) {
        await _secure.delete(key: _kApiKey);
        _apiKeyCache = null;
      } else {
        await _secure.write(key: _kApiKey, value: trimmed);
        _apiKeyCache = trimmed;
      }
    } catch (_) {
      // Keystore unavailable (some emulators / rooted devices).
      _apiKeyCache = trimmed.isEmpty ? null : trimmed;
    }
    notifyListeners();
  }

  // -- SOS release-cancel counter -------------------------------------------

  /// How many times Puck has disarmed itself because the finger lifting off
  /// the bubble said "pocket, not emergency". Surfaced on the settings screen
  /// so the behaviour is visible, not mysterious.
  int get releaseCancels => _prefs.getInt(_kReleaseCancels) ?? 0;

  Future<void> incrementReleaseCancels() async {
    await _prefs.setInt(_kReleaseCancels, releaseCancels + 1);
    notifyListeners();
  }

  // -- Joke shuffle bag (persisted so sessions do not repeat) ---------------

  int get jokeIndex => _prefs.getInt(_kJokeIndex) ?? 0;

  Future<void> setJokeIndex(int i) => _prefs.setInt(_kJokeIndex, i);

  List<int>? get jokeOrder {
    final List<String>? raw = _prefs.getStringList(_kJokeOrder);
    return raw?.map(int.parse).toList(growable: false);
  }

  Future<void> setJokeOrder(List<int> order) async {
    await _prefs.setStringList(
      _kJokeOrder,
      order.map((int e) => e.toString()).toList(growable: false),
    );
  }

  // -- Privacy --------------------------------------------------------------

  static const String _kCloudEnabled = 'privacy.cloud.enabled';
  static const String _kDeviceId = 'privacy.device.id';
  static const String _kGestureCardShown = 'firstrun.gestures.shown';
  static const String _kHoldDiscovered = 'sos.hold.discovered';

  /// The one switch that stops everything leaving the phone.
  ///
  /// Default on, because the assistant answering a typed question is the
  /// feature rather than a favour, and because an app that has to be
  /// configured before it is useful is the thing this whole change exists to
  /// remove. What is *not* default is anything hidden: the switch is one tap
  /// from the top of settings, and the screen that lists exactly what leaves
  /// the phone sits next to it.
  bool get cloudEnabled => _prefs.getBool(_kCloudEnabled) ?? true;

  Future<void> setCloudEnabled(bool enabled) async {
    await _prefs.setBool(_kCloudEnabled, enabled);
    notifyListeners();
  }

  /// A random identifier for rate limiting, generated on first launch.
  ///
  /// It is not an account, not an install ID and not derived from anything
  /// about the device: 16 random bytes, stored locally, resettable from
  /// settings. Its only job is to let the proxy count requests per device
  /// without knowing who anyone is.
  String get deviceId {
    final String? existing = _prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final String created = _newDeviceId();
    _prefs.setString(_kDeviceId, created);
    return created;
  }

  /// Forgets the identifier. The next request gets a new one, which also
  /// clears any rate-limit history attached to the old one.
  Future<void> resetDeviceId() async {
    await _prefs.remove(_kDeviceId);
    notifyListeners();
  }

  /// True once the hold-to-SOS has actually been performed. The bubble's
  /// resting ring is a hint, and a hint that outlives the thing it hinted at
  /// is decoration.
  bool get holdDiscovered => _prefs.getBool(_kHoldDiscovered) ?? false;

  Future<void> markHoldDiscovered() async {
    if (holdDiscovered) return;
    await _prefs.setBool(_kHoldDiscovered, true);
    notifyListeners();
  }

  bool get gestureCardShown => _prefs.getBool(_kGestureCardShown) ?? false;

  Future<void> markGestureCardShown() async {
    await _prefs.setBool(_kGestureCardShown, true);
    notifyListeners();
  }

  /// Erases everything Puck stored on this device: the contact number, the
  /// optional API key, the joke cursor, the counters and the device ID.
  /// Nothing is kept "just in case" -- a clear-data button that leaves
  /// something behind is a lie.
  Future<void> clearAllLocalData() async {
    const List<String> keys = <String>[
      _kContactPhone,
      _kSosHoldSeconds,
      _kJokeIndex,
      _kJokeOrder,
      _kReleaseCancels,
      _kDeviceId,
      _kGestureCardShown,
      _kHoldDiscovered,
      _kCloudEnabled,
    ];
    for (final String key in keys) {
      await _prefs.remove(key);
    }
    try {
      await _secure.delete(key: _kApiKey);
    } catch (_) {
      // Keystore unavailable: the key was never readable anyway.
    }
    _apiKeyCache = null;
    notifyListeners();
  }

  /// UUID v4 from `Random.secure()`. Hand-rolled rather than adding a package
  /// for sixteen bytes of formatting; the version and variant bits are set so
  /// the result is a well-formed UUID that any server-side rate limiter will
  /// accept as an opaque key.
  static String _newDeviceId() {
    final math.Random rng = math.Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // RFC 4122 variant
    String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    final String h = List<int>.generate(16, hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  // -- Lifecycle ------------------------------------------------------------

  /// Called once from the home screen so [groqApiKey] is populated before
  /// first use.
  Future<void> hydrate() async {
    await loadApiKey();
    // Touch the device id once at startup so the first network call does not
    // race the write that creates it.
    deviceId;
    notifyListeners();
  }
}
