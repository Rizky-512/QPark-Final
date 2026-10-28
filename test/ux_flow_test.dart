import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/logic/remote_service.dart';
import 'package:qpark/ui/app.dart';
import 'widget_test.dart' show ticket, settle;

class Scenario {
  Json session = ticket();
  bool offline = false, expired = false;
  int quotes = 0, payments = 0;
  final calls = <String>[];
  Future<http.Response> respond(http.Request request) async {
    calls.add(request.url.path);
    if (offline) throw http.ClientException('offline');
    if (expired && request.url.path == '/api/officer/monitor') {
      return http.Response(
        jsonEncode({'error': 'Sesi berakhir', 'code': 'auth'}),
        401,
      );
    }
    final data = <String, dynamic>{'server_time': 1800000100};
    switch (request.url.path) {
      case '/api/capacity':
        data.addAll({
          'total': 20,
          'occupied': 1,
          'available': 19,
          'full': false,
        });
      case '/api/ticket':
        data['session'] = session;
      case '/api/officer/monitor':
        data['sessions'] = [session];
      case '/api/officer/scan':
        data['session'] = session;
      case '/api/officer/authorize':
        session.addAll({
          'state': 'EXIT_AUTHORIZED',
          'authorization': {'id': 'auth', 'expires_at': 1800000220},
        });
        data['session'] = session;
      case '/api/officer/complete':
        session.addAll({'state': 'COMPLETED', 'authorization': null});
        data['session'] = session;
      case '/api/officer/manual-quote':
      case '/api/invoice':
        quotes++;
        final invoice = {
          'id': 'invoice',
          'kind': 'BASE',
          'state': 'PENDING',
          'amount': 7000,
          'hours': 1,
          'duration': 100,
          'expires_at': 1800000400,
        };
        session['invoices'] = [invoice];
        data.addAll({'session': session, 'invoice': invoice});
      case '/api/payment':
        payments++;
        session.addAll({
          'payment_status': 'Lunas',
          'amount_paid': 7000,
          'window_status': 'VALID',
          'window': {'deadline': 1800001000},
          'exit_qr': 'test-exit-qr',
        });
        data.addAll({'outcome': 'SUCCESS', 'session': session});
      case '/api/admin/settings':
        data['settings'] = {
          'capacity': 20,
          'car_rate': 7000,
          'motor_rate': 2000,
        };
      case '/api/admin/users':
        data['users'] = <Json>[];
      default:
        data.addAll({'sessions': <Json>[], 'total': 0, 'revenue': 0});
    }
    return http.Response(jsonEncode(data), 200);
  }
}

