import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// End-to-end crypto for Kalisi — pure Dart (pointycastle), so it works in
/// unit tests, on Android, and matches the web app's WebCrypto scheme exactly.
///
/// Scheme (identical to the web app):
///  - Identity keypair: ECDH P-256 (secp256r1). Public key shared as JWK {x,y}.
///  - Shared secret: ECDH → the raw X coordinate (32 bytes). WebCrypto's
///    deriveKey(ECDH → AES-GCM) uses exactly these 32 bytes as the AES key.
///  - Message: AES-256-GCM encrypt(JSON.stringify(obj)) with a random 12-byte IV.
///    Output blob = ciphertext || 16-byte tag (WebCrypto layout).
///  - Deletion receipt: SHA-256 of the ciphertext (hex).
class KalisiCrypto {
  static final ECDomainParameters _domain = ECDomainParameters('secp256r1');
  static final Random _rnd = Random.secure();

  /// Generate a new identity keypair (privateJwk, publicJwk) as JSON strings.
  static ({String privateJwk, String publicJwk}) generateKeyPairSync() {
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(
          ECKeyGeneratorParameters(_domain), _secureRandom()));
    final pair = gen.generateKeyPair();
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;

    final x = _fieldToBytes(pub.Q!.x!.toBigInteger()!);
    final y = _fieldToBytes(pub.Q!.y!.toBigInteger()!);
    final d = _fieldToBytes(priv.d!);

