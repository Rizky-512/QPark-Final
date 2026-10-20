import 'dart:io';
import 'package:drift/native.dart';
import 'package:qpark/data/database.dart';
import 'package:qpark/data/sqlite_repository.dart';
import 'package:qpark/domain/models.dart';
import 'package:qpark/logic/security.dart';
import 'package:qpark/logic/services.dart';

/// Database nyata sementara; biaya hash kecil hanya untuk fixture tes.
class Fixture {
  Fixture._(
    this.repo,
    this.service,
    this.security,
    this.admin,
    this.officer,
    this.now,
  );
  final SqliteParkingRepository repo;
  final QParkService service;
  final PasswordSecurity security;
  final Session admin, officer;
  DateTime now;
  static Future<Fixture> create() async {
    final repo = SqliteParkingRepository(
      QParkDatabase(
        NativeDatabase.memory(),
        File('assets/schema.sql').readAsStringSync(),
      ),
    );
    final security = PasswordSecurity(iterations: 1000);
    await repo.seed(
      await security.hash('Admin123!'),
      await security.hash('Petugas123!'),
    );
    late Fixture result;
    final service = QParkService(
      repo,
      security: security,
      clock: () => result.now,
    );
    final admin = await service.login('admin', 'Admin123!'),
        officer = await service.login('petugas', 'Petugas123!');
    result = Fixture._(
      repo,
      service,
      security,
      admin,
      officer,
      DateTime(2026, 10, 4, 10),
    );
    return result;
  }

  Future<void> close() => repo.close();
}
