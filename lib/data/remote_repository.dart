import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logic/request_metrics.dart';

typedef Json = Map<String, dynamic>;

class ApiError implements Exception {
  const ApiError(this.message, this.code, this.status);
  final String message, code;
  final int status;
  bool get retryable =>
      status == 0 || status == 408 || status == 429 || status >= 500;
  @override
  String toString() => message;
}

/// Sessions/payments live on the server. Client clocks/amounts are never sent.
class RemoteRepository {
  RemoteRepository(
    this.baseUrl, {
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 12),
  }) : client = client ?? http.Client();
  final String baseUrl;
  final http.Client client;
  final Duration requestTimeout;
  final RequestMetrics metrics = RequestMetrics();
  String? customerKey;
  Future<String> explainForecast(Json forecast, {required String token}) async {
    throw const ApiError(
      'Penjelasan Gemini tersedia pada koneksi Supabase. Prediksi regresi tetap berjalan.',
      'unsupported',
      503,
    );
  }

  Future<Json> request(
    String method,
    String path, {
    Json? body,
    String? token,
  }) async {
    final clock = Stopwatch()..start();
    String? errorCode;
    try {
      return await performRequest(
        method,
        path,
        body: body,
        token: token,
      ).timeout(requestTimeout);
    } on TimeoutException {
      errorCode = 'timeout';
      throw const ApiError(
        'Server belum merespons. Hasil operasi belum terkonfirmasi; coba lagi dengan operasi yang sama.',
        'timeout',
        0,
      );
    } on ApiError catch (error) {
      errorCode = error.code;
      rethrow;
    } catch (_) {
      errorCode = 'invalid_response';
      throw const ApiError(
        'Respons server belum dapat dibaca. Coba lagi.',
        'invalid_response',
        502,
      );
    } finally {
      metrics.record(clock.elapsedMilliseconds, errorCode: errorCode);
    }
  }

  Future<Json> performRequest(
    String method,
    String path, {
    Json? body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      'X-QPark-Customer': ?customerKey,
    };
    try {
      final response = await (method == 'GET'
          ? client.get(uri, headers: headers)
          : client.post(uri, headers: headers, body: jsonEncode(body ?? {})));
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