Future<RemoteService> mount(
  WidgetTester tester,
  Scenario scenario, {
  String role = 'CUSTOMER',
  Size size = const Size(360, 800),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({
    'qpark_plates_v3': ['B123AB'],
    'qpark_selected_v3': 'B123AB',
  });
  final service = RemoteService(
    RemoteRepository('http://test', client: MockClient(scenario.respond)),
    await SharedPreferences.getInstance(),
  );
  if (role == 'CUSTOMER') {
    service.enterCustomerDemo();
  } else {
    service.token = 'staff';
    service.role = role;
    service.username = 'Petugas uji';
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('capture'),
      child: QParkApp(initialize: () async => service),
    ),
  );
  await settle(tester);
  return service;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/ux_checks/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets('QR exit retains physical verification and final confirmation', (
    tester,
  ) async {
    final scenario = Scenario();
    await mount(tester, scenario, role: 'PETUGAS');
    await tap(tester, find.byKey(const Key('nav-2')));
    expect(find.byKey(const Key('exit-token')), findsNothing);
    await tap(tester, find.text('Kamera tidak tersedia?'));
    await tester.enterText(find.byKey(const Key('exit-token')), 'test-token');
    await tap(tester, find.byKey(const Key('exit-scan')));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('exit-plate')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('exit-authorize')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('exit-plate')), 'B123AB');
    await tap(tester, find.byKey(const Key('exit-match')));
    await tap(tester, find.byKey(const Key('exit-authorize')));
    expect(find.text('Gerbang simulasi: TERBUKA'), findsOneWidget);
    await tap(tester, find.byKey(const Key('exit-complete')));
    expect(scenario.calls, isNot(contains('/api/officer/complete')));
    await tap(tester, find.text('Ya, sudah keluar'));
    expect(scenario.calls, contains('/api/officer/complete'));
    expect(
      find.text('Sesi selesai. Pindai QR kendaraan berikutnya.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Customer readiness, simulated payment, exit QR and offline recovery',
    (tester) async {
      final scenario = Scenario();
      final service = await mount(tester, scenario);
      await capture(tester, 'customer-phone');
      await tap(tester, find.byKey(const Key('nav-1')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('invoice-open')))
            .onPressed,
        isNull,
      );
      await tap(tester, find.byKey(const Key('payment-ready')));
      await tap(tester, find.byKey(const Key('invoice-open')));
      expect(scenario.quotes, 1);
      await tap(tester, find.byKey(const Key('payment-success')));
      expect(scenario.payments, 1);
      expect(find.text('QR keluar'), findsOneWidget);
      expect(find.byKey(const Key('invoice-open')), findsNothing);
      await tap(tester, find.byKey(const Key('nav-0')));
      await tap(tester, find.byKey(const Key('nav-1')));
      await capture(tester, 'customer-exit-qr');
      scenario.offline = true;
      await service.sync();
      await settle(tester);
      expect(find.textContaining('QR disembunyikan'), findsOneWidget);
      scenario.offline = false;
      await service.sync();
      await settle(tester);
      expect(find.textContaining('QR disembunyikan'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Manual quote auto-load and form survives switching exit method',
    (tester) async {
      final scenario = Scenario();
      await mount(tester, scenario, role: 'PETUGAS');
      await tap(tester, find.byKey(const Key('nav-2')));
      await tap(tester, find.text('Bayar manual'));
      await tap(tester, find.byType(DropdownButtonFormField<String>));
      await tap(tester, find.text('B123AB · Mobil').last);
      expect(scenario.quotes, 1);
      final cash = find.widgetWithText(TextField, 'Uang diterima (Rp)');
      await tester.enterText(cash, '10000');
      await settle(tester);
      expect(find.text('Kembalian: Rp3.000'), findsOneWidget);
      await tap(tester, find.text('QR keluar'));
      await tap(tester, find.text('Bayar manual'));
      expect(tester.widget<TextField>(cash).controller!.text, '10000');
      expect(scenario.quotes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final role in ['CUSTOMER', 'PETUGAS', 'ADMIN']) {
    testWidgets('Small phone, larger text and keyboard: $role', (tester) async {
      await mount(
        tester,
        Scenario(),
        role: role,
        size: const Size(320, 640),
        scale: 1.3,
      );
      await tap(
        tester,
        find.byKey(Key(role == 'CUSTOMER' ? 'vehicle-add' : 'nav-1')),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      final field = find.byKey(
        Key(role == 'CUSTOMER' ? 'vehicle-plate' : 'entry-plate'),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, 'B456CD');
      await settle(tester);
      expect(tester.takeException(), isNull);
      await capture(tester, 'keyboard-${role.toLowerCase()}');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });
  }
  testWidgets(
    'Expired staff session explains recovery and removes operational access',
    (tester) async {
      final scenario = Scenario();
      final service = await mount(tester, scenario, role: 'PETUGAS');
      scenario.expired = true;
      await service.sync();
      await settle(tester);
      expect(find.textContaining('Sesi petugas berakhir.'), findsOneWidget);
      expect(find.byKey(const Key('nav-1')), findsNothing);
      expect(service.officer, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Admin laptop and compact operational navigation', (
    tester,
  ) async {
    await mount(tester, Scenario(), role: 'ADMIN', size: const Size(1280, 800));
    await capture(tester, 'admin-laptop');
    expect(find.byKey(const Key('nav-5')), findsOneWidget);
    tester.view.physicalSize = const Size(360, 800);
    await settle(tester);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.byKey(const Key('nav-5')), findsNothing);
    await tap(tester, find.byKey(const Key('admin-menu')));
    expect(find.byKey(const Key('nav-5')), findsOneWidget);
    await capture(tester, 'admin-phone-menu');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
