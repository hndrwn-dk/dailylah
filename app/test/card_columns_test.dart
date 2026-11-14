// The cards of a tab: one column on a phone, two on a wide window (CardColumns in widgets.dart).
import 'package:dailylah/ui/app_frame.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/shell.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

Widget _card(String name, double height) => SizedBox(key: Key(name), height: height, child: Text(name));

Future<void> _pump(WidgetTester tester, double width, List<Widget> children) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 2000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => AppFrame(child: child!),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CardColumns(children: children),
        ),
      ),
    ),
  ));
}

Rect _rect(WidgetTester tester, String name) => tester.getRect(find.byKey(Key(name)));

void main() {
  group('splitColumns', () {
    test('splits where the taller column is shortest, reading order kept', () {
      expect(splitColumns([100, 100, 100, 100], [false, false, false, false]), 2);
      expect(splitColumns([300, 100, 100, 100], [false, false, false, false]), 1);
      expect(splitColumns([100, 100, 100, 300], [false, false, false, false]), 3);
    });

    test('on a tie the left column is the taller one', () {
      // 1|2 gives 100 and 200, 2|1 gives 200 and 100: the same height, left first.
      expect(splitColumns([100, 100, 100], [false, false, false]), 2);
    });

    test('a heading is never the last on the left with its card on the right', () {
      // Without the rule the split would fall after the heading (index 2).
      expect(splitColumns([100, 100, 20, 180], [false, false, true, false]), 2);
      expect(splitColumns([20, 100, 20, 100], [true, false, true, false]), 2);
    });

    test('one card, or nothing to split, stays on the left', () {
      expect(splitColumns([100], [false]), 1);
      expect(splitColumns([], []), 0);
      expect(splitColumns([20, 100], [true, false]), 2);
    });
  });

  testWidgets('on a phone the children are stacked and stretched', (tester) async {
    await _pump(tester, 400, [
      FullWidth(child: _card('banner', 40)),
      const SectionTitle('Title'),
      _card('a', 100),
      _card('b', 100),
    ]);
    expect(_rect(tester, 'banner'), const Rect.fromLTWH(16, 0, 368, 40));
    expect(_rect(tester, 'a').left, 16);
    expect(_rect(tester, 'a').width, 368);
    expect(_rect(tester, 'b').top, _rect(tester, 'a').bottom);
  });

  testWidgets('700 dp (one 600 dp column) is still one column', (tester) async {
    await _pump(tester, 700, [_card('a', 100), _card('b', 100)]);
    expect(_rect(tester, 'a').width, 568);
    expect(_rect(tester, 'b').top, _rect(tester, 'a').bottom);
  });

  testWidgets('880 dp: full-width children span, cards go left then right in order', (tester) async {
    await _pump(tester, 880, [
      FullWidth(child: _card('banner', 40)),
      _card('a', 100),
      _card('b', 100),
      _card('c', 100),
      _card('d', 100),
      FullWidth(child: _card('note', 30)),
      _card('e', 50),
    ]);
    // 880 - 2 x 16 padding = 848; two columns of 416 with a 16 dp gap.
    expect(_rect(tester, 'banner'), const Rect.fromLTWH(16, 0, 848, 40));
    expect(_rect(tester, 'a'), const Rect.fromLTWH(16, 40, 416, 100));
    expect(_rect(tester, 'b'), const Rect.fromLTWH(16, 140, 416, 100));
    expect(_rect(tester, 'c'), const Rect.fromLTWH(448, 40, 416, 100));
    expect(_rect(tester, 'd'), const Rect.fromLTWH(448, 140, 416, 100));
    // After the run: the note spans again, and the next run starts under it.
    expect(_rect(tester, 'note'), const Rect.fromLTWH(16, 240, 848, 30));
    expect(_rect(tester, 'e'), const Rect.fromLTWH(16, 270, 416, 50));
  });

  testWidgets('880 dp: a section title stays above its card', (tester) async {
    await _pump(tester, 880, [
      const SectionTitle('One'),
      _card('a', 200),
      const SectionTitle('Two'),
      _card('b', 300),
    ]);
    final two = tester.getRect(find.text('Two'));
    final b = _rect(tester, 'b');
    expect(b.left, 448);
    expect(two.left, greaterThanOrEqualTo(448));
    expect(two.bottom, lessThanOrEqualTo(b.top));
    expect(tester.getRect(find.text('One')).left, lessThan(448));
  });

  testWidgets('880 dp: a heading marked KeepWithNext stays above its card', (tester) async {
    // Without the mark the split falls after the heading: 110 | 85 beats 48 | 147.
    await _pump(tester, 880, [
      _card('button', 48),
      KeepWithNext(child: _card('heading', 62)),
      _card('panel', 85),
    ]);
    expect(_rect(tester, 'button').left, 16);
    expect(_rect(tester, 'heading'), const Rect.fromLTWH(448, 0, 416, 62));
    expect(_rect(tester, 'panel'), const Rect.fromLTWH(448, 62, 416, 85));
  });

  testWidgets('880 dp: a list two levels inside a column does not split either', (tester) async {
    await _pump(tester, 880, [
      CardColumns(children: [
        CardColumns(children: [_card('a1', 100), _card('a2', 100)]),
      ]),
      _card('b', 200),
    ]);
    expect(_rect(tester, 'a1'), const Rect.fromLTWH(16, 0, 416, 100));
    expect(_rect(tester, 'a2'), const Rect.fromLTWH(16, 100, 416, 100));
    expect(_rect(tester, 'b'), const Rect.fromLTWH(448, 0, 416, 200));
  });

  testWidgets('880 dp: a list inside one of the columns does not split again', (tester) async {
    await _pump(tester, 880, [
      CardColumns(children: [_card('a1', 100), _card('a2', 100)]),
      _card('b', 200),
      // Inside a full-width child there is room: this one splits.
      FullWidth(child: CardColumns(children: [_card('c1', 100), _card('c2', 100)])),
    ]);
    expect(_rect(tester, 'a1'), const Rect.fromLTWH(16, 0, 416, 100));
    expect(_rect(tester, 'a2'), const Rect.fromLTWH(16, 100, 416, 100));
    expect(_rect(tester, 'b'), const Rect.fromLTWH(448, 0, 416, 200));
    expect(_rect(tester, 'c1'), const Rect.fromLTWH(16, 200, 416, 100));
    expect(_rect(tester, 'c2'), const Rect.fromLTWH(448, 200, 416, 100));
  });

  testWidgets('880 dp: cards in the right column take taps, and state survives fold and unfold', (tester) async {
    var taps = 0;
    await _pump(tester, 880, [
      _card('a', 100),
      SizedBox(height: 100, child: TextButton(onPressed: () => taps++, child: const Text('tap'))),
      const SizedBox(height: 60, child: TextField()),
    ]);
    await tester.tap(find.text('tap'));
    expect(taps, 1);
    await tester.enterText(find.byType(TextField), 'kept');
    final state = tester.state(find.byType(TextField));
    // One column and two are the same widgets: what was typed and the field's state stay.
    for (final width in [400.0, 880.0, 700.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 2000);
      await tester.pumpAndSettle();
      expect(find.text('kept'), findsOneWidget);
      expect(tester.state(find.byType(TextField)), same(state));
    }
  });

  testWidgets('the tabs keep their place through fold and unfold, and tap-again goes to the top', (tester) async {
    const c = Condition('fold', size: Size(880, 600));
    await applyCondition(tester, c);
    await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
    await settle(tester);
    final shell = tester.state(find.byType(AppShell));
    ScrollPosition today() => Scrollable.of(tester.element(find.text('MRT & LRT').first)).position;
    // Two columns: the MRT card is beside the trip, not under it.
    expect(tester.getTopLeft(find.text('MRT & LRT').first).dx, greaterThan(440));
    today().jumpTo(120);
    await tester.pump();
    for (final size in const [Size(400, 800), Size(700, 600), Size(880, 600)]) {
      tester.view.physicalSize = size * 3;
      await settle(tester);
      expect(tester.state(find.byType(AppShell)), same(shell));
      expect(today().pixels, 120);
      expect(tester.takeException(), isNull);
    }
    expect(containerOf(tester).read(shellTabProvider), 0);
    await tester.tap(find.byIcon(Icons.wb_sunny));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(today().pixels, 0);
  });
}
