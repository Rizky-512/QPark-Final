import 'dart:async';
import 'customer_auth.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/customer_repository.dart';
import '../data/remote_repository.dart';
import '../domain/errors.dart';
import '../domain/rules.dart';

/// Account-scoped operations and adaptive, single-flight synchronization.
class RemoteService extends ChangeNotifier {
  RemoteService(
    this.repository,
    this.preferences, {
    this.customerAuth = const PendingSupabaseAuth(),
    this.customerData,
  }) {
    _restoreDemoVehicles();
    repository.customerKey =
        preferences.getString('qpark_device_key_v1') ?? newKey();
    unawaited(
      preferences.setString('qpark_device_key_v1', repository.customerKey!),
    );
    final raw = preferences.getString('qpark_pending_v4');
    if (raw != null) {
      try {
        for (final value in jsonDecode(raw) as List) {
          if (value is Map &&
              value['owner'] is String &&
              value['path'] is String &&
              value['signature'] is String &&
              value['body'] is Map &&
              value['body']['operation_key'] is String &&
              !value['owner'].startsWith('staff:')) {
            _pending.add(Map<String, dynamic>.from(value));
          }
        }
      } catch (_) {
        sessionNotice =
            'Antrean lokal tidak dapat dibaca. Periksa status tiket sebelum mengulang transaksi.';
      }
    }
    // Old unscoped queues cannot safely be assigned to the current account.
    if (preferences.getString('qpark_pending_v3') != null && raw == null) {
      sessionNotice =
          'Ada antrean dari versi lama. Periksa tiket dengan petugas sebelum mengulang transaksi.';
    }
    revoked.addAll(preferences.getStringList('qpark_revocations_v3') ?? []);
    customerIdentity = customerAuth.currentIdentity;
    _authSubscription = customerAuth.authStateChanges.listen(
      (identity) => unawaited(_applyCustomerIdentity(identity)),
    );
    final identity = customerIdentity;
    if (identity != null) unawaited(_applyCustomerIdentity(identity));
  }
  final CustomerAuthProvider customerAuth;
  final CustomerRepository? customerData;
  StreamSubscription<CustomerIdentity?>? _authSubscription;
  CustomerIdentity? customerIdentity;
  bool customerDemo = false;
  String? sessionNotice;
  bool get signedIn => officer || customerDemo || customerIdentity != null;
  void enterCustomerDemo() {
    if (customerAuth.currentIdentity != null) {
      sessionNotice =
          'Sesi Google belum berakhir. Masuk kembali dengan Google lalu coba keluar lagi sebelum memakai demo.';
      emit();
      return;
    }
    _contextEpoch++;
    customerIdentity = null;
    customerDemo = true;
    sessionNotice = null;
    _restoreDemoVehicles();
    emit();
    unawaited(sync());
  }

  Future<void> loginCustomerGoogle() async {
    await customerAuth.signInWithGoogle();
    final identity = customerAuth.currentIdentity;
    if (identity != null && customerIdentity?.id != identity.id) {
      await _applyCustomerIdentity(identity);
    }
  }

  String _selectedKey(CustomerIdentity identity) =>
      'qpark_selected_supabase_${identity.id}';

  void _restoreDemoVehicles() {
    plates = List<String>.from(
      preferences.getStringList('qpark_plates_v3') ?? [],
    );
    selected = preferences.getString('qpark_selected_v3');
    if (!plates.contains(selected)) {
      selected = plates.isEmpty ? null : plates.first;
    }
    ticket = null;
  }

