// Bus arriving on the screens: I'm leaving picks the bus, bells on the board switch it, the trip
// banner shows it and opens its board, and Today keeps the trip near the top.
import 'package:dailylah/bus_watch.dart';
import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/today.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:dailylah/ui/wake.dart';
import 'package:dailylah/wake_session.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/harness.dart';

const _normal = Condition('normal');
const _s = S();

// Service 10 along Marine Parade Road (web/data/bus_routes.json): six stops from Siglap Sth CC.
const _siglap = Place(kind: PlaceKind.other, name: 'Siglap Sth CC', addrLat: 1.313904, addrLng: 103.931711);
const _stPatricks = Place(kind: PlaceKind.other, name: "St. Patrick's Green", addrLat: 1.309281, addrLng: 103.914345);

/// The planner with a searched start and destination, on Bus/MRT.
Future<ProviderContainer> _plan(
  WidgetTester tester, {
  Condition c = _normal,
  Favorites fav = householdFavorites,
  bool toHere = false,
}) async {
  await applyCondition(tester, c);
  await tester.pumpWidget(appUnder(c, fav, tuesdayMorning));
  await settle(tester);
  Navigator.of(tester.element(find.byType(TodayPage)))
      .push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
  await settle(tester);
  final box = containerOf(tester);
  box.read(goPicksProvider.notifier).state++;
  box.read(goAdhocFromProvider.notifier).state = _siglap;
  box.read(goFromKeyProvider.notifier).state = 'adhoc';
  if (toHere) {
    box.read(goFromHereProvider.notifier).state =
        Place(kind: PlaceKind.other, name: _s.hereNow, addrLat: _stPatricks.lat, addrLng: _stPatricks.lng);
    box.read(goKeyProvider.notifier).state = 'here';
  } else {
    box.read(goAdhocDestProvider.notifier).state = _stPatricks;
    box.read(goKeyProvider.notifier).state = 'adhoc';
  }
  await settle(tester);
  return box;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(target);
  await tester.pump();
  await settle(tester);
}

Future<void> _end(WidgetTester tester, ProviderContainer box) async {
  box.read(busWatchProvider.notifier).stop();
  await tester.runAsync(() => box.read(habitsProvider.notifier).cancelTrip());
  await tester.pump();
}

