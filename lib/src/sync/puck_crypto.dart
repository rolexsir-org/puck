import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Puck crypto for Dart — X25519 → HKDF-SHA256 → AES-256-GCM.
///
/// A line-for-line sibling of `shared/src/crypto.ts`: same primitives, same
/// KDF info string, same envelope shape. The info string is load-bearing —
/// change it in one language and the other cannot decrypt.
class PuckCrypto {
  PuckCrypto._();

  static final X25519 _x25519 = X25519();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final AesGcm _aes = AesGcm.with256bits();
  static final Random _rng = Random.secure();

  static const List<int> _hkdfInfo = <int>[
    0x70, 0x75, 0x63, 0x6b, 0x2e, 0x76, 0x31, 0x2e, // "puck.v1."
    0x61, 0x65, 0x73, 0x2d, 0x67, 0x63, 0x6d, // "aes-gcm"
  ];

  static const List<int> _vaultInfo = <int>[
    0x70, 0x75, 0x63, 0x6b, 0x2e, 0x76, 0x61, 0x75, 0x6c, 0x74, 0x2e, 0x76, 0x31,
  ];

  // -- encoding -------------------------------------------------------------

  static String b64u(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List fromB64u(String s) {
    final String padded = s.replaceAll('-', '+').replaceAll('_', '/');
    final int rem = padded.length % 4;
    return base64.decode(rem == 0 ? padded : padded + '=' * (4 - rem));
  }

  static Uint8List random(int n) {
    final Uint8List out = Uint8List(n);
    for (int i = 0; i < n; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }

  // -- keys ------------------------------------------------------------------

  static Future<SimpleKeyPair> newDeviceKeyPair() => _x25519.newKeyPair();

  static Future<String> publicKeyOf(SimpleKeyPair kp) async {
    final SimplePublicKey pub = await kp.extractPublicKey();
    return b64u(Uint8List.fromList(pub.bytes));
  }

  /// The vault key, derived from a WebAuthn PRF output.
  static Future<SecretKey> deriveVaultKey({
    required Uint8List prfOutput,
    required String userId,
  }) async {
    return _hkdf.deriveKey(
      secretKey: SecretKey(prfOutput),
      nonce: utf8.encode(userId),
      info: _vaultInfo,
    );
  }

  static Future<SecretKey> vaultKeyFromBytes(Uint8List raw) async =>
      SecretKey(raw);

  static Future<Uint8List> vaultKeyBytes(SecretKey key) async =>
      Uint8List.fromList(await key.extractBytes());

  // -- sealed box ------------------------------------------------------------

  /// Ephemeral-sender sealed box, matching `sealTo` in the TS client.
  static Future<SealedEnvelope> sealTo(
    String recipientPubB64u,
    Object value,
  ) async {
    final SimpleKeyPair ephemeral = await _x25519.newKeyPair();
    final SimplePublicKey remote = SimplePublicKey(
      fromB64u(recipientPubB64u),
      type: KeyPairType.x25519,
    );

    final SecretKey shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: remote,
    );
    final SecretKey aes = await _deriveAes(shared);

    final Uint8List nonce = random(12);
    final SecretBox box = await _aes.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: aes,
      nonce: nonce,
    );

    final SimplePublicKey ephPub = await ephemeral.extractPublicKey();
    return SealedEnvelope(
      e: b64u(Uint8List.fromList(ephPub.bytes)),
      n: b64u(nonce),
      c: b64u(Uint8List.fromList(box.concatenation())),
    );
  }

  static Future<T> openFrom<T>(
    SimpleKeyPair deviceKeyPair,
    SealedEnvelope envelope,
  ) async {
    final String? e = envelope.e;
    if (e == null) throw const PuckCryptoException('not a sealed box');

    final SimplePublicKey ephPub =
        SimplePublicKey(fromB64u(e), type: KeyPairType.x25519);
    final SecretKey shared = await _x25519.sharedSecretKey(
      keyPair: deviceKeyPair,
      remotePublicKey: ephPub,
    );
    final SecretKey aes = await _deriveAes(shared);

    final List<int> clear = await _aes.decrypt(
      SecretBox.fromConcatenation(
        fromB64u(envelope.c),
        nonceLength: 12,
        macLength: 16,
      ),
      secretKey: aes,
    );
    return jsonDecode(utf8.decode(clear)) as T;
  }

  // -- symmetric vault -------------------------------------------------------

  static Future<SealedEnvelope> sealWithVault(
    SecretKey vaultKey,
    Object value,
  ) async {
    final Uint8List nonce = random(12);
    final SecretBox box = await _aes.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: vaultKey,
      nonce: nonce,
    );
    return SealedEnvelope(
      n: b64u(nonce),
      c: b64u(Uint8List.fromList(box.concatenation())),
    );
  }

  static Future<T> openWithVault<T>(
    SecretKey vaultKey,
    SealedEnvelope envelope,
  ) async {
    final List<int> clear = await _aes.decrypt(
      SecretBox.fromConcatenation(
        fromB64u(envelope.c),
        nonceLength: 12,
        macLength: 16,
      ),
      secretKey: vaultKey,
    );
    return jsonDecode(utf8.decode(clear)) as T;
  }

  static Future<SecretKey> unwrapVaultKey(
    SimpleKeyPair deviceKeyPair,
    SealedEnvelope wrapped,
  ) async {
    final String raw = await openFrom<String>(deviceKeyPair, wrapped);
    return SecretKey(fromB64u(raw));
  }

  // -- internals -------------------------------------------------------------

  static Future<SecretKey> _deriveAes(SecretKey shared) => _hkdf.deriveKey(
        secretKey: shared,
        nonce: const <int>[],
        info: _hkdfInfo,
      );
}

/// Wire shape shared with the TypeScript client.
class SealedEnvelope {
  const SealedEnvelope({this.e, required this.n, required this.c});

  factory SealedEnvelope.fromJson(Map<String, dynamic> json) => SealedEnvelope(
        e: json['e'] as String?,
        n: json['n'] as String,
        c: json['c'] as String,
      );

  final String? e;
  final String n;
  final String c;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (e != null) 'e': e,
        'n': n,
        'c': c,
      };
}

class PuckCryptoException implements Exception {
  const PuckCryptoException(this.message);
  final String message;

  @override
  String toString() => 'PuckCryptoException: $message';
}
