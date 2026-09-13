import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:puck/src/data/llm/groq_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User settings.
///
/// Split storage, on purpose:
///   * SharedPreferences -- preferences. Non-sensitive, cheap, synchronous-ish.
///   * flutter_secure_storage -- the API key. It lands in the iOS Keychain /
///     Android Keystore, not in a world-readable XML file in /data/data.
///
/// Nothing here is a "nice to have": the emergency contact is the difference
/// between SOS working and SOS being a torch with a screen.
class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._prefs, {FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static const String _kContactName = 'sos.contact.name';
  static const String _kContactPhone = 'sos.contact.phone';
  static const String _kHaptics = 'a11y.haptics';
  static const String _kTorch = 'sos.torch';
  static const String _kStrobe = 'sos.strobe';
  static const String _kModel = 'llm.model';
  static const String _kApiKey = 'llm.groq.key';
  static const String _kJokeIndex = 'fun.joke.index';
  static const String _kJokeOrder = 'fun.joke.order';
  static const String _kIntroSeen = 'ux.intro.seen';
  static const String _kGiggleFromModel = 'fun.giggle.model';

  /// Off by default. The bundled shuffle bag answers instantly, offline, and
  /// for free; a model round-trip on the "feel-good, feel-instant" gesture is
  /// a bad trade unless you specifically want an endless supply.
  bool get giggleFromModel => _prefs.getBool(_kGiggleFromModel) ?? false;

  Future<void> setGiggleFromModel(bool v) => _setBool(_kGiggleFromModel, v);

  /// Whether the one-time gesture legend has been acknowledged.
  bool get introSeen => _prefs.getBool(_kIntroSeen) ?? false;

  Future<void> dismissIntro() async {
    await _prefs.setBool(_kIntroSeen, true);
    notifyListeners();
  }

  bool _loaded = false;

  // -- Emergency contact ----------------------------------------------------

  String get contactName => _prefs.getString(_kContactName) ?? '';
  String get contactPhone => _prefs.getString(_kContactPhone) ?? '';

  bool get hasEmergencyContact =>
      contactPhone.trim().isNotEmpty &&
      contactPhone.replaceAll(RegExp(r'\D'), '').length >= 6;

  Future<void> setEmergencyContact({String? name, String? phone}) async {
    if (name != null) await _prefs.setString(_kContactName, name.trim());
    if (phone != null) await _prefs.setString(_kContactPhone, phone.trim());
    notifyListeners();
  }

  String get contactLabel {
    final String name = contactName.trim();
    if (name.isNotEmpty) return name;
    final String phone = contactPhone.trim();
    return phone.isEmpty ? 'no contact set' : phone;
  }

  // -- Behaviour toggles ----------------------------------------------------

  bool get hapticsEnabled => _prefs.getBool(_kHaptics) ?? true;
  bool get torchEnabled => _prefs.getBool(_kTorch) ?? true;
  bool get strobeEnabled => _prefs.getBool(_kStrobe) ?? true;

  Future<void> setHaptics(bool v) => _setBool(_kHaptics, v);
  Future<void> setTorch(bool v) => _setBool(_kTorch, v);
  Future<void> setStrobe(bool v) => _setBool(_kStrobe, v);

  Future<void> _setBool(String key, bool v) async {
    await _prefs.setBool(key, v);
    notifyListeners();
  }

  // -- Model ----------------------------------------------------------------

  String get llmModel => _prefs.getString(_kModel) ?? GroqLlmProvider.defaultModel;

  Future<void> setLlmModel(String model) async {
    await _prefs.setString(_kModel, model.trim());
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

  /// Called once from main() so [groqApiKey] is populated before first use.
  Future<void> hydrate() async {
    if (_loaded) return;
    _loaded = true;
    await loadApiKey();
    notifyListeners();
  }
}