  Future<void> _applyCustomerIdentity(CustomerIdentity? identity) async {
    if (disposed) return;
    _contextEpoch++;
    final epoch = _contextEpoch;
    customerIdentity = identity;
    customerDemo = false;
    customerError = null;
    ticket = null;
    if (identity == null) {
      _restoreDemoVehicles();
      emit();
      return;
    }

    // Never expose the previous local/demo user's plates while cloud data loads.
    plates = [];
    selected = null;
    emit();
    final repository = customerData;
    if (repository == null) return;
    try {
      final cloudPlates = await repository.listVehicles(identity.id);
      if (disposed ||
          _contextEpoch != epoch ||
          customerIdentity?.id != identity.id) {
        return;
      }
      plates = cloudPlates;
      final saved = preferences.getString(_selectedKey(identity));
      selected = plates.contains(saved)
          ? saved
          : (plates.isEmpty ? null : plates.first);
      customerError = null;
      emit();
      await sync();
    } catch (caught) {
      // Authentication remains valid. Mutating actions will surface the actual
      // database error; keeping this list empty avoids cross-account leakage.
      if (customerIdentity?.id == identity.id) {
        customerError = caught is QParkException
            ? caught.message
            : 'Data kendaraan Supabase tidak dapat dimuat.';
        emit();
      }
    }
  }

  Future<void> refreshCustomerData() async {
    final identity = customerIdentity;
    if (identity != null) {
      plates = [];
      await _applyCustomerIdentity(identity);
    }
  }

  final RemoteRepository repository;
  final SharedPreferences preferences;
  List<String> plates = [];
  String? selected, token, username, error, customerError;
  String role = 'PENGENDARA';
  bool get admin => officer && role == 'ADMIN';
  Json? capacity, ticket;
  List<Json> sessions = [];
  final List<Json> _pending = [];
  String get operationOwner => officer
      ? 'staff:$token'
      : customerIdentity != null
      ? 'user:${customerIdentity!.id}'
      : 'demo:${repository.customerKey}';
  List<Json> get pending =>
      _pending.where((p) => p['owner'] == operationOwner).toList();
  int _contextEpoch = 0, consecutiveFailures = 0;
  bool foreground = true, _started = false, retrying = false;
  Future<void>? _syncFuture;
  final Map<String, Future<Json>> _posts = {};
  DateTime? lastSyncedAt;
  Duration get pollDelay => Duration(
    seconds: consecutiveFailures > 0
        ? min(60, 5 * (1 << min(consecutiveFailures - 1, 4)))
        : officer || (ticket != null && ticket!['state'] != 'COMPLETED')
        ? 5
        : 30,
  );

  final List<String> revoked = [];
  bool online = false, syncing = false, disposed = false;
  Timer? timer;
  double? _serverTime;
  final Stopwatch _elapsed = Stopwatch();
  double get serverNow =>
      (_serverTime ?? 0) + _elapsed.elapsedMilliseconds / 1000;
  bool get officer => token != null;
  void emit() {
    if (!disposed) notifyListeners();
  }

  void observe(Json r) {
    if (r['server_time'] is num) {
      _serverTime = (r['server_time'] as num).toDouble();
      _elapsed
        ..reset()
        ..start();
    }
  }

  String newKey() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void start() {
    if (_started || disposed) return;
    _started = true;
    if (foreground) unawaited(sync());
  }

  void setForeground(bool value) {
    if (foreground == value || disposed) return;
    foreground = value;
    timer?.cancel();
    if (value && _started) unawaited(sync());
  }

  void _schedule() {
    timer?.cancel();
    if (_started && foreground && !disposed) {
      timer = Timer(pollDelay, () => unawaited(sync()));
    }
  }

  Future<void> persistPending() async {
    // Staff queues only live in memory: no staff session tokens on disk here.
    await preferences.setString(
      'qpark_pending_v4',
      jsonEncode(
        _pending
            .where((p) => !(p['owner'] as String).startsWith('staff:'))
            .toList(),
      ),
    );
  }

  Future<void> sync() {
    if (disposed) return Future.value();
    return _syncFuture ??= _syncLoop().whenComplete(() {
      _syncFuture = null;
      _schedule();
    });
  }

  Future<void> _syncLoop() async {
    syncing = true;
    timer?.cancel();
    int epoch;
    do {
      epoch = _contextEpoch;
      await _syncOnce(epoch);
    } while (!disposed && foreground && epoch != _contextEpoch);
    syncing = false;
    emit();
  }

