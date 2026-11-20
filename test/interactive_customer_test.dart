import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qpark/ui/widgets/customer_ticket_details.dart';
import 'package:qpark/ui/widgets/payment_confirmation.dart';
import 'ux_flow_test.dart' show Scenario, mount, tap, capture;
import 'widget_test.dart' show settle;

class MultiVehicleScenario extends Scenario {
  @override
  Future<http.Response> respond(http.Request request) async {
    if (request.url.path == '/api/ticket') {
      final plate = request.url.queryParameters['plate'];
      return http.Response(
        jsonEncode({
          'server_time': 1800000100,
          'session': {
            ...session,
            'plate': plate,
            'id': 'ticket-$plate',
            'vehicle_type': plate == 'B456CD' ? 'MOTOR' : 'MOBIL',
          },
        }),
        200,
      );
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
  testWidgets('Phone carousel and arrow selection open live ticket detail', (
    tester,
  ) async {
    final service = await mount(tester, MultiVehicleScenario());
    service.plates.add('B456CD');
    service.emit();
    await settle(tester);
    await tap(tester, find.byKey(const Key('vehicle-next')));
    expect(service.selected, 'B456CD');
    expect(service.ticket?['plate'], 'B456CD');
    await tap(tester, find.byKey(const ValueKey('vehicle-card-B456CD')));
    expect(find.text('Detail tiket'), findsOneWidget);
    expect(find.byType(CustomerTicketDetails), findsOneWidget);
    await capture(tester, 'interactive-ticket-phone');
    await service.selectPlate('B123AB');
    await settle(tester);
    expect(find.text('Pilihan kendaraan berubah'), findsOneWidget);
    expect(find.byType(CustomerTicketDetails), findsNothing);
    await tap(tester, find.byKey(const Key('ticket-detail-close')));
    await tester.ensureVisible(find.byKey(const Key('vehicle-carousel')));
    await tester.drag(
      find.byKey(const Key('vehicle-carousel')),
      const Offset(-300, 0),
    );
    await settle(tester);
    expect(service.selected, 'B456CD');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Desktop uses side details and phone retains selection after resizing',
    (tester) async {
      final service = await mount(
        tester,
        MultiVehicleScenario(),
        size: const Size(1280, 900),
      );
      service.plates.add('B456CD');
      service.emit();
      await settle(tester);
      await tap(tester, find.byKey(const ValueKey('vehicle-card-B456CD')));
      expect(service.selected, 'B456CD');
      expect(find.byKey(const Key('desktop-ticket-panel')), findsOneWidget);
      expect(find.byKey(const Key('customer-action-dock')), findsOneWidget);
      await capture(tester, 'interactive-customer-desktop');
      tester.view.physicalSize = const Size(360, 800);
      await settle(tester);
      expect(service.selected, 'B456CD');
      expect(
        tester
            .widget<PageView>(find.byKey(const Key('vehicle-carousel')))
            .controller!
            .page,
        1,
      );
      expect(find.byKey(const Key('desktop-ticket-panel')), findsNothing);
      final selectedCard = tester.getRect(
        find.byKey(const ValueKey('vehicle-card-B456CD')),
      );
      expect(selectedCard.left, greaterThanOrEqualTo(16));
      expect(selectedCard.right, lessThanOrEqualTo(344));
      await capture(tester, 'interactive-customer-phone');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Uncertain offline payment never displays success animation', (
    tester,
  ) async {
    final scenario = Scenario();
    final service = await mount(tester, scenario);
    await tap(tester, find.byKey(const Key('nav-1')));
    await tap(tester, find.byKey(const Key('payment-ready')));
    await tap(tester, find.byKey(const Key('invoice-open')));
    scenario.offline = true;
    await tap(tester, find.byKey(const Key('payment-success')));
    expect(find.byType(PaymentConfirmation), findsNothing);
    expect(service.pending, isNotEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Confirmed payment animates separately from the exit QR', (
    tester,
  ) async {
    final scenario = Scenario();
    await mount(tester, scenario);
    await tap(tester, find.byKey(const Key('nav-1')));
    await tap(tester, find.byKey(const Key('payment-ready')));
    await tap(tester, find.byKey(const Key('invoice-open')));
    await tap(tester, find.byKey(const Key('payment-success')));
    expect(find.byType(PaymentConfirmation), findsOneWidget);
    expect(find.text('QR keluar'), findsOneWidget);
    expect(scenario.payments, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
