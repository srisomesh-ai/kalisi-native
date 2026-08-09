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
  Future<Persona> createIdentity({
    required String name,
    required String username,
  }) async {
    final keys = await KalisiCrypto.generateKeyPair();
    final res = await _api.register(
      name: name,
      username: username,
      pubkey: keys.publicJwk,
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
