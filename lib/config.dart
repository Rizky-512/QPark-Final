import 'package:flutter/foundation.dart';

/// Public configuration; API_BASE_URL must never contain credentials.
abstract final class AppConfig {
  static const simulation = bool.fromEnvironment(
    'QPARK_SIMULATION',
    defaultValue: true,
  );
  static const databaseName =
      'qpark_flutter_v1'; // legacy data remains untouched

  /// Supabase's project URL and public/publishable key are injected at build
  /// time. Never put a service-role key in a Flutter application.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const supabaseMobileRedirectUrl = String.fromEnvironment(
    'SUPABASE_MOBILE_REDIRECT_URL',
    defaultValue: 'id.qpark.qpark://login-callback/',
  );

  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static void validateSupabase() {
    final onlyOneValue = supabaseUrl.isEmpty != supabasePublishableKey.isEmpty;
    if (onlyOneValue) {
      throw const FormatException(
        'SUPABASE_URL dan SUPABASE_PUBLISHABLE_KEY harus diisi bersamaan.',
      );
    }
    if (supabaseUrl.isNotEmpty) {
      final uri = Uri.tryParse(supabaseUrl);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException(
          'SUPABASE_URL harus berupa alamat HTTPS proyek Supabase.',
        );
      }
    }
  }

  static String get apiBaseUrl {
    const explicit = String.fromEnvironment('API_BASE_URL');
    if (explicit.isNotEmpty) return explicit.replaceFirst(RegExp(r'/$'), '');
    return kIsWeb ? Uri.base.origin : 'http://10.0.2.2:7357';
  }
}
