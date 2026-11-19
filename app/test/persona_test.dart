// Persona journeys (docs/QA.md "Persona journeys"): what five kinds of people do with the app, as
// far as the other tests do not already follow it. Each test is one journey through the real
// widgets with the fakes in support/harness.dart: a fixed clock, a fake API, no network.
//
//   Office worker      fixed commute, Wake me on the bus, the app killed in the middle of a trip
//   Student            school as the only commute, MOE school holidays, a code from a parent
//   University student a server that is slow to wake up
//   Homemaker          only a home saved, no commute at all
//   Senior             the largest text, every permission denied
//
// A new feature adds its case to the persona it matters to.
import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/home.dart';
import 'package:dailylah/ui/more.dart';
import 'package:dailylah/ui/today.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:dailylah/ui/wake.dart';
import 'package:dailylah/wake_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/harness.dart';

const _normal = Condition('normal');
const _s = S();
const _tabs = ['Today', 'Nearby', 'Home', 'History', 'More'];
const _nearbySections = ['bus', 'eat', 'green', 'park', 'taxi', 'toilet', 'prayer', 'help'];

final _home = householdFavorites.places[PlaceKind.home]!;
final _school = householdFavorites.places[PlaceKind.school]!;

/// Someone at home all day: a home and nothing else.
final _homeOnly = Favorites(places: {PlaceKind.home: _home}, onboarded: true);

/// A student: home and school, no work.
final _student = Favorites(places: {PlaceKind.home: _home, PlaceKind.school: _school}, onboarded: true);

/// The server takes [wait] to answer (Render waking up from sleep).
class _SlowApi extends FakeApi {
  _SlowApi(this.wait);
  final Duration wait;

  @override
  Future<Map<String, dynamic>> forecast() => Future.delayed(wait, super.forecast);
  @override
  Future<Map<String, dynamic>> trainAlerts() => Future.delayed(wait, super.trainAlerts);
  @override
  Future<Map<String, dynamic>> busArrival(String stopCode) => Future.delayed(wait, () => super.busArrival(stopCode));
  @override
  Future<Map<String, dynamic>> weather(String kind) => Future.delayed(wait, () => super.weather(kind));
  @override
  Future<Map<String, dynamic>> taxis() => Future.delayed(wait, super.taxis);
}

/// Every alert the app posts through its notification plugin while the test runs.
List<Map<Object?, Object?>> _alerts(WidgetTester tester) {
  final shown = <Map<Object?, Object?>>[];
  const channel = MethodChannel('dailylah/notify');
  const plain = MethodChannel('dexterous.com/flutter/local_notifications');
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(plain, (call) async => switch (call.method) {
        'initialize' || 'areNotificationsEnabled' || 'requestNotificationsPermission' => true,
        _ => null,
      });
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'show') shown.add((call.arguments as Map).cast<Object?, Object?>());
    return true;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(plain, null);
  });
  return shown;
}

