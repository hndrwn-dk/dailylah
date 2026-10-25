import 'package:dailylah/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a bus plate as ListTile leading leaves room for the title', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ListTile(leading: BusPlate('43'), title: Text('Wake me before Marine Pde Stn Exit 2')),
            Row(children: [BusPlate('858A'), Expanded(child: Text('next'))]),
          ],
        ),
      ),
    ));
    final plate = tester.getSize(find.byType(BusPlate).first);
    expect(plate.width, lessThan(120));
    expect(plate.width, greaterThanOrEqualTo(60));
    expect(tester.getSize(find.text('Wake me before Marine Pde Stn Exit 2')).width, greaterThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog buttons sit side by side with equal width', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (d) => AlertDialog(
                content: const Text('Remove these 3 entries from History?'),
                actions: [
                  DialogButtons(cancelLabel: 'Cancel', confirmLabel: 'Remove', onCancel: () {}, onConfirm: () {}),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final cancel = tester.getRect(find.widgetWithText(OutlinedButton, 'Cancel'));
    final remove = tester.getRect(find.widgetWithText(FilledButton, 'Remove'));
    expect(cancel.top, remove.top);
    expect(cancel.width, closeTo(remove.width, 1));
    expect(cancel.right, lessThan(remove.left));
    expect(tester.takeException(), isNull);
  });
}
