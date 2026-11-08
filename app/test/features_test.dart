// Feature tests: one per user-facing feature, driving the real widgets the way a user
// would (tap, sheet, button) with the fakes in support/harness.dart. Every feature PR adds
// its test here (see CLAUDE.md, "Testing a feature").
import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/l10n.dart';
import 'package:dailylah/api.dart';
import 'package:dailylah/logic.dart' show offsetMetres, parseSharedPlace, rideMinutesTo;
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/mrt_ride.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/store.dart';
import 'package:dailylah/ui/address_picker.dart';
import 'package:dailylah/ui/bus_sheet.dart';
import 'package:dailylah/ui/history.dart';
import 'package:dailylah/ui/mrt_ride.dart';
import 'package:dailylah/ui/theme.dart';
import 'package:dailylah/ui/today.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;

import 'support/harness.dart';

const _normal = Condition('normal');

/// OneMap that knows one postal code (Somerset Bencoolen) and no shop names.
class _OneMap extends OneMapApi {
  final queries = <String>[];
  @override
  Future<Map<String, dynamic>> search(String query) async {
    queries.add(query);
    return {
      'results': [
        if (query == '189630')
          {
            'BLK_NO': '51',
            'ROAD_NAME': 'BENCOOLEN STREET',
            'BUILDING': 'SOMERSET BENCOOLEN SINGAPORE',
            'POSTAL': '189630',
            'LATITUDE': '1.29661',
            'LONGITUDE': '103.85220',
            'SEARCHVAL': 'SOMERSET BENCOOLEN SINGAPORE',
          },
      ],
    };
  }
}

/// Google Maps short links that lead nowhere (no network in tests).
class _NoMapsLinks extends MapsLinks {
  @override
  Future<String?> expand(String link) async => null;
}

/// The redirect Google sends for a route shared from Google Maps (Your location → Putra Minang).
class _RouteLink extends MapsLinks {
  final opened = <String>[];
  @override
  Future<String?> expand(String link) async {
    opened.add(link);
    return 'https://www.google.com/maps/dir/1.3015204,103.9050613/Putra+Minang+Restaurant+Bencoolen/'
        'data=!4m12!4m11!1m1!4e1!1m5!1m4!1s0x31da19faa330d147:0x815145de046b9fd8!8m2!3d1.2994204999999999'
        '!4d103.85050939999999!2m1!11b1!3e2?g_st=ac';
  }
}

Widget _appWithOneMap(OneMapApi oneMap, {MapsLinks? links}) => ProviderScope(retry: noRetry,
      overrides: [
        ...overridesFor(_normal, householdFavorites, tuesdayMorning),
        oneMapProvider.overrideWithValue(oneMap),
        mapsLinksProvider.overrideWithValue(links ?? _NoMapsLinks()),
      ],
      child: const DailyLahApp(),
    );
const _tabs = {'Today': 0, 'Nearby': 1, 'Home': 2, 'History': 3, 'More': 4};

/// Live arrivals with LTA GPS: service 10 three stops before Tampines Int (route 10
/// direction 2 ends there), service 858A on the timetable only (Monitored 0).
class GpsApi extends FakeApi {
  GpsApi(this.busLat, this.busLng);
  final double busLat;
  final double busLng;

  @override
  Future<Map<String, dynamic>> busArrival(String stopCode) async {
    String at(int min) => DateTime(2026, 10, 20, 7, min).toIso8601String();
    return {
      'data': {
        'Services': [
          {
            'ServiceNo': '10',
            'NextBus': {
              'EstimatedArrival': at(4),
              'Load': 'SEA',
              'Latitude': '$busLat',
              'Longitude': '$busLng',
              'Monitored': 1,
            },
          },
          {
            'ServiceNo': '858A',
            'NextBus': {'EstimatedArrival': at(9), 'Load': 'SEA', 'Latitude': '0.0', 'Longitude': '0.0', 'Monitored': 0},
          },
        ],
      },
    };
  }
}

/// Arrivals relative to the real clock (bus times are parsed against now): at Tampines Int, a
/// 5 min walk from home, the first 10 (the direct bus to work) comes in 1 min, too soon.
class _SoonApi extends FakeApi {
  @override
  Future<Map<String, dynamic>> busArrival(String stopCode) async {
    String at(int min) => DateTime.now().add(Duration(minutes: min, seconds: 20)).toIso8601String();
    Map<String, dynamic> bus(String no, int a, int b) => {
          'ServiceNo': no,
          'NextBus': {'EstimatedArrival': at(a), 'Load': 'SEA', 'Feature': 'WAB', 'Type': 'DD'},
          'NextBus2': {'EstimatedArrival': at(b), 'Load': 'SEA', 'Feature': 'WAB', 'Type': 'DD'},
        };
    return {
      'data': {
        'Services': [bus('10', 1, 12), bus('12', 2, 4), bus('14', 9, 20), bus('858', 1, 2), bus('293', 12, 25)],
      },
    };
  }
}

Object? _bundle(String name) => jsonDecode(File('../web/data/$name.json').readAsStringSync());

