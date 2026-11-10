import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/ui/common.dart';
import 'package:qpark/ui/widgets/page_motion.dart';

void main() {
  test('Text and semantic status colors meet 4.5:1 contrast', () {
    for (final pair in [
      (AppColors.text, AppColors.surface),
      (AppColors.muted, AppColors.background),
      (AppColors.muted, AppColors.surface),
      (Colors.white, AppColors.primary),
      (AppColors.primary, AppColors.successBackground),
      (AppColors.warning, AppColors.warningBackground),
      (AppColors.danger, AppColors.dangerBackground),
    ]) {
      final a = pair.$1.computeLuminance(), b = pair.$2.computeLuminance();
      final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: '$pair');
    }
  });

  testWidgets('Rapid tab changes preserve form and scroll state', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: PageMotion(
                index: selected,
                children: [
                  SingleChildScrollView(
                    controller: scroll,
                    child: const Column(
                      children: [
                        TextField(key: Key('draft')),
                        SizedBox(height: 1600),
                      ],
                    ),
                  ),
                  const Center(child: Text('Second page')),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('draft')), 'B123AB');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    scroll.jumpTo(300);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      update(() => selected = 1 - selected);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
    expect(scroll.offset, 300);
    scroll.jumpTo(0);
    await tester.pump();
    expect(find.text('B123AB'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Reduced motion switches immediately without fading content', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return PageMotion(
                index: selected,
                children: const [Text('First'), Text('Second')],
              );
            },
          ),
        ),
      ),
    );
    update(() => selected = 1);
    await tester.pump();
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(PageMotion),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    expect(find.text('Second'), findsOneWidget);
  });
}
