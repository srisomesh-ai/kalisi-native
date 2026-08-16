import 'dart:convert';
import 'package:drift/drift.dart';
import '../db/database.dart';
import '../api/api_client.dart';
import '../crypto/kalisi_crypto.dart';
import '../../util/ids.dart';

/// Handles sending and receiving encrypted messages, and persisting them.
class MessageRepository {
  final KalisiDb _db;
  final ApiClient _api;
  /// Called when the other side signals they're typing.
  final void Function(String contactId)? onTyping;
  /// Called for call signalling (offer / answer / ice / end).
  final void Function(Contact from, String kind, Map<String, dynamic> data)?
      onCallSignal;
  MessageRepository(this._db, this._api, {this.onTyping, this.onCallSignal});

  /// Send a text message to a contact.
  /// 1. store locally (status: sending), 2. encrypt, 3. POST to server,
  /// 4. update status to sent/failed.
  Future<void> sendText({
    required Persona me,
    required Contact contact,
    required String text,
    Message? replyTo,
    String? replyToWho,
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
      replyToId: Value(replyTo?.id),
      replyToText: Value(replyTo == null
          ? null
          : switch (replyTo.kind) {
              'img' => '📷 Photo',
              'voice' => '🎤 Voice message',
              _ => replyTo.body,
            }),
      replyToWho: Value(replyTo == null ? null : replyToWho),
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
      'replyTo': replyTo == null
          ? null
          : {
              'id': replyTo.id,
              'who': replyToWho,
              'text': switch (replyTo.kind) {
                'img' => '📷 Photo',
                'voice' => '🎤 Voice message',
                _ => replyTo.body,
              },
            },
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
      // Offline or the server is unreachable — keep the encrypted envelope
      // and let the queue deliver it when the connection is back.
      if (_isNetworkIssue(e)) {
        await _db.markQueued(
          cid,
          jsonEncode({'to': contact.kalId, 'obj': obj}),
        );
        return;
      }
      await _db.updateMessageStatus(cid, 'failed');
      rethrow;
    }
  }

  /// Anything that looks like a connectivity problem rather than a rejection.
  bool _isNetworkIssue(Object e) {
    if (e is ApiException) {
      return e.error == 'network_error' || e.error == 'timeout';
    }
    return true; // dio/socket errors land here too
  }

  /// Try to deliver anything waiting in the queue. Called by the poller.
  Future<int> flushQueue(Persona me) async {
    final queued = await _db.queuedMessages(me.id);
    if (queued.isEmpty) return 0;
    var sent = 0;
    for (final m in queued) {
      final env = m.pendingEnvelope;
      if (env == null) continue;
      // give up after a lot of tries so it can't retry forever
      if (m.sendAttempts >= 50) {
        await _db.updateMessageStatus(m.id, 'failed');
        continue;
      }
      try {
        final data = jsonDecode(env) as Map<String, dynamic>;
        final to = data['to']?.toString();
        final obj = (data['obj'] as Map).cast<String, dynamic>();
        final contact = await _db.contactById(m.contactId);
        if (to == null || contact?.publicJwk == null) continue;

        final enc = await KalisiCrypto.encryptObject(
            obj, me.privateJwk, contact!.publicJwk!);
        await _api.send(
          kalId: me.kalId,
          token: me.token,
          to: to,
          clientId: m.id,
          iv: enc.iv,
          blob: enc.blob,
        );
        await _db.markSent(m.id);
        sent++;
      } catch (_) {
        await _db.bumpAttempts(m.id, m.sendAttempts + 1);
        // stop on the first failure — still offline, try again next tick
        break;
      }
    }
    return sent;
  }

