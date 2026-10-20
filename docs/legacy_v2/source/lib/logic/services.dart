import '../data/parking_repository.dart';
import '../domain/errors.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import 'security.dart';

/// Use case dan otorisasi. Sesi hanya dibuat melalui login yang berhasil.
class QParkService {
  QParkService(
    this.repository, {
    PasswordSecurity? security,
    DateTime Function()? clock,
  }) : security = security ?? PasswordSecurity(),
       clock = clock ?? DateTime.now;
  final ParkingRepository repository;
  final PasswordSecurity security;
  final DateTime Function() clock;
  final Map<String, int> _sessions = {};
  Future<Session> login(String username, String password) async {
    final found = await repository.credentials(username.trim().toLowerCase());
    if (found == null ||
        !found.user.active ||
        !await security.verify(password, found.passwordHash)) {
      throw const QParkException('Nama pengguna atau kata sandi tidak valid.');
    }
    final session = Session(security.randomToken(), found.user);
    _sessions[session.token] = found.user.id;
    return session;
  }

  void logout(Session session) => _sessions.remove(session.token);
  Future<AppUser> requireUser(Session session, [Role? role]) async {
    if (_sessions[session.token] != session.user.id) {
      throw const SessionExpired();
    }
    final user = await repository.user(session.user.id);
    if (user == null || !user.active || _sessions[session.token] != user.id) {
      logout(session);
      throw const SessionExpired();
    }
    if (role != null && user.role != role) {
      throw const QParkException('Anda tidak berhak melakukan tindakan ini.');
    }
    return user;
  }

  Future<Dashboard> dashboard(Session session, [String query = '']) async {
    await requireUser(session);
    return repository.dashboard(query);
  }

  Future<List<Visit>> active(Session session, [String query = '']) async {
    await requireUser(session, Role.officer);
    return repository.active(query);
  }

  Future<Visit> enter(Session session, String plate, Vehicle vehicle) async {
    final user = await requireUser(session, Role.officer);
    return repository.createEntry(
      normalizePlate(plate),
      vehicle,
      clock(),
      user.id,
    );
  }

  Future<Quote> quote(Session session, String id) async {
    await requireUser(session, Role.officer);
    final visit = await repository.visit(id);
    if (visit == null || !visit.active) {
      throw const QParkException(
        'Transaksi aktif tidak ditemukan atau sudah selesai.',
      );
    }
    return calculateQuote(visit, clock());
  }

  Future<Visit> pay(
    Session session,
    String id,
    String cash,
    int expectedTotal,
  ) async {
    final actor = await requireUser(session, Role.officer);
    final estimate = await quote(session, id);
    if (estimate.total != expectedTotal) {
      throw PriceChanged(estimate);
    }
    final received = parseRupiah(cash);
    if (received < estimate.total) {
      throw const QParkException('Uang diterima belum mencukupi total biaya.');
    }
    return repository.completePayment(estimate, received, actor.id);
  }

  Future<List<Visit>> history(Session session, HistoryFilter filter) async {
    await requireUser(session);
    validateFilter(filter);
    return repository.history(filter);
  }

  Future<Visit> detail(Session session, String id) async {
    await requireUser(session);
    final result = await repository.visit(id);
    if (result == null) {
      throw const QParkException('Transaksi tidak ditemukan.');
    }
    return result;
  }

  Future<Revenue> revenue(Session session, HistoryFilter filter) async {
    await requireUser(session, Role.admin);
    validateFilter(filter);
    return repository.revenue(filter);
  }

  Future<List<ParkingSetting>> settings(Session session) async {
    await requireUser(session, Role.admin);
    return repository.settings();
  }

  Future<void> updateSetting(
    Session session,
    Vehicle vehicle,
    String capacity,
    String rate,
  ) async {
    final actor = await requireUser(session, Role.admin);
    final parsedRate = parseRupiah(rate, 'Tarif per jam');
    if (parsedRate == 0) {
      throw const QParkException('Tarif per jam harus lebih dari 0.');
    }
    return repository.updateSetting(
      ParkingSetting(vehicle, parseInteger(capacity, 'Kapasitas'), parsedRate),
      actor.id,
    );
  }

  Future<List<AppUser>> officers(Session session) async {
    await requireUser(session, Role.admin);
    return repository.officers();
  }

  Future<AppUser> createOfficer(
    Session session,
    String name,
    String username,
    String password,
  ) async {
    final actor = await requireUser(session, Role.admin);
    final clean = username.trim().toLowerCase();
    if (name.trim().isEmpty) {
      throw const QParkException('Nama petugas wajib diisi.');
    }
    if (!RegExp(r'^[a-z0-9_.]{3,32}$').hasMatch(clean)) {
      throw const QParkException(
        'Nama pengguna harus 3–32 huruf kecil, angka, titik, atau garis bawah.',
      );
    }
    if (password.trim().isEmpty || password.length < 8) {
      throw const QParkException(
        'Kata sandi minimal 8 karakter dan tidak boleh hanya spasi.',
      );
    }
    final hash = await security.hash(password);
    await requireUser(session, Role.admin);
    return repository.createOfficer(name.trim(), clean, hash, actor.id);
  }

  Future<void> setOfficerActive(Session session, int id, bool active) async {
    final actor = await requireUser(session, Role.admin);
    return repository.setOfficerActive(id, active, actor.id);
  }
}