void main() {
  group('choosing the bus', () {
    testWidgets("I'm leaving remembers the trip and watches the bus to leave for; bells switch it",
        (tester) async {
      final box = await _plan(tester);
      expect(find.byTooltip(_s.busAlertMe), findsNothing, reason: 'no bells before the rider has left');
      expect(find.byTooltip(_s.busAlertStop), findsNothing);

      await _tap(tester, find.text(_s.imLeaving));
      final h = box.read(habitsProvider);
      expect(h.tripStop, isNotNull);
      expect(h.tripBus, '10');
      expect(h.tripTo?.name, "St. Patrick's Green");
      expect(box.read(busWatchProvider)?.service, '10');
      expect(box.read(busWatchProvider)?.stop.code, h.tripStop);

      // The watched row says so, and its bell stops the watch.
      expect(find.byTooltip(_s.busAlertStop), findsOneWidget);
      // TalkBack hears the bell as a switch that is on.
      final semantics = tester.ensureSemantics();
      final bell = tester.getSemantics(find.byTooltip(_s.busAlertStop));
      expect(bell.flagsCollection.isToggled, Tristate.isTrue);
      semantics.dispose();
      expect(find.text(_s.busAlerting), findsOneWidget);
      await _tap(tester, find.byTooltip(_s.busAlertStop));
      expect(box.read(busWatchProvider), isNull);
      expect(box.read(habitsProvider).tripBus, isNull);
      expect(box.read(habitsProvider).tripStop, h.tripStop);

      // Any direct bus can be picked with its bell.
      expect(find.byTooltip(_s.busAlertMe), findsWidgets);
      await _tap(tester, find.byTooltip(_s.busAlertMe).first);
      expect(box.read(busWatchProvider)?.service, '10');
      expect(box.read(habitsProvider).tripBus, '10');
      expect(tester.takeException(), isNull);
      await _end(tester, box);
    });

    testWidgets('the row still opens Where\'s my bus?', (tester) async {
      final box = await _plan(tester);
      await _tap(tester, find.text(_s.imLeaving));
      await _tap(tester, find.text(_s.busAlerting));
      expect(find.text(_s.whereBusTitle), findsOneWidget);
      await _end(tester, box);
    });

    testWidgets('with Bus arriving switched off there are no bells and no watch', (tester) async {
      final box = await _plan(tester, fav: householdFavorites.copyWith(busAlerts: false));
      await _tap(tester, find.text(_s.imLeaving));
      expect(box.read(habitsProvider).tripStart, isNotNull);
      expect(box.read(busWatchProvider), isNull);
      expect(find.byTooltip(_s.busAlertMe), findsNothing);
      expect(find.byTooltip(_s.busAlertStop), findsNothing);
      await _end(tester, box);
    });

    testWidgets('without location the filled bell first asks, and only the next tap stops', (tester) async {
      const denied = Condition('location denied', location: LocationPermission.denied);
      final box = await _plan(tester, c: denied);
      await _tap(tester, find.text(_s.imLeaving));
      expect(box.read(busWatchProvider)?.background, isFalse);
      expect(find.text(_s.busAlertsNeedLocation), findsOneWidget);
      // The hint says to tap a bell: on the watched row that tap asks, it does not switch off.
      await _tap(tester, find.byTooltip(_s.busAlertAsk));
      expect(box.read(busWatchProvider)?.service, '10', reason: 'still watching');
      expect(box.read(busWatchProvider)?.asked, isTrue);
      expect(find.text(_s.busAlertsNeedLocation), findsNothing, reason: 'asked once; not offered again');
      await _tap(tester, find.byTooltip(_s.busAlertStop));
      expect(box.read(busWatchProvider), isNull);
      await _end(tester, box);
    });

    testWidgets('a trip to the current location keeps no destination and has no bells', (tester) async {
      final box = await _plan(tester, toHere: true);
      await _tap(tester, find.text(_s.imLeaving));
      expect(box.read(habitsProvider).tripStart, isNotNull);
      expect(box.read(habitsProvider).tripTo, isNull);
      expect(box.read(busWatchProvider), isNull);
      expect(find.byTooltip(_s.busAlertMe), findsNothing);
      await _end(tester, box);
    });

    testWidgets('a trip by car to the same place has no bells on its bus board', (tester) async {
      // Every timed trip remembers where it goes now; only a bus trip may watch a bus.
      final box = await _plan(tester);
      await tester.runAsync(() => box.read(habitsProvider.notifier).startTrip(
          'Siglap>St. Patrick', DateTime.now(), mode: TravelMode.car.name, to: _stPatricks));
      await settle(tester);
      expect(box.read(habitsProvider).tripTo?.name, "St. Patrick's Green");
      expect(find.byTooltip(_s.busAlertMe), findsNothing);
      expect(find.byTooltip(_s.busAlertStop), findsNothing);
      await _end(tester, box);
    });

    testWidgets('the bells fit at 200% text on a 320 dp phone', (tester) async {
      const small = Condition('small, large text', textScale: 2.0, size: Size(320, 640));
      final box = await _plan(tester, c: small);
      await _tap(tester, find.text(_s.imLeaving));
      expect(find.byTooltip(_s.busAlertStop), findsOneWidget);
      expect(tester.takeException(), isNull);
      final bell = tester.getSize(find.byTooltip(_s.busAlertStop));
      expect(bell.width, greaterThanOrEqualTo(48));
      expect(bell.height, greaterThanOrEqualTo(48));
      await _end(tester, box);
    });
  });

  group('the trip bar', () {
    const fullerton =
        Place(kind: PlaceKind.other, name: 'Fullerton', addrLat: 1.285618, addrLng: 103.853422);
    final start = DateTime(2026, 10, 20, 6, 51);

    /// Today with a trip to Fullerton running from Tampines Int ([stop] as remembered).
    Future<ProviderContainer> running(WidgetTester tester,
        {Condition c = _normal, String? stop = '75009', Place? to = fullerton}) async {
      await applyCondition(tester, c);
      await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
      await settle(tester);
      final box = containerOf(tester);
      await tester.runAsync(() =>
          box.read(habitsProvider.notifier).startTrip('Home>Fullerton', start, to: to, stop: stop, bus: '10'));
      await settle(tester);
      return box;
    }

    /// Puts the watch in a known state, as a poll would.
    Future<void> watching(WidgetTester tester, ProviderContainer box,
        {int minutes = 5, int? stopsAway = 4, bool stale = false, bool done = false, bool background = true}) async {
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      box.read(busWatchProvider.notifier).state = BusWatchState(
        stop: tampinesInt,
        service: '10',
        alight: fullertonSq,
        toLabel: 'Fullerton',
        started: start,
        track: BusTrack(service: '10', due: start),
        eta: BusEta(service: '10', minutes: minutes, load: 'SEA'),
        fetchedAt: DateTime(2026, 10, 20, 6, 58),
        stopsAway: stopsAway,
        stale: stale,
        done: done,
        background: background,
      );
      await settle(tester);
    }

    testWidgets('says the watched bus, and the time on the way without one', (tester) async {
      final box = await running(tester);
      expect(find.textContaining('On the way since 6:51'), findsOneWidget);
      await watching(tester, box);
      expect(find.text('10 in 5 min · 4 stops away'), findsOneWidget);
      expect(find.textContaining('On the way since'), findsNothing);
      await watching(tester, box, minutes: 0, stopsAway: null);
      expect(find.text('10 arriving'), findsOneWidget);
      await watching(tester, box, stale: true);
      expect(find.text('10 · Updated 6:58'), findsOneWidget);
      expect(find.text(_s.busAlertsNeedLocation), findsNothing);
      await _end(tester, box);
    });

    testWidgets('without the location service the board says how to get alerts with the screen off',
        (tester) async {
      final box = await running(tester);
      await watching(tester, box, background: false);
      expect(find.descendant(of: find.byType(TripBanner), matching: find.text(_s.busAlertsNeedLocation)),
          findsNothing, reason: 'the bar stays short');
      await tester.tap(find.text('Home → Fullerton'));
      await settle(tester);
      expect(
          find.descendant(of: find.byType(RunningTripPage), matching: find.text(_s.busAlertsNeedLocation)),
          findsOneWidget);
      await _end(tester, box);
    });

    testWidgets('a tap opens the board of the remembered stop; Stop timing and Arrived stay', (tester) async {
      final box = await running(tester);
      expect(find.byTooltip(_s.tripCancel), findsOneWidget);
      expect(find.text(_s.arrived), findsOneWidget);
      // What opens something shows it: a chevron beside the trip.
      expect(find.descendant(of: find.byType(TripBanner), matching: find.byIcon(Icons.chevron_right)),
          findsOneWidget);
      await tester.tap(find.text('Home → Fullerton'));
      await settle(tester);
      expect(find.byType(RunningTripPage), findsOneWidget);
      expect(find.byType(TripBusCard), findsOneWidget);
      expect(find.text(_s.fromStop('Tampines Int')), findsOneWidget);
      expect(find.byTooltip(_s.busAlertMe), findsWidgets, reason: 'the board has its bells');
      expect(find.text(_s.arrived), findsOneWidget, reason: 'the bar is on the page too');
      expect(tester.takeException(), isNull);

      await _tap(tester, find.text(_s.openPlanner));
      expect(find.byType(TripPlannerPage), findsOneWidget);
      // The trip ends from the planner: this page goes, the planner stays.
      await _end(tester, box);
      await settle(tester);
      expect(find.byType(TripPlannerPage), findsOneWidget);
      expect(find.byType(RunningTripPage, skipOffstage: false), findsNothing);
    });

    testWidgets('the page closes when the trip ends', (tester) async {
      final box = await running(tester);
      await tester.tap(find.text('Home → Fullerton'));
      await settle(tester);
      expect(find.byType(RunningTripPage), findsOneWidget);
      await _end(tester, box);
      await settle(tester);
      expect(find.byType(RunningTripPage), findsNothing);
    });

    testWidgets('unknown stop: a stop that is no longer in the list, or no destination, opens nothing',
        (tester) async {
      var box = await running(tester, stop: '00000');
      await tester.tap(find.text('Home → Fullerton'));
      await settle(tester);
      expect(find.byType(RunningTripPage), findsNothing);
      expect(find.descendant(of: find.byType(TripBanner), matching: find.byIcon(Icons.chevron_right)),
          findsNothing);
      expect(find.textContaining('On the way since'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _end(tester, box);

      box = await running(tester, to: null);
      await tester.tap(find.text('Home → Fullerton'));
      await settle(tester);
      expect(find.byType(RunningTripPage), findsNothing);
      expect(tester.takeException(), isNull);
      await _end(tester, box);
    });

    testWidgets('when the bus has gone it offers Wake me at the stop to get off', (tester) async {
      final box = await running(tester);
      await watching(tester, box, done: true);
      final offer = find.text(_s.wakeMeAt('Fullerton Sq'));
      expect(offer, findsOneWidget);
      await tester.tap(offer);
      await settle(tester);
      expect(find.byType(WakeMePage), findsOneWidget);
      box.read(wakeProvider.notifier).stop();
      await _end(tester, box);
    });

    testWidgets('fits at 200% text on a 320 dp phone', (tester) async {
      const small = Condition('small, large text', textScale: 2.0, size: Size(320, 640));
      final box = await running(tester, c: small);
      await watching(tester, box);
      expect(find.textContaining('10 in 5 min'), findsOneWidget);
      await watching(tester, box, done: true);
      await watching(tester, box, background: false);
      expect(tester.takeException(), isNull);
      await _end(tester, box);
    });
  });

  group('Today', () {
    const fullerton =
        Place(kind: PlaceKind.other, name: 'Fullerton', addrLat: 1.285618, addrLng: 103.853422);

    Future<ProviderContainer> today(WidgetTester tester, DateTime now) async {
      await applyCondition(tester, _normal);
      await tester.pumpWidget(appUnder(_normal, householdFavorites, now));
      await settle(tester);
      return containerOf(tester);
    }

    double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

    testWidgets('on a day off the running trip has its board under the weather', (tester) async {
      final box = await today(tester, saturdayMorning);
      expect(find.byType(TripBusCard), findsNothing);
      final planAt = top(tester, find.byType(PlanTripCard, skipOffstage: false));
      await tester.runAsync(() => box.read(habitsProvider.notifier).startTrip(
          'Home>Fullerton', saturdayMorning.subtract(const Duration(minutes: 9)),
          to: fullerton, stop: tampinesInt.code));
      await settle(tester);
      final board = find.byType(TripBusCard, skipOffstage: false);
      expect(board, findsOneWidget);
      expect(find.text(_s.fromStop('Tampines Int'), skipOffstage: false), findsOneWidget);
      expect(top(tester, board), lessThan(planAt), reason: 'above where the planner card was');
      expect(find.byType(PlanTripCard, skipOffstage: false), findsOneWidget, reason: 'the planner card stays');
      expect(tester.takeException(), isNull);
      await _end(tester, box);
      await settle(tester);
      expect(find.byType(TripBusCard, skipOffstage: false), findsNothing);
    });

    testWidgets('a planned trip not left for is one tap from the top', (tester) async {
      final box = await today(tester, saturdayMorning);
      expect(find.text(_s.planTrip, skipOffstage: false), findsOneWidget);
      final before = top(tester, find.byType(PlanTripCard, skipOffstage: false));
      box.read(goAdhocDestProvider.notifier).state = fullerton;
      box.read(goKeyProvider.notifier).state = 'adhoc';
      await settle(tester);
      final card = find.byType(PlanTripCard, skipOffstage: false);
      expect(card, findsOneWidget, reason: 'moved, not shown twice');
      expect(find.text(_s.planTripTo('Fullerton'), skipOffstage: false), findsOneWidget);
      expect(find.text(_s.planTripSee, skipOffstage: false), findsOneWidget);
      expect(top(tester, card), lessThan(before));
      await _tap(tester, find.text(_s.planTripTo('Fullerton')));
      expect(find.byType(TripPlannerPage), findsOneWidget);
    });

    testWidgets('after leaving and Arrived, the planned trip is not offered again', (tester) async {
      final box = await _plan(tester);
      await _tap(tester, find.text(_s.imLeaving));
      Navigator.of(tester.element(find.byType(TripPlannerPage))).pop();
      await settle(tester);
      await tester.runAsync(() async {
        box.read(busWatchProvider.notifier).stop();
        await box.read(habitsProvider.notifier).finishTrip(tuesdayMorning.add(const Duration(minutes: 30)));
      });
      await settle(tester);
      expect(find.text(_s.planTripTo("St. Patrick's Green"), skipOffstage: false), findsNothing);
      expect(find.text(_s.planTrip, skipOffstage: false), findsOneWidget);
    });

    testWidgets('the commute card is not doubled when the commute is the running trip', (tester) async {
      final box = await today(tester, tuesdayMorning);
      final cards = find.byType(TripBusCard, skipOffstage: false).evaluate().length;
      expect(cards, greaterThan(0), reason: 'the commute shows its buses');
      final work = householdFavorites.places[PlaceKind.work]!;
      await tester.runAsync(() => box.read(habitsProvider.notifier).startTrip(
          'home>work', tuesdayMorning.subtract(const Duration(minutes: 2)),
          to: work, stop: tampinesInt.code));
      await settle(tester);
      expect(find.byType(TripBusCard, skipOffstage: false).evaluate().length, cards);
      await _end(tester, box);
    });
  });
}
