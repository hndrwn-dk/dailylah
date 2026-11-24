// The MRT & LRT card on Today (`_MrtCard` in ui/today.dart): one status pill, the starred lines as
// tiles, the other lines as plates, and each disrupted line in its own red box.
import 'package:dailylah/l10n.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const s = S();

Finder _card() => find.ancestor(of: find.text(s.mrtLinesAll).first, matching: find.byType(Panel)).first;

Finder _inCard(Finder f) => find.descendant(of: _card(), matching: f);

Future<void> _open(WidgetTester tester, {Favorites fav = householdFavorites, String? down, DateTime? at}) async {
  const c = Condition('phone');
  await applyCondition(tester, c);
  await tester.pumpWidget(appUnder(c, fav, at ?? tuesdayMorning, disruptedLine: down));
  await settle(tester);
  await tester.scrollUntilVisible(find.text(s.mrtLinesAll), 300, scrollable: find.byType(Scrollable).first);
  await settle(tester);
}

void main() {
  testWidgets('all running: one pill, no "Running normally" per line, starred lines as tiles', (tester) async {
    await _open(tester);
    expect(_inCard(find.text(s.mrtAllRunning(trainLines.length))), findsOneWidget);
    expect(_inCard(find.text(s.mrtNormal)), findsNothing);
    // householdFavorites stars DTL and EWL: two tiles with their names, the rest as plates.
    expect(_inCard(find.bySemanticsLabel(RegExp('^${trainLines['DTL']}, starred'))), findsOneWidget);
    expect(_inCard(find.bySemanticsLabel(RegExp('^${trainLines['EWL']}, starred'))), findsOneWidget);
    expect(_inCard(find.byTooltip('${trainLines['NSL']} · ${s.starLine}')), findsOneWidget);
    expect(_inCard(find.text(s.starHint)), findsOneWidget);
  });

  testWidgets('tapping a tile unstars the line; tapping a plate stars it; a fourth star is refused', (tester) async {
    await _open(tester);
    final container = containerOf(tester);
    await tester.tap(_inCard(find.bySemanticsLabel(RegExp('^${trainLines['DTL']}, starred'))));
    await settle(tester);
    expect(container.read(favoritesProvider).lines, {'EWL'});
    await tester.tap(_inCard(find.byTooltip('${trainLines['NSL']} · ${s.starLine}')));
    await settle(tester);
    await tester.tap(_inCard(find.byTooltip('${trainLines['CCL']} · ${s.starLine}')));
    await settle(tester);
    expect(container.read(favoritesProvider).lines, {'EWL', 'NSL', 'CCL'});
    await tester.tap(_inCard(find.byTooltip('${trainLines['TEL']} · ${s.starLine}')));
    await tester.pump();
    expect(find.text(s.maxStarredLines), findsOneWidget);
    expect(container.read(favoritesProvider).lines, {'EWL', 'NSL', 'CCL'});
  });

  testWidgets('a disruption: red pill, its own box with what LTA says, the starred tile says Disrupted',
      (tester) async {
    await _open(tester, down: 'EWL');
    expect(_inCard(find.text(s.mrtLinesDown(1))), findsOneWidget);
    expect(_inCard(find.text('${trainLines['EWL']} · ${s.mrtDisrupted}')), findsOneWidget);
    expect(_inCard(find.bySemanticsLabel(RegExp('^${trainLines['EWL']}, starred, ${s.mrtDisrupted}'))), findsOneWidget);
    expect(_inCard(find.text(s.mrtAllRunning(trainLines.length))), findsNothing);
  });

  testWidgets('no starred lines: no tiles, every line a plate, and the hint about alerts for any line', (tester) async {
    await _open(tester, fav: householdFavorites.copyWith(lines: const {}));
    expect(_inCard(find.bySemanticsLabel(RegExp(', starred'))), findsNothing);
    expect(_inCard(find.byTooltip('${trainLines['EWL']} · ${s.starLine}')), findsOneWidget);
    expect(_inCard(find.text(s.starHintNone)), findsOneWidget);
  });

  testWidgets('at 200% text the tiles stack, one a row, and nothing overflows', (tester) async {
    const c = Condition('big', textScale: 2);
    await applyCondition(tester, c);
    await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayEvening));
    await settle(tester);
    await tester.scrollUntilVisible(find.text(s.mrtLinesAll), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    final a = tester.getRect(_inCard(find.bySemanticsLabel(RegExp('^${trainLines['EWL']}, starred'))));
    final b = tester.getRect(_inCard(find.bySemanticsLabel(RegExp('^${trainLines['DTL']}, starred'))));
    expect(a.left, b.left);
    expect(a.top, isNot(b.top));
    expect(tester.takeException(), isNull);
  });
}
