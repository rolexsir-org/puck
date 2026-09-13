import 'dart:async';

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

  // -- Lifecycle ------------------------------------------------------------

  /// Called once from the home screen so [groqApiKey] is populated before
  /// first use.
  Future<void> hydrate() async {
    await loadApiKey();
    notifyListeners();
  }
}
