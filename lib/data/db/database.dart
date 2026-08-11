import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

/// Personas = identities on this device. Each has its own keypair + @username.
class Personas extends Table {
  TextColumn get id => text()(); // local uuid
  TextColumn get kalId => text()(); // KAL-XXXX-XXXX from server
  TextColumn get username => text()();
  TextColumn get name => text()();
  TextColumn get token => text()(); // auth token from server
  TextColumn get privateJwk => text()();
  TextColumn get publicJwk => text()();
  TextColumn get avatar => text().nullable()();   // base64 data URL
  BoolColumn get active => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Contacts belong to a persona.
class Contacts extends Table {
  TextColumn get id => text()(); // local uuid
  TextColumn get personaId => text()();
  TextColumn get kalId => text()();
  TextColumn get username => text().nullable()();
  TextColumn get name => text()();
  TextColumn get publicJwk => text().nullable()();
  BoolColumn get verified => boolean().withDefault(const Constant(false))();
  BoolColumn get blocked => boolean().withDefault(const Constant(false))();
  IntColumn get timer => integer().withDefault(const Constant(0))(); // disappearing seconds
  IntColumn get lastSeen => integer().withDefault(const Constant(0))();
  TextColumn get mood => text().nullable()();
  TextColumn get avatar => text().nullable()();   // base64 data URL
  /// True while a sent friend request has not been accepted yet.
  BoolColumn get pending => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Messages belong to a contact.
class Messages extends Table {
  TextColumn get id => text()(); // client id (cid)
  TextColumn get contactId => text()();
  TextColumn get personaId => text()();
  TextColumn get fromMe => text()(); // 'me' | 'them'
  TextColumn get kind => text().withDefault(const Constant('text'))(); // text|img|voice
  TextColumn get body => text().nullable()();
  TextColumn get mediaPath => text().nullable()();
  IntColumn get ts => integer()();
  TextColumn get status => text().withDefault(const Constant('sent'))(); // sent|delivered|read
  BoolColumn get burn => boolean().withDefault(const Constant(false))();
  BoolColumn get burned => boolean().withDefault(const Constant(false))();
  IntColumn get expireAt => integer().nullable()();
  TextColumn get reactionMine => text().nullable()();
  TextColumn get reactionTheirs => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Personas, Contacts, Messages])
class KalisiDb extends _$KalisiDb {
  KalisiDb() : super(_open());

  /// For unit tests — pass an in-memory NativeDatabase.
  KalisiDb.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(contacts, contacts.mood);
            await m.addColumn(contacts, contacts.pending);
          }
          if (from < 3) {
            await m.addColumn(personas, personas.avatar);
            await m.addColumn(contacts, contacts.avatar);
          }
        },
      );

  // ---- Personas ----
  Future<List<Persona>> allPersonas() => select(personas).get();
  Future<Persona?> activePersona() =>
      (select(personas)..where((t) => t.active.equals(true)))
          .getSingleOrNull();
  Future<void> upsertPersona(PersonasCompanion p) =>
      into(personas).insertOnConflictUpdate(p);
  /// Update my display name and/or avatar.
  Future<void> updateProfile(String id, {String? name, String? avatar}) =>
      (update(personas)..where((t) => t.id.equals(id))).write(
        PersonasCompanion(
          name: name == null ? const Value.absent() : Value(name),
          avatar: avatar == null ? const Value.absent() : Value(avatar),
        ),
      );

  Future<void> setActivePersona(String id) async {
    await (update(personas)).write(const PersonasCompanion(active: Value(false)));
    await (update(personas)..where((t) => t.id.equals(id)))
        .write(const PersonasCompanion(active: Value(true)));
  }

  /// Log out (delete) a persona and all its data.
  Future<void> logoutPersona(String id) async {
    await (delete(messages)..where((t) => t.personaId.equals(id))).go();
    await (delete(contacts)..where((t) => t.personaId.equals(id))).go();
    await (delete(personas)..where((t) => t.id.equals(id))).go();
  }

  // ---- Contacts ----
  Stream<List<Contact>> watchContacts(String personaId) =>
      (select(contacts)..where((t) => t.personaId.equals(personaId))).watch();
  Future<List<Contact>> contactsFor(String personaId) =>
      (select(contacts)..where((t) => t.personaId.equals(personaId))).get();
  Future<Contact?> contactById(String id) =>
      (select(contacts)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<Contact?> contactByKalId(String personaId, String kalId) =>
      (select(contacts)
            ..where((t) => t.personaId.equals(personaId) & t.kalId.equals(kalId)))
          .getSingleOrNull();
  Future<void> upsertContact(ContactsCompanion c) =>
      into(contacts).insertOnConflictUpdate(c);
  Future<void> deleteContact(String id) async {
    await (delete(messages)..where((t) => t.contactId.equals(id))).go();
    await (delete(contacts)..where((t) => t.id.equals(id))).go();
  }

  // ---- Messages ----
  Stream<List<Message>> watchMessages(String contactId) =>
      (select(messages)
            ..where((t) => t.contactId.equals(contactId))
            ..orderBy([(t) => OrderingTerm.asc(t.ts)]))
          .watch();
  Future<void> insertMessage(MessagesCompanion m) =>
      into(messages).insertOnConflictUpdate(m);
  Future<void> updateMessageStatus(String id, String status) =>
      (update(messages)..where((t) => t.id.equals(id)))
          .write(MessagesCompanion(status: Value(status)));

  /// Mark a message as burned (its content is gone).
  Future<void> markBurned(String id) =>
      (update(messages)..where((t) => t.id.equals(id))).write(
          const MessagesCompanion(burned: Value(true), body: Value(null)));

  /// Set the reaction the other person left on one of my messages.
  Future<void> setReaction(String id, String? emoji) =>
      (update(messages)..where((t) => t.id.equals(id)))
          .write(MessagesCompanion(reactionTheirs: Value(emoji)));

  /// Set my own reaction on a message.
  Future<void> setMyReaction(String id, String? emoji) =>
      (update(messages)..where((t) => t.id.equals(id)))
          .write(MessagesCompanion(reactionMine: Value(emoji)));
  Future<void> clearMessages(String contactId) =>
      (delete(messages)..where((t) => t.contactId.equals(contactId))).go();

  /// Delete a single message by id (used for delete-for-everyone control msg).
  Future<void> deleteMessageById(String id) =>
      (delete(messages)..where((t) => t.id.equals(id))).go();
  Future<Message?> lastMessage(String contactId) => (select(messages)
        ..where((t) => t.contactId.equals(contactId))
        ..orderBy([(t) => OrderingTerm.desc(t.ts)])
        ..limit(1))
      .getSingleOrNull();
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'kalisi.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
