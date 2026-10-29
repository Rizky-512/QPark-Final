import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/logic/remote_service.dart';
import 'package:qpark/ui/pages/analytics_page.dart';
import 'package:qpark/ui/remote_common.dart';

void main() {
  testWidgets('calendar supports previous month and bounded end date', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = RemoteRepository('http://test');
    final service = RemoteService(repo, await SharedPreferences.getInstance());
    addTearDown(service.dispose);
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnalyticsPage(
              args: RemoteArgs(service, (_) {}),
              active: false,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pilih tanggal'));
    await tester.pumpAndSettle();
    final before = tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .initialDate!;
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final endPicker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    final previousMonth = DateTime(before.year, before.month - 1, 15);
    expect(endPicker.firstDate, previousMonth);
    expect(
      endPicker.lastDate.difference(endPicker.firstDate).inDays,
      lessThan(366),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
