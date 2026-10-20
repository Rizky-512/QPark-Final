import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/logic/remote_service.dart';
import 'package:qpark/ui/app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Json ticket() => {
  'id': 'QP-test-session',
  'plate': 'B123AB',
  'entered_at': 1800000000,
  'state': 'IN_AREA',
  'duration_seconds': 100,
  'amount_paid': 0,
  'window_status': 'NONE',
  'window': null,
  'authorization': null,
  'payment_status': 'Belum dibayar',
  'invoices': <Json>[],
  'exit_qr': null,
};
void main() {
  for (final role in ['ADMIN', 'PETUGAS']) {
    testWidgets('direct staff login from customer landing: $role', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final service = RemoteService(
        RemoteRepository(
          'http://test',
          client: MockClient((req) async {
            final Json data = {
              'server_time': 1800000100,
              'total': 20,
              'occupied': 0,
              'available': 20,
              'full': false,
              'sessions': <Json>[],
            };
            if (req.url.path == '/api/login') {
              data.addAll({
                'role': role,
                'username': 'tester',
                'token': 'token',
              });
            }
            if (req.url.path == '/api/admin/settings') {
              data['settings'] = {
                'capacity': 20,
                'car_rate': 7000,
                'motor_rate': 2000,
              };
            }
            if (req.url.path == '/api/admin/users') {
              data['users'] = <Json>[];
            }
            return http.Response(jsonEncode(data), 200);
          }),
        ),
        await SharedPreferences.getInstance(),
      );
      await tester.pumpWidget(QParkApp(initialize: () async => service));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('officer-login')));
      await tester.tap(find.byKey(const Key('officer-login')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('login-username')), 'tester');
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'password123',
      );
      await tester.ensureVisible(find.byKey(const Key('login-submit')));
      await tester.tap(find.byKey(const Key('login-submit')));
      await settle(tester);
      expect(find.text('Ringkasan parkir'), findsOneWidget);
      expect(service.role, role);
      expect(service.customerDemo, isFalse);
      expect(
        find.byKey(const Key('nav-5')),
        role == 'ADMIN' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final role in ['PETUGAS', 'ADMIN']) {
    for (final size in [const Size(360, 800), const Size(1280, 720)]) {
      testWidgets(
        'AT01/36 existing theme, customer login and officer pages ${size.width} $role',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({
            'qpark_plates_v3': ['B123AB'],
            'qpark_selected_v3': 'B123AB',
          });
          final prefs = await SharedPreferences.getInstance();
          final client = MockClient((req) async {
            Json data = {'server_time': 1800000100};
            if (req.url.path == '/api/capacity') {
              data.addAll({
                'total': 20,
                'occupied': 1,
                'available': 19,
                'full': false,
              });
            }
            if (req.url.path == '/api/ticket') data['session'] = ticket();
            if (req.url.path == '/api/officer/monitor') {
              data['sessions'] = [ticket()];
            }
            if (req.url.path == '/api/login') {
              data.addAll({
                'token': 'test-token',
                'username': 'petugas',
                'role': role,
              });
            }
            if (req.url.path == '/api/admin/analytics') {
              data.addAll({
                'from_date': '2026-10-01',
                'to_date': '2026-10-07',
                'arrivals': 0,
                'completed_count': 0,
                'excluded_active_count': 0,
                'mean_minutes': null,
                'median_minutes': null,
                'occupancy_pct': 0,
                'peak_occupied': 0,
                'busiest': null,
                'vehicles': {'MOBIL': 0, 'MOTOR': 0},
                'payments': {
                  'QR_SIMULASI': {'count': 0, 'amount': 0},
                  'MANUAL': {'count': 0, 'amount': 0},
                },
                'daily': [
                  {'date': '2026-10-07', 'arrivals': 0, 'occupancy_pct': 0},
                ],
                'hourly': List.generate(24, (i) => {'hour': i, 'arrivals': 0}),
                'weekdays': List.generate(
                  7,
                  (i) => {'label': 'Hari $i', 'arrivals': 0},
                ),
                'heatmap': <Json>[],
              });
            }
            if (req.url.path == '/api/admin/settings') {
              data['settings'] = {
                'capacity': 20,
                'car_rate': 7000,
                'motor_rate': 2000,
              };
            }
            if (req.url.path == '/api/admin/users') data['users'] = <Json>[];
            if (req.url.path.endsWith('/history')) {
              data.addAll({'sessions': <Json>[], 'total': 0, 'revenue': 0});
            }
            return http.Response(jsonEncode(data), 200);
          });
          final service = RemoteService(
            RemoteRepository('http://test', client: client),
            prefs,
          );
          await tester.pumpWidget(QParkApp(initialize: () async => service));
          await settle(tester);
          expect(find.text('Login customer'), findsOneWidget);
          expect(find.byKey(const Key('nav-0')), findsNothing);
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(const Key('customer-google')),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byKey(const Key('customer-demo')));
          await settle(tester);
          expect(find.text('Parkir lebih mudah'), findsOneWidget);
          expect(find.byKey(const Key('login-username')), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('nav-1')));
          await settle(tester);
          expect(find.text('Siap meninggalkan parkir?'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('officer-login')));
          await settle(tester);
          await tester.enterText(
            find.byKey(const Key('login-username')),
            'petugas',
          );
          await tester.enterText(
            find.byKey(const Key('login-password')),
            'Testing123!',
          );
          await tester.ensureVisible(find.byKey(const Key('login-submit')));
          await tester.tap(find.byKey(const Key('login-submit')));
          await settle(tester);
          expect(find.text('Ringkasan parkir'), findsOneWidget);
          expect(tester.takeException(), isNull);
          for (final index in [
            1,
            2,
            3,
            if (role == 'ADMIN') ...[4, 5],
            0,
          ]) {
            await tester.ensureVisible(find.byKey(Key('nav-$index')));
            await tester.tap(find.byKey(Key('nav-$index')));
            await settle(tester);
            expect(tester.takeException(), isNull);
            if (index == 5) {
              expect(find.text('Analisis Parkir'), findsOneWidget);
            }
            if (index == 2) {
              await tester.tap(find.text('Bayar manual'));
              await settle(tester);
              expect(tester.takeException(), isNull);
            }
          }
          await tester.tap(find.byKey(const Key('logout')));
          await settle(tester);
          await tester.tap(find.text('Keluar akun'));
          await settle(tester);
          expect(find.text('Login customer'), findsOneWidget);
          expect(service.plates, ['B123AB']);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
