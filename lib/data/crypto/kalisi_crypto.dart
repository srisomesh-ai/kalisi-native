import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// End-to-end crypto for Kalisi — matches the web app's scheme so messages
/// sent between the app and web interoperate.
///
/// Scheme:
///  - Identity keypair: ECDH P-256 (secp256r1), public key shared as JWK.
///  - Shared secret: ECDH between my private key and their public key.
///  - Message key: derived AES-GCM 256 from the shared secret.
///  - Payload: AES-GCM encrypt(plaintext) with a random 12-byte IV.
///  - Deletion receipt: SHA-256 of the ciphertext.
class KalisiCrypto {
  // Use the pure-Dart implementations explicitly. The default Cryptography
  // backend throws UnimplementedError for ECDH P-256 / AES-GCM unless a
  // platform backend is registered; DartCryptography implements them directly.
  static final _ecdh = DartEcdh.p256();
  static final _aes = DartAesGcm(secretKeyLength: 32);
  static final _sha256 = DartSha256();

  /// Generate a new identity keypair. Returns (privateJwk, publicJwk) as JSON strings.
  static Future<({String privateJwk, String publicJwk})> generateKeyPair() async {
    final kp = await _ecdh.newKeyPair();
    final keyData = await kp.extract();
    final pub = keyData.publicKey;

    final pubJwk = _publicKeyToJwk(pub);
    final privJwk = {
      ...pubJwk,
      'd': _b64u(keyData.d),
    };
    return (
      privateJwk: jsonEncode(privJwk),
      publicJwk: jsonEncode(pubJwk),
    );
  }

  static Map<String, dynamic> _publicKeyToJwk(EcPublicKey pub) => {
        'kty': 'EC',
        'crv': 'P-256',
        'x': _b64u(pub.x),
        'y': _b64u(pub.y),
      };

  /// Rebuild an EcKeyPair from stored private JWK.
  static EcKeyPairData _keyPairFromJwk(String privateJwk) {
    final j = jsonDecode(privateJwk) as Map<String, dynamic>;
    return EcKeyPairData(
      d: _unb64u(j['d'] as String),
      x: _unb64u(j['x'] as String),
      y: _unb64u(j['y'] as String),
      type: KeyPairType.p256,
    );
  }

  static EcPublicKey _publicFromJwk(String publicJwk) {
    final j = jsonDecode(publicJwk) as Map<String, dynamic>;
    return EcPublicKey(
      x: _unb64u(j['x'] as String),
      y: _unb64u(j['y'] as String),
      type: KeyPairType.p256,
    );
  }

  /// Derive the shared AES-GCM key between my private key and their public key.
  static Future<SecretKey> _sharedKey(
      String myPrivateJwk, String theirPublicJwk) async {
    final myKp = _keyPairFromJwk(myPrivateJwk);
    final theirPub = _publicFromJwk(theirPublicJwk);
    final shared = await _ecdh.sharedSecretKey(
      keyPair: myKp,
      remotePublicKey: theirPub,
    );
    final bytes = await shared.extractBytes();
    return SecretKey(bytes);
  }

  /// Encrypt plaintext for a recipient. Returns {iv, data} base64 strings.
  static Future<({String iv, String data})> encrypt(
    String plaintext,
    String myPrivateJwk,
    String theirPublicJwk,
  ) async {
    final key = await _sharedKey(myPrivateJwk, theirPublicJwk);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    // Web stores ciphertext+tag together; concatenate as cipherText||mac.
    final combined = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
    return (
      iv: _b64(Uint8List.fromList(nonce)),
      data: _b64(combined),
    );
  }

  /// Decrypt a payload from a sender.
  static Future<String> decrypt(
    String ivB64,
    String dataB64,
    String myPrivateJwk,
    String theirPublicJwk,
  ) async {
    final key = await _sharedKey(myPrivateJwk, theirPublicJwk);
    final nonce = _unb64(ivB64);
    final combined = _unb64(dataB64);
    // Last 16 bytes = GCM tag.
    final cipherText = combined.sublist(0, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));
    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  /// SHA-256 deletion receipt of the ciphertext (hex).
  static Future<String> receipt(String dataB64) async {
    final hash = await _sha256.hash(_unb64(dataB64));
    return hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Short device-key fingerprint (for the Privacy screen).
  static Future<String> fingerprint(String publicJwk) async {
    final hash = await _sha256.hash(utf8.encode(publicJwk));
    final hex = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    // groups of 4, 8 groups
    final groups = <String>[];
    for (var i = 0; i < 32 && i < hex.length; i += 4) {
      groups.add(hex.substring(i, i + 4));
    }
    return groups.join(' ');
  }

  // ---- base64 helpers ----
  static String _b64(Uint8List b) => base64.encode(b);
  static Uint8List _unb64(String s) => base64.decode(s);
  static String _b64u(List<int> b) =>
      base64Url.encode(b).replaceAll('=', '');
  static Uint8List _unb64u(String s) {
    var t = s.replaceAll('-', '+').replaceAll('_', '/');
    while (t.length % 4 != 0) {
      t += '=';
    }
    return base64.decode(t);
  }
}
