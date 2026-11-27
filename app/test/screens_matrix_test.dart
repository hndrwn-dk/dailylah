// Regression matrix: every screen under every condition in docs/QA.md section 4
// (offline, permission denied, 200% text, dark mode, small screen).
//
// A test fails when a screen throws, overflows (yellow/black stripes), or shows nothing.
// Flutter reports layout overflow as a test failure on its own, so most checks here are
// "render it, scroll through it, expect no exception".
import 'package:dailylah/data.dart';
import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/mrt_ride.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/wake_session.dart';
import 'package:dailylah/ui/about.dart';
import 'package:dailylah/ui/address_picker.dart';
import 'package:dailylah/ui/bus_sheet.dart';
import 'package:dailylah/ui/history.dart';
import 'package:dailylah/ui/home.dart';
import 'package:dailylah/ui/homes.dart';
import 'package:dailylah/ui/more.dart';
import 'package:dailylah/ui/mrt_ride.dart';
import 'package:dailylah/ui/setup.dart';
import 'package:dailylah/ui/stop_picker.dart';
import 'package:dailylah/ui/today.dart';
import 'package:dailylah/ui/toilets.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:dailylah/ui/wake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Tabs by index in the shell: Today, Nearby, Home, More.
const _tabs = {'Today': 0, 'Nearby': 1, 'Home': 2, 'History': 3, 'More': 4};

const _nearbySections = ['bus', 'eat', 'green', 'park', 'taxi', 'toilet', 'prayer', 'help'];

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

const _blockWoodlands = HdbBlock(
  block: '1',
  street: 'MARSILING DR',
  town: 'WOODLANDS',
  yearCompleted: 1973,
  floors: 11,
  lat: 1.44062,
  lng: 103.77573,
  postal: '730001',
);

/// Woodlands is the office area itself: "In this area", no fare estimate, no best in its lines.
final _officeTown = householdFavorites.copyWith(
  wtlArea: 'woodlands',
  compareBlocks: ['1|MARSILING DR', '156|TAMPINES ST 12', '101|ANG MO KIO AVE 3'],
);

/// Pages opened with Navigator.push from the tabs.
final Map<String, Widget Function()> _pages = {
  'Setup (first run, empty)': () => const SetupPage(firstRun: true),
  'Setup (edit, filled)': () => const SetupPage(),
  'Stop picker': () => const StopPickerPage(title: 'Pick a stop near Home'),
  'Stop arrivals': () => const StopArrivalsPage(stop: tampinesInt),
  'Plan a trip': () => const TripPlannerPage(),
  'Plan a trip (Home → Work by bus)': () => const _PlannerWith(from: 'home', to: 'work'),
  'Plan a trip (searched address → Gym)': () => const _PlannerWith(from: 'adhoc', to: 'extra:0'),
  'Plan a trip (no direct bus: ways with changes)': () => const _PlannerWith(
      from: 'adhoc',
      to: 'adhoc',
      dest: Place(
          kind: PlaceKind.other, name: 'ST Engineering Hub', address: 'ST Engineering Hub', addrLat: 1.3917, addrLng: 103.8480)),
  'Address search (shared, no address)': () =>
      AddressPickerPage(title: 'Search', note: const S().sharedNoAddress('Putra Minang Restaurant Bencoolen')),
  'Wake me': () => const WakeMePage(service: '10', alight: fullertonSq),
  'Running trip': () => const _RunningTrip(),
  'Running trip (step by step)': () => const _RunningTrip(steps: [
        TripStep(kind: StepKind.walk, from: '', to: '75009', fromName: '', toName: 'Tampines Int', minutes: 4),
        TripStep(
            kind: StepKind.bus,
            from: '75009',
            to: '03011',
            fromName: 'Tampines Int',
            toName: 'Fullerton Sq',
            service: '10',
            stops: 30,
            minutes: 48,
            routeKey: '10|1'),
        TripStep(kind: StepKind.walk, from: '03011', to: '', fromName: 'Fullerton Sq', toName: '', minutes: 3),
      ]),
  'Need a toilet? (bus)': () => const _ToiletSheetOnBus(),
  'Block search': () => const BlockSearchPage(),
  'Block page': () => const BlockPage(block: _block156),
  'Compare blocks': () => const ComparePage(),
  'Compare blocks (one block, add another)': () => const ComparePage(),
  'Add a block to compare': () => BlockSearchPage(onPick: (_) {}),
  'Block page (office area in its town)': () => const BlockPage(block: _blockWoodlands),
  'Compare blocks (one in the office area)': () => const ComparePage(),
  'Agent check': () => const AgentCheckPage(),
  'Family share': () => const FamilySharePage(),
  'About': () => const AboutDailyLahPage(),
  'On the train': () => const _OnTheTrain(),
  'Need a toilet? (train)': () => const _OnTheTrain(toilets: true),
  'Taxi': () => Scaffold(body: TaxiSheet(origin: householdFavorites.places[PlaceKind.home]!)),
  "Where's my bus": () => const Scaffold(body: WhereBusSheet(stop: tampinesInt, service: '10')),
  'Today: at the office (greeting instead of the trip)': () => const Scaffold(
        body: SingleChildScrollView(child: AtPlaceCard(kind: PlaceKind.work, leaveAt: TimeOfDayHM(18, 0))),
      ),
  'Today: at the office at lunch time': () => const Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            AtPlaceCard(
              kind: PlaceKind.work,
              leaveAt: TimeOfDayHM(18, 0),
              lunch: LunchPick(
                  Hawker(id: 'x', name: 'Tampines Round Market & Food Centre', address: '', lat: 1.35, lng: 103.94), 250),
            ),
            LunchCard(),
          ]),
        ),
      ),
  'Change line': () => Scaffold(
        body: MrtLineSheet(
          from: householdFavorites.places[PlaceKind.home]!,
          to: householdFavorites.places[PlaceKind.work]!,
        ),
      ),
};

