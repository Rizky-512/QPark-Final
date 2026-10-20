import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/data/database.dart';
import 'package:qpark/data/sqlite_repository.dart';
import 'package:qpark/domain/errors.dart';
import 'package:qpark/domain/models.dart';
import 'package:qpark/logic/services.dart';
import 'support.dart';

void main() {
  late Fixture f;
  setUp(() async => f = await Fixture.create());
  tearDown(() async => f.close());
  test('AT-01 login username normal, pesan umum, logout', () async {
    expect(
      (await f.service.login(' ADMIN ', 'Admin123!')).user.role,
      Role.admin,
    );
    for (final name in ['admin', 'tidak_ada', '']) {
      await expectLater(
        f.service.login(name, 'salah'),
        throwsA(
          isA<QParkException>().having(
            (e) => e.message,
            'pesan',
            'Nama pengguna atau kata sandi tidak valid.',
          ),
        ),
      );
    }
    f.service.logout(f.officer);
    await expectLater(
      f.service.dashboard(f.officer),
      throwsA(isA<SessionExpired>()),
    );
  });
  test('AT-02 seluruh tindakan sensitif memiliki otorisasi service', () async {
    final actions = <Future<Object?> Function()>[
      () => f.service.enter(f.admin, 'B123ABC', Vehicle.motor),
      () => f.service.active(f.admin),
      () => f.service.quote(f.admin, 'dummy'),
      () => f.service.pay(f.admin, 'dummy', '2000', 2000),
      () => f.service.settings(f.officer),
      () => f.service.officers(f.officer),
      () => f.service.updateSetting(f.officer, Vehicle.motor, '2', '2000'),
      () => f.service.createOfficer(f.officer, 'X', 'barux', '12345678'),
      () => f.service.setOfficerActive(f.officer, 2, false),
      () =>
          f.service.revenue(f.officer, HistoryFilter(start: f.now, end: f.now)),
    ];
    for (final action in actions) {
      await expectLater(action(), throwsA(isA<QParkException>()));
    }
  });
  test('AT-02 sesi palsu dan lintas service ditolak', () async {
    await expectLater(
      f.service.dashboard(Session('palsu', f.officer.user)),
      throwsA(isA<SessionExpired>()),
    );
    await expectLater(
      QParkService(f.repo, security: f.security).dashboard(f.officer),
      throwsA(isA<SessionExpired>()),
    );
  });
  test('AT-02 buat petugas, lowercase unik, password minimum', () async {
    final u = await f.service.createOfficer(
      f.admin,
      ' Budi ',
      ' BUDI ',
      '12345678',
    );
    expect(u.username, 'budi');
    expect(u.name, 'Budi');
    expect((await f.service.login('budi', '12345678')).user.id, u.id);
    await expectLater(
      f.service.createOfficer(f.admin, 'Budi', 'BUDI', '12345678'),
      throwsA(isA<QParkException>()),
    );
    await expectLater(
      f.service.createOfficer(f.admin, 'X', 'test', '1234567'),
      throwsA(isA<QParkException>()),
    );
    await expectLater(
      f.service.createOfficer(f.admin, 'X', 'test', '        '),
      throwsA(isA<QParkException>()),
    );
    await expectLater(
      f.service.createOfficer(f.admin, '', 'test', '12345678'),
      throwsA(isA<QParkException>()),
    );
  });
  test('AT-12 nonaktif menolak sesi terbuka dan login', () async {
    final v = await f.service.enter(f.officer, 'B123ABC', Vehicle.motor);
    await f.service.setOfficerActive(f.admin, f.officer.user.id, false);
    await expectLater(
      f.service.detail(f.officer, v.id),
      throwsA(isA<SessionExpired>()),
    );
    await expectLater(
      f.service.login('petugas', 'Petugas123!'),
      throwsA(isA<QParkException>()),
    );
    await f.service.setOfficerActive(f.admin, f.officer.user.id, true);
    await expectLater(
      f.service.dashboard(f.officer),
      throwsA(isA<SessionExpired>()),
    );
    expect((await f.service.login('petugas', 'Petugas123!')).user.active, true);
    await expectLater(
      f.service.setOfficerActive(f.admin, f.admin.user.id, false),
      throwsA(isA<QParkException>()),
    );
  });
  test('AT-03 ID waktu snapshot petugas dan slot', () async {
    final v = await f.service.enter(f.officer, 'b 123 abc', Vehicle.motor);
    expect(v.id, startsWith('QP-'));
    expect(v.plate, 'B123ABC');
    expect(v.enteredAt, f.now);
    expect(v.hourlyRate, 2000);
    expect(v.entryOfficerId, 2);
    expect(v.active, true);
    final d = await f.service.dashboard(f.admin);
    expect(d.slots.firstWhere((s) => s.vehicle == Vehicle.motor).available, 1);
    expect(d.slots.firstWhere((s) => s.vehicle == Vehicle.car).available, 1);
  });
  test('AT-04 duplikat lintas jenis dan masuk lagi setelah lunas', () async {
    final v = await f.service.enter(f.officer, 'B123ABC', Vehicle.motor);
    await expectLater(
      f.service.enter(f.officer, 'b 123 abc', Vehicle.car),
      throwsA(isA<QParkException>()),
    );
    await f.service.pay(f.officer, v.id, '2000', 2000);
    final next = await f.service.enter(f.officer, 'B123ABC', Vehicle.car);
    expect(next.id, isNot(v.id));
    expect(next.vehicle, Vehicle.car);
  });
  test('AT-05 penuh per jenis dan kapasitas nol', () async {
    await f.service.enter(f.officer, 'B111ABC', Vehicle.motor);
    await f.service.enter(f.officer, 'B222ABC', Vehicle.motor);
    await expectLater(
      f.service.enter(f.officer, 'B333ABC', Vehicle.motor),
      throwsA(isA<QParkException>()),
    );
    await f.service.updateSetting(f.admin, Vehicle.car, '0', '5000');
    await expectLater(
      f.service.enter(f.officer, 'B444ABC', Vehicle.car),
      throwsA(isA<QParkException>()),
    );
    expect(
      (await f.service.dashboard(f.admin)).slots.every((s) => s.full),
      true,
    );
  });
  test('AT-07 uang kurang, kembalian, bukti, dan pelepasan slot', () async {
    final v = await f.service.enter(f.officer, 'B123ABC', Vehicle.motor);
    f.now = f.now.add(const Duration(minutes: 61));
    await expectLater(
      f.service.pay(f.officer, v.id, '3000', 4000),
      throwsA(isA<QParkException>()),
    );
    expect((await f.repo.visit(v.id))!.active, true);
    final r = await f.service.pay(f.officer, v.id, 'Rp5.000', 4000);
    expect(r.total, 4000);
    expect(r.received, 5000);
    expect(r.change, 1000);
    expect(r.hours, 2);
    expect(r.exitOfficerId, 2);
    expect(r.status, 'Selesai · Lunas');
    expect((await f.service.dashboard(f.officer)).slots.first.available, 2);
  });
  test('AT-08 klik ganda hanya satu pembayaran', () async {
    final v = await f.service.enter(f.officer, 'B123ABC', Vehicle.motor);
    final results = await Future.wait(
      List.generate(2, (_) async {
        try {
          await f.service.pay(f.officer, v.id, '2000', 2000);
          return true;
        } on QParkException {
          return false;
        }
      }),
    );
    expect(results.where((ok) => ok).length, 1);
    expect(
      (await f.service.revenue(
        f.admin,
        HistoryFilter(start: f.now, end: f.now),
      )).total,
      2000,
    );
  });
  test('AT-08 masuk serentak tidak melampaui kapasitas', () async {
    final results = await Future.wait(
      List.generate(5, (i) async {
        try {
          await f.service.enter(f.officer, 'B${i}ABC', Vehicle.car);
          return true;
        } on QParkException {
          return false;
        }
      }),
    );
    expect(results.where((ok) => ok).length, 1);
  });
  test('AT-08 kegagalan simpan pembayaran rollback', () async {
    final v = await f.service.enter(f.officer, 'B123ABC', Vehicle.motor);
    await f.repo.db.customStatement(
      "CREATE TRIGGER test_fail BEFORE UPDATE ON transaksi_parkir BEGIN SELECT RAISE(ABORT,'simulasi gagal'); END;",
    );
    await expectLater(
      f.service.pay(f.officer, v.id, '2000', 2000),
      throwsA(isA<StorageException>()),
    );
    final r = (await f.repo.visit(v.id))!;
    expect(r.active, true);
    expect(r.total, isNull);
    expect(r.received, isNull);
    expect((await f.service.dashboard(f.officer)).slots.first.occupied, 1);
  });
  test('AT-08 kegagalan masuk tidak meninggalkan data parsial', () async {
    await f.repo.db.customStatement(
      "CREATE TRIGGER test_fail BEFORE INSERT ON transaksi_parkir BEGIN SELECT RAISE(ABORT,'simulasi gagal'); END;",
    );
    await expectLater(
      f.service.enter(f.officer, 'B123ABC', Vehicle.motor),
      throwsA(isA<StorageException>()),
    );
    expect((await f.service.dashboard(f.officer)).visits, isEmpty);
  });
  test('AT-09 biaya berubah memerlukan konfirmasi ulang', () async {
    final v = await f.service.enter(f.officer, 'B123ABC', Vehicle.motor);
    final old = await f.service.quote(f.officer, v.id);
    f.now = f.now.add(const Duration(minutes: 61));
    await expectLater(
      f.service.pay(f.officer, v.id, '5000', old.total),
      throwsA(
        isA<PriceChanged>().having((e) => e.quote.total, 'biaya baru', 4000),
      ),
    );
    expect((await f.repo.visit(v.id))!.active, true);
    final q = await f.service.quote(f.officer, v.id);
    expect(
      (await f.service.pay(f.officer, v.id, '5000', q.total)).change,
      1000,
    );
  });
  test(
    'AT-10 riwayat inklusif, jenis, pelat, ID dan pendapatan total biaya',
    () async {
      f.now = DateTime(2026, 10, 4);
      final a = await f.service.enter(f.officer, 'B111ABC', Vehicle.motor);
      await f.service.pay(f.officer, a.id, '10000', 2000);
      f.now = DateTime(2026, 10, 4, 23, 59, 59, 999);
      final b = await f.service.enter(f.officer, 'B222ABC', Vehicle.car);
      await f.service.pay(f.officer, b.id, '20000', 5000);
      f.now = DateTime(2026, 10, 5);
      final c = await f.service.enter(f.officer, 'B333ABC', Vehicle.car);
      await f.service.pay(f.officer, c.id, '5000', 5000);
      final day = DateTime(2026, 10, 4),
          filter = HistoryFilter(
            start: DateTime(2026, 10, 4),
            end: DateTime(2026, 10, 4),
          );
      expect((await f.service.history(f.officer, filter)).length, 2);
      final revenue = await f.service.revenue(f.admin, filter);
      expect(revenue.count, 2);
      expect(revenue.total, 7000);
      expect(
        (await f.service.history(
          f.officer,
          HistoryFilter(start: day, end: day, vehicle: Vehicle.car),
        )).single.id,
        b.id,
      );
      expect(
        (await f.service.history(
          f.officer,
          HistoryFilter(start: day, end: day, query: 'b 111 abc'),
        )).single.id,
        a.id,
      );
      expect(
        (await f.service.history(
          f.officer,
          HistoryFilter(start: day, end: day, query: a.id),
        )).single.id,
        a.id,
      );
      expect(
        await f.service.history(
          f.officer,
          HistoryFilter(start: day, end: day, query: '%'),
        ),
        isEmpty,
      );
      final empty = await f.service.revenue(
        f.admin,
        HistoryFilter(start: DateTime(2000), end: DateTime(2000)),
      );
      expect(empty.count, 0);
      expect(empty.total, 0);
    },
  );
  test('AT-11 tarif snapshot dan kapasitas ditolak atomik', () async {
    final old = await f.service.enter(f.officer, 'B111ABC', Vehicle.motor);
    await expectLater(
      f.service.updateSetting(f.admin, Vehicle.motor, '0', '9999'),
      throwsA(isA<QParkException>()),
    );
    expect((await f.service.settings(f.admin)).first.hourlyRate, 2000);
    await f.service.updateSetting(f.admin, Vehicle.motor, '2', '3000');
    final next = await f.service.enter(f.officer, 'B222ABC', Vehicle.motor);
    expect(next.hourlyRate, 3000);
    expect((await f.service.quote(f.officer, old.id)).total, 2000);
    for (final rate in ['0', '-1', '1.5']) {
      await expectLater(
        f.service.updateSetting(f.admin, Vehicle.motor, '2', rate),
        throwsA(isA<QParkException>()),
      );
    }
  });
  test(
    'BR-12 transaksi lunas tidak dapat diedit dihapus atau dibayar ulang',
    () async {
      final v = await f.service.enter(f.officer, 'B123ABC', Vehicle.motor);
      await f.service.pay(f.officer, v.id, '2000', 2000);
      await expectLater(
        f.service.pay(f.officer, v.id, '2000', 2000),
        throwsA(isA<QParkException>()),
      );
      await expectLater(
        f.repo.db.customStatement('UPDATE transaksi_parkir SET total_biaya=0'),
        throwsA(anything),
      );
      await expectLater(
        f.repo.db.customStatement('DELETE FROM transaksi_parkir'),
        throwsA(anything),
      );
      expect((await f.repo.visit(v.id))!.total, 2000);
    },
  );
  test('UC-02 database rusak menjadi error bukan slot kosong', () async {
    await f.repo.db.customStatement('DROP TABLE transaksi_parkir');
    await expectLater(
      f.service.dashboard(f.officer),
      throwsA(isA<StorageException>()),
    );
  });
  test('AT-12 persistensi setelah tutup dan buka SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('qpark_test_'),
        schema = File('assets/schema.sql').readAsStringSync();
    final file = File('${dir.path}/qpark.sqlite');
    final first = SqliteParkingRepository(
      QParkDatabase(NativeDatabase(file), schema),
    );
    try {
      await first.seed(
        await f.security.hash('Admin123!'),
        await f.security.hash('Petugas123!'),
      );
      final service = QParkService(first, security: f.security);
      final session = await service.login('petugas', 'Petugas123!');
      await service.enter(session, 'B123ABC', Vehicle.motor);
      await first.close();
      final second = SqliteParkingRepository(
        QParkDatabase(NativeDatabase(file), schema),
      );
      try {
        expect((await second.active('')).single.plate, 'B123ABC');
      } finally {
        await second.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
