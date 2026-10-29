import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'remote_repository.dart';

/// Keeps the existing `/api/*` contract while executing it transactionally in
/// PostgreSQL through the `qpark_request` Supabase RPC.
class SupabaseRemoteRepository extends RemoteRepository {
  SupabaseRemoteRepository(this.supabase) : super('');

  final SupabaseClient supabase;

  @override
  Future<String> explainForecast(Json forecast, {required String token}) async {
    try {
      final response = await supabase.functions
          .invoke(
            'parking-explain',
            body: {'token': token, 'forecast': forecast},
          )
          .timeout(const Duration(seconds: 35));
      final body = response.data;
      if (body is Map && body['explanation'] is String) {
        return body['explanation'] as String;
      }
      throw const ApiError('Penjelasan AI belum tersedia.', 'ai', 502);
    } on FunctionException catch (e) {
      final details = e.details;
      throw ApiError(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'Fitur Gemini belum aktif. Periksa deployment Edge Function dan Secrets Supabase.',
        'ai',
        e.status,
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError('Koneksi AI terputus. Coba lagi nanti.', 'ai', 503);
    }
  }

  @override
  Future<Json> request(
    String method,
    String path, {
    Json? body,
    String? token,
  }) async {
    final uri = Uri.parse(path);
    try {
      final response = await supabase.rpc(
        'qpark_request',
        params: {
          'p_method': method,
          'p_path': uri.path,
          'p_query': uri.queryParameters,
          'p_body': body ?? <String, dynamic>{},
          'p_token': token,
        },
      );
      if (response is! Map) {
        throw const ApiError(
          'Respons Supabase tidak dikenali.',
          'invalid_response',
          502,
        );
      }
      return Map<String, dynamic>.from(response);
    } on ApiError {
      rethrow;
    } on PostgrestException catch (error) {
      dynamic decoded;
      try {
        decoded = jsonDecode(error.message);
      } on FormatException {
        // Fall through to a safe message without exposing database internals.
      }
      if (decoded is Map) {
        throw ApiError(
          decoded['error'] as String? ?? 'Permintaan ditolak Supabase.',
          decoded['code'] as String? ?? error.code ?? 'supabase',
          (decoded['status'] as num?)?.toInt() ?? 400,
        );
      }
      throw ApiError(
        'Supabase menolak permintaan. Pastikan migration terbaru sudah dijalankan.',
        error.code ?? 'supabase',
        400,
      );
    } catch (_) {
      throw const ApiError(
        'Supabase tidak terjangkau. Periksa koneksi internet.',
        'offline',
        0,
      );
    }
  }
}