/// "Need a toilet?" on bus 10 from Tampines Int (toilets from the harness).
class _ToiletSheetOnBus extends ConsumerStatefulWidget {
  const _ToiletSheetOnBus();

  @override
  ConsumerState<_ToiletSheetOnBus> createState() => _ToiletSheetOnBusState();
}

class _ToiletSheetOnBusState extends ConsumerState<_ToiletSheetOnBus> {
  static const _alight = BusStop(code: '96109', name: 'Opp Blk 3012', road: 'Simei St 1', lat: 1.337371, lng: 103.950673);

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(wakeProvider.notifier).start('10', _alight, null, from: tampinesInt));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: ToiletSheet(ride: ToiletRide.bus));
}

/// The board of a trip being timed from Tampines Int to Fullerton, one tap from the trip bar.
class _RunningTrip extends ConsumerStatefulWidget {
  const _RunningTrip({this.steps = const []});

  /// A trip with changes shows its steps.
  final List<TripStep> steps;

  @override
  ConsumerState<_RunningTrip> createState() => _RunningTripState();
}

class _RunningTripState extends ConsumerState<_RunningTrip> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(habitsProvider.notifier).startTrip(
          'Home>Fullerton',
          tuesdayMorning.subtract(const Duration(minutes: 9)),
          to: const Place(kind: PlaceKind.other, name: 'Fullerton', addrLat: 1.285618, addrLng: 103.853422),
          stop: widget.steps.isEmpty ? tampinesInt.code : null,
          steps: widget.steps,
        ));
  }

  @override
  Widget build(BuildContext context) => const RunningTripPage();
}

/// "I'm on the train" from Tampines to Raffles Place: the ride page, or its "Need a toilet?" sheet.
class _OnTheTrain extends ConsumerStatefulWidget {
  const _OnTheTrain({this.toilets = false});
  final bool toilets;

  @override
  ConsumerState<_OnTheTrain> createState() => _OnTheTrainState();
}

class _OnTheTrainState extends ConsumerState<_OnTheTrain> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final stations = await ref.read(mrtStationsProvider.future);
      final fav = householdFavorites.places;
      final plan = mrtPlan(stations, fav[PlaceKind.home]!, fav[PlaceKind.work]!);
      final ride = plan == null ? null : mrtRide(stations, plan);
      if (ride != null && mounted) await ref.read(rideProvider.notifier).start(ride);
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.toilets ? const Scaffold(body: ToiletSheet(ride: ToiletRide.train)) : const MrtRidePage();
}

/// The trip planner with both ends already picked, as after a few taps.
class _PlannerWith extends ConsumerStatefulWidget {
  const _PlannerWith({required this.from, required this.to, this.dest});
  final String from;
  final String to;

  /// The searched destination when [to] is 'adhoc'.
  final Place? dest;

  @override
  ConsumerState<_PlannerWith> createState() => _PlannerWithState();
}

class _PlannerWithState extends ConsumerState<_PlannerWith> {
  @override
  void initState() {
    super.initState();
    // After the planner's own start (Here, once the location comes in).
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      ref.read(goAdhocFromProvider.notifier).state = const Place(
        kind: PlaceKind.other,
        name: 'Marine Parade Central Hawker Centre And Market',
        address: '84 MARINE PARADE CENTRAL',
        addrLat: 1.3025,
        addrLng: 103.9071,
      );
      if (widget.dest != null) ref.read(goAdhocDestProvider.notifier).state = widget.dest;
      ref.read(goFromKeyProvider.notifier).state = widget.from;
      ref.read(goKeyProvider.notifier).state = widget.to;
    });
  }

  @override
  Widget build(BuildContext context) => const TripPlannerPage();
}

/// Screens with an open finding (docs/QA.md "Open findings"): skipped under the conditions where
/// they fail today, so the finding stays visible in the test run. Remove the entry in the pull
/// request that fixes it.
final Map<String, bool Function(Condition)> _knownIssues = {};

