import 'dart:convert';
import 'package:drift/drift.dart';
import '../db/database.dart';
import '../api/api_client.dart';
import '../../util/ids.dart';

/// Handles finding people and managing contact requests.
class ContactsRepository {
  final KalisiDb _db;
  final ApiClient _api;
  ContactsRepository(this._db, this._api);

  /// Look up a user by @username or KAL-id. Returns their server record.
  Future<LookupResult> lookup(String handle) async {
    final res = await _api.lookup(handle.replaceAll('@', '').trim());
    final u = res['user'] as Map?;
    if (u == null) throw ApiException('not_found');
    return LookupResult(
      kalId: u['kal_id'].toString(),
      username: u['username']?.toString(),
      name: u['name']?.toString() ?? u['username']?.toString() ?? 'Unknown',
      // Server returns pubkey as a decoded object → re-encode to store as JWK string.
      publicJwk: u['pubkey'] == null ? null : _jsonString(u['pubkey']),
      avatar: u['avatar']?.toString(),
    );
  }

  /// Send a contact request to a user (by their KAL-id).
  Future<String> sendRequest(Persona me, String toKalId) async {
    final res = await _api.reqSend(
      kalId: me.kalId,
      token: me.token,
      to: toKalId,
    );
    // Server may auto-accept if they already requested us.
    if (res['auto_accepted'] == true || res['already'] == 'accepted') {
      return 'accepted';
    }
    return 'pending';
  }

  /// Add someone as a contact locally (after lookup/accept).
  Future<Contact> addContact(
    Persona me, {
    required String kalId,
    String? username,
    required String name,
    String? publicJwk,
    String? avatar,
    bool verified = false,
  }) async {
    final existing = await _db.contactByKalId(me.id, kalId);
    final id = existing?.id ?? newUuid();
    await _db.upsertContact(ContactsCompanion(
      id: Value(id),
      personaId: Value(me.id),
      kalId: Value(kalId),
      username: Value(username),
      name: Value(name),
      publicJwk: Value(publicJwk),
      avatar: avatar == null ? const Value.absent() : Value(avatar),
      verified: Value(verified),
      createdAt: Value(existing?.createdAt ?? nowMs()),
    ));
    return (await _db.contactById(id))!;
  }

  /// Full "add a friend by @username" flow: look them up, send a request,
  /// and store them locally so a chat thread appears.
  Future<Contact> addFriend(Persona me, String handle) async {
    final found = await lookup(handle);
    if (found.kalId == me.kalId) {
      throw ApiException('thats_you');
    }
    final status = await sendRequest(me, found.kalId);
    final contact = await addContact(
      me,
      kalId: found.kalId,
      username: found.username,
      name: found.name,
      publicJwk: found.publicJwk,
      avatar: found.avatar,
      verified: status == 'accepted',
    );
    return contact;
  }

  /// Pending incoming requests from the server.
  Future<List<IncomingRequest>> incomingRequests(Persona me) async {
    final res = await _api.reqList(kalId: me.kalId, token: me.token);
    final list = (res['requests'] as List?) ?? const [];
    return list.map((r) {
      final m = r as Map;
      return IncomingRequest(
        fromKalId: m['from_id'].toString(),
        username: m['username']?.toString(),
        name: m['name']?.toString() ?? m['username']?.toString() ?? 'Unknown',
      );
    }).toList();
  }

  /// Refresh which contacts are accepted, so a chat unlocks as soon as the
  /// other person accepts (and stays locked until then).
  Future<void> syncState(Persona me) async {
    final res = await _api.contactsState(kalId: me.kalId, token: me.token);
    final accepted = ((res['accepted'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    final pendingOut = ((res['pending_out'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();

    final mine = await _db.contactsFor(me.id);
    for (final c in mine) {
      final isAccepted = accepted.contains(c.kalId);
      final isPending = pendingOut.contains(c.kalId);
      if (c.verified != isAccepted || c.pending != isPending) {
        await _db.setContactState(c.id,
            verified: isAccepted, pending: isPending);
      }
    }
  }

  /// Pull contacts' current display name and photo so profile changes show up.
  Future<void> syncProfiles(Persona me) async {
    final mine = await _db.contactsFor(me.id);
    if (mine.isEmpty) return;
    final res = await _api.contactsProfiles(
      kalId: me.kalId,
      token: me.token,
      ids: mine.map((c) => c.kalId).toList(),
    );
    final users = (res['users'] as List?) ?? const [];
    final byId = <String, Map>{};
    for (final u in users) {
      if (u is Map && u['kal_id'] != null) byId[u['kal_id'].toString()] = u;
    }
    for (final c in mine) {
      final u = byId[c.kalId];
      if (u == null) continue;
      final name = u['name']?.toString() ??
          u['username']?.toString() ??
          c.name;
      final avatar = u['avatar']?.toString();
      final avatarChanged = (avatar ?? '') != (c.avatar ?? '');
      if (name != c.name || avatarChanged) {
        await _db.setContactProfile(c.id, name: name, avatar: avatar ?? '');
      }
    }
  }

  /// Accept or reject an incoming request. On accept, store them as a contact.
  Future<void> actOnRequest(
    Persona me,
    IncomingRequest req,
    bool accept,
  ) async {
    await _api.reqAct(
      kalId: me.kalId,
      token: me.token,
      from: req.fromKalId,
      action: accept ? 'accept' : 'reject',
    );
    if (accept) {
      // Look them up to get their public key, then store.
      String? pubJwk;
      String name = req.name;
      String? username = req.username;
      try {
        final found = await lookup(req.username ?? req.fromKalId);
        pubJwk = found.publicJwk;
        name = found.name;
        username = found.username;
      } catch (_) {}
      await addContact(
        me,
        kalId: req.fromKalId,
        username: username,
        name: name,
        publicJwk: pubJwk,
        verified: true,
      );
    }
  }

  static String _jsonString(Object o) => jsonEncode(o);
}

// ---- models ----
class LookupResult {
  final String kalId;
  final String? username;
  final String name;
  final String? publicJwk;
  final String? avatar;
  LookupResult({
    required this.kalId,
    this.username,
    required this.name,
    this.publicJwk,
    this.avatar,
  });
}

class IncomingRequest {
  final String fromKalId;
  final String? username;
  final String name;
  IncomingRequest({
    required this.fromKalId,
    this.username,
    required this.name,
  });
}