void main() {
  group('Office worker', () {
    testWidgets('Wake me keeps watching on every tab, and Stop ends it', (tester) async {
      await applyCondition(tester, _normal);
      final alerts = _alerts(tester);
      await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayEvening));
      await settle(tester);
      final box = containerOf(tester);
      // On bus 10 at Tampines Int, a long way from Fullerton Sq.
      await tester.runAsync(() => box.read(wakeProvider.notifier).start('10', fullertonSq, null, from: tampinesInt));
      await settle(tester);

      final riding = find.descendant(
          of: find.byType(WakeBanner), matching: find.textContaining(_s.wakeRiding('10', 'Fullerton Sq')));
      for (var tab = 0; tab < _tabs.length; tab++) {
        box.read(shellTabProvider.notifier).state = tab;
        await settle(tester);
        expect(riding, findsOneWidget, reason: 'the banner is gone on ${_tabs[tab]}');
      }
      expect(box.read(wakeProvider)!.left, greaterThan(5000));
      expect(alerts, isEmpty, reason: 'far from the stop: nothing to say yet');

      await tester.tap(find.descendant(of: find.byType(WakeBanner), matching: find.text(_s.wakeStop)));
      await settle(tester);
      expect(box.read(wakeProvider), isNull);
      expect(riding, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wake me at the stop: one alert, and the page says the stop is next', (tester) async {
      await applyCondition(tester, _normal);
      final alerts = _alerts(tester);
      // The phone is at Tampines Int, the stop to wake at.
      await tester.pumpWidget(
          pageUnder(_normal, householdFavorites, tuesdayEvening, const WakeMePage(service: '10', alight: tampinesInt)));
      await settle(tester);
      expect(find.text(_s.wakeNowAt('Tampines Int')), findsOneWidget);
      expect(alerts, hasLength(1));
      expect('${(alerts.single['note'] as Map)['body']}', contains('Tampines Int'));
      expect(containerOf(tester).read(wakeProvider)!.done, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Wake me without location says why and watches nothing', (tester) async {
      const denied = Condition('location denied', location: LocationPermission.deniedForever);
      await applyCondition(tester, denied);
      final alerts = _alerts(tester);
      await tester.pumpWidget(
          pageUnder(denied, householdFavorites, tuesdayEvening, const WakeMePage(service: '10', alight: fullertonSq)));
      await settle(tester);
      expect(find.text(_s.locationDenied), findsOneWidget);
      expect(containerOf(tester).read(wakeProvider)!.left, isNull);
      expect(alerts, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('A trip being timed is still there after the app is killed and opened again', (tester) async {
      await applyCondition(tester, _normal);
      await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
      await settle(tester);
      await containerOf(tester)
          .read(habitsProvider.notifier)
          .startTrip('home>work', DateTime.now().subtract(const Duration(minutes: 10)), mode: 'transit', km: 18);
      await settle(tester);
      final arrived = find.descendant(of: find.byType(TripBanner), matching: find.text('Arrived'));
      expect(arrived, findsOneWidget);

      // Killed and opened again: a new app on the same stored data.
      await tester.pumpWidget(KeyedSubtree(key: UniqueKey(), child: appUnder(_normal, householdFavorites, tuesdayMorning)));
      await settle(tester);
      expect(containerOf(tester).read(habitsProvider).tripRoute, 'home>work');
      expect(arrived, findsOneWidget);
      await tester.tap(arrived);
      await settle(tester);
      final trip = containerOf(tester).read(habitsProvider).trips.single;
      expect(trip.route, 'home>work');
      expect(trip.minutes, inInclusiveRange(10, 11));
      expect(arrived, findsNothing);
    });
  });

  group('Student', () {
    testWidgets('School is the trip on a school day; on an MOE school holiday a banner replaces it', (tester) async {
      await applyCondition(tester, _normal);
      // Tuesday 10 Nov 2026: a school day.
      await tester.pumpWidget(appUnder(_normal, _student, DateTime(2026, 11, 10, 6, 30)));
      await settle(tester);
      expect(find.byType(TripSection), findsOneWidget);
      expect(find.textContaining('no school today'), findsNothing);

      // Tuesday 24 Nov 2026: Year-end holidays in web/data/school_holidays.json.
      await tester.pumpWidget(
          KeyedSubtree(key: UniqueKey(), child: appUnder(_normal, _student, DateTime(2026, 11, 24, 6, 30))));
      await settle(tester);
      expect(find.textContaining(_s.schoolHolidayToday('Year-end holidays')), findsOneWidget);
      expect(find.byType(TripSection), findsNothing);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('A code from a parent: only what is ticked is taken, a wrong code says so', (tester) async {
      await applyCondition(tester, _normal);
      await tester.pumpWidget(pageUnder(_normal, _student, tuesdayMorning, const FamilySharePage()));
      await settle(tester);
      final box = containerOf(tester);
      final field = find.byType(TextField);
      final import = find.widgetWithText(FilledButton, _s.importCode);

      await tester.ensureVisible(field);
      await tester.enterText(field, 'not a code');
      await tester.ensureVisible(import);
      await tester.pump();
      await tester.tap(import);
      await settle(tester);
      expect(find.text(_s.importInvalid), findsOneWidget);
      expect(box.read(favoritesProvider).places.keys, {PlaceKind.home, PlaceKind.school});
      await tester.pump(const Duration(seconds: 5)); // the message goes away
      await settle(tester);

      // The parent shares home, work and school; the student has no work place yet.
      final code = encodeShareCode(
          householdFavorites, const ShareChoice(places: {PlaceKind.home, PlaceKind.work, PlaceKind.school}));
      await tester.ensureVisible(field);
      await tester.enterText(field, code);
      await tester.ensureVisible(import);
      await tester.pump();
      await tester.tap(import);
      await settle(tester);
      expect(find.text(_s.importWhat), findsOneWidget);
      await expectAccessible(tester);
      await tester.tap(find.text(_s.importSelected));
      await settle(tester);
      final places = box.read(favoritesProvider).places;
      expect(places[PlaceKind.work]?.address, '1 RAFFLES PLACE');
      expect(places[PlaceKind.school]?.address, _school.address);
      expect(find.text(_s.importDone), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('University student', () {
    testWidgets('A server slow to wake up: Today is there at once and fills in when it answers', (tester) async {
      await applyCondition(tester, _normal);
      await tester.pumpWidget(ProviderScope(
        retry: noRetry,
        overrides: [
          toiletsProvider.overrideWith((ref) async => harnessToilets),
          initialFavoritesProvider.overrideWithValue(householdFavorites),
          apiProvider.overrideWithValue(_SlowApi(const Duration(seconds: 50))),
          bundleRepoProvider.overrideWithValue(FileBundles()),
          clockProvider.overrideWith((ref) => Stream.value(tuesdayMorning)),
        ],
        child: const DailyLahApp(),
      ));
      await settle(tester);
      // Nothing has answered yet: the page, the trip and the tabs are usable all the same.
      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(TripSection), findsOneWidget);
      expect(find.textContaining('Thundery', findRichText: true), findsNothing);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
      for (var tab = 1; tab < _tabs.length; tab++) {
        containerOf(tester).read(shellTabProvider.notifier).state = tab;
        await settle(tester);
        expect(tester.takeException(), isNull, reason: '${_tabs[tab]} while the server is waking up');
      }

      containerOf(tester).read(shellTabProvider.notifier).state = 0;
      await tester.pump(const Duration(seconds: 55));
      await settle(tester);
      // Back at the top of Today, the forecast for home has arrived.
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, 2000), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.textContaining('Thundery', findRichText: true), findsWidgets);
      await scrollThrough(tester, times: 2);
      expect(tester.takeException(), isNull);
      // Let the calls still on their way finish before the test ends.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 60));
    });
  });

  group('Homemaker', () {
    for (final c in const [
      _normal,
      Condition('phone 360x640dp, text 130%', textScale: 1.3, size: Size(360, 640)),
      Condition('foldable landscape 880dp', size: Size(880, 600)),
    ]) {
      testWidgets('Only a home saved, ${c.name}: no commute, Plan a trip, every tab and section opens',
          (tester) async {
        await applyCondition(tester, c);
        await tester.pumpWidget(appUnder(c, _homeOnly, tuesdayMorning));
        await settle(tester);
        final box = containerOf(tester);
        expect(find.byType(TodayPage), findsOneWidget);
        expect(find.byType(TripSection), findsNothing);
        await tester.scrollUntilVisible(find.byType(PlanTripCard), 200,
            scrollable: find.byType(Scrollable).hitTestable().first);
        await expectAccessible(tester);

        for (final section in _nearbySections) {
          box.read(shellTabProvider.notifier).state = 1;
          box.read(nearbySectionProvider.notifier).state = section;
          await settle(tester);
          await scrollThrough(tester, times: 3);
          expect(tester.takeException(), isNull, reason: 'Nearby: $section');
        }
        for (final section in HomePage.sections) {
          box.read(shellTabProvider.notifier).state = 2;
          box.read(homeSectionProvider.notifier).state = section;
          await settle(tester);
          await scrollThrough(tester, times: 3);
          expect(tester.takeException(), isNull, reason: 'Home: $section');
        }
        for (final tab in [3, 4]) {
          box.read(shellTabProvider.notifier).state = tab;
          await settle(tester);
          await expectAccessible(tester);
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: _tabs[tab]);
        }
      });
    }
  });

  group('Senior', () {
    const senior = Condition('text 200%, location denied',
        textScale: 2.0, size: Size(360, 640), location: LocationPermission.deniedForever);

    testWidgets('Largest text and no location: every tab can be read and tapped, Plan a trip opens', (tester) async {
      await applyCondition(tester, senior);
      await tester.pumpWidget(appUnder(senior, householdFavorites, tuesdayMorning));
      await settle(tester);
      final box = containerOf(tester);
      for (var tab = 0; tab < _tabs.length; tab++) {
        box.read(shellTabProvider.notifier).state = tab;
        await settle(tester);
        await expectAccessible(tester);
        await scrollThrough(tester);
        await expectAccessible(tester);
        expect(tester.takeException(), isNull, reason: _tabs[tab]);
      }

      box.read(shellTabProvider.notifier).state = 0;
      await settle(tester);
      final plan = find.byType(PlanTripCard);
      await tester.scrollUntilVisible(plan, 200, scrollable: find.byType(Scrollable).hitTestable().first);
      // Clear of the tab bar, which floats over the end of the list.
      await tester.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(plan);
      await settle(tester);
      expect(find.byType(TripPlannerPage), findsOneWidget);
      await expectAccessible(tester);
      expect(tester.takeException(), isNull);
    });
  });

  // Open findings (docs/QA.md "Open findings"): what the app should do and does not do yet.
  // Remove the `skip` in the pull request that fixes the finding.
  group('Open findings', () {
    testWidgets('QA-01: the tab buttons are at least 48 dp tall and wide', skip: true, (tester) async {
      const small = Condition('small screen 320dp', size: Size(320, 568));
      await applyCondition(tester, small);
      await tester.pumpWidget(appUnder(small, householdFavorites, tuesdayMorning));
      await settle(tester);
      for (final tab in _tabs) {
        final size = tester.getSize(find.byTooltip(tab));
        expect(size.height, greaterThanOrEqualTo(48), reason: tab);
        expect(size.width, greaterThanOrEqualTo(48), reason: tab);
      }
    });

    testWidgets('QA-02: TalkBack says the name of the selected tab once', skip: true, (tester) async {
      await applyCondition(tester, _normal);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
      await settle(tester);
      expect(find.bySemanticsLabel('Today\nToday'), findsNothing, reason: 'the selected tab is named twice');
      expect(find.bySemanticsLabel('Today'), findsOneWidget);
      handle.dispose();
    });
  });
}
