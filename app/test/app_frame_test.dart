import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:dailylah/ui/app_frame.dart';
import 'package:dailylah/ui/theme.dart';
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

  testWidgets('a phone (400 dp) gets the full width and the same MediaQuery as before', (tester) async {
    final seen = await pumpFrame(tester, const Size(400, 800));
    expect(tester.getRect(find.byKey(const Key('page'))), const Rect.fromLTWH(0, 0, 400, 800));
    expect(seen.size, const Size(400, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('exactly $kMaxContentWidth dp is still a phone', (tester) async {
    final seen = await pumpFrame(tester, const Size(kMaxContentWidth, 800));
    expect(tester.getRect(find.byKey(const Key('page'))).width, kMaxContentWidth);
    expect(seen.size.width, kMaxContentWidth);
  });

  testWidgets('an unfolded foldable upright (700 dp) gets a centred 600 dp column', (tester) async {
    final seen = await pumpFrame(tester, const Size(700, 600));
    expect(tester.getRect(find.byKey(const Key('page'))), const Rect.fromLTWH(50, 0, 600, 600));
    expect(seen.size, const Size(600, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the column keeps height, padding and the keyboard inset', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    final seen = await pumpFrame(tester, const Size(700, 600), padding: const FakeViewPadding(top: 24, bottom: 48));
    expect(seen.size, const Size(600, 600));
    expect(seen.padding.top, 24);
    expect(seen.viewInsets.bottom, 300);
  });

  testWidgets('sheets and dialogs stay inside the column', (tester) async {
    await pumpFrame(tester, const Size(700, 600));
    final context = tester.element(find.byKey(const Key('page')));
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(key: Key('sheet'), height: 200, width: double.infinity),
    );
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byKey(const Key('sheet')));
    expect(sheet.left, greaterThanOrEqualTo(50));
    expect(sheet.right, lessThanOrEqualTo(650));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    showDialog<void>(context: context, builder: (_) => const AlertDialog(key: Key('dialog'), title: Text('Hello')));
    await tester.pumpAndSettle();
    final dialog = tester.getRect(find.byKey(const Key('dialog')));
    expect(dialog.left, greaterThanOrEqualTo(50));
    expect(dialog.right, lessThanOrEqualTo(650));
    expect(dialog.center.dx, 350);
  });

  testWidgets('a side cutout narrows the room: 640 dp with 48 dp each side is a phone', (tester) async {
    final seen = await pumpFrame(tester, const Size(640, 360), padding: const FakeViewPadding(left: 48, right: 48));
    expect(tester.getRect(find.byKey(const Key('page'))), const Rect.fromLTWH(48, 0, 544, 360));
    expect(seen.size.width, 640);
  });

  testWidgets('a fold is where the column sees it', (tester) async {
    tester.view.displayFeatures = const [
      DisplayFeature(
        bounds: Rect.fromLTWH(350, 0, 0, 600),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    final seen = await pumpFrame(tester, const Size(700, 600));
    expect(seen.displayFeatures.single.bounds, const Rect.fromLTWH(300, 0, 0, 600));
    expect(seen.displayFeatures.single.state, DisplayFeatureState.postureHalfOpened);
  });

  // Flutter places this toolbar by window coordinates in the topmost overlay. With the
  // Navigator's overlay on top (moved to the column) it was held to the window's first 600 dp:
  // away from a selection on the right, and dead to taps where it reached beside the column.
  for (final (where, dx) in [('left', 20.0), ('right', 560.0)]) {
    testWidgets('Cut/Copy/Paste is at the selection and can be tapped ($where of the field)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(700, 600);
      addTearDown(tester.view.reset);
      const before = 'Tampines Street 12 beside the big market and the interchange for all buses';
      final text = TextEditingController(text: before);
      addTearDown(text.dispose);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => AppFrame(child: child!),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 200, 16, 0),
            child: TextField(controller: text),
          ),
        ),
      ));
      final field = tester.getRect(find.byType(TextField));
      expect(field.left, 66);
      final press = field.centerLeft + Offset(dx, 0);
      await tester.longPressAt(press);
      await tester.pumpAndSettle();
      final toolbar = tester.getRect(find.text('Cut')).expandToInclude(tester.getRect(find.text('Select all')));
      expect(toolbar.left, lessThan(press.dx));
      expect(toolbar.right, greaterThan(press.dx));
      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();
      expect(text.text, isNot(before));
    });
  }

  testWidgets('a feature beside the column is dropped, one across its edge is cut', (tester) async {
    tester.view.displayFeatures = const [
      DisplayFeature(
        bounds: Rect.fromLTWH(0, 0, 30, 600),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      ),
      DisplayFeature(
        bounds: Rect.fromLTWH(10, 0, 80, 600),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureFlat,
      ),
    ];
    final seen = await pumpFrame(tester, const Size(700, 600));
    expect(seen.displayFeatures.single.bounds, const Rect.fromLTRB(0, 0, 40, 600));
  });

  testWidgets('folding and unfolding keep the page, its state and the focus', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppFrame(child: child!),
      home: const Scaffold(body: TextField()),
    ));
    await tester.enterText(find.byType(TextField), 'Bedok');
    final state = tester.state(find.byType(TextField));
    final focus = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    expect(focus.hasFocus, isTrue);
    for (final size in const [Size(700, 600), Size(400, 800), Size(880, 600), Size(400, 800)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(state));
      expect(find.text('Bedok'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(tester.getRect(find.byType(Scaffold)).width, size.width == 700 ? 600 : size.width);
    }
  });

  testWidgets('the frame follows a new child from MaterialApp', (tester) async {
    Widget app(String label) => Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Theme(data: ThemeData(), child: AppFrame(child: Text(label))),
          ),
        );
    await tester.pumpWidget(app('one'));
    expect(find.text('one'), findsOneWidget);
    await tester.pumpWidget(app('two'));
    await tester.pump();
    expect(find.text('two'), findsOneWidget);
  });

  // ------------------------------------------------------------ two columns from 840 dp

  test('frameWidth: one column up to 840 dp, then two up to 1040 dp, one again at large text', () {
    expect(frameWidth(360, 1), 360);
    expect(frameWidth(600, 1), 600);
    expect(frameWidth(601, 1), 600);
    expect(frameWidth(700, 1), 600);
    expect(frameWidth(839, 1), 600);
    expect(frameWidth(840, 1), 840);
    expect(frameWidth(880, 1), 880);
    expect(frameWidth(1040, 1), 1040);
    expect(frameWidth(1400, 1), 1040);
    // Two columns of 416 dp at 880 dp: fine up to 130% text, too narrow at 200%.
    expect(frameWidth(880, 1.3), 880);
    expect(frameWidth(880, 1.31), 600);
    expect(frameWidth(880, 2), 600);
    expect(frameWidth(1400, 1.5), 1040);
    expect(frameWidth(1400, 2), 600);
  });

  for (final width in [840.0, 880.0]) {
    testWidgets('$width dp: the tabs get the full width and are wide', (tester) async {
      final seen = await pumpFrame(tester, Size(width, 600));
      expect(tester.getRect(find.byKey(const Key('page'))), Rect.fromLTWH(0, 0, width, 600));
      expect(seen.size, Size(width, 600));
      expect(isWide(tester.element(find.byKey(const Key('page')))), isTrue);
    });
  }

  testWidgets('1400 dp: 1040 dp, centred, with the page colour beside it', (tester) async {
    final seen = await pumpFrame(tester, const Size(1400, 800));
    expect(tester.getRect(find.byKey(const Key('page'))), const Rect.fromLTWH(180, 0, 1040, 800));
    expect(seen.size, const Size(1040, 800));
  });

  testWidgets('839 dp and 880 dp at 200% text stay in one 600 dp column', (tester) async {
    var seen = await pumpFrame(tester, const Size(839, 600));
    expect(seen.size.width, 600);
    expect(isWide(tester.element(find.byKey(const Key('page')))), isFalse);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    seen = await pumpFrame(tester, const Size(880, 600));
    expect(seen.size.width, 600);
    expect(tester.getRect(find.byKey(const Key('page'))), const Rect.fromLTWH(140, 0, 600, 600));
  });

  testWidgets('at 880 dp a pushed page, a sheet and a dialog stay 600 dp wide, centred', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(880, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      builder: (context, child) => AppFrame(child: child!),
      home: const Scaffold(body: SizedBox.expand(key: Key('tabs'))),
    ));
    final tabs = tester.element(find.byKey(const Key('tabs')));
    late MediaQueryData seen;
    Navigator.of(tabs).push(MaterialPageRoute<void>(builder: (context) {
      seen = MediaQuery.of(context);
      return const Scaffold(body: SizedBox.expand(key: Key('pushed')));
    }));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('pushed'))), const Rect.fromLTWH(140, 0, 600, 600));
    expect(seen.size, const Size(600, 600));
    final pushed = tester.element(find.byKey(const Key('pushed')));
    expect(isWide(pushed), isFalse);
    // The page colour covers the tabs beside the pushed page.
    expect(find.byKey(const Key('tabs')).hitTestable(), findsNothing);

    showModalBottomSheet<void>(
      context: pushed,
      builder: (_) => const SizedBox(key: Key('sheet'), height: 200, width: double.infinity),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('sheet'))).width, 600);
    expect(tester.getRect(find.byKey(const Key('sheet'))).center.dx, 440);
    // The dimming covers the whole window: a tap beside the sheet closes it.
    await tester.tapAt(const Offset(20, 100));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sheet')), findsNothing);

    Navigator.of(pushed).pop();
    await tester.pumpAndSettle();
    showModalBottomSheet<void>(
      context: tabs,
      builder: (_) => const SizedBox(key: Key('sheet'), height: 200, width: double.infinity),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('sheet'))).width, 600);
    Navigator.of(tabs).pop();
    await tester.pumpAndSettle();
    showDialog<void>(context: tabs, builder: (_) => const AlertDialog(key: Key('dialog'), title: Text('Hello')));
    await tester.pumpAndSettle();
    final card = tester.getRect(
        find.descendant(of: find.byKey(const Key('dialog')), matching: find.byType(Material)).first);
    expect(card.width, lessThanOrEqualTo(600));
    expect(card.center.dx, 440);
  });

  testWidgets('a pushed page keeps its state and focus through fold, unfold and turn', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      builder: (context, child) => AppFrame(child: child!),
      home: const Scaffold(body: SizedBox.expand(key: Key('tabs'))),
    ));
    Navigator.of(tester.element(find.byKey(const Key('tabs'))))
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: TextField())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bedok');
    final state = tester.state(find.byType(TextField));
    final focus = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    for (final size in const [Size(700, 600), Size(880, 600), Size(1400, 800), Size(400, 800)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(state));
      expect(find.text('Bedok'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(tester.getRect(find.byType(TextField)).width, size.width > 600 ? 600 : size.width);
    }
  });

  testWidgets('two columns beside a side cutout: a fold is still where the column sees it', (tester) async {
    tester.view.displayFeatures = const [
      DisplayFeature(
        bounds: Rect.fromLTWH(488, 0, 0, 600),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    // 976 dp with 48 dp on each side: 880 dp of room, all of it used.
    final seen = await pumpFrame(tester, const Size(976, 600), padding: const FakeViewPadding(left: 48, right: 48));
    expect(tester.getRect(find.byKey(const Key('page'))), const Rect.fromLTWH(48, 0, 880, 600));
    expect(seen.size.width, 880);
    expect(seen.displayFeatures.single.bounds, const Rect.fromLTWH(440, 0, 0, 600));
  });
}