  void _expireStaff() {
    final oldOwner = operationOwner;
    token = null;
    username = null;
    role = 'PENGENDARA';
    sessions = [];
    ticket = null;
    _pending.removeWhere((p) => p['owner'] == oldOwner);
    _contextEpoch++;
    sessionNotice =
        'Sesi petugas berakhir. Masuk kembali untuk melanjutkan pelayanan.';
  }

  Future<void> _syncOnce(int epoch) async {
    final currentPlate = selected;
    final currentToken = token;
    try {
      final c = await repository.request('GET', '/api/capacity');
      for (final old in List<String>.from(revoked)) {
        await repository.request('POST', '/api/logout', token: old);
        revoked.remove(old);
        await preferences.setStringList('qpark_revocations_v3', revoked);
      }
      Json? nextTicket;
      if (currentPlate != null && currentToken == null) {
        final prior = (ticket?['plate']) == currentPlate
            ? (ticket?['id'])
            : null;
        final r = await repository.request(
          'GET',
          '/api/ticket?plate=${Uri.encodeComponent(currentPlate)}${prior == null ? '' : '&previous=$prior'}',
        );
        nextTicket = r['session'] as Json?;
      }
      List<Json> nextSessions = [];
      if (currentToken != null) {
        final r = await repository.request(
          'GET',
          '/api/officer/monitor',
          token: currentToken,
        );
        nextSessions = (r['sessions'] as List).cast<Json>();
      }
      if (disposed || epoch != _contextEpoch) return;
      observe(c);
      capacity = c;
      ticket = nextTicket;
      sessions = nextSessions;
      online = true;
      error = null;
      consecutiveFailures = 0;
      lastSyncedAt = DateTime.now();
    } on ApiError catch (e) {
      if (disposed || epoch != _contextEpoch) return;
      if (e.status == 401 && currentToken != null && token == currentToken) {
        _expireStaff();
      }
      if (e.status == 401 || e.status == 403) ticket = null;
      online = false;
      consecutiveFailures++;
      error = e.message;
    } catch (_) {
      if (disposed || epoch != _contextEpoch) return;
      online = false;
      consecutiveFailures++;
      error = 'Data belum dapat diperbarui. Coba lagi.';
    }
  }

  Future<void> savePlate(String value, {String? replacing}) async {
    final normal = normalizePlate(value);
    if (plates.contains(normal) && normal != replacing) {
      throw const QParkException('Nopol sudah tersimpan di perangkat ini.');
    }
    final next = List<String>.from(plates);
    if (replacing == null) {
      next.add(normal);
    } else {
      final index = next.indexOf(replacing);
      if (index >= 0) next[index] = normal;
    }
    final identity = customerIdentity;
    if (identity != null && customerData != null) {
      if (replacing == null) {
        await customerData!.addVehicle(identity.id, normal);
      } else {
        await customerData!.replaceVehicle(identity.id, replacing, normal);
      }
      customerError = null;
    } else {
      await preferences.setStringList('qpark_plates_v3', next);
    }
    if (customerIdentity?.id != identity?.id || disposed) return;
    plates = next;
    await selectPlate(normal);
  }

  Future<void> removePlate(String value) async {
    final next = plates.where((p) => p != value).toList();
    final identity = customerIdentity;
    if (identity != null && customerData != null) {
      await customerData!.removeVehicle(identity.id, value);
      customerError = null;
    } else {
      await preferences.setStringList('qpark_plates_v3', next);
    }
    if (customerIdentity?.id != identity?.id || disposed) return;
    plates = next;
    await selectPlate(
      selected == value ? (plates.isEmpty ? null : plates.first) : selected,
    );
  }

