import 'package:flutter_test/flutter_test.dart';
import 'package:kalisi/data/crypto/kalisi_crypto.dart';

void main() {
  test('generateKeyPair produces valid JWK', () async {
    final keys = await KalisiCrypto.generateKeyPair();
    expect(keys.publicJwk, contains('"kty":"EC"'));
    expect(keys.publicJwk, contains('"crv":"P-256"'));
    expect(keys.privateJwk, contains('"d":'));
  });

  test('encryptObject then decryptObject round-trips', () async {
    final alice = await KalisiCrypto.generateKeyPair();
    final bob = await KalisiCrypto.generateKeyPair();

    final obj = {
      'kind': 'text',
      'text': 'Hello Bob — this is a secret 🔐',
      'cid': 'm1',
      'ts': 1234567890,
    };

    final enc =
        await KalisiCrypto.encryptObject(obj, alice.privateJwk, bob.publicJwk);
    final dec = await KalisiCrypto.decryptObject(
        enc.iv, enc.blob, bob.privateJwk, alice.publicJwk);

    expect(dec['text'], obj['text']);
    expect(dec['cid'], 'm1');
    expect(dec['ts'], 1234567890);
  });

  test('both directions work (Bob replies to Alice)', () async {
    final alice = await KalisiCrypto.generateKeyPair();
    final bob = await KalisiCrypto.generateKeyPair();

    final reply = {'kind': 'text', 'text': 'Got it 👍', 'cid': 'm2', 'ts': 99};
    final enc =
        await KalisiCrypto.encryptObject(reply, bob.privateJwk, alice.publicJwk);
    final dec = await KalisiCrypto.decryptObject(
        enc.iv, enc.blob, alice.privateJwk, bob.publicJwk);

    expect(dec['text'], 'Got it 👍');
  });

  test('wrong key cannot decrypt', () async {
    final alice = await KalisiCrypto.generateKeyPair();
    final bob = await KalisiCrypto.generateKeyPair();
    final eve = await KalisiCrypto.generateKeyPair();

    final obj = {'kind': 'text', 'text': 'secret', 'cid': 'm3', 'ts': 1};
    final enc =
        await KalisiCrypto.encryptObject(obj, alice.privateJwk, bob.publicJwk);

    expect(
      () => KalisiCrypto.decryptObject(
          enc.iv, enc.blob, eve.privateJwk, alice.publicJwk),
      throwsA(anything),
    );
  });

  test('deletion receipt is deterministic', () async {
    final r1 = await KalisiCrypto.receipt('aGVsbG8=');
    final r2 = await KalisiCrypto.receipt('aGVsbG8=');
    expect(r1, r2);
    expect(r1.length, 64);
  });
}
