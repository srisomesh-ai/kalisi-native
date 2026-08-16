import 'dart:convert';
import 'package:drift/drift.dart';
import '../db/database.dart';
import '../api/api_client.dart';
import '../crypto/kalisi_crypto.dart';
import '../../util/ids.dart';

class AuthRepository {
  final KalisiDb _db;
  final ApiClient _api;
  AuthRepository(this._db, this._api);

  /// Create a brand-new identity: generate keys, register with the server,
  /// store the persona locally, mark it active.
  ///
  /// Returns the created [Persona]. Throws [ApiException] on failure.
  /// Sign back in on a new phone with a username and password.
  Future<Persona> recover({
    required String username,
    required String password,
  }) async {
    final saltRes = await _api.recoverSalt(username: username);
    final salt = saltRes['salt']?.toString();
    if (salt == null || salt.isEmpty) throw ApiException('no_recovery');

    final keys = KalisiCrypto.keyPairFromPassword(username, password, salt);
    final verifier = KalisiCrypto.verifierFor(username, password, salt);

    final res = await _api.recoverLogin(
      username: username,
      verifier: verifier,
      pubkey: jsonDecode(keys.publicJwk) as Map<String, dynamic>,
    );

    final kalId = res['kal_id']?.toString() ?? '';
    final token = res['token']?.toString() ?? '';
    final name = res['name']?.toString() ?? username;
    final id = newUuid();

    await _db.upsertPersona(PersonasCompanion.insert(
      id: id,
      kalId: kalId,
      username: username,
      name: name,
      token: token,
      privateJwk: keys.privateJwk,
      publicJwk: keys.publicJwk,
      createdAt: nowMs(),
      active: const Value(true),
    ));
    await _db.setActivePersona(id);
    return (await _db.activePersona())!;
  }

  Future<Persona> createIdentity({
    required String name,
    required String username,
    String? password,
  }) async {
    // With a password the key is derived from it, so the account can be
    // recovered on another phone. Without one, the key is random and lives
    // only here.
    String? salt;
    String? verifier;
    final keys = password == null || password.isEmpty
        ? await KalisiCrypto.generateKeyPair()
        : () {
            salt = KalisiCrypto.newSalt();
            verifier = KalisiCrypto.verifierFor(username, password, salt!);
            return KalisiCrypto.keyPairFromPassword(username, password, salt!);
          }();

    final res = await _api.register(
      name: name,
      username: username,
      pubkey: keys.publicJwk,
      verifier: verifier,
      salt: salt,
    );

    final kalId = res['kal_id']?.toString() ?? '';
    final token = res['token']?.toString() ?? '';
    final id = newUuid();

    final companion = PersonasCompanion.insert(
      id: id,
      kalId: kalId,
      username: username,
      name: name,
      token: token,
      privateJwk: keys.privateJwk,
      publicJwk: keys.publicJwk,
      createdAt: nowMs(),
      active: const Value(true),
    );

    // Deactivate others, then insert active.
    await (_db.update(_db.personas))
        .write(const PersonasCompanion(active: Value(false)));
    await _db.upsertPersona(companion);

    return (await _db.activePersona())!;
  }

  /// Check if a username is available (server-side).
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final res = await _api.checkUsername(username);
      return res['available'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Persona>> personas() => _db.allPersonas();
  Future<void> switchPersona(String id) => _db.setActivePersona(id);
}