void main() {
  testWidgets('Ate here on a halal place logs the meal with its name and it shows in History', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['Nearby']!;
    box.read(nearbySectionProvider.notifier).state = 'eat';
    await settle(tester);

    // First place in "Halal food nearby" (Nearby starts on Here = Tampines Int).
    final halalTile = find.widgetWithIcon(ListTile, Icons.restaurant_outlined).first;
    await tester.ensureVisible(halalTile);
    await tester.pump();
    final name = ((tester.widget<ListTile>(halalTile).title!) as Text).data!;
    await tester.tap(halalTile);
    await settle(tester);
    await tester.tap(find.text('Ate here'));
    await settle(tester);

    final meal = box.read(habitsProvider).meals.single;
    expect(meal.name, name);
    expect(meal.hawkerId, startsWith('p:'));
    expect(find.text('Noted: $name.'), findsOneWidget);

    box.read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);
    expect(find.descendant(of: find.byType(HistoryPage), matching: find.text(name)), findsOneWidget);
  });

  testWidgets('Tapping a meal in History changes when it was eaten', (tester) async {
    await applyCondition(tester, _normal);
    tester.platformDispatcher.alwaysUse24HourFormatTestValue = true;
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    await box.read(habitsProvider.notifier).restore(Habits(
      meals: [MealLog(hawkerId: 'p:1.35000,103.94000', at: DateTime(2026, 10, 20, 6, 30), name: 'Test Kitchen')],
    ));
    box.read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);

    // Bring the row above the floating tab bar, then tap it.
    final row = find.text('Test Kitchen');
    await tester.ensureVisible(row);
    await tester.drag(find.descendant(of: find.byType(HistoryPage), matching: find.byType(Scrollable)).first,
        const Offset(0, -300), warnIfMissed: false);
    await tester.pump();
    await tester.tap(row);
    await settle(tester);
    expect(find.byType(TimePickerDialog), findsOneWidget);
    // Type the time instead of using the dial.
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await settle(tester);
    final fields = find.descendant(of: find.byType(TimePickerDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '06');
    await tester.enterText(fields.at(1), '05');
    await tester.tap(find.text('OK'));
    await settle(tester);

    final meal = box.read(habitsProvider).meals.single;
    expect(meal.at, DateTime(2026, 10, 20, 6, 5));
    expect(meal.name, 'Test Kitchen');
  });

  testWidgets('Live arrivals say where the bus is now, or that the time is only the timetable', (tester) async {
    // Bus 10 is at the stop three before Tampines Int on route 10 direction 2.
    final route = ((_bundle('bus_routes') as Map)['10|2'] as List);
    final i = route.indexWhere((r) => (r as List).first == tampinesInt.code);
    final code = (route[i - 3] as List).first as String;
    final stop = (_bundle('bus_stops') as List).cast<Map>().firstWhere((s) => s['c'] == code);

    await applyCondition(tester, _normal);
    await tester.pumpWidget(ProviderScope(retry: noRetry,
      overrides: [
        initialFavoritesProvider.overrideWithValue(householdFavorites),
        apiProvider.overrideWithValue(GpsApi((stop['la'] as num).toDouble(), (stop['lo'] as num).toDouble())),
        bundleRepoProvider.overrideWithValue(FileBundles()),
        clockProvider.overrideWith((ref) => Stream.value(tuesdayMorning)),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const StopArrivalsPage(stop: tampinesInt)),
    ));
    await settle(tester);

    expect(find.textContaining('Now near ${stop['n']} · 3\u00A0stops\u00A0away', findRichText: true), findsOneWidget);
    expect(find.textContaining('Timetable estimate, no live GPS', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("Tapping a bus opens Where's my bus with the bus on its route", (tester) async {
    final route = ((_bundle('bus_routes') as Map)['10|2'] as List);
    final i = route.indexWhere((r) => (r as List).first == tampinesInt.code);
    final code = (route[i - 3] as List).first as String;
    final stop = (_bundle('bus_stops') as List).cast<Map>().firstWhere((s) => s['c'] == code);

    await applyCondition(tester, _normal);
    await tester.pumpWidget(ProviderScope(retry: noRetry,
      overrides: [
        initialFavoritesProvider.overrideWithValue(householdFavorites),
        apiProvider.overrideWithValue(GpsApi((stop['la'] as num).toDouble(), (stop['lo'] as num).toDouble())),
        bundleRepoProvider.overrideWithValue(FileBundles()),
        clockProvider.overrideWith((ref) => Stream.value(tuesdayMorning)),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const StopArrivalsPage(stop: tampinesInt)),
    ));
    await settle(tester);

    Finder row(String service) => find.byWidgetPredicate((w) => w is BusRow && w.eta.service == service);
    await tester.tap(row('10'));
    await settle(tester);
    final sheet = find.byType(WhereBusSheet);
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text("Where's my bus?")), findsOneWidget);
    // The bus is drawn at its stop, three stops before the rider's stop (Tampines Int).
    expect(find.descendant(of: sheet, matching: find.text(stop['n'] as String)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('bus here')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text(tampinesInt.name)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('YOU ·')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Open in Maps')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // A bus without live GPS: no bus on the route and no map button.
    Navigator.of(tester.element(sheet)).pop();
    await settle(tester);
    await tester.tap(row('858A'));
    await settle(tester);
    expect(find.textContaining('not shown on the route'), findsOneWidget);
    expect(find.text('Open in Maps'), findsNothing);
    expect(find.text('bus here'), findsNothing);
  });

  testWidgets('EV drivers see chargers with their plug and live free spots in Nearby', (tester) async {
    await applyCondition(tester, _normal);
    // One Type 2 site 120 m from Tampines Int (where Nearby starts) and one CHAdeMO-only site.
    final sites = [
      EvSite.fromBundle({
        'id': 'EV1',
        'n': 'BLK 520 TAMPINES CENTRAL MULTI STOREY CAR PARK',
        'a': '520 TAMPINES CENTRAL SINGAPORE 520520',
        'pc': '520520',
        'la': tampinesInt.lat + 0.001,
        'lo': tampinesInt.lng,
        'op': ['SP MOBILITY'],
        'pl': [
          {'t': 'Type 2', 'c': 'AC', 'kw': 7.4, 'p': 0.698, 'pu': 'kWh', 'n': 2},
        ],
      }),
      EvSite.fromBundle({
        'id': 'EV2',
        'n': 'CHADEMO ONLY',
        'a': '1 TAMPINES SINGAPORE 520001',
        'pc': '520001',
        'la': tampinesInt.lat,
        'lo': tampinesInt.lng + 0.001,
        'pl': [
          {'t': 'CHAdeMO', 'c': 'DC', 'kw': 50, 'n': 1},
        ],
      }),
    ];
    await tester.pumpWidget(ProviderScope(retry: noRetry,
      overrides: [
        ...overridesFor(_normal, householdFavorites, tuesdayMorning),
        evSitesProvider.overrideWith((ref) async => sites),
      ],
      child: const DailyLahApp(),
    ));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['Nearby']!;
    box.read(nearbySectionProvider.notifier).state = 'park';
    await settle(tester);

    final row = find.widgetWithText(InkWell, 'Blk 520 Tampines Central Multi Storey Car Park');
    await tester.ensureVisible(row);
    await tester.pump();
    expect(row, findsOneWidget);
    expect(find.text('Chademo Only'), findsNothing); // not the user's plug
    // Same look as car park lots: the free count big, "of N free" under it.
    expect(find.descendant(of: row, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('of 2 free')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('1/2')), findsNothing);
    expect(find.descendant(of: row, matching: find.textContaining('Type 2 AC 7.4 kW')), findsOneWidget);

    await tester.tap(row);
    await settle(tester);
    expect(find.text('1 of 2 free'), findsOneWidget);
    expect(find.text('Operator: SP MOBILITY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Turning on "My car is electric" in More picks a plug', (tester) async {
    await applyCondition(tester, _normal);
    const fav = Favorites(places: {PlaceKind.home: Place(kind: PlaceKind.home, addrLat: 1.35, addrLng: 103.94)}, onboarded: true);
    await tester.pumpWidget(appUnder(_normal, fav, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['More']!;
    await settle(tester);
    final toggle = find.widgetWithText(SwitchListTile, 'My car is electric');
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await settle(tester);
    expect(box.read(favoritesProvider).evPlug, 'any');
    // One row for the plug, the choices in a sheet (room for more plugs later).
    final plugRow = find.widgetWithText(ListTile, 'My plug');
    await tester.ensureVisible(plugRow);
    await tester.pump();
    expect(find.descendant(of: plugRow, matching: find.text('Any plug')), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(plugRow);
    await settle(tester);
    expect(find.text('Which plug does your car use?'), findsOneWidget);
    expect(find.text('DC fast charging, on most newer cars'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'CCS2'));
    await settle(tester);
    expect(find.text('Which plug does your car use?'), findsNothing);
    expect(find.descendant(of: plugRow, matching: find.text('CCS2')), findsOneWidget);
    expect(box.read(favoritesProvider).evPlug, 'CCS2');
  });

  testWidgets('A trip from the planner is timed with the banner and lands in History with its cost', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    box.read(goKeyProvider.notifier).state = 'work';
    await settle(tester);

    final leave = find.text("I'm leaving");
    await tester.ensureVisible(leave);
    await tester.pump();
    await tester.tap(leave);
    await settle(tester);
    final route = box.read(habitsProvider).tripRoute!;
    expect(route, endsWith('>work'));
    // The tabs are hidden behind the planner, so the running trip shows on the page.
    expect(find.byType(TripBanner), findsOneWidget);
    expect(find.text("I'm leaving"), findsNothing);

    // Pretend it started 25 minutes ago, then arrive.
    final h = box.read(habitsProvider);
    await box.read(habitsProvider.notifier).startTrip(route, DateTime.now().subtract(const Duration(minutes: 25)),
        mode: h.tripMode, km: h.tripKm);
    await settle(tester);
    final arrived = find.descendant(of: find.byType(TripBanner), matching: find.text('Arrived'));
    await tester.ensureVisible(arrived);
    await tester.pump();
    await tester.tap(arrived);
    await settle(tester);
    final trip = box.read(habitsProvider).trips.single;
    expect(trip.route, route);
    expect(trip.minutes, 25);
    expect(trip.km, isNotNull); // straight-line km, for the fare estimate in History
    expect(find.byType(TripBanner), findsNothing);

    Navigator.of(tester.element(find.byType(TripPlannerPage))).pop();
    await settle(tester);
    box.read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);
    final label = route.startsWith('home') ? 'Home → Work' : '${route.split('>').first} → Work';
    expect(find.descendant(of: find.byType(HistoryPage), matching: find.text(label)), findsOneWidget);
  });

  testWidgets('A halal place can be starred, stays put, and is listed first next time', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['Nearby']!;
    box.read(nearbySectionProvider.notifier).state = 'eat';
    await settle(tester);
    final seeAll = find.descendant(of: find.widgetWithText(SectionTitle, 'Halal food nearby'), matching: find.text('See all'));
    await tester.ensureVisible(seeAll);
    await tester.pump();
    await tester.tap(seeAll);
    await settle(tester);

    // Star the third place: it is saved, only that row is starred, and it does not jump.
    final rows = find.widgetWithIcon(ListTile, Icons.restaurant_outlined);
    final third = tester.widget<ListTile>(rows.at(2));
    final name = (third.title! as Text).data!;
    final star = find.descendant(of: rows.at(2), matching: find.byIcon(Icons.star_border));
    await tester.ensureVisible(star);
    await tester.pump();
    await tester.tap(star);
    await settle(tester);
    expect(box.read(favoritesProvider).halalPlaces, hasLength(1));
    expect(box.read(favoritesProvider).halalPlaces.single, startsWith('p:'));
    expect(box.read(favoritesProvider).halalPlaces.single, endsWith('|$name'));
    String titleAt(int i) => (tester.widget<ListTile>(find.widgetWithIcon(ListTile, Icons.restaurant_outlined).at(i)).title! as Text).data!;
    expect(titleAt(2), name);
    expect(find.descendant(of: find.widgetWithIcon(ListTile, Icons.restaurant_outlined), matching: find.byIcon(Icons.star)),
        findsOneWidget);

    // Next visit: the favourite is listed first.
    await tester.pageBack();
    await settle(tester);
    await tester.ensureVisible(seeAll);
    await tester.pump();
    await tester.tap(seeAll);
    await settle(tester);
    expect(titleAt(0), name);
    expect(find.descendant(of: find.widgetWithIcon(ListTile, Icons.restaurant_outlined).first, matching: find.byIcon(Icons.star)),
        findsOneWidget);
  });

  testWidgets('Taxi sheet answers first, and stands and taxis on the radar can be tapped', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['Nearby']!;
    box.read(nearbySectionProvider.notifier).state = 'taxi';
    await settle(tester);
    await tester.tap(find.textContaining('Taxis nearby').first);
    await settle(tester);

    // 1. The answer.
    expect(find.byType(TaxiEaseCard), findsOneWidget);
    expect(find.textContaining('within 1 km'), findsWidgets);

    // 2. A taxi on the radar: tap it and it says how far and which way.
    final radar = tester.widget<TaxiRadar>(find.byType(TaxiRadar));
    await tester.ensureVisible(find.byType(TaxiRadar));
    await tester.pump();
    final area = tester.getRect(find.descendant(of: find.byType(TaxiRadar), matching: find.byType(AspectRatio)));
    final r = area.shortestSide / 2 - 20;
    final (la, lo) = radar.taxis.first;
    final (e, n) = offsetMetres(radar.origin.lat, radar.origin.lng, la, lo);
    await tester.tapAt(area.center + Offset(e / TaxiRadar.range * r, -n / TaxiRadar.range * r));
    await tester.pump();
    expect(find.textContaining('Free taxi ·'), findsOneWidget);
    expect(find.text('Tap a taxi or a stand for details.'), findsNothing);

    // 3. A stand on the radar opens its sheet.
    final pins = find.byType(TaxiStandPin);
    if (pins.evaluate().isNotEmpty) {
      final name = tester.widget<TaxiStandPin>(pins.first).stand.name;
      final before = find.text(name).evaluate().length;
      await tester.tap(pins.first);
      await settle(tester);
      expect(find.text(name).evaluate().length, greaterThan(before));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets("I'm on the train starts a ride with its stations, banner and Arrived", (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    box.read(goFromKeyProvider.notifier).state = 'home';
    box.read(goKeyProvider.notifier).state = 'work';
    box.read(modeOverrideProvider.notifier).state = {'work': TravelMode.transit};
    await settle(tester);

    final onTrain = find.text("I'm on the train");
    await tester.ensureVisible(onTrain);
    await tester.pump();
    await tester.tap(onTrain);
    await settle(tester);

    final ride = box.read(rideProvider);
    if (ride == null) fail('No ride after tapping');
    expect(ride.ride.board.name, 'Tampines');
    expect(ride.ride.alight.name, 'Raffles Place');
    expect(find.byType(MrtRidePage), findsOneWidget);
    expect(find.text('To Raffles Place'), findsOneWidget);
    expect(find.text('Bedok'), findsOneWidget); // a station on the way
    expect(find.text('Running normally'), findsOneWidget); // line checked at the start
    expect(box.read(habitsProvider).tripStart, isNotNull); // timed for History

    // One stop before the end the alert goes out once.
    // Real async: the alert goes through platform channels (haptics, notifications).
    await tester.runAsync(() => box
        .read(rideProvider.notifier)
        .tickAt(ride.start.add(Duration(minutes: rideMinutesTo(ride.ride, ride.ride.stops - 1)))));
    expect(box.read(rideProvider)!.alerted, isTrue);

    // The ride page is a lazy list: scroll down to the buttons.
    final arrived = find.text("I've arrived");
    await tester.scrollUntilVisible(arrived, 300,
        scrollable: find.descendant(of: find.byType(MrtRidePage), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(arrived);
    await tester.pump();
    await tester.tap(arrived);
    await settle(tester);
    expect(box.read(rideProvider), isNull);
    expect(box.read(habitsProvider).tripStart, isNull);
    expect(find.byType(MrtRidePage), findsNothing);
  });

  testWidgets('Change line picks another line for the trip, remembers it and goes back', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    box.read(goFromKeyProvider.notifier).state = 'home';
    box.read(goKeyProvider.notifier).state = 'work';
    box.read(modeOverrideProvider.notifier).state = {'work': TravelMode.transit};
    await settle(tester);

    // 1. The sheet lists the usual route and the Downtown Line from the same station.
    final change = find.text('Change line');
    await tester.ensureVisible(change);
    await tester.pump();
    await tester.tap(change);
    await settle(tester);
    expect(find.byType(MrtLineSheet), findsOneWidget);
    expect(find.text('How do you want to go today?'), findsOneWidget);
    expect(find.text('Nearest station'), findsOneWidget);
    final blue = find.text('Blue line · Downtown');
    expect(blue, findsOneWidget);

    // 2. Picking it saves the choice for home>work and the card shows it.
    await tester.tap(blue);
    await settle(tester);
    expect(find.byType(MrtLineSheet), findsNothing);
    expect(box.read(favoritesProvider).mrtLines, {'home>work': 'DTL'});
    expect(find.text('Today: Blue line (Downtown)'), findsOneWidget);

    // 3. "I'm on the train" now rides from the Downtown Line platform.
    final onTrain = find.text("I'm on the train");
    await tester.ensureVisible(onTrain);
    await tester.pump();
    await tester.tap(onTrain);
    await settle(tester);
    final ride = box.read(rideProvider);
    if (ride == null) fail('No ride after tapping');
    expect(ride.ride.board.codes, ['DT32']);
    expect(ride.ride.alight.name, 'Raffles Place');
    box.read(rideProvider.notifier).stop();
    Navigator.of(tester.element(find.byType(MrtRidePage))).pop();
    await settle(tester);

    // 4. Going back to the nearest station forgets the pick.
    final again = find.text('Change');
    await tester.ensureVisible(again);
    await tester.pump();
    await tester.tap(again);
    await settle(tester);
    await tester.tap(find.text('Nearest station'));
    await settle(tester);
    expect(box.read(favoritesProvider).mrtLines, isEmpty);
    expect(find.textContaining('Today: '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Appearance in More switches the app to dark and back to the phone setting', (tester) async {
    await applyCondition(tester, _normal);
    const fav = Favorites(places: {PlaceKind.home: Place(kind: PlaceKind.home, addrLat: 1.35, addrLng: 103.94)}, onboarded: true);
    await tester.pumpWidget(appUnder(_normal, fav, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.system);
    box.read(shellTabProvider.notifier).state = _tabs['More']!;
    await settle(tester);
    final row = find.widgetWithText(ListTile, 'Appearance');
    await tester.ensureVisible(row);
    await tester.pump();
    expect(find.descendant(of: row, matching: find.text('Follow my phone')), findsOneWidget);
    await tester.tap(row);
    await settle(tester);
    expect(find.text('How should DailyLah look?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Dark'));
    await settle(tester);
    expect(box.read(favoritesProvider).theme, 'dark');
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(Theme.of(tester.element(row)).brightness, Brightness.dark);
    expect(find.descendant(of: row, matching: find.text('Dark')), findsOneWidget);
    // Back to following the phone (light in this test).
    await tester.tap(row);
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Follow my phone'));
    await settle(tester);
    expect(box.read(favoritesProvider).theme, '');
    expect(Theme.of(tester.element(row)).brightness, Brightness.light);
  });

  testWidgets("What's new shows once after an update and stays closed", (tester) async {
    await applyCondition(tester, _normal);
    const fav = Favorites(
      places: {PlaceKind.home: Place(kind: PlaceKind.home, addrLat: 1.35, addrLng: 103.94)},
      onboarded: true,
      seenVersion: '1.5.0',
    );
    await tester.pumpWidget(ProviderScope(retry: noRetry,
      overrides: [
        ...overridesFor(_normal, fav, tuesdayMorning),
        releaseVersionProvider.overrideWithValue('1.6.0'),
      ],
      child: const DailyLahApp(),
    ));
    await settle(tester);
    final box = containerOf(tester);
    expect(find.byType(WhatsNewCard), findsOneWidget);
    expect(find.text("What's new in 1.6.0"), findsOneWidget);
    expect(find.text(const S().whatsNewNotes.first), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(WhatsNewCard), matching: find.byTooltip('Close')));
    await settle(tester);
    expect(find.byType(WhatsNewCard), findsNothing);
    expect(box.read(favoritesProvider).seenVersion, '1.6.0');
    // Saved, so a restart with the same version does not bring it back.
    final saved = await tester.runAsync(() => FavoritesStore().load());
    expect(saved?.seenVersion, '1.6.0');
  });

  test("The What's new card says the same as the Play release notes", () {
    final notes = File('../docs/store/whatsnew/whatsnew-en-US')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l.startsWith('- ') ? l.substring(2) : l)
        .toList();
    expect(const S().whatsNewNotes, notes);
  });

  testWidgets('Plan a trip: From above To in one route card, the same choices on both, swap and search',
      (tester) async {
    await applyCondition(tester, _normal);
    final oneMap = _OneMap();
    await tester.pumpWidget(_appWithOneMap(oneMap));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);

    // Location is allowed, so the trip starts Here. From is on top, To below, the swap between.
    expect(box.read(goFromKeyProvider), 'here');
    final fromY = tester.getTopLeft(find.text(s.from)).dy;
    final swapY = tester.getTopLeft(find.byTooltip(s.swapEnds)).dy;
    final toY = tester.getTopLeft(find.text(s.to)).dy;
    expect(fromY < swapY && swapY < toY, isTrue);
    // Both ends offer Here, Home, Work, School, the saved Gym and a search field (not a chip).
    for (final label in ['Here', 'Home', 'Work', 'School', 'Gym']) {
      expect(find.text(label), findsNWidgets(2), reason: label);
    }
    expect(find.text(s.searchAddressHint), findsNWidgets(2));
    expect(find.text(s.anyAddress), findsNothing);
    // Gym is saved, so the tip about adding places is not shown.
    expect(find.text(s.addPlacesHint), findsNothing);
    expect(find.text(s.goSomewhereHint), findsOneWidget);

    // To: Work. The summary title stays "From → To".
    await tester.tap(find.text('Work').at(1));
    await settle(tester);
    expect(box.read(goKeyProvider), 'work');
    expect(find.text('Here → Work'), findsOneWidget);

    // Swap: Work → Here.
    await tester.tap(find.byTooltip(s.swapEnds));
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'work');
    expect(box.read(goKeyProvider), 'here');
    expect(find.text('Work → Here'), findsOneWidget);

    // Picking on one end what the other end has swaps them, so a trip never goes to itself.
    await tester.tap(find.text('Work').at(1));
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'here');
    expect(box.read(goKeyProvider), 'work');

    // From: a searched address. The field shows it, selected, and the trip starts there.
    await tester.tap(find.text(s.searchAddressHint).first);
    await settle(tester);
    expect(find.byType(AddressPickerPage), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AddressPickerPage), matching: find.byType(TextField)), '189630');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tester.tap(find.textContaining('51 Bencoolen Street'));
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'adhoc');
    expect(box.read(goAdhocFromProvider)!.postal, '189630');
    final name = box.read(goAdhocFromProvider)!.name!;
    expect(find.text(name), findsWidgets);
    expect(find.text('$name → Work'), findsOneWidget);
    expect(find.text(s.searchAddressHint), findsOneWidget); // To still offers the search

    // Swap carries the searched address to the other end.
    await tester.tap(find.byTooltip(s.swapEnds));
    await settle(tester);
    expect(box.read(goKeyProvider), 'adhoc');
    expect(box.read(goAdhocDestProvider)!.postal, '189630');
    expect(find.text('Work → $name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plan a trip: a second search for To replaces it, and Clear empties it', (tester) async {
    await applyCondition(tester, _normal);
    final oneMap = _OneMap();
    await tester.pumpWidget(_appWithOneMap(oneMap));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    Future<void> searchTo() async {
      await tester.tap(find.text(s.searchAddressHint).last); // the To field
      await settle(tester);
      await tester.enterText(find.descendant(of: find.byType(AddressPickerPage), matching: find.byType(TextField)), '189630');
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      await tester.tap(find.textContaining('51 Bencoolen Street'));
      await settle(tester);
    }

    await searchTo();
    expect(box.read(goKeyProvider), 'adhoc');
    final name = box.read(goAdhocDestProvider)!.name!;
    // Searching again on the same end (the field now shows the place) keeps a destination.
    await tester.tap(find.text(name).last);
    await settle(tester);
    expect(find.byType(AddressPickerPage), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AddressPickerPage), matching: find.byType(TextField)), '189630');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tester.tap(find.textContaining('51 Bencoolen Street'));
    await settle(tester);
    expect(box.read(goKeyProvider), 'adhoc');
    expect(find.text('Here → $name'), findsOneWidget);

    await tester.tap(find.byTooltip(s.clearSearch));
    await settle(tester);
    expect(box.read(goKeyProvider), isNull);
    expect(find.text(s.goSomewhereHint), findsOneWidget);
  });

  testWidgets('Plan a trip: a return trip to Here is kept when the planner opens again', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    final nav = Navigator.of(tester.element(find.byType(TodayPage)));
    nav.push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    await tester.tap(find.text('Work').at(1));
    await settle(tester);
    await tester.tap(find.byTooltip(s.swapEnds));
    await settle(tester);
    expect(find.text('Work → Here'), findsOneWidget);
    nav.pop();
    await settle(tester);

    nav.push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'work');
    expect(box.read(goKeyProvider), 'here');
    expect(find.text('Work → Here'), findsOneWidget);
    expect(find.text('Here → Here'), findsNothing);
  });

  testWidgets('Plan a trip: without location, picks work on the start shown on screen', (tester) async {
    const denied = Condition('denied', location: LocationPermission.deniedForever);
    await applyCondition(tester, denied);
    await tester.pumpWidget(appUnder(denied, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    // Here was the last start, but there is no location: the screen starts from Home.
    box.read(goFromKeyProvider.notifier).state = 'here';
    await settle(tester);
    await tester.tap(find.text('Work').at(1));
    await settle(tester);
    expect(find.text('Home → Work'), findsOneWidget);
    // Picking Work as the start swaps with what is shown: Work → Home.
    await tester.tap(find.text('Work').first);
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'work');
    expect(box.read(goKeyProvider), 'home');
    expect(find.text('Work → Home'), findsOneWidget);
  });

  testWidgets('Plan a trip: the tip about saving places shows only while none beyond Home and Work is saved',
      (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites.copyWith(extraPlaces: const []), tuesdayMorning));
    await settle(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    final tip = find.text(s.addPlacesHint);
    expect(tip, findsOneWidget);
    // Small and at the end, under the route card.
    expect(tester.getTopLeft(tip).dy, greaterThan(tester.getTopLeft(find.text(s.to)).dy));
    expect(tester.widget<Text>(tip).style?.fontSize, Theme.of(tester.element(tip)).textTheme.bodySmall?.fontSize);
  });

  testWidgets('Trip buses: the bus to leave for is on top, buses too soon are dimmed at the end', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(ProviderScope(retry: noRetry, overrides: [
      initialFavoritesProvider.overrideWithValue(householdFavorites),
      apiProvider.overrideWithValue(_SoonApi()),
      bundleRepoProvider.overrideWithValue(FileBundles()),
      clockProvider.overrideWith((ref) => Stream.value(tuesdayMorning)),
    ], child: const DailyLahApp()));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    box.read(goFromKeyProvider.notifier).state = 'home';
    box.read(goKeyProvider.notifier).state = 'work';
    box.read(modeOverrideProvider.notifier).state = {'work': TravelMode.transit};
    await settle(tester);

    // The start stop is labelled.
    expect(find.text(s.fromStop('Tampines Int')), findsOneWidget);
    final board = tester.widget<BusBoard>(find.byType(BusBoard).first);
    final leave = find.textContaining(RegExp(r'^Leave (now|in \d+ min) to catch'));
    expect(leave, findsOneWidget);
    final service = RegExp(r'catch\s(\S+)$').firstMatch(tester.widget<Text>(leave).data!)!.group(1);
    // The suggestion sits above the board, and its bus is the board's first row, never dimmed.
    expect(tester.getTopLeft(leave).dy, lessThan(tester.getTopLeft(find.byType(BusBoard).first).dy));
    expect(board.rows.first.service, service);
    expect(board.rows.first.dim, isFalse);
    // Rows too soon to catch carry the label and come after every catchable one.
    final dims = [for (final r in board.rows) r.dim];
    expect(dims.skipWhile((d) => !d).every((d) => d), isTrue);
    // 10 is the only direct bus: its first one comes before the 5 min walk is done, so the card
    // says to leave for the next one (in 12 min: leave in 7).
    expect(tester.widget<Text>(leave).data, s.leaveInHead('10', 7));
    expect(find.text(s.walkToStopThenBus(5, 12)), findsOneWidget);
    // The board: the 10 in 12 min on top, the 10 in 1 min dimmed "Too soon" at the end.
    expect((board.rows.first.minutes, board.rows.first.dim), (12, false));
    expect((board.rows.last.service, board.rows.last.minutes, board.rows.last.tag), ('10', 1, s.tooSoon));
    for (final r in board.rows) {
      expect(r.tag, r.dim ? s.tooSoon : isNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bus board: a bus too soon to catch is drawn dim with its label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: BusBoard(arrLabel: 'Arr', minLabel: 'min', thenLabel: (m) => 'then $m min', rows: const [
          BoardRow(service: '36', minutes: 9),
          BoardRow(service: '15', minutes: 1, dim: true, tag: 'Too soon'),
        ]),
      ),
    ));
    Color? colorOf(String text) => tester.widget<Text>(find.text(text)).style?.color;
    expect(colorOf('36'), DL.led);
    expect(colorOf('15'), DL.ledDim);
    expect(colorOf('1 min'), DL.ledDim);
    expect(find.text('Too soon'), findsOneWidget);
    // Dim, not hidden: the label keeps the board's small-text contrast.
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets("I'm leaving: the how-to is small under the button and goes once the trip is learned", (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    box.read(goFromKeyProvider.notifier).state = 'home';
    box.read(goKeyProvider.notifier).state = 'work';
    await settle(tester);

    final hint = find.text(s.tripLearnHint);
    final button = find.text(s.imLeaving);
    expect(hint, findsOneWidget);
    expect(tester.getTopLeft(hint).dy, greaterThan(tester.getTopLeft(button).dy));
    expect(tester.widget<Text>(hint).style?.fontSize, Theme.of(tester.element(hint)).textTheme.bodySmall?.fontSize);

    // Three trips on this route: the card says how long it usually takes, and the how-to is gone.
    await box.read(habitsProvider.notifier).restore(Habits(trips: [
      for (final m in [40, 42, 45])
        TripLog(route: 'home>work', start: tuesdayMorning.subtract(Duration(days: m - 39)), minutes: m),
    ]));
    await settle(tester);
    expect(find.text(s.tripLearnHint), findsNothing);
    expect(find.textContaining(s.usualTrip(42, 3)), findsOneWidget);
    expect(find.text(s.imLeaving), findsOneWidget);
  });

  testWidgets('A place shared from Google Maps opens the planner with it as the destination', (tester) async {
    await applyCondition(tester, _normal);
    final oneMap = _OneMap();
    await tester.pumpWidget(_appWithOneMap(oneMap));
    await settle(tester);
    final box = containerOf(tester);
    final shared = parseSharedPlace(
        'Putra Minang Restaurant Bencoolen\n51 Bencoolen St, #01-05, Singapore 189630\nhttps://maps.app.goo.gl/AbC123')!;
    Navigator.of(tester.element(find.byType(TodayPage)))
        .push(MaterialPageRoute<void>(builder: (_) => TripPlannerPage(shared: shared)));
    await settle(tester);

    expect(oneMap.queries, ['189630']); // only the postal code is searched, never the shared text
    expect(box.read(goKeyProvider), 'adhoc');
    final dest = box.read(goAdhocDestProvider)!;
    expect(dest.name, 'Putra Minang Restaurant Bencoolen');
    expect(dest.postal, '189630');
    expect(dest.addrLat, closeTo(1.29661, 1e-6));
    expect(find.text('Putra Minang Restaurant Bencoolen'), findsWidgets);
    expect(find.byType(AddressPickerPage), findsNothing);
  });

  testWidgets('A shared place without an address asks for the postal code, and search explains what it finds',
      (tester) async {
    await applyCondition(tester, _normal);
    final oneMap = _OneMap();
    await tester.pumpWidget(_appWithOneMap(oneMap));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(
        builder: (_) => TripPlannerPage(shared: parseSharedPlace('Putra Minang Restaurant\nhttps://maps.app.goo.gl/x'))));
    await settle(tester);

    expect(find.byType(AddressPickerPage), findsOneWidget);
    expect(find.text(s.sharedNoAddress('Putra Minang Restaurant')), findsOneWidget);

    // A shop name finds nothing on OneMap: the empty state says why and what to try.
    await tester.enterText(find.descendant(of: find.byType(AddressPickerPage), matching: find.byType(TextField)), 'putra minang');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.text(s.noAddressFound), findsOneWidget);
    expect(find.text(s.noAddressTips), findsOneWidget);

    // The postal code does, and becomes the destination under the shared name.
    await tester.enterText(find.descendant(of: find.byType(AddressPickerPage), matching: find.byType(TextField)), '189630');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tester.tap(find.textContaining('51 Bencoolen Street'));
    await settle(tester);
    expect(find.byType(AddressPickerPage), findsNothing);
    final dest = box.read(goAdhocDestProvider)!;
    expect(dest.name, 'Putra Minang Restaurant');
    expect(dest.postal, '189630');
    expect(box.read(goKeyProvider), 'adhoc');
  });

  testWidgets('A route shared from Google Maps opens the planner to its destination', (tester) async {
    await applyCondition(tester, _normal);
    final oneMap = _OneMap();
    final links = _RouteLink();
    await tester.pumpWidget(_appWithOneMap(oneMap, links: links));
    await settle(tester);
    final box = containerOf(tester);
    final shared = parseSharedPlace('https://maps.app.goo.gl/oseWUrfHe23uqLKZ7?g_st=ac', subject: 'Shared route')!;
    Navigator.of(tester.element(find.byType(TodayPage)))
        .push(MaterialPageRoute<void>(builder: (_) => TripPlannerPage(shared: shared)));
    await settle(tester);

    expect(links.opened, ['https://maps.app.goo.gl/oseWUrfHe23uqLKZ7?g_st=ac']);
    expect(oneMap.queries, isEmpty); // the pin is enough, nothing searched
    expect(find.byType(AddressPickerPage), findsNothing);
    final dest = box.read(goAdhocDestProvider)!;
    expect(dest.name, 'Putra Minang Restaurant Bencoolen');
    expect(dest.addrLat, closeTo(1.29942, 1e-4));
    expect(box.read(goKeyProvider), 'adhoc');
  });
}