  Future<void> selectPlate(String? value) async {
    _contextEpoch++;
    selected = value;
    ticket = null;
    final key = customerIdentity == null
        ? 'qpark_selected_v3'
        : _selectedKey(customerIdentity!);
    if (value == null) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, value);
    }
    emit();
    await sync();
  }

  Future<Json> post(String path, Json body, {bool idempotent = false}) {
    final key = '$operationOwner:$path:${jsonEncode(body)}';
    return _posts.putIfAbsent(
      key,
      () => _post(path, body, idempotent: idempotent).whenComplete(() {
        _posts.remove(key);
      }),
    );
  }

  Future<Json> _post(String path, Json body, {bool idempotent = false}) async {
    final owner = operationOwner;
    final epoch = _contextEpoch;
    final currentToken = token;
    Json? operation;
    if (idempotent) {
      final signature = jsonEncode(body);
      final matches = pending.where(
        (p) => p['path'] == path && p['signature'] == signature,
      );
      operation = matches.isEmpty
          ? {
              'owner': owner,
              'path': path,
              'signature': signature,
              'body': {...body, 'operation_key': newKey()},
            }
          : matches.first;
      if (matches.isEmpty) {
        _pending.add(operation);
        await persistPending();
      }
      if (disposed || owner != operationOwner) {
        throw const ApiError(
          'Akun berubah. Periksa transaksi pada akun sebelumnya.',
          'account_changed',
          409,
        );
      }
      body = Map<String, dynamic>.from(operation['body'] as Map);
    }
    try {
      final r = await repository.request(
        'POST',
        path,
        body: body,
        token: currentToken,
      );
      observe(r);
      if (operation != null) {
        _pending.remove(operation);
        await persistPending();
      }
      if (disposed || owner != operationOwner || epoch != _contextEpoch) {
        return r;
      }
      online = true;
      error = null;
      if (r['session'] is Json && r['session']['plate'] == selected) {
        ticket = r['session'] as Json;
      }
      emit();
      unawaited(sync());
      return r;
    } on ApiError catch (e) {
      // HTTP 5xx may hide a committed transaction: retain the same key.
      if (operation != null && !e.retryable) {
        _pending.remove(operation);
        await persistPending();
      }
      if (disposed || owner != operationOwner || epoch != _contextEpoch) {
        rethrow;
      }
      if (e.retryable) online = false;
      if (e.status == 401 && currentToken != null && token == currentToken) {
        _expireStaff();
      }
      error = e.message;
      emit();
      rethrow;
    }
  }

  Future<void> retryPending() async {
    if (retrying) return;
    retrying = true;
    emit();
    final owner = operationOwner;
    try {
      for (final p in pending) {
        if (disposed || owner != operationOwner) break;
        // _post finds the stored key using the original body signature.
        await post(
          p['path'] as String,
          Map<String, dynamic>.from(
            jsonDecode(p['signature'] as String) as Map,
          ),
          idempotent: true,
        );
      }
      await sync();
    } finally {
      retrying = false;
      emit();
    }
  }

  Future<void> login(String name, String password) async {
    final r = await post('/api/login', {
      'username': name,
      'password': password,
    });
    if (customerIdentity != null) await customerAuth.signOut();
    customerDemo = false;
    customerIdentity = null;
    _contextEpoch++;
    ticket = null;
    token = r['token'] as String;
    username = r['username'] as String;
    role = r['role'] as String? ?? 'PETUGAS';
    sessionNotice = null;
    emit();
    await sync();
  }

  Future<void> logout() async {
    _contextEpoch++;
    ticket = null;
    final hadCustomer = customerIdentity != null;
    customerIdentity = null;
    customerDemo = false;
    final old = token;
    token = null;
    username = null;
    role = 'PENGENDARA';
    sessions = [];
    _pending.removeWhere(
      (p) =>
          ((p['path'] as String).startsWith('/api/officer/') ||
          (p['path'] as String).startsWith('/api/admin/')),
    );
    emit();
    if (old != null) {
      revoked.add(old);
      await preferences.setStringList('qpark_revocations_v3', revoked);
    }
    await persistPending();
    if (hadCustomer) {
      try {
        await customerAuth.signOut().timeout(const Duration(seconds: 12));
      } catch (_) {
        sessionNotice =
            'Aplikasi sudah dikunci. Keluar dari Google belum terkonfirmasi; sambungkan internet dan masuk kembali untuk menyelesaikannya.';
        emit();
        return;
      }
    }
    await sync();
  }

  @override
  void dispose() {
    disposed = true;
    timer?.cancel();
    unawaited(_authSubscription?.cancel());
    repository.close();
    super.dispose();
  }
}
