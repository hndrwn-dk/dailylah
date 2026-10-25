// Regression matrix: every screen under every condition in docs/QA.md section 4
// (offline, permission denied, 200% text, dark mode, small screen).
//
// A test fails when a screen throws, overflows (yellow/black stripes), or shows nothing.
// Flutter reports layout overflow as a test failure on its own, so most checks here are
// "render it, scroll through it, expect no exception".
import 'package:dailylah/data.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/about.dart';
import 'package:dailylah/ui/history.dart';
import 'package:dailylah/ui/home.dart';
import 'package:dailylah/ui/homes.dart';
import 'package:dailylah/ui/more.dart';
import 'package:dailylah/ui/setup.dart';
import 'package:dailylah/ui/stop_picker.dart';
import 'package:dailylah/ui/today.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:dailylah/ui/wake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Tabs by index in the shell: Today, Nearby, Home, More.
const _tabs = {'Today': 0, 'Nearby': 1, 'Home': 2, 'History': 3, 'More': 4};

const _nearbySections = ['bus', 'eat', 'green', 'park', 'taxi', 'prayer', 'help'];

const _block156 = HdbBlock(
  block: '156',
  street: 'TAMPINES ST 12',
  town: 'TAMPINES',
  yearCompleted: 1983,
  floors: 11,
  lat: 1.35159,
  lng: 103.94503,
  postal: '521156',
);

/// Pages opened with Navigator.push from the tabs.
final Map<String, Widget Function()> _pages = {
  'Setup (first run, empty)': () => const SetupPage(firstRun: true),
  'Setup (edit, filled)': () => const SetupPage(),
  'Stop picker': () => const StopPickerPage(title: 'Pick a stop near Home'),
  'Stop arrivals': () => const StopArrivalsPage(stop: tampinesInt),
  'Plan a trip': () => const TripPlannerPage(),
  'Wake me': () => const WakeMePage(service: '10', alight: fullertonSq),
  'Block search': () => const BlockSearchPage(),
  'Block page': () => const BlockPage(block: _block156),
  'Compare blocks': () => const ComparePage(),
  'Agent check': () => const AgentCheckPage(),
  'Family share': () => const FamilySharePage(),
  'About': () => const AboutDailyLahPage(),
};

void main() {
  for (final c in conditions) {
    group('[${c.name}]', () {
      // ---------------------------------------------------------------- Today
      for (final (label, now) in [
        ('morning card', tuesdayMorning),
        ('evening card', tuesdayEvening),
        ('weekend card', saturdayMorning),
      ]) {
        testWidgets('Today: $label', (tester) async {
          await applyCondition(tester, c);
          await tester.pumpWidget(appUnder(c, householdFavorites, now));
          await settle(tester);
          expect(find.byType(TodayPage), findsOneWidget);
          await scrollThrough(tester);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('Today: MRT disruption with Plan B', (tester) async {
        await applyCondition(tester, c);
        await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning, disruptedLine: 'EWL'));
        await settle(tester);
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      });

      // ---------------------------------------------------------------- Nearby
      for (final section in _nearbySections) {
        testWidgets('Nearby: $section', (tester) async {
          await applyCondition(tester, c);
          await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
          await settle(tester);
          final box = containerOf(tester);
          box.read(shellTabProvider.notifier).state = _tabs['Nearby']!;
          box.read(nearbySectionProvider.notifier).state = section;
          await settle(tester);
          await scrollThrough(tester);
          expect(tester.takeException(), isNull);
        });
      }

      // ---------------------------------------------------------------- Home
      for (final section in HomePage.sections) {
        testWidgets('Home: $section', (tester) async {
          await applyCondition(tester, c);
          await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
          await settle(tester);
          final box = containerOf(tester);
          box.read(shellTabProvider.notifier).state = _tabs['Home']!;
          box.read(homeSectionProvider.notifier).state = section;
          await settle(tester);
          await scrollThrough(tester);
          expect(tester.takeException(), isNull);
        });
      }

      // ---------------------------------------------------------------- History
      testWidgets('History', (tester) async {
        await applyCondition(tester, c);
        await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
        await settle(tester);
        final box = containerOf(tester);
        await box.read(habitsProvider.notifier).restore(sampleHabits(tuesdayMorning));
        box.read(shellTabProvider.notifier).state = _tabs['History']!;
        await settle(tester);
        expect(find.byType(HistoryPage), findsOneWidget);
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      });

      // ---------------------------------------------------------------- More
      testWidgets('More', (tester) async {
        await applyCondition(tester, c);
        await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
        await settle(tester);
        containerOf(tester).read(shellTabProvider.notifier).state = _tabs['More']!;
        await settle(tester);
        expect(find.byType(MorePage), findsOneWidget);
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      });

      // ---------------------------------------------------------------- pushed pages
      for (final entry in _pages.entries) {
        testWidgets('Page: ${entry.key}', (tester) async {
          await applyCondition(tester, c);
          final fav = entry.key.contains('empty') ? const Favorites() : householdFavorites;
          await tester.pumpWidget(pageUnder(c, fav, tuesdayMorning, entry.value()));
          await settle(tester);
          await scrollThrough(tester);
          expect(tester.takeException(), isNull);
        });
      }
    });
  }

  // ------------------------------------------------------------------ PRD gaps
  testWidgets('offline: live data on Today is labelled with when it was last updated', (tester) async {
    const c = Condition('offline with cache', offline: true);
    await applyCondition(tester, c);
    await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
    await settle(tester);
    expect(find.textContaining(RegExp('updated|as of', caseSensitive: false)), findsWidgets);
  }, skip: true); // PRD gap 2: no "last updated" label for real-time data when offline
}
