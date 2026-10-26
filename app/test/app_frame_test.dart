import 'package:dailylah/ui/app_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the last item stays above a 3-button navigation bar', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppFrame(child: child!),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            const SizedBox(height: 900),
            FilledButton(onPressed: () {}, child: const Text('Save')),
          ],
        ),
      ),
    ));
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    final save = tester.getRect(find.text('Save'));
    expect(save.bottom, lessThanOrEqualTo(800 - 48));
    expect(tester.takeException(), isNull);
  });
}
