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
  }) =>
      call('register', {
        'name': name,
        'username': username,
        // Server expects pubkey as an OBJECT (is_array check), so decode the JWK string.
        'pubkey': jsonDecode(pubkey),
      });

  Future<Map<String, dynamic>> lookup(String username) =>
      call('lookup', {'username': username});

  Future<Map<String, dynamic>> checkUsername(String username) =>
      call('check', {'username': username});

  Future<Map<String, dynamic>> send({
    required String kalId,
    required String token,
    required String to,
    required String clientId,
    required String iv,
    required String blob,
  }) =>
      call('send', {
        'kal_id': kalId,
        'token': token,
        'to': to,
        'client_id': clientId,
        'iv': iv,
        'blob': blob,
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
      call('presence', {'kal_id': kalId, 'token': token, 'kal': targetKalId});

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
}
