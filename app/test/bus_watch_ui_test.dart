// Bus arriving on the screens: I'm leaving picks the bus, bells on the board switch it, the trip
// banner shows it and opens its board, and Today keeps the trip near the top.
import 'package:dailylah/bus_watch.dart';
import 'package:dailylah/l10n.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/today.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

    testWidgets('a trip to the current location keeps no destination and has no bells', (tester) async {
      final box = await _plan(tester, toHere: true);
      await _tap(tester, find.text(_s.imLeaving));
      expect(box.read(habitsProvider).tripStart, isNotNull);
      expect(box.read(habitsProvider).tripTo, isNull);
      expect(box.read(busWatchProvider), isNull);
      expect(find.byTooltip(_s.busAlertMe), findsNothing);
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
}
