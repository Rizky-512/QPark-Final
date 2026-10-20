import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/ui/app.dart';
import 'package:qpark/ui/common.dart';
import 'package:qpark/ui/pages/dashboard_page.dart';
import 'package:qpark/ui/pages/entry_page.dart';
import 'package:qpark/ui/pages/history_page.dart';
import 'package:qpark/ui/pages/officers_page.dart';
import 'package:qpark/ui/pages/payment_page.dart';
import 'package:qpark/ui/pages/settings_page.dart';
import 'package:qpark/domain/models.dart';
import 'support.dart';

Future<void> settled(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget harness(Widget page) => MaterialApp(
  theme: buildTheme(),
  locale: const Locale('id', 'ID'),
  supportedLocales: const [Locale('id', 'ID')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(
    body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: page),
  ),
);
void main() {
  late Fixture f;
  setUp(() async => f = await Fixture.create());
  tearDown(() async => f.close());
  ScreenArgs args(Session s) => ScreenArgs(
    service: f.service,
    session: s,
    dirty: (_) {},
    busy: (_) {},
    expire: () {},
    navigate: (_) {},
  );
  void resize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final size in [
    const Size(1366, 768),
    const Size(390, 844),
    const Size(320, 640),
  ]) {
    testWidgets(
      'NFR-06 semua halaman tanpa overflow pada ${size.width}x${size.height}',
      (tester) async {
        resize(tester, size);
        final officer = args(f.officer), admin = args(f.admin);
        for (final page in [
          DashboardPage(args: officer),
          EntryPage(args: officer),
          PaymentPage(args: officer),
          HistoryPage(args: admin),
          SettingsPage(args: admin),
          OfficersPage(args: admin),
        ]) {
          await tester.pumpWidget(harness(page));
          await settled(tester);
          expect(
            tester.takeException(),
            isNull,
            reason: '${page.runtimeType} pada $size',
          );
          expect(
            find.text('Data belum dapat dimuat. Coba lagi.'),
            findsNothing,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('AT-01 login dan UC-08 konfirmasi logout form belum disimpan', (
    tester,
  ) async {
    resize(tester, const Size(1366, 768));
    await tester.pumpWidget(QParkApp(initialize: () async => f.service));
    await settled(tester);
    await tester.enterText(find.byKey(const Key('login-username')), 'petugas');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'Petugas123!',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await settled(tester);
    expect(find.text('Ringkasan parkir'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-1')));
    await settled(tester);
    await tester.enterText(find.byKey(const Key('entry-plate')), 'B123ABC');
    await tester.tap(find.byKey(const Key('logout')));
    await settled(tester);
    expect(find.text('Keluar dari akun?'), findsOneWidget);
    await tester.tap(find.text('Kembali'));
    await settled(tester);
    expect(find.text('B123ABC'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logout')));
    await settled(tester);
    await tester.tap(find.text('Keluar akun'));
    await settled(tester);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });
  testWidgets('UC-02 error baca tanpa slot palsu', (tester) async {
    await tester.runAsync(
      () => f.repo.db.customStatement('DROP TABLE transaksi_parkir'),
    );
    await tester.pumpWidget(harness(DashboardPage(args: args(f.officer))));
    await settled(tester);
    expect(find.textContaining('Data tidak dapat dibaca'), findsOneWidget);
    expect(find.text('slot tersedia'), findsNothing);
    expect(find.text('Coba lagi'), findsOneWidget);
  });
  testWidgets('AT-09 biaya baru ditampilkan dan perlu konfirmasi kedua', (
    tester,
  ) async {
    await tester.runAsync(
      () => f.service.enter(f.officer, 'B123ABC', Vehicle.motor),
    );
    resize(tester, const Size(1366, 1100));
    await tester.pumpWidget(harness(PaymentPage(args: args(f.officer))));
    await settled(tester);
    await tester.tap(find.text('Pilih'));
    await settled(tester);
    await tester.enterText(find.byKey(const Key('payment-cash')), '5000');
    f.now = f.now.add(const Duration(minutes: 61));
    await tester.tap(find.byKey(const Key('payment-confirm')));
    await settled(tester);
    await tester.tap(find.text('Bayar sekarang'));
    await settled(tester);
    expect(find.text('Rp4.000'), findsOneWidget);
    expect((await tester.runAsync(() => f.repo.active('')))!.length, 1);
    await tester.tap(find.byKey(const Key('payment-confirm')));
    await settled(tester);
    await tester.tap(find.text('Bayar sekarang'));
    await settled(tester);
    expect(find.text('Bukti pembayaran'), findsOneWidget);
    expect((await tester.runAsync(() => f.repo.active('')))!.length, 0);
    expect(tester.takeException(), isNull);
  });
}
