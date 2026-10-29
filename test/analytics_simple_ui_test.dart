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
import 'package:qpark/ui/common.dart';
import 'package:qpark/ui/pages/analytics_page.dart';
import 'package:qpark/ui/remote_common.dart';
import 'package:qpark/ui/widgets/vehicle_pie.dart';
import 'parking_forecast_test.dart' as fixture;

void main() {
  setUpAll(() async {
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await loader.load();
  });
  for (final width in [390.0, 1100.0]) {
    testWidgets('simple analytics readable at width $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final repo = RemoteRepository(
        'http://test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'forecast': fixture.dataset(),
              'server_time': 1793250000,
              'from_date': '2026-10-23',
              'to_date': '2026-10-29',
              'arrivals': 100,
              'mean_minutes': 82,
              'vehicles': {'MOBIL': 30, 'MOTOR': 70},
              'hourly': List.generate(
                24,
                (i) => {'hour': i, 'arrivals': i % 10},
              ),
              'daily': [],
              'weekdays': [],
            }),
            200,
          ),
        ),
      );
      final service = RemoteService(repo, await SharedPreferences.getInstance())
        ..token = 'test'
        ..role = 'ADMIN';
      addTearDown(service.dispose);
      addTearDown(repo.close);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme().copyWith(
            textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: AnalyticsPage(
                    args: RemoteArgs(service, (_) {}),
                    active: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sekitar 18 kendaraan'), findsOneWidget);
      expect(find.textContaining('Motor  70.0%'), findsOneWidget);
      expect(find.textContaining('Mobil  30.0%'), findsOneWidget);
      expect(find.text('Median durasi'), findsNothing);
      expect(tester.takeException(), isNull);
      // Optional local visual review artifact, excluded from source control.
      if (Platform.environment['QPARK_CAPTURE_UI'] == '1') {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final shot = await boundary.toImage();
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/qa').create(recursive: true);
          await File(
            'build/qa/analytics-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      await tester.ensureVisible(find.text('Jelaskan dengan AI'));
      await tester.tap(find.text('Jelaskan dengan AI'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Penjelasan Gemini tersedia'), findsOneWidget);
      expect(find.text('Sekitar 18 kendaraan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('pie handles empty data without a misleading percentage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VehiclePie(cars: 0, motors: 0))),
    );
    expect(find.text('Belum ada kunjungan pada periode ini.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(VehiclePie),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });
}
