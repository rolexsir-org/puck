import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:puck/src/sync/puck_crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';


/// Puck sync client for Dart — the phone agent's link to every other device.
///
/// Mirrors `shared/src/sync-client.ts`. The only behavioural difference is
/// lifecycle: a phone app is suspended and resumed constantly, so this client
/// exposes explicit [pause]/[resume] rather than assuming a permanent
/// connection, and it drops frames while suspended instead of queueing them.
class PuckSyncClient {
  PuckSyncClient({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceClass,
    required this.token,
    required this.deviceKeyPair,
    this.vaultKey,
  });

  final String baseUrl;
  final String deviceId;
  final String deviceClass;
  final String token;
  final SimpleKeyPair deviceKeyPair;
  SecretKey? vaultKey;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  DateTime _lastPong = DateTime.now();
  int _seq = 0;
  int _attempt = 0;
  bool _closed = false;
  bool _paused = false;

  final Map<String, Set<void Function(dynamic, Map<String, dynamic>)>>
      _handlers = <String, Set<void Function(dynamic, Map<String, dynamic>)>>{};
  final Set<void Function(bool)> _stateListeners = <void Function(bool)>{};

  bool get isConnected => _channel != null && !_closed;

  // -- lifecycle -------------------------------------------------------------

  void connect() {
    _closed = false;
    _paused = false;
    _open();
  }

  void _open() {
    final Uri uri = Uri.parse(baseUrl).replace(
      scheme: baseUrl.startsWith('https') ? 'wss' : 'ws',
      queryParameters: <String, String>{
        'deviceId': deviceId,
        'token': token,
        'v': '1',
      },
    );

    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (_) {
      _scheduleReconnect();
      return;
    }

    _lastPong = DateTime.now();
    _sub = _channel!.stream.listen(
      _onMessage,
      onDone: () {
        _channel = null;
        if (!_closed) _scheduleReconnect();
      },
      onError: (Object _) {
        _channel = null;
        if (!_closed) _scheduleReconnect();
      },
    );

    send('hello', <String, dynamic>{
      'deviceClass': deviceClass,
      'vaultKeyEpoch': 0,
    });
    _startHeartbeat();
    _notifyState(true);
  }

  /// Called on `AppLifecycleState.paused`. A phone that pretends to be a
  /// server gets killed for it.
  void pause() {
    _paused = true;
    _stopHeartbeat();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _notifyState(false);
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _attempt = 0;
    _open();
  }

  void close() {
    _closed = true;
    _stopHeartbeat();
    _reconnect?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _notifyState(false);
  }

  void _scheduleReconnect() {
    final int base = 500 * (1 << _attempt.clamp(0, 4));
    final double jitter = base * (0.85 + (DateTime.now().microsecond % 30) / 100);
    _attempt++;
    _reconnect?.cancel();
    _reconnect = Timer(
      Duration(milliseconds: jitter.round().clamp(500, 8000)),
      _open,
    );
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (DateTime.now().difference(_lastPong) > const Duration(seconds: 60)) {
        _channel?.sink.close();
        return;
      }
      send('ping', <String, dynamic>{});
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  // -- frames ----------------------------------------------------------------

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final String? type = frame['t'] as String?;
    if (type == null) return;
    if (type == 'pong') {
      _lastPong = DateTime.now();
      return;
    }

    // Unknown frame types are ignored, not fatal -- PROTOCOL §8.
    final Set<void Function(dynamic, Map<String, dynamic>)>? set =
        _handlers[type];
    if (set == null) return;
    for (final void Function(dynamic, Map<String, dynamic>) h
        in List<void Function(dynamic, Map<String, dynamic>)>.from(set)) {
      try {
        h(frame['payload'], frame);
      } catch (_) {
        // One bad handler must not take down the socket.
      }
    }
  }

  String send(String type, Object payload, {String? to}) {
    final String id = _newId();
    if (_channel == null) return id;

    _channel!.sink.add(jsonEncode(<String, dynamic>{
      'v': 1,
      't': type,
      'id': id,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'from': deviceId,
      'to': to,
      'seq': ++_seq,
      'payload': payload,
    }),);
    return id;
  }

  void on(
    String type,
    void Function(dynamic payload, Map<String, dynamic> frame) handler,
  ) {
    _handlers.putIfAbsent(
      type,
      () => <void Function(dynamic, Map<String, dynamic>)>{},
    ).add(handler);
  }

  void onConnectionState(void Function(bool) listener) {
    _stateListeners.add(listener);
    listener(isConnected);
  }

  void _notifyState(bool up) {
    for (final void Function(bool) l in _stateListeners) {
      l(up);
    }
  }

  // -- behaviours ------------------------------------------------------------

  void publishContext(String label, String headline) {
    send('context.update', <String, dynamic>{
      'kind': 'time',
      'label': label,
      'headline': headline,
      'ttlMs': 120000,
    });
  }

  Future<void> publishIntentStart(String intentId, String query) async {
    final Object payload = vaultKey != null
        ? (await PuckCrypto.sealWithVault(vaultKey!, query)).toJson()
        : query;
    send('intent.start', <String, dynamic>{
      'intentId': intentId,
      'mode': 'intent',
      'query': payload,
      'deviceClass': deviceClass,
    });
  }

  Future<String> publishHandoff({
    required String summary,
    required String targetHint,
  }) async {
    final String handoffId = _newId();
    final Object payload = vaultKey != null
        ? (await PuckCrypto.sealWithVault(vaultKey!, summary)).toJson()
        : summary;
    send('handoff.publish', <String, dynamic>{
      'handoffId': handoffId,
      'intentId': null,
      'targetHint': targetHint,
      'summary': payload,
      'ttlMs': 900000,
    });
    return handoffId;
  }

  void claimHandoff(String handoffId) {
    send('handoff.claim', <String, dynamic>{'handoffId': handoffId});
  }

  /// Reads an offer's summary, decrypting if we hold the vault key.
  Future<String> readHandoff(dynamic offer) async {
    final dynamic summary = (offer as Map)['summary'];
    if (summary is String) return summary;
    if (summary is Map && vaultKey != null) {
      return PuckCrypto.openWithVault<String>(
        vaultKey!,
        SealedEnvelope.fromJson(summary.cast<String, dynamic>()),
      );
    }
    return '[locked]';
  }

  static String _newId() {
    final String t =
        DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
    final Uint8List r = PuckCrypto.random(10);
    String rand = '';
    for (final int b in r) {
      rand += b.toRadixString(16).padLeft(2, '0');
    }
    return '$t$rand';
  }
}
