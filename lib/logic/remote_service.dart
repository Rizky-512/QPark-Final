import 'dart:async';
import 'customer_auth.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/customer_repository.dart';
import '../data/remote_repository.dart';
import '../data/scoped_preferences.dart';
import '../domain/errors.dart';
import '../domain/rules.dart';

/// Account-scoped operations and adaptive, single-flight synchronization.
class RemoteService extends ChangeNotifier {
  RemoteService(
    this.repository,
    SharedPreferences store, {
    String storageNamespace = '',
    this.customerAuth = const PendingSupabaseAuth(),
    this.customerData,
  }) : preferences = ScopedPreferences(store, storageNamespace) {
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
    unawaited(
      refreshVehicleTypes().catchError((Object e) {
        if (!disposed && customerDemo) {
          customerError =
              'Kategori kendaraan belum dapat dimuat. Coba lagi saat koneksi tersedia.';
          emit();
        }
      }),
    );
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

  final Map<String, String> vehicleTypes = {};
  final Map<String, bool> evPlates = {};

  List<String> get registeredEvPlates =>
      plates.where((p) => evPlates[p] == true).toList();

  Future<void> refreshVehicleTypes() async {
    final owner = operationOwner;
    final r = await repository.request('GET', '/api/customer/vehicle-types');
    if (disposed || operationOwner != owner) return;
    vehicleTypes
      ..clear()
      ..addAll(Map<String, String>.from(r['vehicle_types'] as Map? ?? {}));
    if (r['ev_plates'] is Map) {
      evPlates
        ..clear()
        ..addAll(
          (r['ev_plates'] as Map).map(
            (k, v) => MapEntry(k.toString(), v == true),
          ),
        );
    }
    emit();
  }

  void _restoreDemoVehicles() {
    vehicleTypes.clear();
    evPlates.clear();
    plates = List<String>.from(
      preferences.getStringList('qpark_plates_v3') ?? [],
    );
    final savedEv = preferences.getStringList('qpark_ev_plates_v1') ?? [];
    for (final p in savedEv) {
      evPlates[p] = true;
    }
    selected = preferences.getString('qpark_selected_v3');
    if (!plates.contains(selected)) {
      selected = plates.isEmpty ? null : plates.first;
    }
    ticket = null;
  }

  // Google-gated theme & profile customization (per Google user ID).
  bool darkMode = false;
  int themeColorValue = 0xFF166534;
  String? customAvatarBase64;
  bool get canCustomizeAppearance => customerIdentity != null;
  bool get activeDarkMode => canCustomizeAppearance && darkMode;
  int get activeThemeColorValue =>
      canCustomizeAppearance ? themeColorValue : 0xFF166534;
  String? get activeCustomAvatarBase64 =>
      canCustomizeAppearance ? customAvatarBase64 : null;

  void _loadAppearance(CustomerIdentity? identity) {
    if (identity == null) {
      darkMode = false;
      themeColorValue = 0xFF166534;
      customAvatarBase64 = null;
      return;
    }
    final uid = identity.id;
    darkMode = preferences.getString('qpark_theme_dark_$uid') == '1';
    themeColorValue =
        int.tryParse(preferences.getString('qpark_theme_color_$uid') ?? '') ??
        0xFF166534;
    customAvatarBase64 = preferences.getString('qpark_avatar_$uid');
  }

  Future<void> setDarkMode(bool value) async {
    final identity = customerIdentity;
    if (identity == null) return;
    darkMode = value;
    await preferences.setString(
      'qpark_theme_dark_${identity.id}',
      value ? '1' : '0',
    );
    emit();
  }

  Future<void> setThemeColor(int argb) async {
    final identity = customerIdentity;
    if (identity == null) return;
    themeColorValue = argb;
    await preferences.setString('qpark_theme_color_${identity.id}', '$argb');
    emit();
  }

  Future<void> setCustomAvatarBase64(String? b64) async {
    final identity = customerIdentity;
    if (identity == null) return;
    customAvatarBase64 = b64;
    final key = 'qpark_avatar_${identity.id}';
    if (b64 == null || b64.isEmpty) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, b64);
    }
    emit();
  }

  Future<void> _applyCustomerIdentity(CustomerIdentity? identity) async {
    if (disposed) return;
    _contextEpoch++;
    final epoch = _contextEpoch;
    customerIdentity = identity;
    customerDemo = false;
    customerError = null;
    ticket = null;
    _loadAppearance(identity);
    if (identity == null) {
      _restoreDemoVehicles();
      emit();
      return;
    }

    // Never expose the previous local/demo user's plates while cloud data loads.
    plates = [];
    vehicleTypes.clear();
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
      await refreshVehicleTypes();
      if (disposed || _contextEpoch != epoch) return;
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
  final ScopedPreferences preferences;
  List<String> plates = [];
  String? selected, token, username, error, customerError;
  String? staffLocationId, staffLocationName, selectedLocationId;
  String role = 'PENGENDARA';
  bool get superadmin => officer && role == 'SUPERADMIN';
  bool get admin => officer && (role == 'ADMIN' || role == 'SUPERADMIN');
  String get roleLabel => switch (role) {
    'SUPERADMIN' => 'Superadmin',
    'ADMIN' => 'Pengelola',
    'PETUGAS' => 'Petugas',
    _ => 'Pengendara',
  };
  String? get activeLocationId => officer
      ? (superadmin ? selectedLocationId : staffLocationId)
      : selectedLocationId;
  Json? capacity, ticket;
  List<Json> locations = [];
  List<Json> promos = [];
  List<Json> evBookings = [];
  List<Json> sessions = [];
  int walletBalance = 0;
  List<Json> walletTransactions = [];
  bool walletLoaded = false;
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
    // Publish after sync() has stored its shared future, so UI listeners cannot
    // accidentally start a second request while showing refresh feedback.
    scheduleMicrotask(() {
      if (syncing) emit();
    });
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
    staffLocationId = null;
    staffLocationName = null;
    role = 'PENGENDARA';
    sessions = [];
    ticket = null;
    _pending.removeWhere((p) => p['owner'] == oldOwner);
    _contextEpoch++;
    sessionNotice =
        'Sesi petugas berakhir. Masuk kembali untuk melanjutkan pelayanan.';
  }

  void selectLocation(String? locationId) {
    if (selectedLocationId == locationId) return;
    _contextEpoch++;
    selectedLocationId = locationId;
    emit();
    unawaited(sync());
  }

  Future<void> refreshWallet() async {
    if (officer || !signedIn) return;
    final owner = operationOwner;
    final r = await repository.request('GET', '/api/wallet');
    if (disposed || operationOwner != owner) return;
    observe(r);
    walletBalance = (r['balance'] as num?)?.toInt() ?? 0;
    walletTransactions = ((r['transactions'] as List?) ?? const [])
        .cast<Json>();
    walletLoaded = true;
    emit();
  }

  Future<Json> topUpWallet(int amount) async {
    final r = await post('/api/wallet/topup', {
      'amount': amount,
    }, idempotent: true);
    if (!disposed) {
      walletBalance = (r['balance'] as num?)?.toInt() ?? walletBalance;
      if (r['transactions'] is List) {
        walletTransactions = (r['transactions'] as List).cast<Json>();
      }
      walletLoaded = true;
      emit();
    }
    return r;
  }

  Future<Json> inspectPaymentQr(String qr) =>
      repository.request('POST', '/api/wallet/inspect', body: {'qr': qr});

  Future<void> refreshEvBookings() async {
    if (officer || !signedIn) return;
    final owner = operationOwner;
    final r = await repository.request('GET', '/api/ev/bookings');
    if (disposed || operationOwner != owner) return;
    observe(r);
    if (r['bookings'] is List) {
      evBookings = (r['bookings'] as List).cast<Json>();
      emit();
    }
  }

  Future<Json> bookEv({
    required String locationId,
    required String plate,
    required int durationHours,
  }) async {
    final r = await post('/api/ev/book', {
      'location_id': locationId,
      'plate': plate,
      'duration_hours': durationHours,
    }, idempotent: true);
    if (!disposed && r['bookings'] is List) {
      evBookings = (r['bookings'] as List).cast<Json>();
      emit();
    }
    return r;
  }

  Future<Json> cancelEvBooking(String bookingId) async {
    final r = await post('/api/ev/cancel', {
      'booking_id': bookingId,
    }, idempotent: true);
    if (!disposed && r['bookings'] is List) {
      evBookings = (r['bookings'] as List).cast<Json>();
      emit();
    }
    return r;
  }

  Future<Json> payWithWallet({
    String? qr,
    String? invoiceId,
    String? promoId,
  }) async {
    final r = await post('/api/wallet/pay', {
      'qr': ?qr,
      'invoice_id': ?invoiceId,
      'promo_id': ?promoId,
    }, idempotent: true);
    if (!disposed) {
      if (r['balance'] is num) {
        walletBalance = (r['balance'] as num).toInt();
        walletLoaded = true;
      }
      if (r['session'] is Json) {
        final session = r['session'] as Json;
        final sessionPlate = session['plate'] as String?;
        if (sessionPlate != null &&
            (selected == null || selected == sessionPlate)) {
          ticket = session;
        }
      }
      emit();
      unawaited(refreshWallet().catchError((_) {}));
    }
    return r;
  }

  Future<void> _syncOnce(int epoch) async {
    final currentPlate = selected;
    final currentToken = token;
    final locParam = activeLocationId;
    try {
      final capPath = locParam == null
          ? '/api/capacity'
          : '/api/capacity?location_id=${Uri.encodeComponent(locParam)}';
      final c = await repository.request('GET', capPath, token: currentToken);
      for (final old in List<String>.from(revoked)) {
        await repository.request('POST', '/api/logout', token: old);
        revoked.remove(old);
        await preferences.setStringList('qpark_revocations_v3', revoked);
      }
      Json? nextTicket;
      if (signedIn && currentPlate != null && currentToken == null) {
        final prior = (ticket?['plate']) == currentPlate
            ? (ticket?['id'])
            : null;
        final r = await repository.request(
          'GET',
          '/api/ticket?plate=${Uri.encodeComponent(currentPlate)}${prior == null ? '' : '&previous=$prior'}',
        );
        nextTicket = r['session'] as Json?;
      }
      int nextBalance = walletBalance;
      List<Json> nextWalletTxs = walletTransactions;
      bool nextWalletLoaded = walletLoaded;
      final hasV5Backend = c['locations'] is List;
      if (signedIn && currentToken == null && hasV5Backend) {
        try {
          final w = await repository.request('GET', '/api/wallet');
          if (w['balance'] is num) {
            nextBalance = (w['balance'] as num).toInt();
            nextWalletTxs = ((w['transactions'] as List?) ?? const [])
                .cast<Json>();
            nextWalletLoaded = true;
          }
        } catch (_) {
          // Keep previous wallet state if server doesn't expose wallet yet.
        }
      }
      List<Json> nextEvBookings = evBookings;
      if (signedIn && currentToken == null && hasV5Backend) {
        try {
          final eb = await repository.request('GET', '/api/ev/bookings');
          if (eb['bookings'] is List) {
            nextEvBookings = (eb['bookings'] as List).cast<Json>();
          }
        } catch (_) {}
      }
      List<Json> nextSessions = [];
      if (currentToken != null) {
        final monitorPath = superadmin && locParam != null
            ? '/api/officer/monitor?location_id=${Uri.encodeComponent(locParam)}'
            : '/api/officer/monitor';
        final r = await repository.request(
          'GET',
          monitorPath,
          token: currentToken,
        );
        nextSessions = (r['sessions'] as List).cast<Json>();
      }
      if (disposed || epoch != _contextEpoch) return;
      observe(c);
      capacity = c;
      if (c['locations'] is List) {
        locations = (c['locations'] as List).cast<Json>();
      }
      if (c['promos'] is List) {
        promos = (c['promos'] as List).cast<Json>();
      }
      evBookings = nextEvBookings;
      ticket = nextTicket;
      sessions = nextSessions;
      walletBalance = nextBalance;
      walletTransactions = nextWalletTxs;
      walletLoaded = nextWalletLoaded;
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

  Future<void> savePlate(
    String value, {
    String? replacing,
    String? vehicleType,
    bool isEv = false,
  }) async {
    final normal = normalizePlate(value);
    if (plates.contains(normal) && normal != replacing) {
      throw const QParkException('Nopol sudah tersimpan di perangkat ini.');
    }
    final owner = operationOwner;
    if (vehicleType != null) {
      await repository.request(
        'POST',
        '/api/customer/vehicle-type',
        body: {'plate': normal, 'vehicle_type': vehicleType, 'is_ev': isEv},
      );
      if (disposed || operationOwner != owner) return;
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
    if (vehicleType != null) {
      vehicleTypes[normal] = vehicleType;
      evPlates[normal] = isEv;
    }
    if (replacing != null && replacing != normal) {
      evPlates.remove(replacing);
      if (vehicleTypes.containsKey(replacing)) {
        await repository.request(
          'POST',
          '/api/customer/vehicle-type',
          body: {'plate': replacing, 'remove': true},
        );
        vehicleTypes.remove(replacing);
      }
    }
    if (identity == null) {
      await preferences.setStringList(
        'qpark_ev_plates_v1',
        evPlates.entries.where((e) => e.value).map((e) => e.key).toList(),
      );
    }
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
    if (vehicleTypes.containsKey(value)) {
      await repository.request(
        'POST',
        '/api/customer/vehicle-type',
        body: {'plate': value, 'remove': true},
      );
    }
    if (customerIdentity?.id != identity?.id || disposed) return;
    vehicleTypes.remove(value);
    evPlates.remove(value);
    if (identity == null) {
      await preferences.setStringList(
        'qpark_ev_plates_v1',
        evPlates.entries.where((e) => e.value).map((e) => e.key).toList(),
      );
    }
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
    staffLocationId = r['location_id'] as String?;
    staffLocationName = r['location_name'] as String?;
    selectedLocationId = staffLocationId;
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
    staffLocationId = null;
    staffLocationName = null;
    selectedLocationId = null;
    role = 'PENGENDARA';
    sessions = [];
    walletBalance = 0;
    walletTransactions = [];
    walletLoaded = false;
    evBookings = [];
    _loadAppearance(null);
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
