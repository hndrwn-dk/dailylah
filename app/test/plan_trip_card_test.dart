// "Plan a trip" on Today (`PlanTripCard` in ui/trip.dart): "Where to?" opens the planner on its
// place search, a saved place's chip opens it with that destination picked, the heading opens it
// as it is, and on a wide window the card spans both columns.
import 'package:dailylah/l10n.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/address_picker.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const s = S();

Finder _inCard(Finder f) => find.descendant(of: find.byType(PlanTripCard), matching: f);

Future<void> _open(WidgetTester tester, Condition c) async {
  await applyCondition(tester, c);
  await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
  await settle(tester);
  await tester.scrollUntilVisible(find.text(s.whereTo), 300, scrollable: find.byType(Scrollable).first);
  await settle(tester);
}

void main() {
  testWidgets('a saved place chip opens the planner with that destination', (tester) async {
    await _open(tester, const Condition('phone'));
    final box = containerOf(tester);
    for (final name in ['Home', 'Work', 'School']) {
      expect(_inCard(find.text(name)), findsOneWidget, reason: name);
    }
    await tester.tap(_inCard(find.text('Work')));
    await settle(tester);
    expect(find.byType(TripPlannerPage), findsOneWidget);
    expect(box.read(goKeyProvider), 'work');
    expect(box.read(goFromKeyProvider), isNot('work'));
  });

  testWidgets('picking the place the planner starts from starts it from here instead', (tester) async {
    await _open(tester, const Condition('phone'));
    final box = containerOf(tester);
    box.read(goFromKeyProvider.notifier).state = 'home';
    await tester.tap(_inCard(find.text('Home')));
    await settle(tester);
    expect(box.read(goKeyProvider), 'home');
    expect(box.read(goFromKeyProvider), 'here');
  });

  testWidgets('"Where to?" opens the place search for the destination', (tester) async {
    await _open(tester, const Condition('phone'));
    await tester.tap(_inCard(find.bySemanticsLabel(s.whereTo)));
    await settle(tester);
    expect(find.byType(AddressPickerPage), findsOneWidget);
    expect(find.byType(TripPlannerPage, skipOffstage: false), findsOneWidget, reason: 'under the search');
  });

  testWidgets('the heading opens the planner as it is', (tester) async {
    await _open(tester, const Condition('phone'));
    await tester.tap(_inCard(find.text(s.planTrip)));
    await settle(tester);
    expect(find.byType(TripPlannerPage), findsOneWidget);
    expect(find.byType(AddressPickerPage), findsNothing);
  });

  for (final c in const [Condition('fold', size: Size(880, 600)), Condition('big', textScale: 2)]) {
    testWidgets('${c.name}: the card fits, every tap target is 48 dp', (tester) async {
      await _open(tester, c);
      final card = tester.getRect(find.byType(PlanTripCard));
      if (c.name == 'fold') {
        // Across both columns: as wide as the page's cards, not one column.
        expect(card.width, greaterThan(700));
      }
      for (final e in _inCard(find.byType(InkWell)).evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        expect(r.height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
