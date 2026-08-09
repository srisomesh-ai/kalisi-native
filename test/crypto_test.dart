import 'package:flutter_test/flutter_test.dart';
import 'package:kalisi/data/crypto/kalisi_crypto.dart';

void main() {
  test('generateKeyPair produces valid JWK', () async {
    final keys = await KalisiCrypto.generateKeyPair();
    expect(keys.publicJwk, contains('"kty":"EC"'));
    expect(keys.publicJwk, contains('"crv":"P-256"'));
    expect(keys.privateJwk, contains('"d":'));
  });

  test('encrypt then decrypt round-trips between two identities', () async {
    final alice = await KalisiCrypto.generateKeyPair();
    final bob = await KalisiCrypto.generateKeyPair();

    const msg = 'Hello Bob — this is a secret 🔐';
    final enc = await KalisiCrypto.encrypt(msg, alice.privateJwk, bob.publicJwk);

    // Bob decrypts using his private key + Alice's public key
    final dec =
        await KalisiCrypto.decrypt(enc.iv, enc.data, bob.privateJwk, alice.publicJwk);
    expect(dec, msg);
  });

  test('deletion receipt is deterministic', () async {
    final r1 = await KalisiCrypto.receipt('aGVsbG8=');
    final r2 = await KalisiCrypto.receipt('aGVsbG8=');
    expect(r1, r2);
    expect(r1.length, 64); // sha-256 hex
  });

  test('fingerprint works', () async {
    final k = await KalisiCrypto.generateKeyPair();
    final fp = await KalisiCrypto.fingerprint(k.publicJwk);
    expect(fp.split(' ').length, greaterThan(4));
  });
}
