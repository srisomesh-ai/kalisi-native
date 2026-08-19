import 'dart:io';
import 'package:drift/drift.dart';
import '../../util/ids.dart';
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
  /// Group rows live alongside contacts.
  BoolColumn get isGroup => boolean().withDefault(const Constant(false))();
  TextColumn get groupKey => text().nullable()();      // shared AES key (b64)
  TextColumn get groupMembers => text().nullable()();  // JSON list of KAL-ids
  BoolColumn get muted => boolean().withDefault(const Constant(false))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
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
  TextColumn get replyToId => text().nullable()();
  TextColumn get replyToText => text().nullable()();
  TextColumn get replyToWho => text().nullable()();
  /// Kept for messages that still need sending, so they can be retried.
  TextColumn get pendingEnvelope => text().nullable()();
  IntColumn get sendAttempts => integer().withDefault(const Constant(0))();
  BoolColumn get starred => boolean().withDefault(const Constant(false))();
  /// Caption on a photo, and document details.
  TextColumn get caption => text().nullable()();
  TextColumn get fileName => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  /// When a message was last edited (null if never).
  IntColumn get editedAt => integer().nullable()();
  /// Set when this message is a reply to someone's status.
  TextColumn get statusQuote => text().nullable()();
  TextColumn get statusThumb => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Personas, Contacts, Messages])
class KalisiDb extends _$KalisiDb {
  KalisiDb() : super(_open());

  /// For unit tests — pass an in-memory NativeDatabase.
  KalisiDb.forTesting(super.executor);