bool _knownIssue(String test, Condition c) => _knownIssues[test]?.call(c) ?? false;

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
          await expectAccessible(tester);
          await scrollThrough(tester, accessible: true);
          await expectAccessible(tester);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets("Today: What's new after an update", (tester) async {
        await applyCondition(tester, c);
        await tester.pumpWidget(ProviderScope(retry: noRetry,
          overrides: [
            ...overridesFor(c, householdFavorites, tuesdayMorning),
            releaseVersionProvider.overrideWithValue('1.6.0'),
          ],
          child: const DailyLahApp(),
        ));
        await settle(tester);
        // At 200% text the hero pushes the card below the first screen, so scroll to it.
        await tester.scrollUntilVisible(find.byType(WhatsNewCard), 200,
            scrollable: find.byType(Scrollable).hitTestable().first);
        expect(find.byType(WhatsNewCard), findsOneWidget);
        await expectAccessible(tester);
        await scrollThrough(tester, accessible: true);
        await expectAccessible(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Today: MRT disruption with Plan B', (tester) async {
        await applyCondition(tester, c);
        await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning, disruptedLine: 'EWL'));
        await settle(tester);
        await expectAccessible(tester);
        await scrollThrough(tester, accessible: true);
        await expectAccessible(tester);
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
          await expectAccessible(tester);
          await scrollThrough(tester, accessible: true);
          await expectAccessible(tester);
          expect(tester.takeException(), isNull);
        });
      }

      // What My home links to on a page of its own.
      for (final topic in HomePage.topics) {
        testWidgets('Home: $topic page', (tester) async {
          await applyCondition(tester, c);
          await tester.pumpWidget(pageUnder(c, householdFavorites, tuesdayMorning, HomeTopicPage(topic: topic)));
          await settle(tester);
          await expectAccessible(tester);
          await scrollThrough(tester, accessible: true);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('Nearby: the list of places', (tester) async {
        await applyCondition(tester, c);
        await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
        await settle(tester);
        containerOf(tester).read(shellTabProvider.notifier).state = _tabs['Nearby']!;
        await settle(tester);
        await tester.tap(find.byTooltip(const S().nearbyChangePlace));
        await settle(tester);
        expect(find.text(const S().nearbyWhere), findsOneWidget);
        await expectAccessible(tester);
        expect(tester.takeException(), isNull);
      });

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
          await expectAccessible(tester);
          await scrollThrough(tester, accessible: true);
          await expectAccessible(tester);
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
        await expectAccessible(tester);
        await scrollThrough(tester, accessible: true);
        await expectAccessible(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('History: meal sheet (price, day and time)', (tester) async {
        await applyCondition(tester, c);
        await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
        await settle(tester);
        final box = containerOf(tester);
        await box.read(habitsProvider.notifier).restore(Habits(
          meals: [MealLog(hawkerId: 'p:1.35000,103.94000', at: DateTime(2026, 10, 20, 6, 30), name: 'Test Kitchen')],
        ));
        box.read(shellTabProvider.notifier).state = _tabs['History']!;
        await settle(tester);
        // Bring the row clear of the floating tab bar, then open its sheet.
        final row = find.text('Test Kitchen');
        final list = find.byType(Scrollable).hitTestable().first;
        await tester.scrollUntilVisible(row, 150, scrollable: list);
        await Scrollable.ensureVisible(tester.element(row), alignment: 0.4);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(row);
        await settle(tester);
        expect(find.text(const S().mealChangeTime), findsOneWidget);
        await expectAccessible(tester);
        await scrollThrough(tester, times: 3, accessible: true);
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
        await expectAccessible(tester);
        await scrollThrough(tester, accessible: true);
        await expectAccessible(tester);
        expect(tester.takeException(), isNull);
      });

      // ---------------------------------------------------------------- pushed pages
      for (final entry in _pages.entries) {
        testWidgets('Page: ${entry.key}', skip: _knownIssue('Page: ${entry.key}', c), (tester) async {
          await applyCondition(tester, c);
          final fav = entry.key.contains('empty')
              ? const Favorites()
              : entry.key.contains('office area')
                  ? _officeTown
                  : entry.key.contains('one block')
                      ? householdFavorites.copyWith(compareBlocks: ['156|TAMPINES ST 12'], recentBlocks: ['101|ANG MO KIO AVE 3'])
                      : householdFavorites;
          await tester.pumpWidget(pageUnder(c, fav, tuesdayMorning, entry.value()));
          await settle(tester);
          // The block page runs long (commute and the town board): scroll to its end.
          await expectAccessible(tester);
          // A ride must be running, or these two pages are empty and prove nothing.
          if (entry.key.contains('train') && c.cachedBundles) {
            expect(containerOf(tester).read(rideProvider), isNotNull, reason: 'no ride was started');
          }
          await scrollThrough(tester, times: entry.key.startsWith('Block page') ? 30 : 8, accessible: true);
          await expectAccessible(tester);
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
