// The "By MRT" card of a trip (`_MrtOption` in ui/trip.dart): the same status pill as the MRT &
// LRT card, the door to door minutes, the route drawn as a line, and each disrupted line of the
// trip in its own red box.
import 'package:dailylah/l10n.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const s = S();

Finder _card() => find.ancestor(of: find.text(s.mrtOption).first, matching: find.byType(Panel)).first;

Finder _inCard(Finder f) => find.descendant(of: _card(), matching: f);

Future<void> _open(WidgetTester tester, {String? down, Condition c = const Condition('phone')}) async {
  await applyCondition(tester, c);
  await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning, disruptedLine: down));
  await settle(tester);
  await tester.scrollUntilVisible(find.text(s.mrtOption), 300, scrollable: find.byType(Scrollable).first);
  await settle(tester);
}

void main() {
  testWidgets('running: one pill, the minutes door to door, the route from Home to Work', (tester) async {
    await _open(tester);
    expect(_inCard(find.text(s.mrtRunning)), findsOneWidget);
    expect(_inCard(find.textContaining('running normally')), findsNothing);
    expect(_inCard(find.text(s.mrtDoorNote)), findsOneWidget);
    expect(_inCard(find.textContaining(RegExp(r'^~\d+ min · \d+ stops$'))), findsOneWidget);
    // Both ends of the trip are on the line, with a walk at each end.
    expect(_inCard(find.text('Home')), findsOneWidget);
    expect(_inCard(find.text('Work')), findsOneWidget);
    expect(_inCard(find.textContaining(RegExp(r'^Walk .* min$'))), findsNWidgets(2));
    expect(_inCard(find.text(s.imOnTrain)), findsOneWidget);
    expect(_inCard(find.text(s.changeLine)), findsOneWidget);
    expect(_inCard(find.text(s.mrtRouteInMaps)), findsOneWidget);
  });

  testWidgets('a disruption on the trip\'s line: red pill and its own box', (tester) async {
    await _open(tester, down: 'EWL');
    expect(_inCard(find.text(s.mrtLinesDown(1))), findsOneWidget);
    expect(_inCard(find.byType(MrtDisruptionBox)), findsOneWidget);
    expect(_inCard(find.text(s.mrtRunning)), findsNothing);
  });

  for (final c in const [Condition('big', textScale: 2), Condition('small', size: Size(320, 640))]) {
    testWidgets('${c.name}: the route still fits', (tester) async {
      await _open(tester, c: c);
      expect(_inCard(find.text(s.mrtDoorNote)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
