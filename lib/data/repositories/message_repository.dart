import 'package:drift/drift.dart';
import '../db/database.dart';
import '../api/api_client.dart';
import '../crypto/kalisi_crypto.dart';
import '../../util/ids.dart';

/// Handles sending and receiving encrypted messages, and persisting them.
class MessageRepository {
  final KalisiDb _db;
  final ApiClient _api;
  MessageRepository(this._db, this._api);

  /// Send a text message to a contact.
  /// 1. store locally (status: sending), 2. encrypt, 3. POST to server,
  /// 4. update status to sent/failed.
  Future<void> sendText({
    required Persona me,
    required Contact contact,
    required String text,
    bool burn = false,
    int timer = 0,
  }) async {
    final cid = newUuid();
    final ts = nowMs();

    // 1. persist immediately so the UI shows it right away
    await _db.insertMessage(MessagesCompanion.insert(
      id: cid,
      contactId: contact.id,
      personaId: me.id,
      fromMe: 'me',
      kind: const Value('text'),
      body: Value(text),
      ts: ts,
      status: const Value('sending'),
      burn: Value(burn),
    ));

    // Need the recipient's public key to encrypt.
    final theirPub = contact.publicJwk;
    if (theirPub == null) {
      await _db.updateMessageStatus(cid, 'failed');
      throw ApiException('no_pubkey');
    }

    // 2. build the SAME object shape the web uses, then encrypt
    final obj = <String, dynamic>{
      'kind': 'text',
      'text': text,
      'img': null,
      'audio': null,
      'wave': null,
      'dur': 0,
      'burn': burn,
      'replyTo': null,
      'cid': cid,
      'ts': ts,
      'timer': timer,
    };

    try {
      final enc = await KalisiCrypto.encryptObject(
        obj,
        me.privateJwk,
        theirPub,
      );
      // 3. send
      await _api.send(
        kalId: me.kalId,
        token: me.token,
        to: contact.kalId,
        clientId: cid,
        iv: enc.iv,
        blob: enc.blob,
      );
      // 4. mark sent
      await _db.updateMessageStatus(cid, 'sent');
    } catch (e) {
      await _db.updateMessageStatus(cid, 'failed');
      rethrow;
    }
  }

  /// Send a media message (photo or voice) to a contact.
  /// [kind] is 'img' or 'voice'. [dataUrl] is a base64 data URL
  /// (image) or base64 audio. [localPath] is stored for local display.
  Future<void> sendMedia({
    required Persona me,
    required Contact contact,
    required String kind, // 'img' | 'voice'
    required String dataUrl,
    String? localPath,
    int durationSec = 0,
    List<int>? waveform,
    bool burn = false,
    int timer = 0,
  }) async {
    final cid = newUuid();
    final ts = nowMs();

    await _db.insertMessage(MessagesCompanion.insert(
      id: cid,
      contactId: contact.id,
      personaId: me.id,
      fromMe: 'me',
      kind: Value(kind),
      body: Value(kind == 'img' ? dataUrl : null),
      mediaPath: Value(localPath),
      ts: ts,
      status: const Value('sending'),
      burn: Value(burn),
    ));

    final theirPub = contact.publicJwk;
    if (theirPub == null) {
      await _db.updateMessageStatus(cid, 'failed');
      throw ApiException('no_pubkey');
    }

    final obj = <String, dynamic>{
      'kind': kind,
      'text': null,
      'img': kind == 'img' ? dataUrl : null,
      'audio': kind == 'voice' ? dataUrl : null,
      'wave': waveform,
      'dur': durationSec,
      'burn': burn,
      'replyTo': null,
      'cid': cid,
      'ts': ts,
      'timer': timer,
    };

    try {
      final enc = await KalisiCrypto.encryptObject(obj, me.privateJwk, theirPub);
      await _api.send(
        kalId: me.kalId,
        token: me.token,
        to: contact.kalId,
        clientId: cid,
        iv: enc.iv,
        blob: enc.blob,
      );
      await _db.updateMessageStatus(cid, 'sent');
    } catch (e) {
      await _db.updateMessageStatus(cid, 'failed');
      rethrow;
    }
  }
  Future<int> poll(Persona me) async {
    final res = await _api.fetch(kalId: me.kalId, token: me.token);

    var received = 0;
    final messages = (res['messages'] as List?) ?? const [];
    for (final raw in messages) {
      final m = (raw as Map).map((k, v) => MapEntry(k.toString(), v));
      final fromKal = m['from']?.toString() ?? '';
      final iv = m['iv']?.toString() ?? '';
      final blob = m['blob']?.toString() ?? '';
      final ts = (m['ts'] is int) ? m['ts'] as int : nowMs();

      // find the contact this is from (must already be a contact with a pubkey)
      final contact = await _db.contactByKalId(me.id, fromKal);
      if (contact == null || contact.publicJwk == null) {
        // message from someone not in contacts yet — skip for now
        continue;
      }

      try {
        final obj = await KalisiCrypto.decryptObject(
          iv,
          blob,
          me.privateJwk,
          contact.publicJwk!,
        );
        final cid = obj['cid']?.toString() ?? newUuid();
        final kind = obj['kind']?.toString() ?? 'text';
        // For media, keep the payload in body so the UI can render it.
        String? body;
        if (kind == 'img') {
          body = obj['img']?.toString();
        } else if (kind == 'voice') {
          body = obj['audio']?.toString();
        } else {
          body = obj['text']?.toString();
        }
        await _db.insertMessage(MessagesCompanion.insert(
          id: cid,
          contactId: contact.id,
          personaId: me.id,
          fromMe: 'them',
          kind: Value(kind),
          body: Value(body),
          ts: (obj['ts'] is int) ? obj['ts'] as int : ts,
          status: const Value('delivered'),
          burn: Value(obj['burn'] == true),
        ));
        received++;
      } catch (_) {
        // couldn't decrypt (key mismatch) — skip silently
        continue;
      }
    }

    // delivery receipts → mark my sent messages as delivered
    final receipts = (res['receipts'] as List?) ?? const [];
    for (final raw in receipts) {
      final r = (raw as Map).map((k, v) => MapEntry(k.toString(), v));
      final cid = r['client_id']?.toString();
      if (cid != null) {
        await _db.updateMessageStatus(cid, 'delivered');
      }
    }

    return received;
  }
}
