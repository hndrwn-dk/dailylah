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

/// A card with its own heading and 20 dp of space above it, like Today's weekend card.
class _Headed extends StatelessWidget implements OpensWithHeading {
  const _Headed({super.key, required this.height});
  final double height;

  @override
  double get headingGap => 20;

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
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
    // A run with one card leaves nothing for the right column: it takes the whole width.
    expect(_rect(tester, 'e'), const Rect.fromLTWH(16, 270, 848, 50));
  });

  testWidgets('880 dp: a heading and its one card take the whole width, not half of it', (tester) async {
    await _pump(tester, 880, [const SectionTitle('Taxi', key: Key('title')), _card('a', 100)]);
    expect(_rect(tester, 'title').width, 848);
    expect(_rect(tester, 'a'), Rect.fromLTWH(16, _rect(tester, 'title').bottom, 848, 100));
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

  testWidgets('880 dp: a heading on top of the right column lines up with the card on the left', (tester) async {
    await _pump(tester, 880, [
      _card('a', 300),
      const SectionTitle('Weekend', key: Key('title')),
      _card('b', 260),
    ]);
    // Without the lift the title's 20 dp of space above it would leave it floating below a's top.
    expect(_rect(tester, 'title').left, greaterThan(440));
    expect(_rect(tester, 'title').top, _rect(tester, 'a').top - 20);
    expect(_rect(tester, 'b').top, _rect(tester, 'title').bottom);
  });

  testWidgets('880 dp: a card that opens with its own heading is lifted the same way', (tester) async {
    await _pump(tester, 880, [_card('a', 300), const _Headed(key: Key('headed'), height: 260)]);
    expect(_rect(tester, 'headed').left, greaterThan(440));
    expect(_rect(tester, 'headed').top, _rect(tester, 'a').top - 20);
  });

  testWidgets('880 dp: headings on top of both columns line up, an empty card is not lifted', (tester) async {
    await _pump(tester, 880, [
      const SectionTitle('Left', key: Key('left')),
      _card('a', 280),
      const SectionTitle('Right', key: Key('right')),
      _card('b', 280),
    ]);
    expect(_rect(tester, 'right').top, _rect(tester, 'left').top);
    // Already level: neither is lifted.
    expect(_rect(tester, 'left').top, 0);
    await _pump(tester, 880, [_card('a', 300), const _Headed(key: Key('empty'), height: 0), _card('b', 260)]);
    expect(_rect(tester, 'b').top, _rect(tester, 'a').top);
  });

  testWidgets('880 dp: a heading on top of the left column lines up with the card on the right', (tester) async {
    await _pump(tester, 880, [
      const SectionTitle('Help', key: Key('title')),
      _card('a', 200),
      _card('b', 260),
    ]);
    expect(_rect(tester, 'b').left, greaterThan(440));
    expect(_rect(tester, 'title').top, _rect(tester, 'b').top - 20);
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

  testWidgets('Nearby > Eat on a fold: hawkers left, halal right, the two headings level', (tester) async {
    const c = Condition('fold', size: Size(880, 600));
    await applyCondition(tester, c);
    await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
    await settle(tester);
    containerOf(tester)
      ..read(shellTabProvider.notifier).state = 1
      ..read(nearbySectionProvider.notifier).state = 'eat';
    await settle(tester);
    final strings = containerOf(tester).read(stringsProvider);
    final eat = tester.getRect(find.widgetWithText(SectionTitle, strings.eat));
    final halal = tester.getRect(find.widgetWithText(SectionTitle, strings.halalNearby));
    expect(eat.right, lessThan(440));
    expect(halal.left, greaterThan(440));
    Finder title(String t) => find.descendant(of: find.byType(SectionTitle), matching: find.text(t));
    expect(tester.getCenter(title(strings.eat)).dy, tester.getCenter(title(strings.halalNearby)).dy);
  });

  testWidgets('Nearby > Help on a fold: 995 and 999 side by side, the two lists level under them', (tester) async {
    const c = Condition('fold', size: Size(880, 600));
    await applyCondition(tester, c);
    await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
    await settle(tester);
    containerOf(tester)
      ..read(shellTabProvider.notifier).state = 1
      ..read(nearbySectionProvider.notifier).state = 'help';
    await settle(tester);
    final strings = containerOf(tester).read(stringsProvider);
    final c995 = tester.getRect(find.text(strings.call995));
    final c999 = tester.getRect(find.text(strings.call999));
    expect(c995.center.dy, c999.center.dy);
    expect(c995.left, lessThan(440));
    expect(c999.left, greaterThan(440));
    Finder title(String t) => find.descendant(of: find.byType(SectionTitle), matching: find.text(t));
    // The two heading rows start on one line (the test font is wider, so a title may wrap).
    Rect row(String t) =>
        tester.getRect(find.descendant(of: find.widgetWithText(SectionTitle, t), matching: find.byType(Row)).first);
    expect(row(strings.helpNearby).top, row(strings.meetingPoints).top);
    expect(tester.getCenter(title(strings.meetingPoints)).dx, greaterThan(440));
    expect(c999.bottom, lessThan(tester.getRect(title(strings.helpNearby)).top));
  });

  testWidgets('the tabs fade under the status bar as under the tab bar, and taps go through', (tester) async {
    const c = Condition('fold', size: Size(880, 600));
    await applyCondition(tester, c);
    tester.view.padding = const FakeViewPadding(top: 24 * 3);
    tester.view.viewPadding = const FakeViewPadding(top: 24 * 3);
    await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
    await settle(tester);
    final fade = find.descendant(of: find.byType(StatusBarFade), matching: find.byType(DecoratedBox));
    expect(tester.getRect(fade), Rect.fromLTWH(0, 0, 880, 24 + StatusBarFade.reach));
    expect(find.descendant(of: find.byType(StatusBarFade), matching: find.byType(IgnorePointer)), findsOneWidget);
    // Nothing on the page at the top is under the fade.
    expect(tester.getTopLeft(find.byType(StickerIconButton).first).dy, greaterThanOrEqualTo(24 + StatusBarFade.reach));
  });

  testWidgets('the tabs keep their place through fold and unfold, and tap-again goes to the top', (tester) async {
    const c = Condition('fold', size: Size(880, 600));
    await applyCondition(tester, c);
    await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
    await settle(tester);
    final shell = tester.state(find.byType(AppShell));
    ScrollPosition today() => Scrollable.of(tester.element(find.text('MRT & LRT').first)).position;
    // Two columns: the trip's MRT card is beside its bus card, not under it.
    final strings = containerOf(tester).read(stringsProvider);
    expect(tester.getTopLeft(find.text(strings.mrtOption).first).dx, greaterThan(440));
    expect(tester.getTopLeft(find.text(strings.busesTo('Work')).first).dx, lessThan(440));
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
