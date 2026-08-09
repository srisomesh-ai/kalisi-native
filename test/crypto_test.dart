import 'package:flutter_test/flutter_test.dart';
import 'package:kalisi/data/crypto/kalisi_crypto.dart';

void main() {
  test('ECDH + AES-GCM round-trips between two identities', () async {
    // Alice and Bob each generate an identity.
    final alice = await KalisiCrypto.generateKeyPair();
    final bob = await KalisiCrypto.generateKeyPair();

    // Alice encrypts a message envelope for Bob.
    final msg = {
      'kind': 'text',
      'text': 'Hello Bob 🙏 from Kalisi',
      'cid': 'abc123',
      'ts': 1720000000000,
      'burn': false,
    };
    final enc = await KalisiCrypto.encryptObject(
      msg,
      alice.privateJwk,
      bob.publicJwk,
    );

    // Bob decrypts using his private key + Alice's public key.
    final dec = await KalisiCrypto.decryptObject(
      enc.iv,
      enc.blob,
      bob.privateJwk,
      alice.publicJwk,
    );

    expect(dec['text'], 'Hello Bob 🙏 from Kalisi');
    expect(dec['kind'], 'text');
    expect(dec['cid'], 'abc123');
  });

  test('shared secret is symmetric (both sides derive same key)', () async {
    final a = await KalisiCrypto.generateKeyPair();
    final b = await KalisiCrypto.generateKeyPair();

    // A encrypts for B, B decrypts — already covered. Now B encrypts for A.
    final enc = await KalisiCrypto.encryptObject(
      {'text': 'reply', 'kind': 'text'},
      b.privateJwk,
      a.publicJwk,
    );
    final dec = await KalisiCrypto.decryptObject(
      enc.iv,
      enc.blob,
      a.privateJwk,
      b.publicJwk,
    );
    expect(dec['text'], 'reply');
  });

  test('wrong key fails to decrypt (security check)', () async {
    final a = await KalisiCrypto.generateKeyPair();
    final b = await KalisiCrypto.generateKeyPair();
    final eve = await KalisiCrypto.generateKeyPair();

    final enc = await KalisiCrypto.encryptObject(
      {'text': 'secret', 'kind': 'text'},
      a.privateJwk,
      b.publicJwk,
    );

    // Eve tries to decrypt with her key — must throw.
    expect(
      () async => KalisiCrypto.decryptObject(
        enc.iv,
        enc.blob,
        eve.privateJwk,
        a.publicJwk,
      ),
      throwsA(anything),
    );
  });
}
