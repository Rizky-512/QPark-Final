import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qpark/ui/widgets/receipt_button.dart';
import 'ux_flow_test.dart' show Scenario, mount, tap;
import 'widget_test.dart' show settle;

class CheckoutScenario extends Scenario {
  String? quotedId;
  @override
  Future<http.Response> respond(http.Request request) {
    if (request.url.path == '/api/officer/manual-quote') {
      quotedId = jsonDecode(request.body)['session_id'] as String;
    }
    return super.respond(request);
  }
}

void main() {
  testWidgets('Officer filter and direct action select the displayed ticket', (
    tester,
  ) async {
    final scenario = CheckoutScenario();
    await mount(tester, scenario, role: 'PETUGAS');
    await tap(tester, find.text('Sudah bayar (0)'));
    expect(find.text('0 kendaraan ditampilkan'), findsOneWidget);
    expect(find.text('Buka tagihan kendaraan'), findsNothing);
    await tap(tester, find.text('Belum bayar (1)'));
    await tap(tester, find.text('Buka tagihan kendaraan'));
    expect(scenario.quotedId, 'QP-test-session');
    expect(scenario.quotes, 1);
    expect(find.text('Uang diterima (Rp)'), findsOneWidget);
    expect(scenario.calls, isNot(contains('/api/officer/manual-pay')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Receipt dialog copies confirmed simulated payment', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final session = Scenario().session
      ..['invoices'] = [
        {
          'id': 'paid',
          'state': 'PAID',
          'amount': 7000,
          'payment_method': 'QR_SIMULASI',
          'paid_at': 1800000100,
        },
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReceiptButton(session: session)),
      ),
    );
    await tap(tester, find.text('Lihat bukti transaksi'));
    expect(find.textContaining('tidak memindahkan uang nyata'), findsOneWidget);
    await tap(tester, find.text('Salin teks'));
    expect(copied, contains('TOTAL TERCATAT: Rp7.000'));
    await tap(tester, find.text('Tutup'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
