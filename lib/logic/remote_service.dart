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

/// Orchestrates local vehicle choices and server state. Poll interval: 2 seconds.
class RemoteService extends ChangeNotifier {
  RemoteService(
    this.repository,
    this.preferences, {
    this.customerAuth = const PendingSupabaseAuth(),
    this.customerData,
  }) {
    _restoreDemoVehicles();
    final raw = preferences.getString('qpark_pending_v3');
    if (raw != null) {
      try {
        pending.addAll((jsonDecode(raw) as List).cast<Json>());
      } catch (_) {
        /* retain corrupt raw, do not fabricate success */
      }
    }
    revoked.addAll(preferences.getStringList('qpark_revocations_v3') ?? []);
    // Session credentials never persist; officer intents from a prior process cannot replay without login.
    pending.removeWhere(
      (p) =>
          ((p['path'] as String).startsWith('/api/officer/') ||
          (p['path'] as String).startsWith('/api/admin/')),
    );
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
    customerIdentity = null;
    customerDemo = true;
    sessionNotice = null;
    _restoreDemoVehicles();
    emit();
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
      if (customerIdentity?.id != identity.id) return;
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
    if (identity != null) await _applyCustomerIdentity(identity);
  }

  final RemoteRepository repository;
  final SharedPreferences preferences;
  List<String> plates = [];
  String? selected, token, username, error, customerError;
  String role = 'PENGENDARA';
  bool get admin => officer && role == 'ADMIN';
  Json? capacity, ticket;
  List<Json> sessions = [];
  final List<Json> pending = [];
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
    unawaited(sync());
    timer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(sync()),
    );
  }

  Future<void> persistPending() async =>
      preferences.setString('qpark_pending_v3', jsonEncode(pending));
  Future<void> sync() async {
    if (syncing || disposed) return;
    syncing = true;
    try {
      final c = await repository.request('GET', '/api/capacity');
      observe(c);
      for (final old in List<String>.from(revoked)) {
        await repository.request('POST', '/api/logout', token: old);
        revoked.remove(old);
        await preferences.setStringList('qpark_revocations_v3', revoked);
      }
      Json? nextTicket;
      final currentPlate = selected;
      if (currentPlate != null) {
        final prior = (ticket?['plate']) == currentPlate
            ? (ticket?['id'])
            : null;
        final r = await repository.request(
          'GET',
          '/api/ticket?plate=${Uri.encodeComponent(currentPlate)}${prior == null ? '' : '&previous=$prior'}',
        );
        nextTicket = r['session'] as Json?;
        observe(r);
      }
      List<Json> nextSessions = [];
      final currentToken = token;
      if (currentToken != null) {
        final r = await repository.request(
          'GET',
          '/api/officer/monitor',
          token: currentToken,
        );
        observe(r);
        nextSessions = (r['sessions'] as List).cast<Json>();
      }
      capacity = c;
      if (selected == currentPlate) ticket = nextTicket;
      if (token == currentToken) sessions = nextSessions;
      online = true;
      error = null;
    } on ApiError catch (e) {
      if (e.status == 401 && token != null) {
        sessionNotice =
            'Sesi petugas berakhir. Masuk kembali untuk melanjutkan pelayanan.';
        token = null;
        username = null;
        role = 'PENGENDARA';
        sessions = [];
      }
      online = false;
      error = e.message;
    } finally {
      syncing = false;
      emit();
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
    plates = next;
    await selectPlate(
      selected == value ? (plates.isEmpty ? null : plates.first) : selected,
    );
  }

  Future<void> selectPlate(String? value) async {
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

  Future<Json> post(String path, Json body, {bool idempotent = false}) async {
    Json? operation;
    if (idempotent) {
      final signature = jsonEncode(body);
      final matches = pending.where(
        (p) => p['path'] == path && p['signature'] == signature,
      );
      operation = matches.isEmpty
          ? {
              'path': path,
              'signature': signature,
              'body': {...body, 'operation_key': newKey()},
            }
          : matches.first;
      if (matches.isEmpty) {
        pending.add(operation);
        await persistPending();
      }
      body = Map<String, dynamic>.from(operation['body'] as Map);
    }
    try {
      final r = await repository.request(
        'POST',
        path,
        body: body,
        token: token,
      );
      observe(r);
      online = true;
      error = null;
      if (operation != null) {
        pending.remove(operation);
        await persistPending();
      }
      if (r['session'] is Json && r['session']['plate'] == selected) {
        ticket = r['session'] as Json;
      }
      emit();
      await sync();
      return r;
    } on ApiError catch (e) {
      // HTTP 5xx may hide a committed transaction: retain the same key.
      if (operation != null && e.status >= 400 && e.status < 500) {
        pending.remove(operation);
        await persistPending();
      }
      if (e.status == 0 || e.status >= 500) online = false;
      if (e.status == 401 && token != null) {
        sessionNotice =
            'Sesi petugas berakhir. Masuk kembali untuk melanjutkan pelayanan.';
        token = null;
        username = null;
        role = 'PENGENDARA';
        sessions = [];
      }
      error = e.message;
      emit();
      rethrow;
    }
  }

  Future<void> retryPending() async {
    await sync();
    for (final p in List<Json>.from(pending)) {
      final path = p['path'] as String;
      if (path.startsWith('/api/officer/') && !officer) continue;
      try {
        final r = await repository.request(
          'POST',
          path,
          body: Map<String, dynamic>.from(p['body'] as Map),
          token: token,
        );
        observe(r);
        pending.remove(p);
        await persistPending();
      } on ApiError catch (e) {
        if (e.status >= 400 && e.status < 500) {
          pending.remove(p);
          await persistPending();
        }
        error = e.message;
        emit();
        rethrow;
      }
    }
    await sync();
  }

  Future<void> login(String name, String password) async {
    final r = await post('/api/login', {
      'username': name,
      'password': password,
    });
    if (customerIdentity != null) await customerAuth.signOut();
    customerDemo = false;
    customerIdentity = null;
    token = r['token'] as String;
    username = r['username'] as String;
    role = r['role'] as String? ?? 'PETUGAS';
    sessionNotice = null;
    emit();
    await sync();
  }

  Future<void> logout() async {
    if (customerIdentity != null) await customerAuth.signOut();
    customerIdentity = null;
    customerDemo = false;
    final old = token;
    token = null;
    username = null;
    role = 'PENGENDARA';
    sessions = [];
    pending.removeWhere(
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
