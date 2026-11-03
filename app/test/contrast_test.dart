// Text contrast on every tab and section, in light and dark mode.
//
// Renders each screen in a very tall window so the whole list is laid out at once (nothing
// sits under the floating tab bar), then runs Flutter's text contrast check: 4.5:1 for
// normal text, 3:1 for large text. This is what caught grey-on-dark chip labels in dark mode.
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/about.dart';
import 'package:dailylah/ui/home.dart';
import 'package:dailylah/ui/homes.dart';
import 'package:dailylah/ui/more.dart';
import 'package:dailylah/ui/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _tabs = {'Today': 0, 'Nearby': 1, 'Home': 2, 'History': 3, 'More': 4};
const _nearbySections = ['bus', 'eat', 'green', 'park', 'taxi', 'prayer', 'help'];

/// Tall enough that every list fits above the tab bar.
const _tall = Size(412, 6000);

Future<void> _open(WidgetTester tester, Condition c, {int tab = 0, void Function(ProviderContainer box)? set}) async {
  await applyCondition(tester, c);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = c.size;
  await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
  await settle(tester);
  final box = containerOf(tester);
  box.read(shellTabProvider.notifier).state = tab;
  set?.call(box);
  await settle(tester);
}

Future<void> _check(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  for (final c in const [
    Condition('light', size: _tall),
    Condition('dark', dark: true, size: _tall),
  ]) {
    group('[${c.name}] contrast', () {
      for (final (label, now) in [
        ('morning', tuesdayMorning),
        ('evening', tuesdayEvening),
        ('weekend', saturdayMorning),
      ]) {
        testWidgets('Today: $label', (tester) async {
          await applyCondition(tester, c);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = c.size;
          await tester.pumpWidget(appUnder(c, householdFavorites, now));
          await settle(tester);
          expect(find.byType(TodayPage), findsOneWidget);
          await _check(tester);
        });
      }

      for (final section in _nearbySections) {
        testWidgets('Nearby: $section', (tester) async {
          await _open(tester, c,
              tab: _tabs['Nearby']!, set: (box) => box.read(nearbySectionProvider.notifier).state = section);
          await _check(tester);
        });
      }

      for (final section in HomePage.sections) {
        testWidgets('Home: $section', (tester) async {
          await _open(tester, c,
              tab: _tabs['Home']!, set: (box) => box.read(homeSectionProvider.notifier).state = section);
          await _check(tester);
        });
      }

      testWidgets('History', (tester) async {
        await _open(tester, c, tab: _tabs['History']!);
        await containerOf(tester).read(habitsProvider.notifier).restore(sampleHabits(tuesdayMorning));
        await settle(tester);
        await _check(tester);
      });

      testWidgets('More', (tester) async {
        await _open(tester, c, tab: _tabs['More']!);
        expect(find.byType(MorePage), findsOneWidget);
        await _check(tester);
      });

      for (final (name, page) in [
        ('Block search', const BlockSearchPage()),
        ('About', const AboutDailyLahPage()),
      ]) {
        testWidgets('Page: $name', (tester) async {
          await applyCondition(tester, c);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = c.size;
          await tester.pumpWidget(pageUnder(c, const Favorites(), tuesdayMorning, page));
          await settle(tester);
          await _check(tester);
        });
      }
    });
  }
}
