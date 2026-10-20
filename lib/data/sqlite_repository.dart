import 'dart:math';
import 'package:drift/drift.dart';
import '../domain/errors.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import 'database.dart';
import 'parking_repository.dart';

/// SQLite bersama untuk HP dan web; semua query input berparameter.
class SqliteParkingRepository implements ParkingRepository {
  SqliteParkingRepository(this.db);
  final QParkDatabase db;
  static const _select =
      '''SELECT t.*, a.nama AS nama_masuk, b.nama AS nama_keluar
    FROM transaksi_parkir t JOIN users a ON a.id_user=t.id_petugas_masuk
    LEFT JOIN users b ON b.id_user=t.id_petugas_keluar''';
  Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on QParkException {
      rethrow;
    } catch (_) {
      throw const StorageException();
    }
  }

  List<Variable> _vars(List<Object> values) => values
      .map((v) => v is int ? Variable<int>(v) : Variable<String>(v as String))
      .toList();
  Future<List<QueryRow>> _rows(String sql, [List<Object> args = const []]) =>
      db.customSelect(sql, variables: _vars(args)).get();
  Future<int> _write(String sql, [List<Object> args = const []]) =>
      db.customUpdate(sql, variables: _vars(args));
  AppUser _user(QueryRow row) => AppUser(
    id: row.read<int>('id_user'),
    name: row.read<String>('nama'),
    username: row.read<String>('username'),
    role: row.read<String>('role') == 'Admin' ? Role.admin : Role.officer,
    active: row.read<int>('aktif') == 1,
  );
  Visit _visit(QueryRow row) {
    final out = row.readNullable<int>('waktu_keluar');
    return Visit(
      id: row.read<String>('id_transaksi'),
      plate: row.read<String>('nomor_polisi'),
      vehicle: row.read<String>('jenis_kendaraan') == 'Motor'
          ? Vehicle.motor
          : Vehicle.car,
      enteredAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('waktu_masuk'),
      ),
      exitedAt: out == null ? null : DateTime.fromMillisecondsSinceEpoch(out),
      hourlyRate: row.read<int>('tarif_per_jam_saat_masuk'),
      entryOfficerId: row.read<int>('id_petugas_masuk'),
      entryOfficerName: row.read<String>('nama_masuk'),
      exitOfficerId: row.readNullable<int>('id_petugas_keluar'),
      exitOfficerName: row.readNullable<String>('nama_keluar'),
      hours: row.readNullable<int>('jam_tertagih'),
      total: row.readNullable<int>('total_biaya'),
      received: row.readNullable<int>('uang_diterima'),
      change: row.readNullable<int>('kembalian'),
    );
  }

  /// Seed hanya mengisi database baru, tidak menimpa pengaturan sebelumnya.
  Future<void> seed(String adminHash, String officerHash) => _safe(
    () => db.transaction(() async {
      if ((await _rows(
            'SELECT COUNT(*) AS n FROM users',
          )).single.read<int>('n') >
          0) {
        return;
      }
      for (final values in [
        ['Administrator', 'admin', adminHash, 'Admin'],
        ['Petugas Parkir', 'petugas', officerHash, 'Petugas'],
      ]) {
        await _write(
          'INSERT INTO users(nama,username,password_hash,role,aktif) VALUES (?,?,?,?,1)',
          values,
        );
      }
      for (final values in [
        ['Motor', 2000, 2],
        ['Mobil', 5000, 1],
      ]) {
        await _write('INSERT INTO tarif_parkir VALUES (?,?)', [
          values[0],
          values[1],
        ]);
        await _write('INSERT INTO kapasitas_parkir VALUES (?,?)', [
          values[0],
          values[2],
        ]);
      }
    }),
  );
  Future<bool> get seeded => _safe(
    () async =>
        (await _rows('SELECT COUNT(*) AS n FROM users')).single.read<int>('n') >
        0,
  );
  @override
  Future<Credentials?> credentials(String username) => _safe(() async {
    final rows = await _rows('SELECT * FROM users WHERE username=?', [
      username,
    ]);
    return rows.isEmpty
        ? null
        : Credentials(
            _user(rows.first),
            rows.first.read<String>('password_hash'),
          );
  });
  @override
  Future<AppUser?> user(int id) => _safe(() async {
    final rows = await _rows('SELECT * FROM users WHERE id_user=?', [id]);
    return rows.isEmpty ? null : _user(rows.single);
  });
  Future<void> _actor(int id, Role role) async {
    final found = await user(id);
    if (found == null || !found.active) throw const SessionExpired();
    if (found.role != role) {
      throw const QParkException('Anda tidak berhak melakukan tindakan ini.');
    }
  }

  @override
  Future<Dashboard> dashboard(String query) => _safe(
    () => db.transaction(() async {
      final rows = await _rows(
        '''SELECT k.jenis_kendaraan, k.kapasitas, COUNT(t.id_transaksi) AS terisi
      FROM kapasitas_parkir k LEFT JOIN transaksi_parkir t
      ON t.jenis_kendaraan=k.jenis_kendaraan AND t.status_parkir='Aktif'
      GROUP BY k.jenis_kendaraan, k.kapasitas ORDER BY k.jenis_kendaraan DESC''',
      );
      if (rows.length != 2) throw const StorageException();
      final slots = rows
          .map(
            (r) => SlotSummary(
              r.read<String>('jenis_kendaraan') == 'Motor'
                  ? Vehicle.motor
                  : Vehicle.car,
              r.read<int>('kapasitas'),
              r.read<int>('terisi'),
            ),
          )
          .toList();
      return Dashboard(slots, await active(query));
    }),
  );
  String _search(String query) =>
      query.toUpperCase().replaceAll(RegExp(r'\s'), '');
  @override
  Future<List<Visit>> active(String query) => _safe(() async {
    final search = _search(query);
    return (await _rows(
      '''$_select WHERE t.status_parkir='Aktif' AND
      (instr(t.nomor_polisi,?)>0 OR instr(upper(t.id_transaksi),?)>0)
      ORDER BY t.waktu_masuk DESC, t.id_transaksi''',
      [search, search],
    )).map(_visit).toList();
  });
  @override
  Future<Visit?> visit(String id) => _safe(() async {
    final rows = await _rows('$_select WHERE t.id_transaksi=?', [id]);
    return rows.isEmpty ? null : _visit(rows.single);
  });
  @override
  Future<Visit> createEntry(
    String plate,
    Vehicle vehicle,
    DateTime now,
    int actor,
  ) => _safe(
    () => db.transaction(() async {
      await _actor(actor, Role.officer);
      final normalized = normalizePlate(plate);
      if ((await _rows(
        "SELECT 1 FROM transaksi_parkir WHERE nomor_polisi=? AND status_parkir='Aktif'",
        [normalized],
      )).isNotEmpty) {
        throw const QParkException(
          'Nomor polisi tersebut masih memiliki transaksi aktif.',
        );
      }
      final setting = (await settings()).singleWhere(
        (s) => s.vehicle == vehicle,
      );
      final occupied = (await _rows(
        "SELECT COUNT(*) AS n FROM transaksi_parkir WHERE jenis_kendaraan=? AND status_parkir='Aktif'",
        [vehicle.label],
      )).single.read<int>('n');
      if (occupied >= setting.capacity) {
        throw QParkException('Parkir ${vehicle.label.toLowerCase()} penuh.');
      }
      final random = Random.secure();
      final suffix = List.generate(
        12,
        (_) => random.nextInt(16).toRadixString(16),
      ).join().toUpperCase();
      final id =
          'QP-${now.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}-$suffix';
      await _write(
        '''INSERT INTO transaksi_parkir(id_transaksi,nomor_polisi,jenis_kendaraan,
      waktu_masuk,tarif_per_jam_saat_masuk,status_parkir,status_pembayaran,id_petugas_masuk)
      VALUES (?,?,?,?,?,'Aktif','Belum Bayar',?)''',
        [
          id,
          normalized,
          vehicle.label,
          now.millisecondsSinceEpoch,
          setting.hourlyRate,
          actor,
        ],
      );
      // Pembacaan bukti bagian dari transaksi: gagal baca berarti rollback.
      return (await visit(id))!;
    }),
  );
  @override
  Future<Visit> completePayment(Quote quote, int received, int actor) => _safe(
    () => db.transaction(() async {
      await _actor(actor, Role.officer);
      final current = await visit(quote.visit.id);
      if (current == null || !current.active) {
        throw const QParkException(
          'Transaksi sudah selesai atau tidak ditemukan.',
        );
      }
      final checked = calculateQuote(current, quote.exitedAt);
      if (checked.total != quote.total ||
          checked.hours != quote.hours ||
          received < checked.total ||
          received > maxInteger) {
        throw const QParkException(
          'Rincian pembayaran tidak valid. Muat ulang estimasi.',
        );
      }
      final changed = await _write(
        '''UPDATE transaksi_parkir SET waktu_keluar=?,jam_tertagih=?,total_biaya=?,
      metode_pembayaran='Tunai',uang_diterima=?,kembalian=?,status_parkir='Selesai',status_pembayaran='Lunas',id_petugas_keluar=?
      WHERE id_transaksi=? AND status_parkir='Aktif' ''',
        [
          quote.exitedAt.millisecondsSinceEpoch,
          checked.hours,
          checked.total,
          received,
          received - checked.total,
          actor,
          current.id,
        ],
      );
      if (changed != 1) {
        throw const QParkException(
          'Transaksi sudah dibayar. Muat ulang daftar.',
        );
      }
      return (await visit(current.id))!;
    }),
  );
  (String, List<Object>) _where(HistoryFilter filter) {
    validateFilter(filter);
    final query = _search(filter.query);
    return (
      '''t.status_parkir='Selesai' AND t.waktu_keluar>=? AND t.waktu_keluar<?
      ${filter.vehicle == null ? '' : 'AND t.jenis_kendaraan=?'}
      AND (instr(t.nomor_polisi,?)>0 OR instr(upper(t.id_transaksi),?)>0)''',
      [
        filter.from.millisecondsSinceEpoch,
        filter.until.millisecondsSinceEpoch,
        if (filter.vehicle != null) filter.vehicle!.label,
        query,
        query,
      ],
    );
  }

  @override
  Future<List<Visit>> history(HistoryFilter filter) => _safe(() async {
    final (where, args) = _where(filter);
    return (await _rows(
      '$_select WHERE $where ORDER BY t.waktu_keluar DESC, t.id_transaksi',
      args,
    )).map(_visit).toList();
  });
  @override
  Future<Revenue> revenue(HistoryFilter filter) => _safe(() async {
    final (where, args) = _where(filter);
    final row = (await _rows(
      'SELECT COUNT(*) AS n,COALESCE(SUM(t.total_biaya),0) AS total FROM transaksi_parkir t WHERE $where',
      args,
    )).single;
    final total = row.read<int>('total');
    if (total > maxInteger) {
      throw const QParkException(
        'Jumlah pendapatan melampaui batas bilangan. Persempit rentang tanggal.',
      );
    }
    return Revenue(row.read<int>('n'), total);
  });
  @override
  Future<List<ParkingSetting>> settings() => _safe(
    () async =>
        (await _rows(
              '''SELECT k.*,t.tarif_per_jam FROM kapasitas_parkir k JOIN tarif_parkir t USING(jenis_kendaraan)
      ORDER BY k.jenis_kendaraan DESC''',
            ))
            .map(
              (r) => ParkingSetting(
                r.read<String>('jenis_kendaraan') == 'Motor'
                    ? Vehicle.motor
                    : Vehicle.car,
                r.read<int>('kapasitas'),
                r.read<int>('tarif_per_jam'),
              ),
            )
            .toList(),
  );
  @override
  Future<void> updateSetting(ParkingSetting setting, int actor) => _safe(
    () => db.transaction(() async {
      await _actor(actor, Role.admin);
      final occupied = (await _rows(
        "SELECT COUNT(*) AS n FROM transaksi_parkir WHERE jenis_kendaraan=? AND status_parkir='Aktif'",
        [setting.vehicle.label],
      )).single.read<int>('n');
      if (setting.capacity < occupied) {
        throw QParkException(
          'Kapasitas tidak boleh di bawah $occupied kendaraan aktif.',
        );
      }
      if (setting.capacity < 0 ||
          setting.hourlyRate <= 0 ||
          setting.capacity > maxInteger ||
          setting.hourlyRate > maxInteger) {
        throw const QParkException('Kapasitas atau tarif tidak valid.');
      }
      await _write(
        'UPDATE kapasitas_parkir SET kapasitas=? WHERE jenis_kendaraan=?',
        [setting.capacity, setting.vehicle.label],
      );
      await _write(
        'UPDATE tarif_parkir SET tarif_per_jam=? WHERE jenis_kendaraan=?',
        [setting.hourlyRate, setting.vehicle.label],
      );
    }),
  );
  @override
  Future<List<AppUser>> officers() => _safe(
    () async => (await _rows(
      "SELECT * FROM users WHERE role='Petugas' ORDER BY username",
    )).map(_user).toList(),
  );
  @override
  Future<AppUser> createOfficer(
    String name,
    String username,
    String hash,
    int actor,
  ) => _safe(
    () => db.transaction(() async {
      await _actor(actor, Role.admin);
      if ((await _rows('SELECT 1 FROM users WHERE username=?', [
        username,
      ])).isNotEmpty) {
        throw const QParkException('Nama pengguna sudah digunakan.');
      }
      await _write(
        "INSERT INTO users(nama,username,password_hash,role,aktif) VALUES (?,?,?,'Petugas',1)",
        [name, username, hash],
      );
      return _user(
        (await _rows('SELECT * FROM users WHERE username=?', [
          username,
        ])).single,
      );
    }),
  );
  @override
  Future<void> setOfficerActive(int id, bool active, int actor) => _safe(
    () => db.transaction(() async {
      await _actor(actor, Role.admin);
      final count = await _write(
        "UPDATE users SET aktif=? WHERE id_user=? AND role='Petugas'",
        [active ? 1 : 0, id],
      );
      if (count != 1) {
        throw const QParkException('Akun petugas tidak ditemukan.');
      }
    }),
  );
  @override
  Future<void> close() => db.close();
}
