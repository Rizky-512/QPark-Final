import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/logic/customer_auth.dart';
import 'package:qpark/logic/remote_service.dart';
import 'package:qpark/ui/app.dart';

Future<void> pumpSettle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _FakeGoogleAuth implements CustomerAuthProvider {
  CustomerIdentity? _id;
  final _ctrl = StreamController<CustomerIdentity?>.broadcast();
  @override
  bool get googleAvailable => true;
  @override
  CustomerIdentity? get currentIdentity => _id;
  @override
  Stream<CustomerIdentity?> get authStateChanges => _ctrl.stream;
  @override
  Future<void> signInWithGoogle() async {
    _id = const CustomerIdentity(id: 'g-1', displayName: 'Rizky Google');
    _ctrl.add(_id);
  }

  @override
  Future<void> signOut() async {
    _id = null;
    _ctrl.add(null);
  }

  Future<void> close() => _ctrl.close();
}

void main() {
  testWidgets(
    'Mobile-first v6: Direct Home without Google login, Dompet QPark, EV blue-plate booking, auto-slide, Promos, and Google-gated theme',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});

      var balance = 0;
      final txs = <Json>[];
      final types = <String, String>{};
      final evPlates = <String, bool>{};
      final evBookings = <Json>[];
      final locations = [
        {
          'id': 'LOC-DEFAULT',
          'name': 'QPark Mall Sentral',
          'address': 'Jl. Sudirman 1',
          'active': true,
          'total': 20,
          'occupied': 2,
          'available': 18,
          'full': false,
          'categories': {
            'MOBIL': {
              'total': 10,
              'occupied': 1,
              'available': 9,
              'full': false,
            },
            'MOTOR': {
              'total': 10,
              'occupied': 1,
              'available': 9,
              'full': false,
            },
          },
          'ev': {
            'total': 4,
            'occupied': 0,
            'available': 4,
            'full': false,
            'rate': 10000,
          },
          'rates': {'MOBIL': 7000, 'MOTOR': 2000, 'EV': 10000},
        },
        {
          'id': 'LOC-2',
          'name': 'QPark Gedung Merdeka',
          'address': 'Jl. Merdeka 45',
          'active': true,
          'total': 35,
          'occupied': 0,
          'available': 35,
          'full': false,
          'categories': {
            'MOBIL': {
              'total': 15,
              'occupied': 0,
              'available': 15,
              'full': false,
            },
            'MOTOR': {
              'total': 20,
              'occupied': 0,
              'available': 20,
              'full': false,
            },
          },
          'ev': {
            'total': 6,
            'occupied': 1,
            'available': 5,
            'full': false,
            'rate': 9000,
          },
          'rates': {'MOBIL': 6000, 'MOTOR': 2000, 'EV': 9000},
        },
      ];
      final promos = [
        {
          'id': 'PRM-1',
          'location_id': 'LOC-DEFAULT',
          'location_name': 'QPark Mall Sentral',
          'title': 'Diskon Parkir 20% Sentral',
          'description': 'Khusus Dompet QPark',
          'code': 'SENTRAL20',
          'discount_type': 'PERCENT',
          'discount_value': 20,
          'starts_at': 1800000000,
          'ends_at': 1802000000,
          'active': true,
        },
      ];

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path == '/api/capacity') {
          final locId = req.url.queryParameters['location_id'] ?? 'LOC-DEFAULT';
          final loc = locations.firstWhere(
            (l) => l['id'] == locId,
            orElse: () => locations.first,
          );
          return http.Response(
            jsonEncode({
              ...loc,
              'location': loc,
              'locations': locations,
              'promos': promos,
              'server_time': 1800000100,
            }),
            200,
          );
        }
        if (path == '/api/promos') {
          return http.Response(
            jsonEncode({'promos': promos, 'server_time': 1800000100}),
            200,
          );
        }
        if (path == '/api/ev/bookings') {
          return http.Response(
            jsonEncode({'bookings': evBookings, 'server_time': 1800000100}),
            200,
          );
        }
        if (path == '/api/ev/book') {
          final body = jsonDecode(req.body) as Json;
          final b = {
            'id': 'EVB-1',
            'location_id': body['location_id'],
            'location_name': 'QPark Mall Sentral',
            'plate': body['plate'],
            'duration_hours': body['duration_hours'],
            'hourly_rate': 10000,
            'estimated_cost': 10000 * (body['duration_hours'] as int),
            'status': 'ACTIVE',
            'booked_at': 1800000100,
            'expires_at': 1800003700,
          };
          evBookings.insert(0, b);
          return http.Response(
            jsonEncode({
              'booking': b,
              'bookings': evBookings,
              'server_time': 1800000100,
            }),
            200,
          );
        }
        if (path == '/api/customer/vehicle-types') {
          return http.Response(
            jsonEncode({'vehicle_types': types, 'ev_plates': evPlates}),
            200,
          );
        }
        if (path == '/api/customer/vehicle-type') {
          final body = jsonDecode(req.body) as Json;
          types[body['plate'] as String] = body['vehicle_type'] as String;
          evPlates[body['plate'] as String] = body['is_ev'] == true;
          return http.Response(
            jsonEncode({
              'vehicle_type': body['vehicle_type'],
              'is_ev': body['is_ev'] == true,
            }),
            200,
          );
        }
        if (path == '/api/wallet') {
          return http.Response(
            jsonEncode({
              'balance': balance,
              'transactions': txs,
              'server_time': 1800000100,
            }),
            200,
          );
        }
        if (path == '/api/wallet/topup') {
          final body = jsonDecode(req.body) as Json;
          final amt = body['amount'] as int;
          balance += amt;
          txs.insert(0, {
            'id': 'WLT-1',
            'kind': 'TOPUP',
            'amount': amt,
            'balance_after': balance,
            'description': 'Top up saldo Dompet QPark (simulasi)',
            'created_at': 1800000100,
          });
          return http.Response(
            jsonEncode({
              'balance': balance,
              'transactions': txs,
              'server_time': 1800000100,
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'server_time': 1800000100}), 200);
      });

      final auth = _FakeGoogleAuth();
      addTearDown(auth.close);
      final service = RemoteService(
        RemoteRepository('http://test', client: client),
        await SharedPreferences.getInstance(),
        customerAuth: auth,
      );
      await tester.pumpWidget(QParkApp(initialize: () async => service));
      await pumpSettle(tester);

      // Opens directly to Home without Google login gate!
      expect(find.byKey(const Key('home-wallet-card')), findsOneWidget);
      expect(find.byKey(const Key('quick-book-ev')), findsOneWidget);
      expect(find.byKey(const Key('quick-vehicle')), findsOneWidget);
      expect(find.byKey(const Key('quick-topup')), findsOneWidget);
      expect(find.byKey(const Key('quick-qr')), findsOneWidget);
      expect(find.byKey(const Key('availability-slider')), findsOneWidget);
      expect(find.text('Diskon Parkir 20% Sentral'), findsOneWidget);
      expect(find.byKey(const Key('fab-scan-qr')), findsOneWidget);

      // Register a blue-plate EV via Kendaraan icon.
      await tester.tap(find.byKey(const Key('quick-vehicle')));
      await pumpSettle(tester);
      await tester.enterText(
        find.byKey(const Key('vehicle-plate')),
        'B 900 EV',
      );
      await tester.tap(find.byKey(const Key('vehicle-category')));
      await pumpSettle(tester);
      await tester.tap(find.text('Mobil').last);
      await pumpSettle(tester);
      await tester.tap(find.byKey(const Key('vehicle-is-ev')));
      await pumpSettle(tester);
      await tester.tap(find.text('Simpan'));
      await pumpSettle(tester);
      expect(service.evPlates['B900EV'], isTrue);

      // Book EV using the registered blue plate.
      await tester.tap(find.byKey(const Key('quick-book-ev')));
      await pumpSettle(tester);
      await tester.ensureVisible(find.byKey(const Key('ev-book-submit')));
      await tester.tap(find.byKey(const Key('ev-book-submit')));
      await pumpSettle(tester);
      expect(evBookings.length, 1);
      Navigator.of(
        tester.element(find.byKey(const Key('ev-book-submit'))),
      ).pop();
      await pumpSettle(tester);

      // Dompet top-up works without Google login.
      await tester.tap(find.byKey(const Key('nav-2')));
      await pumpSettle(tester);
      await tester.ensureVisible(find.byKey(const Key('wallet-topup-submit')));
      await tester.tap(find.byKey(const Key('wallet-topup-submit')));
      await pumpSettle(tester);
      expect(balance, 50000);

      // Akun tab: theme customization is locked before Google login.
      await tester.tap(find.byKey(const Key('nav-3')));
      await pumpSettle(tester);
      expect(find.byKey(const Key('theme-dark-toggle')), findsNothing);
      expect(find.byKey(const Key('account-google-login')), findsOneWidget);

      // Sign in with Google -> Dark Mode & color customization unlock!
      await tester.ensureVisible(find.byKey(const Key('account-google-login')));
      await tester.tap(find.byKey(const Key('account-google-login')));
      await pumpSettle(tester);
      expect(service.canCustomizeAppearance, isTrue);
      await tester.tap(find.byKey(const Key('nav-3')));
      await pumpSettle(tester);
      expect(find.byKey(const Key('theme-dark-toggle')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('theme-dark-toggle')));
      await tester.tap(find.byKey(const Key('theme-dark-toggle')));
      await pumpSettle(tester);
      expect(service.activeDarkMode, isTrue);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
