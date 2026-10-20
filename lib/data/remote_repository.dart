import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiError implements Exception {
  const ApiError(this.message, this.code, this.status);
  final String message, code;
  final int status;
  @override
  String toString() => message;
}

/// Sessions/payments live on the server. Client clocks/amounts are never sent.
class RemoteRepository {
  RemoteRepository(this.baseUrl, {http.Client? client})
    : client = client ?? http.Client();
  final String baseUrl;
  final http.Client client;
  Future<Json> request(
    String method,
    String path, {
    Json? body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final response =
          await (method == 'GET'
                  ? client.get(uri, headers: headers)
                  : client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(body ?? {}),
                    ))
              .timeout(const Duration(seconds: 8));
      final result = jsonDecode(response.body) as Json;
      if (response.statusCode >= 400) {
        throw ApiError(
          result['error'] as String? ?? 'Permintaan ditolak.',
          result['code'] as String? ?? 'server',
          response.statusCode,
        );
      }
      return result;
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(
        'Server tidak terjangkau. Data mungkin belum terbaru; periksa koneksi.',
        'offline',
        0,
      );
    }
  }

  void close() => client.close();
}