  @override
  int get schemaVersion => 9;

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
          if (from < 4) {
            await m.addColumn(messages, messages.replyToId);
            await m.addColumn(messages, messages.replyToText);
            await m.addColumn(messages, messages.replyToWho);
          }
          if (from < 5) {
            await m.addColumn(contacts, contacts.isGroup);
            await m.addColumn(contacts, contacts.groupKey);
            await m.addColumn(contacts, contacts.groupMembers);
          }
          if (from < 6) {
            await m.addColumn(messages, messages.pendingEnvelope);
            await m.addColumn(messages, messages.sendAttempts);
          }
          if (from < 7) {
            await m.addColumn(contacts, contacts.muted);
            await m.addColumn(contacts, contacts.pinned);
            await m.addColumn(contacts, contacts.archived);
            await m.addColumn(messages, messages.starred);
          }
          if (from < 8) {
            await m.addColumn(messages, messages.caption);
            await m.addColumn(messages, messages.fileName);
            await m.addColumn(messages, messages.fileSize);
            await m.addColumn(messages, messages.editedAt);
          }
          if (from < 9) {
            await m.addColumn(messages, messages.statusQuote);
            await m.addColumn(messages, messages.statusThumb);
          }
        },
      );

  // ---- Personas ----
  Future<List<Persona>> allPersonas() => select(personas).get();
  /// Live stream of the active persona (name / avatar changes flow through).
  Stream<Persona?> watchActivePersona() =>
      (select(personas)..where((t) => t.active.equals(true)))
          .watchSingleOrNull();

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
  /// Just the newest message in a chat, for the list preview.
  ///
  /// The list used to stream every message in every chat, and message bodies
  /// hold base64 photos and voice notes — enough to lock up the app.
  Stream<Message?> watchLastMessage(String contactId) =>
      (select(messages)
            ..where((t) => t.contactId.equals(contactId))
            ..orderBy([(t) => OrderingTerm.desc(t.ts)])
            ..limit(1))
          .watchSingleOrNull();

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
  /// Newest message received from someone else (for alerts).
  Future<Message?> latestIncoming(String personaId) =>
      (select(messages)
            ..where((t) =>
                t.personaId.equals(personaId) & t.fromMe.equals('them'))
            ..orderBy([(t) => OrderingTerm.desc(t.ts)])
            ..limit(1))
          .getSingleOrNull();

  /// Update accepted / pending flags for a contact.
  Future<void> setContactState(String contactId,
          {required bool verified, required bool pending}) =>
      (update(contacts)..where((t) => t.id.equals(contactId))).write(
        ContactsCompanion(
          verified: Value(verified),
          pending: Value(pending),
        ),
      );

  /// Update a contact's display name / photo from the server.
  Future<void> setContactProfile(String contactId,
          {required String name, required String avatar}) =>
      (update(contacts)..where((t) => t.id.equals(contactId))).write(
        ContactsCompanion(
          name: Value(name),
          avatar: Value(avatar.isEmpty ? null : avatar),
        ),
      );

  /// Groups this persona belongs to.
  Future<List<Contact>> groupsFor(String personaId) =>
      (select(contacts)
            ..where((t) => t.personaId.equals(personaId) & t.isGroup.equals(true)))
          .get();

  /// Messages still waiting to go out (oldest first).
  Future<List<Message>> queuedMessages(String personaId) =>
      (select(messages)
            ..where((t) =>
                t.personaId.equals(personaId) &
                t.status.equals('queued'))
            ..orderBy([(t) => OrderingTerm.asc(t.ts)])
            ..limit(30))
          .get();

  Future<void> markQueued(String id, String envelope) =>
      (update(messages)..where((t) => t.id.equals(id))).write(
        MessagesCompanion(
          status: const Value('queued'),
          pendingEnvelope: Value(envelope),
        ),
      );

  Future<void> markSent(String id) =>
      (update(messages)..where((t) => t.id.equals(id))).write(
        const MessagesCompanion(
          status: Value('sent'),
          pendingEnvelope: Value(null),
        ),
      );

  Future<void> bumpAttempts(String id, int attempts) =>
      (update(messages)..where((t) => t.id.equals(id)))
          .write(MessagesCompanion(sendAttempts: Value(attempts)));

  Future<void> setMuted(String id, bool v) =>
      (update(contacts)..where((t) => t.id.equals(id)))
          .write(ContactsCompanion(muted: Value(v)));

  Future<void> setPinned(String id, bool v) =>
      (update(contacts)..where((t) => t.id.equals(id)))
          .write(ContactsCompanion(pinned: Value(v)));

  Future<void> setArchived(String id, bool v) =>
      (update(contacts)..where((t) => t.id.equals(id)))
          .write(ContactsCompanion(archived: Value(v)));

  /// Change the text of a message already sent, and mark it edited.
  Future<void> editMessage(String id, String body) =>
      (update(messages)..where((t) => t.id.equals(id))).write(
        MessagesCompanion(body: Value(body), editedAt: Value(nowMs())),
      );

  Future<void> setStarred(String id, bool v) =>
      (update(messages)..where((t) => t.id.equals(id)))
          .write(MessagesCompanion(starred: Value(v)));

  /// Every starred message, newest first.
  Stream<List<Message>> watchStarred(String personaId) =>
      (select(messages)
            ..where((t) =>
                t.personaId.equals(personaId) & t.starred.equals(true))
            ..orderBy([(t) => OrderingTerm.desc(t.ts)]))
          .watch();

  /// Search a chat's messages for a phrase.
  Future<List<Message>> searchInChat(String contactId, String q) =>
      (select(messages)
            ..where((t) =>
                t.contactId.equals(contactId) & t.body.like('%$q%'))
            ..orderBy([(t) => OrderingTerm.desc(t.ts)])
            ..limit(100))
          .get();

  /// Search every chat.
  Future<List<Message>> searchAll(String personaId, String q) =>
      (select(messages)
            ..where((t) =>
                t.personaId.equals(personaId) & t.body.like('%$q%'))
            ..orderBy([(t) => OrderingTerm.desc(t.ts)])
            ..limit(100))
          .get();

  Future<void> setGroupKey(String contactId, String key) =>
      (update(contacts)..where((t) => t.id.equals(contactId)))
          .write(ContactsCompanion(groupKey: Value(key)));

  Future<void> setGroupMembers(String contactId, String membersJson) =>
      (update(contacts)..where((t) => t.id.equals(contactId)))
          .write(ContactsCompanion(groupMembers: Value(membersJson)));

  Future<void> setBlocked(String contactId, bool blocked) =>
      (update(contacts)..where((t) => t.id.equals(contactId)))
          .write(ContactsCompanion(blocked: Value(blocked)));

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
