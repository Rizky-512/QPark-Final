import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qpark/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Customer login appears first on device', (tester) async {
    app.main();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Login customer'), findsOneWidget);
    expect(find.text('Masuk dengan Google'), findsOneWidget);
    await tester.tap(find.text('Coba sebagai customer demo'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Parkir lebih mudah'), findsOneWidget);
  });
}
