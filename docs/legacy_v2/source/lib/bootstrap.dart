import 'package:flutter/services.dart';
import 'config.dart';
import 'data/connection.dart';
import 'data/database.dart';
import 'data/sqlite_repository.dart';
import 'domain/errors.dart';
import 'logic/security.dart';
import 'logic/services.dart';

/// Satu titik pemilihan backend dan seed data demo tanpa kunjungan palsu.
Future<QParkService> bootstrap() async {
  if (AppConfig.backend != 'sqlite') {
    throw const QParkException(
      'Backend belum didukung. Gunakan DB_BACKEND=sqlite.',
    );
  }
  final schema = await rootBundle.loadString('assets/schema.sql');
  final repository = SqliteParkingRepository(
    QParkDatabase(openConnection(), schema),
  );
  final security = PasswordSecurity();
  try {
    if (!await repository.seeded) {
      final hashes = await Future.wait([
        security.hash('Admin123!'),
        security.hash('Petugas123!'),
      ]);
      await repository.seed(hashes[0], hashes[1]);
    }
    return QParkService(repository, security: security);
  } catch (_) {
    await repository.close();
    rethrow;
  }
}
