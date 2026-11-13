import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

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

  /// Pumps a page that fills the frame and reports the MediaQuery it sees.
  Future<MediaQueryData> pumpFrame(WidgetTester tester, Size size, {FakeViewPadding? padding}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    if (padding != null) {
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
    }
    addTearDown(tester.view.reset);
    late MediaQueryData seen;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppFrame(child: child!),
      home: Builder(builder: (context) {
        seen = MediaQuery.of(context);
        return const Scaffold(body: SizedBox.expand(key: Key('page')));
      }),
    ));
    return seen;
  }

  testWidgets('a phone (400 dp) gets the full width and no column', (tester) async {
    final seen = await pumpFrame(tester, const Size(400, 800));
    expect(tester.getRect(find.byKey(const Key('page'))), const Rect.fromLTWH(0, 0, 400, 800));
    expect(seen.size, const Size(400, 800));
    // No column: nothing in the frame is held at the column's width.
    expect(find.byWidgetPredicate((w) => w is SizedBox && w.width == kMaxContentWidth), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exactly $kMaxContentWidth dp is still a phone', (tester) async {
    final seen = await pumpFrame(tester, const Size(kMaxContentWidth, 800));
    expect(tester.getRect(find.byKey(const Key('page'))).width, kMaxContentWidth);
    expect(seen.size.width, kMaxContentWidth);
  });

  testWidgets('an unfolded foldable on its side (880x600 dp) gets a centred 600 dp column', (tester) async {
    final seen = await pumpFrame(tester, const Size(880, 600));
    expect(tester.getRect(find.byKey(const Key('page'))), const Rect.fromLTWH(140, 0, 600, 600));
    expect(seen.size, const Size(600, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the column keeps height, padding and the keyboard inset', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    final seen = await pumpFrame(tester, const Size(880, 600), padding: const FakeViewPadding(top: 24, bottom: 48));
    expect(seen.size, const Size(600, 600));
    expect(seen.padding.top, 24);
    expect(seen.viewInsets.bottom, 300);
  });

  testWidgets('sheets and dialogs stay inside the column', (tester) async {
    await pumpFrame(tester, const Size(880, 600));
    final context = tester.element(find.byKey(const Key('page')));
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(key: Key('sheet'), height: 200, width: double.infinity),
    );
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byKey(const Key('sheet')));
    expect(sheet.left, greaterThanOrEqualTo(140));
    expect(sheet.right, lessThanOrEqualTo(740));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    showDialog<void>(context: context, builder: (_) => const AlertDialog(key: Key('dialog'), title: Text('Hello')));
    await tester.pumpAndSettle();
    final dialog = tester.getRect(find.byKey(const Key('dialog')));
    expect(dialog.left, greaterThanOrEqualTo(140));
    expect(dialog.right, lessThanOrEqualTo(740));
    expect(dialog.center.dx, 440);
  });

  testWidgets('a side cutout narrows the room: 640 dp with 48 dp each side is a phone', (tester) async {
    final seen = await pumpFrame(tester, const Size(640, 360), padding: const FakeViewPadding(left: 48, right: 48));
    expect(tester.getRect(find.byKey(const Key('page'))), const Rect.fromLTWH(48, 0, 544, 360));
    expect(seen.size.width, 640);
  });

  testWidgets('a fold is where the column sees it', (tester) async {
    tester.view.displayFeatures = const [
      DisplayFeature(
        bounds: Rect.fromLTWH(440, 0, 0, 600),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    final seen = await pumpFrame(tester, const Size(880, 600));
    expect(seen.displayFeatures.single.bounds, const Rect.fromLTWH(300, 0, 0, 600));
    expect(seen.displayFeatures.single.state, DisplayFeatureState.postureHalfOpened);
  });
}
