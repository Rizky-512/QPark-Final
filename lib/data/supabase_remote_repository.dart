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
  Future<Json> performRequest(
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
          'p_query': {
            ...uri.queryParameters,
            if (customerKey != null) '_customer_key': customerKey,
          },
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
      final code = error.code ?? 'supabase';
      final message = switch (code) {
        '57014' =>
          'Analisis melewati batas waktu server. Pengelola perlu memasang pembaruan query analisis (005).',
        '42501' =>
          'Akses database ditolak. Pengelola perlu memeriksa izin fungsi aplikasi.',
        '42702' =>
          'Query analisis memiliki nama kolom yang bertabrakan. Pengelola perlu memasang pembaruan SQL terbaru.',
        '42883' || '42P01' || 'PGRST202' =>
          'Fungsi atau tabel aplikasi belum tersedia. Periksa migrasi pada proyek Supabase yang terhubung.',
        _ =>
          'Permintaan Supabase gagal. Kirim kode berikut kepada pengelola untuk diperiksa.',
      };
      final status = switch (code) {
        '57014' || '40001' || '40P01' || '53300' => 503,
        '42501' => 403,
        _ => 500,
      };
      throw ApiError('$message Kode: $code.', code, status);
    } catch (_) {
      throw const ApiError(
        'Supabase tidak terjangkau. Periksa koneksi internet.',
        'offline',
        0,
      );
    }
  }
}
