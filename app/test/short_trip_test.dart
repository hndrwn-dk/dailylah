// Plan a trip for short trips: Walk picked by itself, the bus folded away when it is no quicker
// than walking, and every mode chip showing its own card before anything opens Google Maps.
import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart' show routeMetres, walkMinutesTo;
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/history.dart';
import 'package:dailylah/ui/today.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _normal = Condition('normal');
const _s = S();

// Two stops in a row on service 10 (web/data/bus_routes.json), 436 m apart, and one six stops on.
const _siglap = Place(kind: PlaceKind.other, name: 'Siglap Sth CC', addrLat: 1.313904, addrLng: 103.931711);
const _goodwill = Place(kind: PlaceKind.other, name: 'Goodwill Ct', addrLat: 1.312958, addrLng: 103.927906);
const _stPatricks = Place(kind: PlaceKind.other, name: "St. Patrick's Green", addrLat: 1.309281, addrLng: 103.914345);

/// Every URL handed to url_launcher, instead of leaving the app.
List<String> _catchLaunches(WidgetTester tester) {
  final urls = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') urls.add((call.arguments as Map)['url'] as String);
    return true;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  return urls;
}

/// The planner with a searched start and destination.
Future<void> _plan(WidgetTester tester, Place from, Place to, {Condition c = _normal}) async {
  await applyCondition(tester, c);
  await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
  await settle(tester);
  Navigator.of(tester.element(find.byType(TodayPage)))
      .push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
  await settle(tester);
  final box = containerOf(tester);
  box.read(goPicksProvider.notifier).state++;
  box.read(goAdhocFromProvider.notifier).state = from;
  box.read(goAdhocDestProvider.notifier).state = to;
  box.read(goFromKeyProvider.notifier).state = 'adhoc';
  box.read(goKeyProvider.notifier).state = 'adhoc';
  await settle(tester);
}

/// Scrolls [target] into the middle of the screen (clear of the app bar) and taps it.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(target);
  await tester.pump();
}

Future<void> _tapMode(WidgetTester tester, String label) async {
  await _tap(tester, find.text(label).last);
  await settle(tester);
}