    final pubJwk = {'kty': 'EC', 'crv': 'P-256', 'x': _b64u(x), 'y': _b64u(y)};
    final privJwk = {...pubJwk, 'd': _b64u(d)};
    return (privateJwk: jsonEncode(privJwk), publicJwk: jsonEncode(pubJwk));
  }

  static Future<({String privateJwk, String publicJwk})>
      generateKeyPair() async => generateKeyPairSync();

  // ---- Recovery: a key that can be rebuilt from a password ----

  /// A random salt for a new account, base64.
  static String newSalt() => _b64(_randomBytes(16));

  /// Stretch a password into 32 bytes using PBKDF2-SHA256.
  static Uint8List _stretch(String password, String saltB64, int iterations) {
    final salt = _unb64(saltB64);
    final params = Pbkdf2Parameters(salt, iterations, 32);
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);
    return kdf.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// Rebuild the identity key from a username and password.
  ///
  /// The same inputs always give the same key, so signing in on a new phone
  /// restores the account. The private key never leaves the device.
  static ({String privateJwk, String publicJwk}) keyPairFromPassword(
    String username,
    String password,
    String saltB64,
  ) {
    // bind the key to the username so the same password on two accounts
    // doesn't produce the same key
    final seed = _stretch('kalisi:$username:$password', saltB64, 120000);

    // turn the seed into a valid P-256 private scalar
    var d = _bytesToBigInt(seed);
    final n = _domain.n;
    d = d % (n - BigInt.one) + BigInt.one;

    final priv = ECPrivateKey(d, _domain);
    final q = _domain.G * d;
    final pub = ECPublicKey(q, _domain);

    final x = _fieldToBytes(pub.Q!.x!.toBigInteger()!);
    final y = _fieldToBytes(pub.Q!.y!.toBigInteger()!);
    final dB = _fieldToBytes(priv.d!);

    final pubJwk = {'kty': 'EC', 'crv': 'P-256', 'x': _b64u(x), 'y': _b64u(y)};
    final privJwk = {...pubJwk, 'd': _b64u(dB)};
    return (privateJwk: jsonEncode(privJwk), publicJwk: jsonEncode(pubJwk));
  }

  /// What the server stores to check the password. Derived separately from
  /// the key, so holding it reveals nothing about the key itself.
  static String verifierFor(
    String username,
    String password,
    String saltB64,
  ) =>
      _b64(_stretch('kalisi-verify:$username:$password', saltB64, 60000));

  static BigInt _bytesToBigInt(Uint8List b) {
    var r = BigInt.zero;
    for (final byte in b) {
      r = (r << 8) | BigInt.from(byte);
    }
    return r;
  }

  /// Derive the 32-byte shared AES key (raw ECDH X coordinate).
  static Uint8List _sharedKeyBytes(String myPrivateJwk, String theirPublicJwk) {
    final myJwk = jsonDecode(myPrivateJwk) as Map<String, dynamic>;
    final theirJwk = jsonDecode(theirPublicJwk) as Map<String, dynamic>;

    final d = _bytesToBig(_unb64u(myJwk['d'] as String));
    final priv = ECPrivateKey(d, _domain);

    final theirX = _bytesToBig(_unb64u(theirJwk['x'] as String));
    final theirY = _bytesToBig(_unb64u(theirJwk['y'] as String));
    final theirPoint = _domain.curve.createPoint(theirX, theirY);
    final pub = ECPublicKey(theirPoint, _domain);

    final agreement = ECDHBasicAgreement()..init(priv);
    final sharedBig = agreement.calculateAgreement(pub);
    return _fieldToBytes(sharedBig); // 32-byte big-endian X
  }

  /// Encrypt a message object for a recipient. Returns {iv, blob} base64.
  static ({String iv, String blob}) encryptObjectSync(
    Map<String, dynamic> obj,
    String myPrivateJwk,
    String theirPublicJwk,
  ) {
    final key = _sharedKeyBytes(myPrivateJwk, theirPublicJwk);
    final iv = _randomBytes(12);
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(obj)));

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final out = cipher.process(plain); // ciphertext || 16-byte tag
    return (iv: _b64(iv), blob: _b64(out));
  }

  static Future<({String iv, String blob})> encryptObject(
    Map<String, dynamic> obj,
    String myPrivateJwk,
    String theirPublicJwk,
  ) async =>
      encryptObjectSync(obj, myPrivateJwk, theirPublicJwk);

  // ---- Shared-key (group) encryption ----
  // A group has one random AES key, handed to each member over their
  // pairwise-encrypted 1:1 channel. Group messages are then encrypted once
  // with that key, which is what the server's fan-out expects.

  /// A fresh random 256-bit group key, base64.
  static String newGroupKey() => _b64(_randomBytes(32));

  /// Encrypt an object with a raw base64 key.
  static ({String iv, String blob}) encryptWithKeySync(
    Map<String, dynamic> obj,
    String keyB64,
  ) {
    final key = _unb64(keyB64);
    final iv = _randomBytes(12);
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(obj)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return (iv: _b64(iv), blob: _b64(cipher.process(plain)));
  }

  /// Decrypt an object with a raw base64 key.
  static Map<String, dynamic> decryptWithKeySync(
    String ivB64,
    String blobB64,
    String keyB64,
  ) {
    final key = _unb64(keyB64);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(key), 128, _unb64(ivB64), Uint8List(0)));
    final clear = cipher.process(_unb64(blobB64));
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  /// Decrypt a message from a sender. Returns the decoded JSON object.
  static Map<String, dynamic> decryptObjectSync(
    String ivB64,
    String blobB64,
    String myPrivateJwk,
    String theirPublicJwk,
  ) {
    final key = _sharedKeyBytes(myPrivateJwk, theirPublicJwk);
    final iv = _unb64(ivB64);
    final blob = _unb64(blobB64);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final clear = cipher.process(blob);
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> decryptObject(
    String ivB64,
    String blobB64,
    String myPrivateJwk,
    String theirPublicJwk,
  ) async =>
      decryptObjectSync(ivB64, blobB64, myPrivateJwk, theirPublicJwk);

  /// SHA-256 deletion receipt of the ciphertext (hex).
  static String receipt(String blobB64) => _hex(SHA256Digest().process(_unb64(blobB64)));

  /// Short device-key fingerprint for the Privacy screen.
  static String fingerprint(String publicJwk) {
    final hex =
        _hex(SHA256Digest().process(Uint8List.fromList(utf8.encode(publicJwk))));
    final groups = <String>[];
    for (var i = 0; i < 32 && i < hex.length; i += 4) {
      groups.add(hex.substring(i, i + 4));
    }
    return groups.join(' ');
  }

  // ---- helpers ----
  static SecureRandom _secureRandom() {
    final sr = FortunaRandom();
    final seed = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      seed[i] = _rnd.nextInt(256);
    }
    sr.seed(KeyParameter(seed));
    return sr;
  }

  static Uint8List _randomBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _rnd.nextInt(256);
    }
    return b;
  }

  static Uint8List _fieldToBytes(BigInt v) {
    var hex = v.toRadixString(16);
    if (hex.length > 64) hex = hex.substring(hex.length - 64);
    hex = hex.padLeft(64, '0');
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static BigInt _bytesToBig(Uint8List b) {
    var r = BigInt.zero;
    for (final byte in b) {
      r = (r << 8) | BigInt.from(byte);
    }
    return r;
  }

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  static String _b64(Uint8List b) => base64.encode(b);
  static Uint8List _unb64(String s) => base64.decode(s);
  static String _b64u(Uint8List b) => base64Url.encode(b).replaceAll('=', '');
  static Uint8List _unb64u(String s) {
    var t = s.replaceAll('-', '+').replaceAll('_', '/');
    while (t.length % 4 != 0) {
      t += '=';
    }
    return base64.decode(t);
  }
}