  /// Send a media message (photo or voice) to a contact.
  /// [kind] is 'img' or 'voice'. [dataUrl] is a base64 data URL
  /// (image) or base64 audio. [localPath] is stored for local display.
  Future<void> sendMedia({
    required Persona me,
    required Contact contact,
    required String kind, // 'img' | 'voice' | 'file'
    required String dataUrl,
    String? localPath,
    String? caption,
    String? fileName,
    int? fileSize,
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
      // keep the payload for both photo and voice so it can be replayed
      body: Value(dataUrl),
      mediaPath: Value(localPath),
      caption: Value(caption),
      fileName: Value(fileName),
      fileSize: Value(fileSize),
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
      'file': kind == 'file' ? dataUrl : null,
      'wave': waveform,
      'dur': durationSec,
      'caption': caption,
      'fileName': fileName,
      'fileSize': fileSize,
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

  /// React to a message with an emoji: store locally and notify the sender.
  Future<void> reactTo(Persona me, Message message, String emoji) async {
    await _db.setMyReaction(message.id, emoji);

    final contact = await _db.contactById(message.contactId);
    if (contact?.publicJwk == null) return;

    final obj = <String, dynamic>{
      'kind': 'react',
      'id': message.id,
      'emoji': emoji,
      'cid': newUuid(),
      'ts': nowMs(),
    };
    try {
      final enc = await KalisiCrypto.encryptObject(
          obj, me.privateJwk, contact!.publicJwk!);
      await _api.send(
        kalId: me.kalId,
        token: me.token,
        to: contact.kalId,
        clientId: obj['cid'] as String,
        iv: enc.iv,
        blob: enc.blob,
      );
    } catch (_) {}
  }

  /// Change a message I already sent, and tell the other side.
  Future<void> editText(Persona me, Message message, String text) async {
    await _db.editMessage(message.id, text);
    final contact = await _db.contactById(message.contactId);
    if (contact?.publicJwk == null) return;
    final obj = <String, dynamic>{
      'kind': 'edit',
      'id': message.id,
      'text': text,
      'cid': newUuid(),
      'ts': nowMs(),
    };
    try {
      final enc = await KalisiCrypto.encryptObject(
          obj, me.privateJwk, contact!.publicJwk!);
      await _api.send(
        kalId: me.kalId,
        token: me.token,
        to: contact.kalId,
        clientId: obj['cid'] as String,
        iv: enc.iv,
        blob: enc.blob,
      );
    } catch (_) {}
  }

  /// Delete one of my messages here and ask the other side to remove it too.
  Future<void> deleteForEveryone(Persona me, Message message) async {
    await _db.deleteMessageById(message.id);
    final contact = await _db.contactById(message.contactId);
    if (contact?.publicJwk == null) return;
    final obj = <String, dynamic>{
      'kind': 'delete',
      'id': message.id,
      'cid': newUuid(),
      'ts': nowMs(),
    };
    try {
      final enc = await KalisiCrypto.encryptObject(
          obj, me.privateJwk, contact!.publicJwk!);
      await _api.send(
        kalId: me.kalId,
        token: me.token,
        to: contact.kalId,
        clientId: obj['cid'] as String,
        iv: enc.iv,
        blob: enc.blob,
      );
    } catch (_) {}
  }

  /// Create a group, then hand the shared key to each member over their
  /// own encrypted 1:1 channel (the server fans out one blob to everyone,
  /// so the group must share a single key).
  Future<Contact> createGroup({
    required Persona me,
    required String name,
    required List<Contact> members,
  }) async {
    final res = await _api.groupCreate(
      kalId: me.kalId,
      token: me.token,
      name: name,
      members: members.map((c) => c.kalId).toList(),
    );
    final gid = res['gid']?.toString();
    if (gid == null) throw ApiException('group_failed');
    final memberIds = ((res['members'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();

    final key = KalisiCrypto.newGroupKey();

    // store the group locally
    final localId = newUuid();
    await _db.upsertContact(ContactsCompanion(
      id: Value(localId),
      personaId: Value(me.id),
      kalId: Value(gid),
      name: Value(name),
      isGroup: const Value(true),
      groupKey: Value(key),
      groupMembers: Value(jsonEncode(memberIds)),
      verified: const Value(true),
      createdAt: Value(nowMs()),
    ));

    // give every member the key
    for (final m in members) {
      if (m.publicJwk == null) continue;
      final obj = <String, dynamic>{
        'kind': 'gkey',
        'gid': gid,
        'name': name,
        'key': key,
        'members': memberIds,
        'cid': newUuid(),
        'ts': nowMs(),
      };
      try {
        final enc = await KalisiCrypto.encryptObject(
            obj, me.privateJwk, m.publicJwk!);
        await _api.send(
          kalId: me.kalId,
          token: me.token,
          to: m.kalId,
          clientId: obj['cid'] as String,
          iv: enc.iv,
          blob: enc.blob,
        );
      } catch (_) {}
    }

    return (await _db.contactById(localId))!;
  }

  /// Hand a group's shared key to one member over their 1:1 channel.
  Future<void> shareGroupKey({
    required Persona me,
    required Contact to,
    required String gid,
    required String name,
    required String key,
    required List<String> members,
  }) async {
    if (to.publicJwk == null) return;
    final obj = <String, dynamic>{
      'kind': 'gkey',
      'gid': gid,
      'name': name,
      'key': key,
      'members': members,
      'cid': newUuid(),
      'ts': nowMs(),
    };
    final enc =
        await KalisiCrypto.encryptObject(obj, me.privateJwk, to.publicJwk!);
    await _api.send(
      kalId: me.kalId,
      token: me.token,
      to: to.kalId,
      clientId: obj['cid'] as String,
      iv: enc.iv,
      blob: enc.blob,
    );
  }

  /// Ask a contact to re-send group keys, at most once a minute, so a member
  /// who was offline during a key change recovers without doing anything.
  final Map<String, int> _keyAsks = {};
  Future<void> _maybeRequestGroupKey(Persona me, Contact from) async {
    final last = _keyAsks[from.kalId] ?? 0;
    final now = nowMs();
    if (now - last < 60000) return;
    _keyAsks[from.kalId] = now;

    final obj = <String, dynamic>{
      'kind': 'gkey-request',
      'cid': newUuid(),
      'ts': now,
    };
    try {
      final enc = await KalisiCrypto.encryptObject(
          obj, me.privateJwk, from.publicJwk!);
      await _api.send(
        kalId: me.kalId,
        token: me.token,
        to: from.kalId,
        clientId: obj['cid'] as String,
        iv: enc.iv,
        blob: enc.blob,
      );
    } catch (_) {}
  }

  /// Replace a group's key and hand the new one to everyone still in it.
  ///
  /// Called after removing someone: they keep the old key, but it stops being
  /// used, so they can't read anything sent from now on.
  Future<String> rotateGroupKey({
    required Persona me,
    required Contact group,
    required List<String> members,
  }) async {
    final newKey = KalisiCrypto.newGroupKey();

    // store it locally first, so our own sends use it immediately
    await _db.setGroupKey(group.id, newKey);

    final db = _db;
    for (final kid in members) {
      if (kid == me.kalId) continue;
      final c = await db.contactByKalId(me.id, kid);
      if (c == null || c.publicJwk == null) continue;
      try {
        await shareGroupKey(
          me: me,
          to: c,
          gid: group.kalId,
          name: group.name,
          key: newKey,
          members: members,
        );
      } catch (_) {
        // a member we couldn't reach will pick the key up when they're next
        // online and someone re-shares; the group still works for the rest
      }
    }
    return newKey;
  }

  /// Send a message to a group using its shared key.
  Future<void> sendGroupText({
    required Persona me,
    required Contact group,
    required String text,
  }) async {
    final key = group.groupKey;
    if (key == null) throw ApiException('no_group_key');
    final cid = newUuid();
    final ts = nowMs();

    await _db.insertMessage(MessagesCompanion.insert(
      id: cid,
      contactId: group.id,
      personaId: me.id,
      fromMe: 'me',
      kind: const Value('text'),
      body: Value(text),
      ts: ts,
      status: const Value('sending'),
    ));

    final obj = <String, dynamic>{
      'kind': 'text',
      'gid': group.kalId,
      'text': text,
      'from': me.kalId,
      'fromName': me.name,
      'cid': cid,
      'ts': ts,
    };
    try {
      final enc = KalisiCrypto.encryptWithKeySync(obj, key);
      await _api.groupSend(
        kalId: me.kalId,
        token: me.token,
        gid: group.kalId,
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

  /// Tell a contact we're typing (fire-and-forget, throttled by the caller).
  Future<void> sendTyping(Persona me, Contact contact) async {
    if (contact.publicJwk == null) return;
    final obj = <String, dynamic>{
      'kind': 'typing',
      'cid': newUuid(),
      'ts': nowMs(),
    };
    try {
      final enc = await KalisiCrypto.encryptObject(
          obj, me.privateJwk, contact.publicJwk!);
      await _api.send(
        kalId: me.kalId,
        token: me.token,
        to: contact.kalId,
        clientId: obj['cid'] as String,
        iv: enc.iv,
        blob: enc.blob,
      );
    } catch (_) {}
  }

  /// Tell the sender their disappearing message has been burned.
  Future<void> notifyBurned(Persona me, Message message) async {
    final contact = await _db.contactById(message.contactId);
    if (contact?.publicJwk == null) return;
    final obj = <String, dynamic>{
      'kind': 'burned',
      'id': message.id,
      'cid': newUuid(),
      'ts': nowMs(),
    };
    try {
      final enc = await KalisiCrypto.encryptObject(
          obj, me.privateJwk, contact!.publicJwk!);
      await _api.send(
        kalId: me.kalId,
        token: me.token,
        to: contact.kalId,
        clientId: obj['cid'] as String,
        iv: enc.iv,
        blob: enc.blob,
      );
    } catch (_) {}
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
        Map<String, dynamic>? obj;
        Contact? groupOf;

        // Normal 1:1 message, encrypted for me alone.
        try {
          obj = await KalisiCrypto.decryptObject(
            iv,
            blob,
            me.privateJwk,
            contact.publicJwk!,
          );
        } catch (_) {
          // Not for me pairwise — it may be a group message, which is
          // encrypted once with the group's shared key and fanned out.
          for (final g in await _db.groupsFor(me.id)) {
            final key = g.groupKey;
            if (key == null) continue;
            try {
              obj = KalisiCrypto.decryptWithKeySync(iv, blob, key);
              groupOf = g;
              break;
            } catch (_) {}
          }
          // Nothing matched: the group key may have been rotated while we
          // were offline. Ask the sender to re-send it (at most occasionally).
          if (obj == null && contact.publicJwk != null) {
            await _maybeRequestGroupKey(me, contact);
          }
        }
        if (obj == null) continue;

        // Group messages are stored against the group, not the sender.
        if (groupOf != null) {
          final gkind = obj['kind']?.toString() ?? 'text';
          if (gkind != 'text' && gkind != 'img' && gkind != 'voice') continue;
          final gbody = gkind == 'img'
              ? obj['img']?.toString()
              : (gkind == 'voice'
                  ? obj['audio']?.toString()
                  : obj['text']?.toString());
          if (gbody == null || gbody.trim().isEmpty) continue;
          final who = obj['fromName']?.toString() ?? contact.name;
          await _db.insertMessage(MessagesCompanion.insert(
            id: obj['cid']?.toString() ?? newUuid(),
            contactId: groupOf.id,
            personaId: me.id,
            fromMe: 'them',
            kind: Value(gkind),
            body: Value(gbody),
            replyToWho: Value(who),   // shows who spoke in the group
            ts: (obj['ts'] is int) ? obj['ts'] as int : ts,
            status: const Value('delivered'),
          ));
          received++;
          continue;
        }

        final cid = obj['cid']?.toString() ?? newUuid();
        final kind = obj['kind']?.toString() ?? 'text';

        // Control messages are not chat bubbles — apply effect and skip storing.
        if (kind == 'read' || kind == 'seen') {
          final ids = (obj['ids'] as List?) ?? const [];
          for (final id in ids) {
            await _db.updateMessageStatus(id.toString(), 'read');
          }
          continue;
        }
        if (kind == 'burned') {
          final bid = obj['id']?.toString();
          if (bid != null) await _db.markBurned(bid);
          continue;
        }
        if (kind == 'react' || kind == 'reaction') {
          // web sends {kind:'react', id, emoji}; app earlier used 'target'
          final targetId = (obj['id'] ?? obj['target'])?.toString();
          final emoji = obj['emoji']?.toString();
          if (targetId != null) {
            await _db.setReaction(targetId, (emoji == null || emoji.isEmpty) ? null : emoji);
          }
          continue;
        }
        if (kind == 'edit') {
          final eid = obj['id']?.toString();
          final txt = obj['text']?.toString();
          if (eid != null && txt != null) {
            await _db.editMessage(eid, txt);
          }
          continue;
        }
        if (kind == 'delete') {
          final did = obj['id']?.toString();
          if (did != null) await _db.deleteMessageById(did);
          continue;
        }
        // call setup — hand straight to the call service
        if (kind == 'call-offer' ||
            kind == 'call-answer' ||
            kind == 'call-ice' ||
            kind == 'call-end') {
          onCallSignal?.call(contact, kind, obj);
          continue;
        }

        // someone added me to a group and shared its key
        if (kind == 'gkey') {
          final gid = obj['gid']?.toString();
          final gkey = obj['key']?.toString();
          if (gid != null && gkey != null) {
            final existing = await _db.contactByKalId(me.id, gid);
            await _db.upsertContact(ContactsCompanion(
              id: Value(existing?.id ?? newUuid()),
              personaId: Value(me.id),
              kalId: Value(gid),
              name: Value(obj['name']?.toString() ?? 'Group'),
              isGroup: const Value(true),
              groupKey: Value(gkey),
              groupMembers: Value(jsonEncode(obj['members'] ?? const [])),
              verified: const Value(true),
              createdAt: Value(existing?.createdAt ?? nowMs()),
            ));
          }
          continue;
        }
        // They couldn't read a group message — re-send the keys they need.
        if (kind == 'gkey-request') {
          for (final g in await _db.groupsFor(me.id)) {
            final key = g.groupKey;
            if (key == null) continue;
            List<String> mem = const [];
            try {
              mem = ((jsonDecode(g.groupMembers ?? '[]') as List))
                  .map((e) => '$e')
                  .toList();
            } catch (_) {}
            if (!mem.contains(contact.kalId)) continue;
            try {
              await shareGroupKey(
                me: me,
                to: contact,
                gid: g.kalId,
                name: g.name,
                key: key,
                members: mem,
              );
            } catch (_) {}
          }
          continue;
        }
        if (kind == 'typing') {
          onTyping?.call(contact.id);
          continue;
        }
        if (kind == 'delivered' || kind == 'ctl') {
          continue;
        }
        // Any non-content kind we don't recognise: skip (never show empty bubbles).
        if (kind != 'text' && kind != 'img' && kind != 'voice' &&
            kind != 'file') {
          continue;
        }

        // For media, keep the payload in body so the UI can render it.
        String? body;
        if (kind == 'img') {
          body = obj['img']?.toString();
        } else if (kind == 'voice' || kind == 'file') {
          body = (obj['audio'] ?? obj['file'])?.toString();
        } else {
          body = obj['text']?.toString();
        }
        // Guard: never store an empty text/media bubble.
        if (body == null || body.trim().isEmpty) {
          continue;
        }
        final rep = obj['replyTo'];
        await _db.insertMessage(MessagesCompanion.insert(
          id: cid,
          contactId: contact.id,
          personaId: me.id,
          fromMe: 'them',
          kind: Value(kind),
          body: Value(body),
          caption: Value(obj['caption']?.toString()),
          fileName: Value(obj['fileName']?.toString()),
          fileSize: Value((obj['fileSize'] as num?)?.toInt()),
          replyToId: Value(rep is Map ? rep['id']?.toString() : null),
          replyToText: Value(rep is Map ? rep['text']?.toString() : null),
          replyToWho: Value(rep is Map ? rep['who']?.toString() : null),
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
