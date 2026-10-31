import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/data/supabase_remote_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final code in ['57014', '42501', '42702', 'PGRST202', 'XX000']) {
    test(
      'Supabase $code is actionable without leaking database details',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'code': code,
                'message': 'private database details',
                'details': null,
                'hint': null,
              }),
              400,
              headers: {'content-type': 'application/json'},
              request: request,
            ),
          ),
        );
        addTearDown(client.dispose);
        final repository = SupabaseRemoteRepository(client);
        addTearDown(repository.close);
        await expectLater(
          repository.request('GET', '/api/admin/analytics', token: 'test'),
          throwsA(
            isA<ApiError>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.message, 'safe code', contains('Kode: $code'))
                .having(
                  (e) => e.message,
                  'no internals',
                  isNot(contains('private database details')),
                ),
          ),
        );
      },
    );
  }
}
