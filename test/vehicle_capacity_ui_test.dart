import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'ux_flow_test.dart' show Scenario, mount, tap, capture;
import 'widget_test.dart' show settle;

class CapacityScenario extends Scenario {
  final types = <String, String>{'B123AB': 'MOTOR'};
  final entries = <Map<String, dynamic>>[];
  @override
  Future<http.Response> respond(http.Request request) async {
    final path = request.url.path;
    if (path == '/api/capacity') {
      calls.add(path);
      if (offline) throw http.ClientException('offline');
      return http.Response(
        jsonEncode({
          'server_time': 1800000100,
          'categories': {
            'MOBIL': {
              'total': 10,
              'occupied': 2,
              'available': 8,
              'full': false,
            },
            'MOTOR': {'total': 5, 'occupied': 5, 'available': 0, 'full': true},
          },
        }),
        200,
      );
    }
    if (path == '/api/customer/vehicle-types') {
      return http.Response(jsonEncode({'vehicle_types': types}), 200);
    }
    if (path == '/api/customer/vehicle-type') {
      final body = jsonDecode(request.body);
      types[body['plate']] = body['vehicle_type'];
      return http.Response('{}', 200);
    }
    if (path == '/api/officer/vehicle-type') {
      return http.Response(
        jsonEncode({
          'vehicle_type': types[request.url.queryParameters['plate']],
        }),
        200,
      );
    }
    if (path == '/api/officer/entry') {
      entries.add(jsonDecode(request.body));
      return http.Response(jsonEncode({'session': session}), 200);
    }
    return super.respond(request);
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'Public home shows separate slots and never fetches a private ticket',
    (tester) async {
      final scenario = CapacityScenario();
      final service = await mount(tester, scenario);
      service.customerDemo = false;
      service.emit();
      await settle(tester);
      scenario.calls.clear();
      await service.sync();
      await settle(tester);
      expect(find.text('8 slot tersedia'), findsOneWidget);
      expect(find.text('0 slot tersedia'), findsOneWidget);
      expect(scenario.calls, ['/api/capacity']);
      expect(find.byKey(const Key('nav-0')), findsNothing);
      await capture(tester, 'public-separate-capacity');
      scenario.offline = true;
      await service.sync();
      await settle(tester);
      expect(
        find.text('Koneksi terputus. Data belum diperbarui.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Customer must choose a category when saving a new plate', (
    tester,
  ) async {
    final scenario = CapacityScenario();
    final service = await mount(tester, scenario);
    await tap(tester, find.byKey(const Key('vehicle-add')));
    await tester.enterText(find.byKey(const Key('vehicle-plate')), 'B999NEW');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Simpan'))
          .onPressed,
      isNull,
    );
    await tap(tester, find.byKey(const Key('vehicle-category')));
    await tap(tester, find.text('Motor').last);
    await tap(tester, find.widgetWithText(FilledButton, 'Simpan'));
    expect(scenario.types['B999NEW'], 'MOTOR');
    expect(service.vehicleTypes['B999NEW'], 'MOTOR');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Staff uses stored category; unknown plates can enter a free car slot',
    (tester) async {
      final scenario = CapacityScenario();
      await mount(tester, scenario, role: 'PETUGAS');
      await tap(tester, find.byKey(const Key('nav-1')));
      final field = find.byKey(const Key('entry-plate'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'B123AB');
      await settle(tester);
      expect(find.text('Kategori tersimpan: Motor'), findsOneWidget);
      expect(find.byKey(const Key('entry-type-MOBIL')), findsNothing);
      await tap(tester, find.byKey(const Key('entry-verify')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('entry-save')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, 'B999CAR');
      await settle(tester);
      await tap(tester, find.byKey(const Key('entry-type-MOBIL')));
      await tap(tester, find.byKey(const Key('entry-verify')));
      await tap(tester, find.byKey(const Key('entry-save')));
      expect(scenario.entries.single['vehicle_type'], 'MOBIL');
      expect(scenario.entries.single['plate'], 'B999CAR');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
