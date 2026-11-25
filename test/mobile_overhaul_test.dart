import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/logic/remote_service.dart';
import 'package:qpark/ui/app.dart';

Future<void> pumpSettle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'Mobile-first customer UI: Home, Dompet top-up, Scan QR Pay, Akun, and multi-location cards',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      var balance = 0;
      final txs = <Json>[];
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
          'rates': {'MOBIL': 7000, 'MOTOR': 2000},
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
          'rates': {'MOBIL': 6000, 'MOTOR': 2000},
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
              'server_time': 1800000100,
            }),
            200,
          );
        }
        if (path == '/api/customer/vehicle-types') {
          return http.Response(jsonEncode({'vehicle_types': {}}), 200);
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

      final service = RemoteService(
        RemoteRepository('http://test', client: client),
        await SharedPreferences.getInstance(),
      );
      await tester.pumpWidget(QParkApp(initialize: () async => service));
      await pumpSettle(tester);

      await tester.ensureVisible(find.byKey(const Key('customer-demo')));
      await tester.tap(find.byKey(const Key('customer-demo')));
      await pumpSettle(tester);

      // Mobile bottom bar has 4 tabs + center Scan QR FAB.
      expect(find.byKey(const Key('nav-0')), findsOneWidget);
      expect(find.byKey(const Key('nav-1')), findsOneWidget);
      expect(find.byKey(const Key('nav-2')), findsOneWidget);
      expect(find.byKey(const Key('nav-3')), findsOneWidget);
      expect(find.byKey(const Key('fab-scan-qr')), findsOneWidget);

      // Home displays both locations and floating wallet card.
      expect(find.byKey(const Key('home-wallet-card')), findsOneWidget);
      expect(find.text('QPark Mall Sentral'), findsWidgets);
      expect(find.text('QPark Gedung Merdeka'), findsWidgets);

      // Navigate to Dompet tab and top up Rp50.000.
      await tester.tap(find.byKey(const Key('nav-2')));
      await pumpSettle(tester);
      await tester.ensureVisible(find.byKey(const Key('wallet-topup-submit')));
      await tester.tap(find.byKey(const Key('wallet-topup-submit')));
      await pumpSettle(tester);
      expect(balance, 50000);
      expect(find.text('Rp50.000'), findsWidgets);

      // Navigate to Akun tab.
      await tester.tap(find.byKey(const Key('nav-3')));
      await pumpSettle(tester);
      expect(find.text('Pengaturan & Akses'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
