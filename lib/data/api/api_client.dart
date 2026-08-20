import 'dart:convert';
import 'package:dio/dio.dart';

/// Talks to the existing Kalisi PHP relay API.
/// Every call POSTs {action, ...body} and expects {ok: bool, ...}.
class ApiException implements Exception {
  final String error;
  final Map<String, dynamic> data;
  ApiException(this.error, [this.data = const {}]);
  @override
  String toString() => 'ApiException($error)';
}

class ApiClient {
  static const base = 'https://kalisi.app/api/index.php';

  final Dio _dio;

  ApiClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
          headers: {'Content-Type': 'application/json'},
        ));

  /// Core call. Throws [ApiException] on {ok:false}, or on network failure.
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    try {
      final res = await _dio.post(base, data: {'action': action, ...body});
      var data = res.data;
      // dio may hand back a String if the server's content-type isn't application/json.
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          throw ApiException('bad_response', {'raw': data.toString()});
        }
      }
      final map = data is Map
          ? data.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{'ok': false, 'error': 'bad_response'};
      if (map['ok'] == true) return map;
      throw ApiException(map['error']?.toString() ?? 'api_error', map);
    } on DioException catch (e) {
      throw ApiException('network_error', {'detail': e.message});
    }
  }

  // ---- Typed convenience wrappers ----

  Future<Map<String, dynamic>> register({
    required String name,
    required String username,
    required String pubkey, // JSON string of the public JWK
    String? verifier,       // optional password recovery
    String? salt,
  }) =>
      call('register', {
        'name': name,
        'username': username,
        if (verifier != null) 'verifier': verifier,
        if (salt != null) 'salt': salt,
        // Server expects pubkey as an OBJECT (is_array check), so decode the JWK string.
        'pubkey': jsonDecode(pubkey),
      });

  Future<Map<String, dynamic>> lookup(String handle) =>
      call('lookup', {'handle': handle});

  Future<Map<String, dynamic>> checkUsername(String username) =>
      call('check', {'username': username});

  Future<Map<String, dynamic>> send({
    required String kalId,
    required String token,
    required String to,
    required String clientId,
    required String iv,
    required String blob,
    String? push,   // 'message' | 'call-offer' | 'call' — the payload is
                    // encrypted, so the server needs telling
  }) =>
      call('send', {
        'kal_id': kalId,
        'token': token,
        'to': to,
        'client_id': clientId,
        'iv': iv,
        'blob': blob,
        if (push != null) 'push': push,
      });

  Future<Map<String, dynamic>> fetch({
    required String kalId,
    required String token,
  }) =>
      call('fetch', {'kal_id': kalId, 'token': token});

  Future<Map<String, dynamic>> presence({
    required String kalId,
    required String token,
    required String targetKalId,
  }) =>
      // Server reads last_seen of the kal_id in the body (the target).
      call('presence', {'kal_id': targetKalId, 'token': token});

  Future<Map<String, dynamic>> reqSend({
    required String kalId,
    required String token,
    required String to,
  }) =>
      call('req_send', {'kal_id': kalId, 'token': token, 'to': to});

  Future<Map<String, dynamic>> reqList({
    required String kalId,
    required String token,
  }) =>
      call('req_list', {'kal_id': kalId, 'token': token});

  Future<Map<String, dynamic>> reqAct({
    required String kalId,
    required String token,
    required String from,
    required String action, // 'accept' | 'reject'
  }) =>
      call('req_act', {
        'kal_id': kalId,
        'token': token,
        'from': from,
        'act': action,
      });

  Future<Map<String, dynamic>> fcmRegister({
    required String kalId,
    required String token,
    required String fcmToken,
  }) =>
      call('fcm_register', {
        'kal_id': kalId,
        'token': token,
        'fcm_token': fcmToken,
      });

  Future<Map<String, dynamic>> changeUsername({
    required String kalId,
    required String token,
    required String username,
  }) =>
      call('change_username', {
        'kal_id': kalId,
        'token': token,
        'username': username,
      });

  /// Which of my contacts are accepted vs still pending my request.
  Future<Map<String, dynamic>> contactsState({
    required String kalId,
    required String token,
  }) =>
      call('contacts_state', {'kal_id': kalId, 'token': token});

  /// Create a group on the server.
  Future<Map<String, dynamic>> groupCreate({
    required String kalId,
    required String token,
    required String name,
    required List<String> members,
  }) =>
      call('group_create', {
        'kal_id': kalId,
        'token': token,
        'name': name,
        'members': members,
      });

  /// Fan a group message out to every member.
  Future<Map<String, dynamic>> groupSend({
    required String kalId,
    required String token,
    required String gid,
    required String clientId,
    required String iv,
    required String blob,
  }) =>
      call('group_send', {
        'kal_id': kalId,
        'token': token,
        'gid': gid,
        'client_id': clientId,
        'iv': iv,
        'blob': blob,
      });

  /// Add/remove members, rename, or leave a group.
  Future<Map<String, dynamic>> groupUpdate({
    required String kalId,
    required String token,
    required String gid,
    required String act, // add | remove | rename | leave
    List<String>? members,
    String? member,
    String? name,
  }) =>
      call('group_update', {
        'kal_id': kalId,
        'token': token,
        'gid': gid,
        'act': act,
        if (members != null) 'members': members,
        if (member != null) 'member': member,
        if (name != null) 'name': name,
      });

  Future<Map<String, dynamic>> groupInfo({
    required String kalId,
    required String token,
    required String gid,
  }) =>
      call('group_info', {'kal_id': kalId, 'token': token, 'gid': gid});

  /// Why isn't push working? Reports each step of the chain.
  Future<Map<String, dynamic>> pushCheck({
    required String kalId,
    required String token,
  }) =>
      call('push_check', {'kal_id': kalId, 'token': token});

  /// Send a test notification to this device.
  Future<Map<String, dynamic>> pushTest({
    required String kalId,
    required String token,
  }) =>
      call('push_test', {'kal_id': kalId, 'token': token});

  /// Ask for the salt tied to a username, so the key can be rebuilt.
  Future<Map<String, dynamic>> recoverSalt({required String username}) =>
      call('recover_salt', {'username': username});

  /// Sign in on a new phone with the derived verifier.
  Future<Map<String, dynamic>> recoverLogin({
    required String username,
    required String verifier,
    required Map<String, dynamic> pubkey,
  }) =>
      call('recover_login', {
        'username': username,
        'verifier': verifier,
        'pubkey': pubkey,
      });

  /// Current name/photo for a list of contacts.
  Future<Map<String, dynamic>> contactsProfiles({
    required String kalId,
    required String token,
    required List<String> ids,
  }) =>
      call('contacts_profiles', {
        'kal_id': kalId,
        'token': token,
        'ids': ids,
      });

  /// Update display name / avatar so contacts see them.
  Future<Map<String, dynamic>> profileUpdate({
    required String kalId,
    required String token,
    String? name,
    String? avatar,
  }) =>
      call('profile_update', {
        'kal_id': kalId,
        'token': token,
        if (name != null) 'name': name,
        if (avatar != null) 'avatar': avatar,
      });

  Future<Map<String, dynamic>> statusPost({
    required String kalId,
    required String token,
    required String type, // text|photo|voice
    required String payload,
    bool allowShare = false,
  }) =>
      call('status_post', {
        'kal_id': kalId,
        'token': token,
        'type': type,
        'payload': payload,
        'allow_share': allowShare,
      });

  /// Delete one of my own statuses.
  Future<Map<String, dynamic>> statusDelete({
    required String kalId,
    required String token,
    required int statusId,
  }) =>
      call('status_delete', {
        'kal_id': kalId,
        'token': token,
        'status_id': statusId,
      });

  /// Mark a status as viewed.
  Future<Map<String, dynamic>> statusView({
    required String kalId,
    required String token,
    required int statusId,
  }) =>
      call('status_view', {
        'kal_id': kalId,
        'token': token,
        'status_id': statusId,
      });

  /// Who viewed my status (owner only).
  Future<Map<String, dynamic>> statusViewers({
    required String kalId,
    required String token,
    required int statusId,
  }) =>
      call('status_viewers', {
        'kal_id': kalId,
        'token': token,
        'status_id': statusId,
      });

  /// React to a status (same emoji again clears it).
  Future<Map<String, dynamic>> statusReact({
    required String kalId,
    required String token,
    required int statusId,
    required String emoji,
  }) =>
      call('status_react', {
        'kal_id': kalId,
        'token': token,
        'status_id': statusId,
        'emoji': emoji,
      });

  /// Reactions on a status.
  Future<Map<String, dynamic>> statusReactions({
    required String kalId,
    required String token,
    required int statusId,
  }) =>
      call('status_reactions', {
        'kal_id': kalId,
        'token': token,
        'status_id': statusId,
      });

  Future<Map<String, dynamic>> statusFeed({
    required String kalId,
    required String token,
    required List<String> contacts,
  }) =>
      call('status_feed', {
        'kal_id': kalId,
        'token': token,
        'contacts': contacts,
      });
}