void main() {
  testWidgets('A short trip opens on Walk: the walking card, no buses, and a pick by hand wins', (tester) async {
    final launches = _catchLaunches(tester);
    await _plan(tester, _siglap, _goodwill);
    const straight = 436.0;
    // Walk is the first chip and the one selected.
    final chips = tester.widget<PillRow>(find.byType(PillRow).last);
    expect(chips.items.first.$3, 'Walk');
    expect(chips.selected, TravelMode.walk.name);
    expect(find.textContaining(_s.walkMinutes(routeMetres(straight))), findsOneWidget);
    expect(find.byType(BusBoard), findsNothing);
    expect(find.textContaining(RegExp(r'to\scatch')), findsNothing);
    expect(launches, isEmpty);
    // The walking route is an explicit button.
    await _tap(tester, find.text(_s.walkingRoute));
    expect(launches.single, contains('travelmode=walking'));

    // Bus/MRT picked by hand stays, also after the page rebuilds.
    await _tapMode(tester, 'Bus/MRT');
    expect(tester.widget<PillRow>(find.byType(PillRow).last).selected, TravelMode.transit.name);
    await settle(tester);
    expect(tester.widget<PillRow>(find.byType(PillRow).last).selected, TravelMode.transit.name);
  });

  testWidgets('One stop by bus on a short trip: no "Leave now" card, the buses fold into one line', (tester) async {
    await _plan(tester, _siglap, _goodwill);
    await _tapMode(tester, 'Bus/MRT');
    // Walking stays on top.
    expect(find.textContaining(_s.walkMinutes(routeMetres(436))), findsOneWidget);
    expect(find.textContaining(RegExp(r'to\scatch')), findsNothing);
    final folded = find.text(_s.busNotFaster('10', 1));
    expect(folded, findsOneWidget);
    expect(find.byType(BusBoard), findsNothing);
    expect(
      tester.getTopLeft(find.textContaining(_s.walkMinutes(routeMetres(436)))).dy,
      lessThan(tester.getTopLeft(folded).dy),
    );
    // Still there for a rainy day: one tap opens the board.
    await _tap(tester, folded);
    await settle(tester);
    expect(find.byType(BusBoard), findsOneWidget);
    expect(find.textContaining('1 stop · 0.'), findsOneWidget);
    expect(find.textContaining('1 stops'), findsNothing);
  });

  testWidgets('A longer trip keeps the saved mode and the "Leave to catch" card', (tester) async {
    await _plan(tester, _siglap, _stPatricks);
    expect(tester.widget<PillRow>(find.byType(PillRow).last).selected, TravelMode.transit.name);
    expect(find.textContaining(RegExp(r'to\scatch\s10')), findsOneWidget);
    expect(find.byType(BusBoard), findsWidgets);
    expect(find.textContaining('not faster than walking'), findsNothing);
    expect(walkMinutesTo(2000), greaterThan(20));
  });

  testWidgets('Bicycle, Car, Motorbike and Taxi show their card first; Google Maps opens only from its button',
      (tester) async {
    final launches = _catchLaunches(tester);
    await _plan(tester, _siglap, _stPatricks);
    for (final (label, button, travel) in [
      ('Bicycle', _s.rideInMaps, 'bicycling'),
      ('Car', _s.driveInMaps, 'driving'),
      ('Motorbike', _s.driveInMaps, 'driving'),
      ('Taxi', _s.routeInMaps, 'driving'),
    ]) {
      await _tapMode(tester, label);
      expect(launches, isEmpty, reason: '$label must not leave the app by itself');
      final eta = find.textContaining(RegExp('^About \\d+ min by ${label.toLowerCase()} · \\d'));
      expect(eta, findsOneWidget, reason: label);
      expect(find.text(_s.modeEtaNote), findsOneWidget);
      final open = find.widgetWithText(OutlinedButton, button);
      expect(open, findsOneWidget, reason: label);
      await _tap(tester, open);
      expect(launches.single, contains('travelmode=$travel'), reason: label);
      launches.clear();
    }
  });

  testWidgets('A mode picked by hand belongs to that trip: not to the next place, not to the commute', (tester) async {
    await _plan(tester, _siglap, _goodwill);
    await _tapMode(tester, 'Bus/MRT');
    final box = containerOf(tester);
    // Another short trip in the same destination slot opens on Walk again.
    box.read(goAdhocDestProvider.notifier).state =
        const Place(kind: PlaceKind.other, name: 'Opp Goodwill Ct', addrLat: 1.3132, addrLng: 103.9281);
    await settle(tester);
    expect(tester.widget<PillRow>(find.byType(PillRow).last).selected, TravelMode.walk.name);
    // Walk picked for a short trip does not follow a long one.
    box.read(goAdhocDestProvider.notifier).state = _stPatricks;
    await settle(tester);
    expect(tester.widget<PillRow>(find.byType(PillRow).last).selected, TravelMode.transit.name);
    // Nothing is kept under the commute's keys.
    expect(box.read(modeOverrideProvider).keys.every((k) => k.startsWith('plan:')), isTrue);
  });

  testWidgets('History shows a walked trip with the walking icon', (tester) async {
    await _plan(tester, _siglap, _goodwill);
    final box = containerOf(tester);
    await box.read(habitsProvider.notifier).startTrip('a>b', tuesdayMorning, mode: 'walk', km: 0.4);
    await box.read(habitsProvider.notifier).finishTrip(tuesdayMorning.add(const Duration(minutes: 9)));
    await tester.pumpWidget(pageUnder(_normal, householdFavorites, tuesdayMorning, const Scaffold(body: HistoryPage())));
    await settle(tester);
    expect(find.byIcon(Icons.directions_walk), findsWidgets);
  });

  for (final c in const [
    Condition('text 200% on 320dp', textScale: 2.0, size: Size(320, 640)),
    Condition('dark, text 200% on 320dp', textScale: 2.0, size: Size(320, 640), dark: true),
  ]) {
    testWidgets('Short trip cards hold at ${c.name}', (tester) async {
      await _plan(tester, _siglap, _goodwill, c: c);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
      for (final label in ['Bus/MRT', 'Bicycle', 'Car', 'Taxi']) {
        await _tapMode(tester, label);
        await scrollThrough(tester);
        expect(tester.takeException(), isNull, reason: label);
      }
    });
  }
}
