// The tabs scroll their last item clear of everything that floats at the bottom: the tab bar and,
// while a trip runs, the trip bar above it (`navClearance` in widgets.dart).
import 'package:dailylah/l10n.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const s = S();

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text(s.pullToRefresh), 400, scrollable: find.byType(Scrollable).first);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
  await settle(tester);
}

void main() {
  for (final c in const [Condition('phone'), Condition('big', textScale: 2)]) {
    testWidgets('${c.name}: with a trip running, the end of Today is above the trip bar', (tester) async {
      await applyCondition(tester, c);
      await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
      await settle(tester);
      await containerOf(tester)
          .read(habitsProvider.notifier)
          .startTrip('home>work', DateTime.now().subtract(const Duration(minutes: 5)));
      await settle(tester);
      expect(find.byType(TripBanner), findsOneWidget);
      await _scrollToEnd(tester);
      final bar = tester.getRect(find.byType(TripBanner));
      final end = tester.getRect(find.text(s.pullToRefresh));
      expect(end.bottom, lessThanOrEqualTo(bar.top));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('without a trip the space under the list stays the same', (tester) async {
    const c = Condition('phone');
    await applyCondition(tester, c);
    await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
    await settle(tester);
    await _scrollToEnd(tester);
    final nav = tester.getRect(find.byType(PillNav));
    final end = tester.getRect(find.text(s.pullToRefresh));
    expect(end.bottom, lessThanOrEqualTo(nav.top));
  });
}
