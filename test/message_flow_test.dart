import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalisi/data/db/database.dart';
import 'package:kalisi/data/crypto/kalisi_crypto.dart';

/// This test proves the FULL message pipeline without a network:
/// two identities, encrypt an envelope, "relay" the ciphertext, decrypt,
/// and confirm the plaintext survives — exactly what send/receive do.
void main() {
  test('two users exchange an encrypted message end-to-end', () async {
    final alice = KalisiCrypto.generateKeyPairSync();
    final bob = KalisiCrypto.generateKeyPairSync();

    // Alice composes the same envelope MessageRepository.sendText builds.
    final envelope = {
      'kind': 'text',
      'text': 'Balance ready ✅',
      'cid': 'msg-1',
      'ts': 1720000000000,
      'burn': false,
      'timer': 0,
    };

    // Alice encrypts for Bob.
    final enc = KalisiCrypto.encryptObjectSync(
      envelope,
      alice.privateJwk,
      bob.publicJwk,
    );

    // ---- server relays {iv, blob} untouched ----

    // Bob decrypts what he received.
    final got = KalisiCrypto.decryptObjectSync(
      enc.iv,
      enc.blob,
      bob.privateJwk,
      alice.publicJwk,
    );

    expect(got['text'], 'Balance ready ✅');
    expect(got['cid'], 'msg-1');
    expect(got['kind'], 'text');
  });

  test('database stores and streams messages', () async {
    final db = KalisiDb.forTesting(NativeDatabase.memory());

    // create a persona + contact
    await db.upsertPersona(PersonasCompanion.insert(
      id: 'p1',
      kalId: 'KAL-AAAA-BBBB',
      username: 'somesh',
      name: 'Somesh',
      token: 'tok',
      privateJwk: '{}',
      publicJwk: '{}',
      createdAt: 1,
    ));
    await db.upsertContact(ContactsCompanion.insert(
      id: 'c1',
      personaId: 'p1',
      kalId: 'KAL-CCCC-DDDD',
      name: 'Manoj',
      createdAt: 1,
    ));

    // insert a message
    await db.insertMessage(MessagesCompanion.insert(
      id: 'm1',
      contactId: 'c1',
      personaId: 'p1',
      fromMe: 'me',
      ts: 100,
      body: const Value('Hello'),
    ));

    final msgs = await db.watchMessages('c1').first;
    expect(msgs.length, 1);
    expect(msgs.first.body, 'Hello');

    await db.close();
  });
}
