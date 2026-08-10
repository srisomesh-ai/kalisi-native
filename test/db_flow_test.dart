import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalisi/data/db/database.dart';

/// Verifies the DB operations the screens depend on.
void main() {
  late KalisiDb db;

  setUp(() => db = KalisiDb.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('persona create → active → logout removes everything', () async {
    await db.upsertPersona(PersonasCompanion.insert(
      id: 'p1', kalId: 'KAL-AAAA-BBBB', username: 'somesh', name: 'Somesh',
      token: 't', privateJwk: '{}', publicJwk: '{}', createdAt: 1,
      active: const Value(true),
    ));
    expect((await db.activePersona())?.username, 'somesh');

    await db.upsertContact(ContactsCompanion.insert(
      id: 'c1', personaId: 'p1', kalId: 'KAL-CCCC-DDDD', name: 'Manoj',
      createdAt: 1,
    ));
    await db.insertMessage(MessagesCompanion.insert(
      id: 'm1', contactId: 'c1', personaId: 'p1', fromMe: 'me', ts: 1,
      body: const Value('hi'),
    ));

    // logout wipes persona + contacts + messages
    await db.logoutPersona('p1');
    expect(await db.activePersona(), isNull);
    expect(await db.contactsFor('p1'), isEmpty);
    final msgs = await db.watchMessages('c1').first;
    expect(msgs, isEmpty);
  });

  test('contactByKalId finds the right contact', () async {
    await db.upsertPersona(PersonasCompanion.insert(
      id: 'p1', kalId: 'KAL-AAAA-BBBB', username: 'u', name: 'U',
      token: 't', privateJwk: '{}', publicJwk: '{}', createdAt: 1,
    ));
    await db.upsertContact(ContactsCompanion.insert(
      id: 'c1', personaId: 'p1', kalId: 'KAL-CCCC-DDDD', name: 'Manoj',
      createdAt: 1,
    ));
    final found = await db.contactByKalId('p1', 'KAL-CCCC-DDDD');
    expect(found?.name, 'Manoj');
    final missing = await db.contactByKalId('p1', 'KAL-ZZZZ-ZZZZ');
    expect(missing, isNull);
  });
}
