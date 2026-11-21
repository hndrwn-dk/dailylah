// Feature tests: one per user-facing feature, driving the real widgets the way a user
// would (tap, sheet, button) with the fakes in support/harness.dart. Every feature PR adds
// its test here (see CLAUDE.md, "Testing a feature").
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/l10n.dart';
import 'package:dailylah/api.dart';
import 'package:dailylah/logic.dart' show HistoryKind, HistoryPeriod, alertsOn, offsetMetres, parseSharedPlace, rideMinutesTo, withoutWebAddress;
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/mrt_ride.dart';
import 'package:dailylah/wake_session.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/store.dart';
import 'package:dailylah/ui/address_picker.dart';
import 'package:dailylah/ui/bus_sheet.dart';
import 'package:dailylah/ui/history.dart';
import 'package:dailylah/ui/more.dart';
import 'package:dailylah/ui/mrt_ride.dart';
import 'package:dailylah/ui/home.dart';
import 'package:dailylah/ui/nearby.dart';
import 'package:dailylah/ui/theme.dart';
import 'package:dailylah/ui/today.dart';
import 'package:dailylah/ui/toilets.dart';
import 'package:dailylah/ui/trip.dart';
import 'package:dailylah/ui/wake.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show GeolocatorPlatform, LocationPermission;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

const _normal = Condition('normal');
const _s = S();

/// Live readings from the shared examples in contracts/v1 (PSI 48, rain 0.4 mm, UV 8, WBGT 30.2).
class _ReadingsApi extends FakeApi {
  @override
  Future<Map<String, dynamic>> weather(String kind) async {
    final file = File('../contracts/v1/weather_$kind.json');
    if (!file.existsSync()) return super.weather(kind);
    return ((jsonDecode(file.readAsStringSync()) as Map)['response'] as Map).cast<String, dynamic>();
  }
}

/// The readings answer, the 2-hour forecast does not (its upstream is down and nothing is cached).
class _NoForecastApi extends _ReadingsApi {
  @override
  Future<Map<String, dynamic>> forecast() async => throw DioException(
        requestOptions: RequestOptions(path: '/v1/weather/forecast'),
        type: DioExceptionType.connectionError,
        message: 'forecast down (test)',
      );
}

Widget _appWithReadings(DateTime now) => ProviderScope(retry: noRetry,
      overrides: [
        initialFavoritesProvider.overrideWithValue(householdFavorites),
        apiProvider.overrideWithValue(_ReadingsApi()),
        bundleRepoProvider.overrideWithValue(FileBundles()),
        clockProvider.overrideWith((ref) => Stream.value(now)),
      ],
      child: const DailyLahApp(),
    );

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

/// /v1/places (Geoapify) that knows one restaurant by name.
class _Places extends PlacesApi {
  final queries = <String>[];
  @override
  Future<Map<String, dynamic>> search(String query) async {
    queries.add(query);
    return {
      'fetched_at': 0,
      'data': [
        if (query.toLowerCase().contains('putra'))
          {
            'name': 'Putra Minang',
            'address': '51 Bencoolen Street, Singapore 189630, Singapore',
            'postal': '189630',
            'lat': 1.29942,
            'lng': 103.85051,
            'type': 'amenity',
          },
      ],
    };
  }
}

Widget _appWithOneMap(OneMapApi oneMap, {MapsLinks? links, PlacesApi? places}) => ProviderScope(retry: noRetry,
      overrides: [
        ...overridesFor(_normal, householdFavorites, tuesdayMorning),
        oneMapProvider.overrideWithValue(oneMap),
        placesProvider.overrideWithValue(places ?? _Places()),
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

/// Two buses of service 10, each with its own live position (times against the real clock, as parsed).
class _TwoBusApi extends FakeApi {
  _TwoBusApi(this.lat1, this.lng1, this.lat2, this.lng2);
  final double lat1, lng1, lat2, lng2;

  @override
  Future<Map<String, dynamic>> busArrival(String stopCode) async {
    Map<String, dynamic> bus(int min, double lat, double lng) => {
          'EstimatedArrival': DateTime.now().add(Duration(minutes: min, seconds: 20)).toIso8601String(),
          'Load': 'SEA',
          'Latitude': '$lat',
          'Longitude': '$lng',
          'Monitored': 1,
        };
    return {
      'data': {
        'Services': [
          {'ServiceNo': '10', 'NextBus': bus(4, lat1, lng1), 'NextBus2': bus(15, lat2, lng2)},
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

/// Scrolls [page]'s main list until [target] is built and on screen (large text pushes rows
/// below the first screen, where a lazy list has not built them yet).
Future<void> _scrollTo(WidgetTester tester, Finder target, {required Type page}) async {
  // A `.first` finder throws instead of finding nothing.
  bool missing() {
    try {
      return target.evaluate().isEmpty;
    } on StateError {
      return true;
    }
  }

  for (var i = 0; i < 30 && missing(); i++) {
    await tester.drag(find.byType(page), const Offset(0, -300), warnIfMissed: false);
    await tester.pump();
  }
  await tester.ensureVisible(target);
  await tester.pump();
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
    final halalTile = find.byWidgetPredicate((w) => w is PlaceRow && w.icon == Icons.restaurant_outlined).first;
    await tester.ensureVisible(halalTile);
    await tester.pump();
    final name = tester.widget<PlaceRow>(halalTile).title;
    await tester.tap(halalTile);
    await settle(tester);
    await tester.ensureVisible(find.text('Ate here'));
    await tester.pump();
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
    await tester.tap(find.text(const S().mealChangeTime));
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
    expect(find.text(const S().mealTimeAt('6:05')), findsOneWidget);
    await tester.tap(find.text(const S().save));
    await settle(tester);

    final meal = box.read(habitsProvider).meals.single;
    expect(meal.at, DateTime(2026, 10, 20, 6, 5));
    expect(meal.name, 'Test Kitchen');
    expect(meal.priceCents, isNull, reason: 'changing the time does not add a price');
  });

  testWidgets('History: a meal logged late moves to the day before, and the chart shows what was spent', (tester) async {
    await applyCondition(tester, _normal);
    // The date picker goes by the real clock, so the app runs on it too, and the meal is on the
    // 15th of last month.
    final real = DateTime.now();
    await tester.pumpWidget(appUnder(_normal, householdFavorites, real));
    await settle(tester);
    const s = S();
    final box = containerOf(tester);
    final at = DateTime(real.year, real.month - 1, 15, 12, 30);
    await box.read(habitsProvider.notifier).restore(Habits(
      meals: [MealLog(hawkerId: 'p:1.35000,103.94000', at: at, name: 'Test Kitchen', priceCents: 2000)],
    ));
    box.read(historyPeriodProvider.notifier).state = HistoryPeriod.all;
    box.read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);

    // The chart: one meal, so only Meals in the legend.
    await _scrollTo(tester, find.textContaining(s.spentIn('all')), page: HistoryPage);
    expect(find.text('${s.historyMeals} ${s.money(2000)}'), findsOneWidget);
    expect(find.textContaining(s.spendTransport), findsNothing);

    final row = find.descendant(of: find.byType(HistoryPage), matching: find.text('Test Kitchen'));
    await _scrollTo(tester, row, page: HistoryPage);
    await tester.drag(find.descendant(of: find.byType(HistoryPage), matching: find.byType(Scrollable)).first,
        const Offset(0, -300), warnIfMissed: false);
    await tester.pump();
    await tester.tap(row);
    await settle(tester);
    await tester.tap(find.text(s.mealChangeDate));
    await settle(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('14')));
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.tap(find.text(s.save));
    await settle(tester);

    final meal = box.read(habitsProvider).meals.single;
    expect(meal.at, DateTime(at.year, at.month, 14, 12, 30));
    expect((meal.name, meal.priceCents), ('Test Kitchen', 2000));
  });

  testWidgets(r'Ate here with a price at 200% text on 320 dp: $6 is logged and offered again next time', (tester) async {
    const big = Condition('big', textScale: 2.0, size: Size(320, 780));
    const s = S();
    await applyCondition(tester, big);
    await tester.pumpWidget(appUnder(big, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['Nearby']!;
    box.read(nearbySectionProvider.notifier).state = 'eat';
    await settle(tester);

    final halalTile = find.byWidgetPredicate((w) => w is PlaceRow && w.icon == Icons.restaurant_outlined).first;
    await _scrollTo(tester, halalTile, page: NearbyPage);
    final name = tester.widget<PlaceRow>(halalTile).title;
    Future<void> openSheet() async {
      await _scrollTo(tester, halalTile, page: NearbyPage);
      await tester.tap(halalTile);
      await settle(tester);
      await _scrollTo(tester, find.text(s.ateHere), page: BottomSheet);
    }

    await openSheet();
    // Nothing is picked the first time: one tap on Ate here would log without a price.
    expect(find.text(s.mealPrice), findsOneWidget);
    for (final c in [r'$4', r'$6', r'$8', s.mealPriceOther]) {
      final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, c));
      expect(chip.selected, isFalse);
      expect(tester.getSize(find.widgetWithText(ChoiceChip, c)).height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, r'$6'));
    await tester.pump();
    await tester.tap(find.text(s.ateHere));
    await settle(tester);
    expect(box.read(habitsProvider).meals.single.priceCents, 600);

    // Next time at the same place $6 is already picked.
    await openSheet();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, r'$6')).selected, isTrue);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await settle(tester);

    box.read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);
    await _scrollTo(tester, find.descendant(of: find.byType(HistoryPage), matching: find.text(s.money(600))).first, page: HistoryPage);
    await _scrollTo(tester, find.descendant(of: find.byType(HistoryPage), matching: find.text(name)), page: HistoryPage);
    expect(find.text(r'$6.00'), findsWidgets);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(r'History: a meal gets a typed price (Other) at 200% text; unpriced meals are not counted', (tester) async {
    const big = Condition('big', textScale: 2.0, size: Size(320, 780));
    const s = S();
    await applyCondition(tester, big);
    await tester.pumpWidget(appUnder(big, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    await box.read(habitsProvider.notifier).restore(Habits(meals: [
      MealLog(hawkerId: 'p:1.35000,103.94000', at: DateTime(2026, 10, 20, 6, 30), name: 'Test Kitchen'),
      MealLog(hawkerId: 'p:1.36000,103.95000', at: DateTime(2026, 10, 20, 12), name: 'Other Kitchen', priceCents: 400),
    ]));
    box.read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);
    await _scrollTo(tester, find.descendant(of: find.byType(HistoryPage), matching: find.text(s.money(400))).first, page: HistoryPage);

    final row = find.text('Test Kitchen');
    await _scrollTo(tester, row, page: HistoryPage);
    // Bring the row to the middle of the screen, clear of the floating tab bar, then tap it.
    await tester.drag(find.descendant(of: find.byType(HistoryPage), matching: find.byType(Scrollable)).first,
        Offset(0, 390 - tester.getCenter(row).dy), warnIfMissed: false);
    await tester.pump();
    await tester.tap(row);
    await settle(tester);
    expect(tester.takeException(), isNull);

    // "Other": a wrong amount is refused, a real one is kept.
    await tester.tap(find.widgetWithText(ChoiceChip, s.mealPriceOther));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '250');
    await tester.tap(find.text(s.save).last);
    await settle(tester);
    expect(find.text(s.mealPriceInvalid), findsOneWidget);
    await tester.enterText(find.byType(TextField), '5.5');
    await tester.tap(find.text(s.save).last);
    await settle(tester);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, r'$5.50')).selected, isTrue);
    // A typed price clears like the chips do, then goes back on.
    await tester.tap(find.widgetWithText(ChoiceChip, r'$5.50'));
    await settle(tester);
    expect(find.widgetWithText(ChoiceChip, s.mealPriceOther), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, s.mealPriceOther));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '5.5');
    await tester.tap(find.text(s.save).last);
    await settle(tester);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, r'$5.50')).selected, isTrue);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(s.save));
    await tester.tap(find.text(s.save));
    await settle(tester);

    final meals = box.read(habitsProvider).meals;
    expect(meals.map((m) => m.priceCents), [550, 400]);
    expect(meals.first.at, DateTime(2026, 10, 20, 6, 30), reason: 'the time stays');
    await _scrollTo(tester, find.descendant(of: find.byType(HistoryPage), matching: find.text(s.money(950))).first, page: HistoryPage);
    expect(tester.takeException(), isNull);
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

  testWidgets("Where's my bus opens on the bus that was tapped, and shows a bus between two stops", (tester) async {
    Map stopOf(String code) => (_bundle('bus_stops') as List).cast<Map>().firstWhere((s) => s['c'] == code);
    double mid(String k) => ((stopOf('96281')[k] as num) + (stopOf('76061')[k] as num)) / 2;
    // The next 10 is halfway along the 1.3 km without a stop before Blk 938; the one after is at a stop.
    final api = _TwoBusApi(mid('la'), mid('lo'), (stopOf('96101')['la'] as num).toDouble(), (stopOf('96101')['lo'] as num).toDouble());
    await applyCondition(tester, _normal);
    await tester.pumpWidget(ProviderScope(retry: noRetry,
      overrides: [
        initialFavoritesProvider.overrideWithValue(householdFavorites),
        apiProvider.overrideWithValue(api),
        bundleRepoProvider.overrideWithValue(FileBundles()),
        clockProvider.overrideWith((ref) => Stream.value(tuesdayMorning)),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: WhereBusSheet(stop: tampinesInt, service: '10', minutes: 15)),
      ),
    ));
    await settle(tester);

    // Tapped the bus due in 15 min: that one is shown, not the next.
    ChoiceChip chip(String label) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
    expect(chip('Then · 15 min').selected, isTrue);
    expect(chip('Next · 4 min').selected, isFalse);
    expect(find.text('YOU · 15 min'), findsOneWidget);
    expect(find.text('bus here'), findsOneWidget);
    expect(find.textContaining('On the way'), findsNothing);

    // The next bus is between two stops: drawn after the stop it left, with the distance to go.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Next · 4 min'));
    await settle(tester);
    expect(find.text('YOU · 4 min'), findsOneWidget);
    expect(find.textContaining('On the way · 1.'), findsOneWidget);
    expect(find.text('bus here'), findsOneWidget);
    expect(find.text('passed'), findsOneWidget);
    expect(find.text(stopOf('96281')['n'] as String), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("Already home: Today greets instead of bus times, and a trip still being timed ends", (tester) async {
    // Home is where the test phone is (Tampines Int); the office is at Raffles Place.
    final fav = householdFavorites.copyWith(places: {
      ...householdFavorites.places,
      PlaceKind.home: Place(
        kind: PlaceKind.home,
        stops: const [tampinesInt],
        address: '156 TAMPINES ST 12',
        addrLat: tampinesInt.lat,
        addrLng: tampinesInt.lng,
      ),
    });
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, fav, tuesdayEvening));
    await settle(tester);

    expect(find.text("You're home. Take a rest."), findsOneWidget);
    expect(find.byType(TripSection), findsNothing);
    expect(find.textContaining("I'm leaving"), findsNothing);

    // Forgot Arrived: the trip home is still being timed when the app comes back to the front.
    final box = containerOf(tester);
    await box.read(habitsProvider.notifier).startTrip('work>home', DateTime.now().subtract(const Duration(minutes: 50)));
    await settle(tester);
    expect(box.read(habitsProvider).tripStart, isNotNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(box.read(habitsProvider).tripStart, isNull);
    // No usual time for this trip yet, so the 50 minutes are not logged as one.
    expect(box.read(habitsProvider).trips, isEmpty);

    // Heading out again: the trip is one tap away.
    await tester.tap(find.text('Show my trip anyway'));
    await settle(tester);
    expect(find.byType(TripSection), findsOneWidget);
    expect(find.text("You're home. Take a rest."), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lunch: switched on in More, Today suggests a hawker at the office and opens Nearby on Eat', (tester) async {
    // The office is where the test phone is (Tampines Int), so Today greets instead of showing the trip.
    final atOffice = householdFavorites.copyWith(places: {
      ...householdFavorites.places,
      PlaceKind.work: Place(
        kind: PlaceKind.work,
        stops: const [fullertonSq],
        address: '1 TAMPINES CENTRAL',
        addrLat: tampinesInt.lat,
        addrLng: tampinesInt.lng,
        go: const TimeOfDayHM(8, 0),
        back: const TimeOfDayHM(18, 0),
      ),
    });
    final noon = DateTime(2026, 10, 20, 12);
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, atOffice, noon));
    await settle(tester);
    expect(find.text('Have a good day at work'), findsOneWidget);
    expect(find.textContaining('Lunch?'), findsNothing, reason: 'off until switched on');
    expect(find.byType(LunchCard), findsNothing);

    // More > Alerts: the switch, then the time shows.
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['More']!;
    await settle(tester);
    expect(find.text('Lunch time: 12.00'), findsNothing);
    await tester.scrollUntilVisible(find.text('Lunch suggestion on work days'), 200,
        scrollable: find.descendant(of: find.byType(MorePage), matching: find.byType(Scrollable)).first);
    // Clear of the floating tab bar before tapping.
    await Scrollable.ensureVisible(tester.element(find.text('Lunch suggestion on work days')), alignment: 0.3);
    await settle(tester);
    await tester.tap(find.text('Lunch suggestion on work days'));
    await settle(tester);
    expect(box.read(favoritesProvider).lunchAlerts, isTrue);
    expect(find.text('Lunch time: 12.00'), findsOneWidget);

    // Back on Today: a hawker centre near the office, inside the greeting.
    box.read(shellTabProvider.notifier).state = _tabs['Today']!;
    await settle(tester);
    expect(find.textContaining('Lunch?'), findsOneWidget);
    expect(find.byType(LunchCard), findsNothing);
    await tester.tap(find.text('Where to eat'));
    await settle(tester);
    expect(box.read(shellTabProvider), _tabs['Nearby']);
    expect(box.read(nearbySectionProvider), 'eat');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lunch away from the office: a card on Today that opens Nearby on Eat', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(
        appUnder(_normal, householdFavorites.copyWith(lunchAlerts: true), DateTime(2026, 10, 20, 12)));
    await settle(tester);
    expect(find.byType(LunchCard), findsOneWidget);
    expect(find.textContaining('Lunch?'), findsNothing);
    await tester.tap(find.byType(LunchCard));
    await settle(tester);
    final box = containerOf(tester);
    expect(box.read(shellTabProvider), _tabs['Nearby']);
    expect(box.read(nearbySectionProvider), 'eat');
    // Outside lunch time there is no card.
    await tester.pumpWidget(KeyedSubtree(
        key: UniqueKey(), child: appUnder(_normal, householdFavorites.copyWith(lunchAlerts: true), tuesdayMorning)));
    await settle(tester);
    expect(find.byType(LunchCard), findsNothing);
  });

  testWidgets('Without location, or away from home, Today shows the trip as before', (tester) async {
    const denied = Condition('denied', location: LocationPermission.denied);
    for (final c in [_normal, denied]) {
      await applyCondition(tester, c);
      await tester.pumpWidget(KeyedSubtree(key: UniqueKey(), child: appUnder(c, householdFavorites, tuesdayEvening)));
      await settle(tester);
      expect(find.byType(TripSection), findsOneWidget, reason: c.name);
      expect(find.byType(AtPlaceCard), findsNothing, reason: c.name);
    }
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

  group('More > Alerts > Show me an example', () {
    const notifChannel = MethodChannel('dexterous.com/flutter/local_notifications');
    const richChannel = MethodChannel('dailylah/notify');
    final rich = <Map<Object?, Object?>>[];
    var allowed = true;

    Future<void> openMore(WidgetTester tester) async {
      rich.clear();
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(notifChannel, (call) async => switch (call.method) {
            'initialize' => true,
            'areNotificationsEnabled' || 'requestNotificationsPermission' => allowed,
            _ => null,
          });
      messenger.setMockMethodCallHandler(richChannel, (call) async {
        rich.add((((call.arguments as Map)['note']) as Map).cast<Object?, Object?>());
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(notifChannel, null);
        messenger.setMockMethodCallHandler(richChannel, null);
      });
      await applyCondition(tester, _normal);
      await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
      await settle(tester);
      containerOf(tester).read(shellTabProvider.notifier).state = _tabs['More']!;
      await settle(tester);
      final row = find.widgetWithText(TextButton, 'Show me an example');
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await settle(tester);
    }

    testWidgets('posts every sample alert and leaves the alert log alone', (tester) async {
      allowed = true;
      await openMore(tester);
      expect(rich.map((n) => n['id']).toSet(),
          {102, 108, 109, 101, 110, 103, 105, 112, 106, 104, 111, 107, 120, 121, 122, 123});
      expect(rich.every((n) => (n['pills'] as List).isNotEmpty), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('alerts.sent'), isNull, reason: 'a sample must not stop the real alert');
      expect(find.text('Allow notifications to see the examples'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with notifications not allowed it posts nothing and says why', (tester) async {
      allowed = false;
      await openMore(tester);
      expect(rich, isEmpty);
      expect(find.text('Allow notifications to see the examples'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('More > Alerts: a tile switches its alert, says On or Off, and the count follows', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['More']!;
    await settle(tester);
    final before = alertsOn(box.read(favoritesProvider));
    expect(box.read(favoritesProvider).dengueAlerts, isTrue);
    expect(find.text('$before of 9 on'), findsOneWidget);
    final tile = find.widgetWithText(SettingTile, 'New dengue cluster');
    // Clear of the floating tab bar before tapping.
    await Scrollable.ensureVisible(tester.element(tile), alignment: 0.3);
    await settle(tester);
    expect(find.descendant(of: tile, matching: find.text('On')), findsOneWidget);
    expect(tester.getSemantics(tile), isSemantics(hasToggledState: true, isToggled: true, hasTapAction: true));
    await tester.tap(tile);
    await settle(tester);
    expect(box.read(favoritesProvider).dengueAlerts, isFalse);
    expect(find.descendant(of: tile, matching: find.text('Off')), findsOneWidget);
    expect(tester.getSemantics(tile), isSemantics(hasToggledState: true, isToggled: false, hasTapAction: true));
    expect(find.text('${before - 1} of 9 on'), findsOneWidget);
    // Two tiles side by side, one column once the text is too large for two.
    // (grid width, text scale): a 412, 360 and 320 dp phone have 380, 328 and 288 dp for the grid.
    expect(tileColumns(380, 1.0), 2);
    expect(tileColumns(380, 1.5), 2);
    expect(tileColumns(328, 1.3), 2);
    expect(tileColumns(328, 1.5), 1);
    expect(tileColumns(288, 1.0), 2);
    expect(tileColumns(288, 1.3), 1, reason: 'a long word would break in a tile this narrow');
    expect(tileColumns(380, 2.0), 1);
    // A link tile is a button to TalkBack, with its title and line in one node.
    final link = find.widgetWithText(SettingTile, 'Appearance');
    await Scrollable.ensureVisible(tester.element(link), alignment: 0.3);
    await settle(tester);
    expect(tester.getSemantics(link),
        isSemantics(isButton: true, hasTapAction: true, label: 'Appearance\nFollow my phone'));
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
    final toggle = find.widgetWithText(SettingTile, 'My car is electric');
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
    // The card says the answer and what it is based on, and opens the sheet.
    expect([for (var level = 1; level <= 4; level++) find.text(_s.taxiEaseTitle(level)).evaluate().length], contains(1));
    await tester.tap(find.textContaining('within 500 m').first);
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

  testWidgets('Need a toilet? on the bus lists the stops ahead with a toilet, soonest first', (tester) async {
    await applyCondition(tester, _normal);
    // Bus 10 from Tampines Int towards Changi General Hospital; wake me at Opp Blk 3012.
    const alight = BusStop(code: '96109', name: 'Opp Blk 3012', road: 'Simei St 1', lat: 1.337371, lng: 103.950673);
    const before = BusStop(code: '96289', name: 'Changi General Hosp', road: 'Simei St 3', lat: 1.34004, lng: 103.948359);
    await tester.pumpWidget(pageUnder(_normal, householdFavorites, tuesdayMorning,
        const WakeMePage(service: '10', alight: alight, before: before, from: tampinesInt)));
    await settle(tester);
    final box = containerOf(tester);
    expect(box.read(wakeProvider)?.from?.code, '75009');

    await tester.tap(find.text('Need a toilet?'));
    await settle(tester);
    expect(find.byType(ToiletSheet), findsOneWidget);
    // Two stops ahead have a toilet within 250 m: Opp Our Tampines Hub and Changi General Hosp.
    final rows = tester.widgetList<ListTile>(find.descendant(of: find.byType(ToiletSheet), matching: find.byType(ListTile)));
    expect([for (final r in rows) (r.title as Text).data], [
      'Get off at Opp Our Tampines Hub (in about 2 min)',
      'Get off at Changi General Hosp (in about 6 min)',
    ]);
    expect(find.text('Our Tampines Hub, 2 min walk'), findsOneWidget); // ~120 m, beats the market (~140 m)
    expect(find.textContaining('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.byTooltip('Walking directions'), findsNWidgets(2));
    box.read(wakeProvider.notifier).stop();
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Need a toilet? on the train lists the next stations, with a mall when one is close', (tester) async {
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
    expect(find.byType(MrtRidePage), findsOneWidget);

    final need = find.text('Need a toilet?');
    await tester.scrollUntilVisible(need, 300,
        scrollable: find.descendant(of: find.byType(MrtRidePage), matching: find.byType(Scrollable)).first);
    await tester.tap(need);
    await settle(tester);
    expect(find.byType(ToiletSheet), findsOneWidget);
    final rows = tester.widgetList<ListTile>(find.descendant(of: find.byType(ToiletSheet), matching: find.byType(ListTile)));
    // Simei and Tanah Merah have no toilet in the data: "Stations usually have a toilet". Bedok has
    // Bedok Mall, as quick as Kembangan's station toilet, and malls come first.
    expect([for (final r in rows) (r.title as Text).data], [
      'Get off at Simei (in about 2 min)',
      'Get off at Tanah Merah (in about 4 min)',
      'Get off at Bedok (in about 6 min)',
    ]);
    expect(find.text('Stations usually have a toilet'), findsNWidgets(2));
    expect(find.text('Bedok Mall, 2 min walk'), findsOneWidget);
    box.read(rideProvider.notifier).stop();
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nearby > Toilets shows the three best toilets near the place', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['Nearby']!;
    box.read(adhocPlaceProvider.notifier).state = const Place(
        kind: PlaceKind.other, name: 'Tampines Int', address: 'Tampines Int', addrLat: 1.354076, addrLng: 103.943391);
    box.read(nearbyKeyProvider.notifier).state = 'adhoc';
    await settle(tester);
    await tester.tap(find.text('Toilets'));
    await settle(tester);
    expect(find.text('Toilets nearby'), findsOneWidget);
    final rows = tester.widgetList<PlaceRow>(find.descendant(of: find.byType(ToiletsNearby), matching: find.byType(PlaceRow)));
    // The market is a 1 min walk; the two malls are further.
    expect([for (final r in rows) r.title], ['Tampines Round Market', 'Tampines Mall', 'Our Tampines Hub']);
    expect(rows.first.subtitle, 'Hawker centre · 1 min walk');
    expect((rows.first.figure, rows.first.figureLabel), ('92', 'm'));
    // A row opens the toilet's sheet, where the walking directions are.
    await tester.tap(find.text('Tampines Round Market'));
    await settle(tester);
    expect(find.text(_s.wayWalk), findsWidgets);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.textContaining('© OpenStreetMap contributors'), findsOneWidget);
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

    // While riding, the ongoing notification gets the line and the stops to go, and is only
    // rewritten when that changes.
    final ongoing = <Map<Object?, Object?>>[];
    const richChannel = MethodChannel('dailylah/notify');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(richChannel, (call) async {
      if (call.method == 'showOngoing') ongoing.add((call.arguments as Map).cast<Object?, Object?>());
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(richChannel, null));
    await tester.runAsync(() => box.read(rideProvider.notifier).tickAt(ride.start.add(const Duration(seconds: 20))));
    await tester.runAsync(() => box.read(rideProvider.notifier).tickAt(ride.start.add(const Duration(seconds: 40))));
    expect(ongoing, hasLength(1), reason: 'same text twice: one write');
    expect(ongoing.single['serviceNotificationId'], 75415);
    final watch = (ongoing.single['note'] as Map).cast<Object?, Object?>();
    expect(watch['body'], 'Riding to Raffles Place');
    expect([for (final p in watch['pills'] as List) (p as Map)['text']], ['EWL', '${ride.ride.stops} stops to go']);

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
    final row = find.widgetWithText(SettingTile, 'Appearance');
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

  testWidgets('A public holiday on a workday: no trip on Today, a holiday banner instead', (tester) async {
    const s = S();
    final banner = s.publicHolidayToday('Deepavali (Observed)');
    await applyCondition(tester, _normal);
    // Monday 9 Nov 2026, Deepavali (Observed) in web/data/holidays.json.
    await tester.pumpWidget(appUnder(_normal, householdFavorites, DateTime(2026, 11, 9, 7, 30)));
    await settle(tester);
    expect(find.textContaining(banner), findsOneWidget);
    expect(find.byType(TripSection), findsNothing);
    expect(find.textContaining('Heading to'), findsNothing);

    // The next day is a normal workday: the trip is back and there is no banner.
    await tester.pumpWidget(KeyedSubtree(key: UniqueKey(), child: appUnder(_normal, householdFavorites, DateTime(2026, 11, 10, 7, 30))));
    await settle(tester);
    expect(find.textContaining(banner), findsNothing);
    expect(find.byType(TripSection), findsOneWidget);
  });

  testWidgets('200% text on 320 dp: bus rows, the bus route strip and EV chargers fit', (tester) async {
    const big = Condition('big', textScale: 2.0, size: Size(320, 780));
    for (final page in <Widget>[
      const StopArrivalsPage(stop: tampinesInt),
      const Scaffold(body: WhereBusSheet(stop: tampinesInt, service: '10')),
    ]) {
      await applyCondition(tester, big);
      await tester.pumpWidget(pageUnder(big, householdFavorites, tuesdayMorning, page));
      await settle(tester);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
    }
    // The load meter's label wraps under its bars instead of overflowing.
    await tester.pumpWidget(pageUnder(big, householdFavorites, tuesdayMorning, const StopArrivalsPage(stop: tampinesInt)));
    await settle(tester);
    expect(find.byType(LoadMeter), findsWidgets);

    // At normal text the stop names keep the row: the tag beside them stays narrow.
    await applyCondition(tester, _normal);
    await tester.pumpWidget(pageUnder(
        _normal, householdFavorites, tuesdayMorning, const Scaffold(body: WhereBusSheet(stop: tampinesInt, service: '10'))));
    await settle(tester);
    final rows = find.descendant(of: find.byType(WhereBusSheet), matching: find.byType(IntrinsicHeight));
    expect(rows, findsWidgets);
    for (final row in rows.evaluate()) {
      final name = find.descendant(of: find.byWidget(row.widget), matching: find.byType(Expanded)).first;
      expect(tester.getSize(name).width, greaterThanOrEqualTo(tester.getSize(find.byWidget(row.widget)).width - 64 - 8 - 104 - 1));
    }
    await applyCondition(tester, big);

    // EV chargers on Home > Parking.
    await tester.pumpWidget(appUnder(big, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['Home']!;
    box.read(homeSectionProvider.notifier).state = 'parking';
    await settle(tester);
    await scrollThrough(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TalkBack: pills say which one is on and are 48 dp tall; the taxi map can be read and tapped', (tester) async {
    final semantics = tester.ensureSemantics();
    await applyCondition(tester, _normal);
    final home = householdFavorites.places[PlaceKind.home]!;
    await tester.pumpWidget(pageUnder(
      _normal,
      householdFavorites,
      tuesdayMorning,
      Scaffold(
        body: ListView(children: [
          PillRow(
            items: const [('all', Icons.list, 'All'), ('trip', Icons.route_outlined, 'Trips')],
            selected: 'all',
            onTap: (_) {},
          ),
          Center(child: StickerIconButton(icon: Icons.settings_outlined, onPressed: () {}, tooltip: 'Settings')),
          TaxiRadar(
            origin: home,
            taxis: [(home.lat + 0.002, home.lng)],
            stands: [EPoint(name: 'Test stand', lat: home.lat - 0.002, lng: home.lng)],
          ),
        ]),
      ),
    ));
    await settle(tester);
    expect(tester.getSemantics(find.text('All')), isSemantics(label: 'All', isButton: true, isSelected: true));
    expect(tester.getSemantics(find.text('Trips')), isSemantics(label: 'Trips', isButton: true, isSelected: false));
    for (final label in ['All', 'Trips']) {
      final pill = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      expect(tester.getSize(pill).height, greaterThanOrEqualTo(48));
    }
    expect(tester.getSize(find.byType(StickerIconButton)), const Size.square(48));
    expect(tester.getSize(find.byType(TaxiStandPin)), const Size.square(48));

    // The painted radar has a label, and its tap picks the nearest taxi.
    const s = S();
    final radar = find.semantics.byLabel(s.taxiRadarLabel(1));
    expect(radar, findsOneWidget);
    expect(find.text(s.taxiTapHint), findsOneWidget);
    tester.semantics.tap(radar);
    await tester.pump();
    expect(find.textContaining('Free taxi · '), findsOneWidget);
    // TalkBack reads the picked taxi: the line under the map is a live region.
    expect(tester.getSemantics(find.textContaining('Free taxi · ')), isSemantics(isLiveRegion: true));
    // The map is one TalkBack node: no tap target on the page that TalkBack reads as nothing.
    final taps = find.semantics.byPredicate((n) => n.getSemanticsData().hasAction(SemanticsAction.tap) && n.label.isEmpty && n.tooltip.isEmpty);
    expect(taps, findsNothing);

    // A taxi queuing at a stand: a tap on the taxi's side of the 48 dp pin picks the taxi; a tap on
    // the stand's centre opens the stand.
    final cab = (home.lat + 0.0003, home.lng);
    final queue = EPoint(name: 'Queue stand', lat: home.lat + 0.0003, lng: home.lng + 0.0001);
    await tester.pumpWidget(pageUnder(
      _normal,
      householdFavorites,
      tuesdayMorning,
      Scaffold(body: ListView(children: [TaxiRadar(origin: home, taxis: [cab], stands: [queue])])),
    ));
    await settle(tester);
    final pin = find.byType(TaxiStandPin);
    final pinBox = tester.getRect(pin);
    final stand = pinBox.center;
    // The taxi is drawn left of the stand's centre (smaller longitude), inside the pin.
    await tester.tapAt(Offset(pinBox.left + 4, stand.dy));
    await tester.pump();
    expect(find.textContaining('Free taxi · '), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tapAt(stand);
    await settle(tester);
    expect(find.text('Queue stand'), findsWidgets, reason: 'the stand sheet opens');
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await settle(tester);

    // No free taxi, one stand: the stand is still its own button, not part of the map's label.
    await tester.pumpWidget(pageUnder(
      _normal,
      householdFavorites,
      tuesdayMorning,
      Scaffold(
        body: ListView(children: [
          TaxiRadar(origin: home, taxis: const [], stands: [EPoint(name: 'Test stand', lat: home.lat - 0.002, lng: home.lng)]),
        ]),
      ),
    ));
    await settle(tester);
    final standNode = find.semantics.byPredicate((n) => n.label.startsWith('Test stand'));
    expect(standNode, findsOneWidget);
    expect(standNode.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(find.semantics.byLabel(s.taxiRadarLabel(0)), findsOneWidget);
    semantics.dispose();
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
    for (final label in ['Current location', 'Home', 'Work', 'School', 'Gym']) {
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
    expect(find.text('Current location → Work'), findsOneWidget);

    // Swap: Work → Here.
    await tester.tap(find.byTooltip(s.swapEnds));
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'work');
    expect(box.read(goKeyProvider), 'here');
    expect(find.text('Work → Current location'), findsOneWidget);

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

  testWidgets('Plan a trip: a restaurant name is found by place search, with attribution', (tester) async {
    await applyCondition(tester, _normal);
    final oneMap = _OneMap();
    final places = _Places();
    await tester.pumpWidget(_appWithOneMap(oneMap, places: places));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);

    await tester.tap(find.text(s.searchAddressHint).last); // the To field
    await settle(tester);
    expect(find.text(s.placeHint), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AddressPickerPage), matching: find.byType(TextField)), 'putra minang');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(places.queries, ['putra minang']);
    expect(oneMap.queries, isEmpty);
    expect(find.text(s.placesAttribution), findsOneWidget);
    await tester.tap(find.text('Putra Minang, 51 Bencoolen Street'));
    await settle(tester);

    expect(find.byType(AddressPickerPage), findsNothing);
    expect(box.read(goKeyProvider), 'adhoc');
    final dest = box.read(goAdhocDestProvider)!;
    expect(dest.name, 'Putra Minang'); // the place name, not the whole address
    expect(dest.postal, '189630');
    expect(dest.addrLat, closeTo(1.29942, 1e-6));

    // A postal code still goes to OneMap, and OneMap results carry no attribution.
    await tester.tap(find.text(s.searchAddressHint).first); // the From field
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AddressPickerPage), matching: find.byType(TextField)), '189630');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(places.queries, ['putra minang']);
    expect(oneMap.queries, ['189630']);
    expect(find.textContaining('51 Bencoolen Street'), findsOneWidget);
    expect(find.text(s.placesAttribution), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The address picker outside Plan a trip (setup) never calls place search', (tester) async {
    await applyCondition(tester, _normal);
    final oneMap = _OneMap();
    final places = _Places();
    const s = S();
    await tester.pumpWidget(ProviderScope(retry: noRetry,
      overrides: [
        ...overridesFor(_normal, householdFavorites, tuesdayMorning),
        oneMapProvider.overrideWithValue(oneMap),
        placesProvider.overrideWithValue(places),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: AddressPickerPage(title: s.addressFor('Home'))),
    ));
    await settle(tester);
    expect(find.text(s.addressHint), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'putra minang');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(places.queries, isEmpty);
    expect(oneMap.queries, ['putra minang']);
    expect(find.text(s.noAddressTips), findsOneWidget);
    expect(find.text(s.placesAttribution), findsNothing);
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
    expect(find.text('Current location → $name'), findsOneWidget);

    await tester.tap(find.byTooltip(s.clearSearch));
    await settle(tester);
    expect(box.read(goKeyProvider), isNull);
    expect(find.text(s.goSomewhereHint), findsOneWidget);
  });

  testWidgets('Plan a trip: picking the other end swaps the searched place along', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    const searched = Place(kind: PlaceKind.other, name: 'Bencoolen', addrLat: 1.29661, addrLng: 103.85220);
    box.read(goAdhocFromProvider.notifier).state = searched;
    box.read(goFromKeyProvider.notifier).state = 'adhoc';
    box.read(goKeyProvider.notifier).state = 'home';
    await settle(tester);
    expect(find.text('Bencoolen → Home'), findsOneWidget);
    // Home on From: the ends swap, and the searched place goes to To with them.
    await tester.tap(find.text('Home').first);
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'home');
    expect(box.read(goKeyProvider), 'adhoc');
    expect(box.read(goAdhocDestProvider)?.name, 'Bencoolen');
    expect(find.text('Home → Bencoolen'), findsOneWidget);
  });

  testWidgets("Plan a trip: \"You're here\" only when the trip starts Here", (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    // A destination 50 m from the phone (Tampines Int).
    final near = Place(kind: PlaceKind.other, name: 'Near', addrLat: tampinesInt.lat + 0.00045, addrLng: tampinesInt.lng);
    box.read(goAdhocDestProvider.notifier).state = near;
    box.read(goKeyProvider.notifier).state = 'adhoc';
    box.read(modeOverrideProvider.notifier).state = {'adhoc': TravelMode.transit};
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'here');
    expect(find.text(s.youAreHere), findsOneWidget);
    // The same spot as a searched start is a start, not "you are here".
    box.read(goAdhocFromProvider.notifier).state =
        Place(kind: PlaceKind.other, name: 'Searched', addrLat: tampinesInt.lat, addrLng: tampinesInt.lng);
    box.read(goFromKeyProvider.notifier).state = 'adhoc';
    await settle(tester);
    expect(find.text('Searched → Near'), findsOneWidget);
    expect(find.text(s.youAreHere), findsNothing);
  });

  testWidgets('Plan a trip: with both ends searched, a new search changes only its own end', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(_appWithOneMap(_OneMap()));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    box.read(goAdhocFromProvider.notifier).state = const Place(kind: PlaceKind.other, name: 'Start A', addrLat: 1.30, addrLng: 103.85);
    box.read(goAdhocDestProvider.notifier).state = const Place(kind: PlaceKind.other, name: 'End B', addrLat: 1.35, addrLng: 103.94);
    box.read(goFromKeyProvider.notifier).state = 'adhoc';
    box.read(goKeyProvider.notifier).state = 'adhoc';
    await settle(tester);
    expect(find.text('Start A → End B'), findsOneWidget);
    await tester.tap(find.text('End B').last);
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AddressPickerPage), matching: find.byType(TextField)), '189630');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tester.tap(find.textContaining('51 Bencoolen Street'));
    await settle(tester);
    expect(box.read(goAdhocFromProvider)!.name, 'Start A');
    expect(box.read(goAdhocDestProvider)!.postal, '189630');
    expect(find.textContaining(RegExp(r'^Start A → ')), findsOneWidget);
    expect(find.text(s.searchAddressHint), findsNothing);
  });

  testWidgets('Trip buses at 200% text on 320 dp: the bus plate sits above the leave line', (tester) async {
    const big = Condition('big', textScale: 2.0, size: Size(320, 780));
    await applyCondition(tester, big);
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
    final leave = find.text(s.leaveInHead('10', 7));
    await tester.ensureVisible(leave);
    await tester.pump();
    final card = find.ancestor(of: leave, matching: find.byType(Panel)).first;
    final plate = find.descendant(of: card, matching: find.byType(BusPlate));
    expect(tester.getBottomLeft(plate).dy, lessThanOrEqualTo(tester.getTopLeft(leave).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets("Plan a trip: From and To at the same spot say You're already there, no walk or buses", (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    // A searched start at the work address, to Work.
    final work = householdFavorites.places[PlaceKind.work]!;
    box.read(goAdhocFromProvider.notifier).state =
        Place(kind: PlaceKind.other, name: '1 Raffles Place', addrLat: work.lat, addrLng: work.lng);
    box.read(goFromKeyProvider.notifier).state = 'adhoc';
    box.read(goKeyProvider.notifier).state = 'work';
    await settle(tester);
    expect(find.text('1 Raffles Place → Work'), findsOneWidget);
    expect(find.text(s.alreadyThere), findsOneWidget);
    expect(find.textContaining('0 min'), findsNothing);
    expect(find.byType(BusBoard), findsNothing);
    expect(find.text(s.imLeaving), findsNothing);

    // A trip being timed still shows on the page, with Arrived.
    await box.read(habitsProvider.notifier).startTrip('home>work', tuesdayMorning);
    await settle(tester);
    expect(find.byType(TripBanner), findsOneWidget);
    expect(find.text(s.alreadyThere), findsOneWidget);
  });

  testWidgets('Bus board at 100% text on 360 dp: details stay beside the number', (tester) async {
    const phone = Condition('phone', size: Size(360, 780));
    await applyCondition(tester, phone);
    const note = '43 stops · 19.5 km · get off at OUE Bayfront';
    // Inside the page and card paddings, as in Nearby and the planner (about 267 dp wide).
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: BusBoard(arrLabel: 'Arr', minLabel: 'min', thenLabel: (m) => 'then $m min', rows: [
            BoardRow(service: '10', minutes: 2, info: 'Seats free', note: note, onTap: () {}),
          ]),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.getTopLeft(find.text(note)).dx, greaterThan(tester.getTopRight(find.text('10')).dx));
  });

  testWidgets('Plan a trip: an old Here destination is dropped when the planner opens again', (tester) async {
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
    expect(find.text('Work → Current location'), findsOneWidget);
    nav.pop();
    await settle(tester);

    nav.push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    // Here is wherever the phone is now: the old destination is gone and the trip starts Here.
    expect(box.read(goKeyProvider), isNull);
    expect(box.read(goFromKeyProvider), 'here');
    expect(find.text('Current location → Current location'), findsNothing);
    expect(find.text(const S().goSomewhereHint), findsOneWidget);
  });

  testWidgets('Plan a trip: picks made while the location is coming in are kept', (tester) async {
    await applyCondition(tester, _normal);
    final gps = Completer<void>();
    GeolocatorPlatform.instance = FakeGeolocator(LocationPermission.whileInUse, gate: gps);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    final nav = Navigator.of(tester.element(find.byType(TodayPage)));
    nav.push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    // The fix is slow: the user picks Work as the start and School as the destination first.
    await tester.tap(find.text('Work').first);
    await tester.tap(find.text('School').last);
    await settle(tester);
    gps.complete();
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'work');
    expect(box.read(goKeyProvider), 'school');
    expect(find.text('Work → School'), findsOneWidget);
    nav.pop();
    await settle(tester);
  });

  testWidgets('Plan a trip: a place shared in while the location is coming in stays the destination', (tester) async {
    await applyCondition(tester, _normal);
    final gps = Completer<void>();
    GeolocatorPlatform.instance = FakeGeolocator(LocationPermission.whileInUse, gate: gps);
    await tester.pumpWidget(_appWithOneMap(_OneMap()));
    await settle(tester);
    final box = containerOf(tester);
    // Left from an earlier visit: a trip back to Here.
    box.read(goKeyProvider.notifier).state = 'here';
    final shared = parseSharedPlace('Somerset Bencoolen\nSingapore 189630\nhttps://maps.app.goo.gl/AbC123')!;
    Navigator.of(tester.element(find.byType(TodayPage)))
        .push(MaterialPageRoute<void>(builder: (_) => TripPlannerPage(shared: shared)));
    await settle(tester);
    expect(box.read(goKeyProvider), 'adhoc');
    gps.complete();
    await settle(tester);
    expect(box.read(goKeyProvider), 'adhoc');
    expect(box.read(goAdhocDestProvider)!.postal, '189630');
    expect(box.read(goFromKeyProvider), 'here');
  });

  testWidgets('Plan a trip: Here on both ends never makes a trip to itself', (tester) async {
    const denied = Condition('denied', location: LocationPermission.deniedForever);
    await applyCondition(tester, denied);
    await tester.pumpWidget(appUnder(denied, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    // The start waits on Here; the location then comes for a Here destination.
    box.read(goFromKeyProvider.notifier).state = 'here';
    box.read(goKeyProvider.notifier).state = 'here';
    box.read(goFromHereProvider.notifier).state =
        Place(kind: PlaceKind.other, name: 'Current location', addrLat: tampinesInt.lat, addrLng: tampinesInt.lng);
    await settle(tester);
    expect(find.text('Current location → Current location'), findsNothing);
    expect(find.text('Home → Current location'), findsOneWidget);
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

  testWidgets('Bus board at 200% text on 320 dp: words move down whole, never break inside', (tester) async {
    const big = Condition('big', textScale: 2.0, size: Size(320, 780));
    await applyCondition(tester, big);
    // The app's fonts, so words have their real widths (the test font draws every letter 1 em wide).
    await tester.runAsync(() async {
      for (final (family, files) in [
        ('PlusJakartaSans', ['assets/fonts/PlusJakartaSans-Variable.ttf']),
        ('BarlowCondensed', ['assets/fonts/BarlowCondensed-SemiBold.ttf', 'assets/fonts/BarlowCondensed-Bold.ttf']),
      ]) {
        final loader = FontLoader(family);
        for (final f in files) {
          loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
        }
        await loader.load();
      }
    });
    const info = 'Seats free · ♿ Wheelchair · Double deck';
    const note = '43 stops · 19.5 km · get off at OUE Bayfront';
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: BusBoard(arrLabel: 'Arr', minLabel: 'min', thenLabel: (m) => 'then $m min', rows: [
            BoardRow(service: '10', minutes: 2, next: 11, load: 'SEA', info: info, note: note, onTap: () {}),
          ]),
        ),
      ),
    ));
    await tester.pump();
    final scaler = MediaQuery.textScalerOf(tester.element(find.byType(BusBoard)));
    // Every word of the details fits on a line of its text box.
    for (final (text, finder) in [
      (info, find.textContaining('Wheelchair', findRichText: true)),
      (note, find.text(note)),
    ]) {
      final para = tester.renderObject<RenderParagraph>(finder);
      final style = para.text.style;
      for (final word in text.split(' ')) {
        final tp = TextPainter(text: TextSpan(text: word, style: style), textDirection: TextDirection.ltr, textScaler: scaler)
          ..layout();
        expect(tp.width, lessThanOrEqualTo(para.size.width), reason: '"$word" is wider than its line');
      }
    }
    // The details sit under the number at full width.
    expect(tester.getTopLeft(find.text(note)).dx, closeTo(tester.getTopLeft(find.text('10')).dx, 2));
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

  testWidgets('Plan a trip from the current location: History says where it started', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    // A trip logged by an older version, from "Here".
    await box.read(habitsProvider.notifier).restore(Habits(trips: [
      TripLog(route: 'Here>Masjid Sultan', start: tuesdayMorning.subtract(const Duration(hours: 1)), minutes: 11),
    ]));
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    // The phone is at Tampines Int (the fake location), beside Tampines station.
    expect(box.read(goFromKeyProvider), 'here');
    await tester.tap(find.text('Work').at(1));
    await settle(tester);
    expect(find.text('Current location → Work'), findsOneWidget);
    await _scrollTo(tester, find.text(s.imLeaving), page: TripPlannerPage);
    await tester.tap(find.text(s.imLeaving));
    await settle(tester);
    expect(box.read(habitsProvider).tripRoute, 'Near Tampines station>work');
    expect(find.text('Near Tampines station → Work'), findsOneWidget);

    Navigator.of(tester.element(find.byType(TripPlannerPage))).pop();
    await settle(tester);
    box.read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);
    final history = find.byType(HistoryPage);
    await _scrollTo(tester, find.text('Current location → Masjid Sultan'), page: HistoryPage);
    expect(find.descendant(of: history, matching: find.text('Here → Masjid Sultan')), findsNothing);
  });

  testWidgets("Plan a trip from the current location: I'm on the train logs it under the same name", (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    const s = S();
    Navigator.of(tester.element(find.byType(TodayPage))).push(MaterialPageRoute<void>(builder: (_) => const TripPlannerPage()));
    await settle(tester);
    expect(box.read(goFromKeyProvider), 'here');
    await tester.tap(find.text('Work').at(1));
    await settle(tester);
    await _scrollTo(tester, find.text(s.imOnTrain), page: TripPlannerPage);
    await tester.tap(find.text(s.imOnTrain));
    await settle(tester);
    expect(box.read(habitsProvider).tripRoute, 'Near Tampines station>work');
    // A line picked for a trip from here before the chip was renamed is still found.
    final here = box.read(goFromHereProvider)!;
    expect(mrtRouteKey(s, here, householdFavorites.places[PlaceKind.work]!), 'Here>work');
  });

  testWidgets('A History total shrinks a long figure instead of cutting it off', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 158,
            child: BentoTile(icon: Icons.local_parking, value: '100 parkings', caption: '3 h', fitValue: true),
          ),
        ),
      ),
    ));
    final text = find.text('100 parkings');
    expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse);
    expect(tester.getRect(text).right, lessThanOrEqualTo(158));
  });

  test('History totals go to one column sooner than the tiles of More', () {
    expect(tileColumns(328, 1.0, 150), 2);
    expect(tileColumns(328, 1.3, 150), 1);
    expect(tileColumns(288, 1.0, 150), 1);
  });

  testWidgets('History: the totals are the filter, four tiles of one size that keep their figures', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    await box.read(habitsProvider.notifier).restore(Habits(
      trips: [TripLog(route: 'home>work', start: tuesdayMorning.subtract(const Duration(hours: 2)), minutes: 40, mode: 'transit', km: 12)],
      meals: [
        MealLog(hawkerId: 'h1', at: tuesdayMorning.subtract(const Duration(hours: 1)), priceCents: 4390),
        MealLog(hawkerId: 'h2', at: tuesdayMorning.subtract(const Duration(hours: 3)), name: 'No Price Kitchen'),
      ],
    ));
    box.read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);
    final page = find.byType(HistoryPage);
    expect(find.descendant(of: page, matching: find.byType(PillRow)), findsNothing);
    expect(find.descendant(of: page, matching: find.byType(BentoTile)), findsNothing);

    Finder tile(String name) =>
        find.ancestor(of: find.descendant(of: page, matching: find.text(name)), matching: find.byType(InkWell)).first;
    final names = [_s.historyAll, _s.historyTrips, _s.historyParking, _s.historyMeals];
    final rects = [for (final n in names) tester.getRect(tile(n))];
    expect({for (final r in rects) r.width.round()}, hasLength(1), reason: '$rects');
    expect({for (final r in rects) r.top.round()}, hasLength(1), reason: 'one row on a phone');
    expect({for (final r in rects) r.height.round()}, hasLength(1));
    expect(rects.first.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    // The period is one rail, and its last choice says what it is.
    expect(find.text(_s.historyPeriod('all')), findsOneWidget);
    expect(_s.historyPeriod('all'), 'All time');

    // Picking Meals filters the list; the tiles keep counting the whole week.
    expect(find.descendant(of: tile(_s.historyTrips), matching: find.text('1')), findsOneWidget);
    await tester.tap(tile(_s.historyMeals));
    await settle(tester);
    expect(box.read(historyKindProvider), HistoryKind.meal);
    expect(find.descendant(of: tile(_s.historyTrips), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: tile(_s.historyMeals), matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: page, matching: find.text('Home → Work')), findsNothing);

    // A meal with no price offers to add one where the figure would be; the priced one shows it.
    final rows = tester.widgetList<PlaceRow>(find.descendant(of: page, matching: find.byType(PlaceRow))).toList();
    expect(rows, hasLength(2));
    final unpriced = rows.firstWhere((r) => r.title == 'No Price Kitchen');
    expect((unpriced.figure, unpriced.action), (null, _s.historyAddPrice));
    expect(rows.firstWhere((r) => r.title != 'No Price Kitchen').figure, _s.money(4390));
    expect(find.text(_s.historySwipeHint), findsOneWidget);

    await tester.tap(tile(_s.historyAll));
    await settle(tester);
    expect(box.read(historyKindProvider), isNull);
    // An estimated fare says so in a word.
    final trip = tester.widget<PlaceRow>(find.descendant(of: page, matching: find.widgetWithText(PlaceRow, 'Home → Work')));
    expect(trip.figureLabel, _s.historyEstimate);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('History at ${(scale * 100).round()}% text: a large cost and the names stay on one line', (tester) async {
      final c = Condition('h', textScale: scale, size: scale > 1 ? const Size(320, 780) : const Size(360, 780));
      await applyCondition(tester, c);
      await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
      await settle(tester);
      final box = containerOf(tester);
      await box.read(habitsProvider.notifier).restore(Habits(
        parkings: [ParkLog(name: 'Mall', start: tuesdayMorning.subtract(const Duration(hours: 3)), minutes: 300, costCents: 12345)],
      ));
      box.read(shellTabProvider.notifier).state = _tabs['History']!;
      await settle(tester);
      final page = find.byType(HistoryPage);

      // No taller than one line of its own style: not broken between digits or letters.
      void oneLine(Finder text, String what) {
        final w = tester.widget<Text>(text);
        final style = w.style!;
        final scaler = MediaQuery.textScalerOf(tester.element(text));
        final line = scaler.scale(style.fontSize!) * (style.height ?? 1.5);
        expect(tester.getSize(text).height, lessThanOrEqualTo(line + 1), reason: '$what at $scale');
      }

      for (final p in ['week', 'month', 'all']) {
        oneLine(find.descendant(of: page, matching: find.text(_s.historyPeriod(p))), _s.historyPeriod(p));
        // A name is never wider than its third of the rail, also when it is the picked one.
        box.read(historyPeriodProvider.notifier).state = HistoryPeriod.values.byName(p);
        await settle(tester);
        final name = find.descendant(of: page, matching: find.text(_s.historyPeriod(p)));
        final segment = find.ancestor(of: name, matching: find.byType(InkWell)).first;
        // Measured as drawn (its own style and the text setting), not as laid out: a name laid
        // out too wide is clipped to its box and would still "fit".
        final painter = TextPainter(
          text: TextSpan(text: _s.historyPeriod(p), style: tester.widget<Text>(name).style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(tester.element(name)),
        )..layout();
        expect(painter.width, lessThanOrEqualTo(tester.getSize(segment).width - 12), reason: '$p at $scale');
        painter.dispose();
      }
      for (final name in [_s.historyAll, _s.historyTrips, _s.historyParking, _s.historyMeals]) {
        oneLine(find.descendant(of: page, matching: find.text(name)), name);
      }
      final row = find.descendant(of: page, matching: find.byType(PlaceRow));
      await _scrollTo(tester, row, page: HistoryPage);
      oneLine(find.descendant(of: row, matching: find.text(_s.money(12345))), 'the cost');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('History with nothing logged: the note, and no tiles of zeros', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    containerOf(tester).read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);
    final page = find.byType(HistoryPage);
    expect(find.text(_s.historyEmpty), findsOneWidget);
    expect(find.descendant(of: page, matching: find.text(_s.historyTrips)), findsNothing);
    expect(find.descendant(of: page, matching: find.text(_s.historyCostNote)), findsNothing);
    expect(find.text(_s.historyPeriod('week')), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('Today readings: only Air looks tappable and opens its sheet; UV and heat are a flat strip',
      (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(_appWithReadings(tuesdayMorning));
    await settle(tester);

    const s = S();
    final air = find.textContaining(s.airLabel);
    expect(air, findsOneWidget);
    // The reading that opens something is a raised card with a chevron and a tap.
    final airCard = find.ancestor(of: air, matching: find.byType(Panel));
    expect(airCard, findsOneWidget);
    expect(find.descendant(of: airCard, matching: find.byIcon(Icons.chevron_right)), findsOneWidget);
    // The others open nothing, so they are no card and take no tap.
    for (final caption in ['${s.uvLabel} · ', '${s.heatLabel} · ']) {
      final reading = find.textContaining(caption);
      expect(reading, findsOneWidget, reason: caption);
      expect(find.ancestor(of: reading, matching: find.byType(Panel)), findsNothing, reason: caption);
      expect(find.ancestor(of: reading, matching: find.byType(InkWell)), findsNothing, reason: caption);
    }
    // Side by side on a phone at normal text.
    expect(tester.getTopLeft(find.textContaining('${s.uvLabel} · ')).dy,
        closeTo(tester.getTopLeft(find.textContaining('${s.heatLabel} · ')).dy, 8));

    await tester.ensureVisible(air);
    await tester.tap(air);
    await settle(tester);
    expect(find.text(s.moreAtHaze), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today says rain once, in the weather card: forecast, rain now and the tip for the mode', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(_appWithReadings(tuesdayMorning));
    await settle(tester);

    const s = S();
    final card = find.ancestor(of: find.text(s.bringUmbrella), matching: find.byType(Panel));
    expect(card, findsOneWidget);
    // What the gauge reads now is a line of that card, not a reading of its own.
    expect(find.descendant(of: card, matching: find.text(s.rainingNow(0.4))), findsOneWidget);
    // No banner repeats the forecast.
    expect(find.textContaining('Rain expected near'), findsNothing);
    // Bus/MRT has no rain tip; Car has one, in the card and not as a banner in the trip.
    expect(find.text(s.rainTip(TripAdvice.rainDrive)!), findsNothing);
    await tester.scrollUntilVisible(find.byType(ModeRail), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byTooltip('Car'));
    await settle(tester);
    expect(find.text(s.tripAdvice(TripAdvice.rainDrive)), findsNothing);
    await tester.scrollUntilVisible(find.text(s.bringUmbrella), -200, scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: card, matching: find.text(s.rainTip(TripAdvice.rainDrive)!)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today still says it is raining, with the tip, when the forecast cannot be read', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(ProviderScope(retry: noRetry,
      overrides: [
        initialFavoritesProvider.overrideWithValue(householdFavorites),
        apiProvider.overrideWithValue(_NoForecastApi()),
        bundleRepoProvider.overrideWithValue(FileBundles()),
        clockProvider.overrideWith((ref) => Stream.value(tuesdayMorning)),
      ],
      child: const DailyLahApp(),
    ));
    await settle(tester);

    const s = S();
    expect(find.text(s.bringUmbrella), findsNothing);
    expect(find.text(s.rainingNow(0.4)), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(ModeRail), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byTooltip('Car'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text(s.rainingNow(0.4)), -200, scrollable: find.byType(Scrollable).first);
    expect(find.text(s.rainTip(TripAdvice.rainDrive)!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today readings at 200% text on 320 dp: the strip stacks and nothing overflows', (tester) async {
    await applyCondition(tester, const Condition('large text, small phone', textScale: 2.0, size: Size(320, 640)));
    await tester.pumpWidget(_appWithReadings(tuesdayMorning));
    await settle(tester);

    const s = S();
    final uv = find.textContaining('${s.uvLabel} · ');
    final heat = find.textContaining('${s.heatLabel} · ');
    await tester.scrollUntilVisible(heat, 200, scrollable: find.byType(Scrollable).first);
    expect(uv, findsOneWidget);
    expect(tester.getTopLeft(heat).dy, greaterThan(tester.getBottomLeft(uv).dy - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Trip modes are one row: a tap or a drag of the thumb picks, and the heading names the pick',
      (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);

    ModeRail rail() => tester.widget<ModeRail>(find.byType(ModeRail));
    const s = S();
    await tester.scrollUntilVisible(find.byType(ModeRail), 200, scrollable: find.byType(Scrollable).first);
    final keys = [for (final m in rail().items) m.$1];
    expect(keys.first, 'walk');
    // Every mode but Bus/MRT shows a rough time; names are tooltips, the pick is named in the heading.
    for (final m in rail().items) {
      expect(m.$4 == null, m.$1 == 'transit', reason: m.$1);
      expect(find.byTooltip(m.$3), findsOneWidget);
    }
    expect(find.text(s.tripBy(s.modeLabel(rail().selected))), findsOneWidget);

    await tester.tap(find.byTooltip('Car'));
    await settle(tester);
    expect(rail().selected, 'car');
    expect(find.text(s.tripBy('Car')), findsOneWidget);

    // Drag the thumb from Car to the mode on its left.
    await tester.scrollUntilVisible(find.byType(ModeRail), -200, scrollable: find.byType(Scrollable).first);
    final car = keys.indexOf('car');
    final from = tester.getCenter(find.byTooltip('Car'));
    final to = tester.getCenter(find.byTooltip(s.modeLabel(keys[car - 1])));
    await tester.dragFrom(from, to - from);
    await settle(tester);
    expect(rail().selected, keys[car - 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Trip modes at 200% text on 320 dp are named tiles that still pick', (tester) async {
    const c = Condition('large text, small phone', textScale: 2.0, size: Size(320, 640));
    await applyCondition(tester, c);
    await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
    await settle(tester);

    final taxi = find.descendant(of: find.byType(ModeRail), matching: find.text('Taxi'));
    await tester.scrollUntilVisible(taxi, 200, scrollable: find.byType(Scrollable).first);
    expect(find.byTooltip('Taxi'), findsNothing);
    // Clear of the tab bar at the bottom.
    await Scrollable.ensureVisible(tester.element(taxi), alignment: 0.5);
    await settle(tester);
    await tester.tap(taxi);
    await settle(tester);
    expect(tester.widget<ModeRail>(find.byType(ModeRail)).selected, 'taxi');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nearby: the place button opens the list of places, tiles switch the section, a car park opens its sheet',
      (tester) async {
    const denied = Condition('denied', location: LocationPermission.deniedForever);
    await applyCondition(tester, denied);
    await tester.pumpWidget(appUnder(denied, householdFavorites, tuesdayMorning));
    await settle(tester);
    containerOf(tester).read(shellTabProvider.notifier).state = _tabs['Nearby']!;
    await settle(tester);

    // No place yet: the button asks for one and opens the list. Home has its own tab.
    await tester.tap(find.text(_s.nearbyChoosePlace));
    await settle(tester);
    expect(find.text(_s.nearbyWhere), findsOneWidget);
    for (final name in [_s.hereNow, 'Work', 'School', 'Gym', _s.nearbySearchPlace]) {
      expect(find.widgetWithText(ListTile, name), findsOneWidget, reason: name);
    }
    expect(find.widgetWithText(ListTile, 'Home'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Gym'));
    await settle(tester);

    // The place is said once, on the button; the sections are tiles, not pills.
    expect(find.text('Gym · TAMPINES HUB'), findsOneWidget);
    expect(find.text('TAMPINES HUB'), findsNothing);
    final page = find.byType(NearbyPage);
    expect(find.descendant(of: page, matching: find.byType(PillRow)), findsNothing);
    final tiles = tester.widget<SectionTiles>(find.descendant(of: page, matching: find.byType(SectionTiles)));
    expect(tiles.selected, 'bus');
    // The hint about tapping a bus is said once for the three boards.
    expect(find.text(_s.tapBusHint), findsOneWidget);

    await tester.tap(find.text('Parking'));
    await settle(tester);
    expect(find.text(_s.parkNearby), findsOneWidget);
    // A car park row opens that car park's sheet, not the whole list.
    final row = find.byWidgetPredicate((w) => w is PlaceRow && w.icon == Icons.local_parking).first;
    await tester.ensureVisible(row);
    await tester.pump();
    final address = tester.widget<PlaceRow>(row).title;
    await tester.tap(row);
    await settle(tester);
    expect(find.text(_s.saveCarpark), findsOneWidget);
    expect(find.text(address), findsNWidgets(2));
    expect(find.byType(AppBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Section tiles: four a row, fewer when the longest name would not fit, the last one fills its row',
      (tester) async {
    expect(SectionTiles.columns(380, 52), 4);
    expect(SectionTiles.columns(288, 52), 4);
    expect(SectionTiles.columns(288, 104), 2);
    expect(SectionTiles.columns(120, 200), 1);

    // Seven sections (Prayer off): Help takes the two columns left in the second row.
    const keys = ['bus', 'eat', 'green', 'park', 'taxi', 'toilet', 'help'];
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 380,
            child: SectionTiles(
              items: [for (final k in keys) (k, Icons.circle_outlined, k)],
              selected: 'bus',
              danger: const {'help'},
              onTap: (k) => tapped = k,
            ),
          ),
        ),
      ),
    ));
    final bus = tester.getSize(find.ancestor(of: find.text('bus'), matching: find.byType(InkWell)));
    final help = tester.getSize(find.ancestor(of: find.text('help'), matching: find.byType(InkWell)));
    expect(help.width, greaterThan(bus.width * 2 - 1));
    expect(bus.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    expect(tester.getTopLeft(find.text('taxi')).dy, greaterThan(tester.getTopLeft(find.text('park')).dy));
    await tester.tap(find.text('help'));
    expect(tapped, 'help');
  });

  testWidgets('Home: eight section tiles, Safety has the calls and the meeting points, My home links to the rest',
      (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['Home']!;
    await settle(tester);
    final page = find.byType(HomePage);

    // Tiles, not pills: two rows of four on a phone.
    expect(find.descendant(of: page, matching: find.byType(PillRow)), findsNothing);
    final tiles = tester.widget<SectionTiles>(find.descendant(of: page, matching: find.byType(SectionTiles)));
    expect([for (final (k, _, _) in tiles.items) k], HomePage.sections);
    expect(HomePage.sections, hasLength(8));
    // "Community" is a little wider than a quarter of the row: it is drawn smaller, not on a row of three.
    expect(SectionTiles.columns(380, 80), 4);
    expect(SectionTiles.columns(380, 120), 3);

    // The block's facts lie flat; the price card says where it goes and opens the block page.
    for (final label in [_s.factBuilt, _s.factLease, _s.factStoreys]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text(_s.watchingBlock), findsOneWidget);
    await tester.tap(find.text(_s.watchStop));
    await settle(tester);
    expect(box.read(favoritesProvider).watchedBlocks, isEmpty);
    expect(find.text(_s.watchStart), findsOneWidget);

    // Around your home: a row opens its section...
    final school = find.widgetWithText(PlaceRow, _s.nearestPrimary);
    await tester.ensureVisible(school);
    await tester.pump();
    expect(tester.widget<PlaceRow>(school).figure, isNotNull);
    await tester.tap(school);
    await settle(tester);
    expect(box.read(homeSectionProvider), 'schools');

    // ...or a page of its own, for what is no longer a section.
    box.read(homeSectionProvider.notifier).state = 'home';
    await settle(tester);
    for (final topic in HomePage.topics) {
      final row = find.widgetWithText(PlaceRow, _s.homeTopic(topic));
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await settle(tester);
      expect(find.widgetWithText(AppBar, _s.homeTopic(topic)), findsOneWidget, reason: topic);
      await tester.pageBack();
      await settle(tester);
    }

    // Safety: the calls first (999 in amber, as on Nearby), then the meeting points further down.
    await tester.ensureVisible(find.text('Safety'));
    await tester.pump();
    await tester.tap(find.text('Safety'));
    await settle(tester);
    expect(box.read(homeSectionProvider), 'safety');
    expect(find.text(_s.call995), findsOneWidget);
    final police = tester.widget<Panel>(find.ancestor(of: find.text(_s.call999), matching: find.byType(Panel)).first);
    expect(police.color, DL.amber);
    await tester.scrollUntilVisible(find.text(_s.meetingPoints), 300, scrollable: find.byType(Scrollable).hitTestable().first);
    expect(find.text(_s.meetingPoints), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home lists: a row shows its distance large, no web address and no call button; nor does the ActiveSG sheet',
      (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['Home']!;
    box.read(homeSectionProvider.notifier).state = 'weekend';
    await settle(tester);
    await scrollThrough(tester);
    final page = find.byType(HomePage);
    final rows = tester.widgetList<PlaceRow>(find.descendant(of: page, matching: find.byType(PlaceRow), skipOffstage: false));
    expect(rows, isNotEmpty);
    for (final r in rows) {
      expect(r.subtitle ?? '', isNot(contains('http')), reason: r.title);
      expect(r.figure, isNotNull, reason: r.title);
    }
    expect(find.descendant(of: page, matching: find.byIcon(Icons.call_outlined), skipOffstage: false), findsNothing);

    // The ActiveSG sheet has the booking button, so it does not print the site's address either.
    final sport = find.descendant(of: page, matching: find.byWidgetPredicate((w) => w is PlaceRow && w.icon == Icons.sports_tennis_outlined)).first;
    // Opened through the row's own action: after the scroll the row may sit under the tab bar.
    tester.widget<PlaceRow>(sport).onTap();
    await settle(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text(_s.bookOnActiveSg, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('http', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A list row for an e-waste point whose details hold a link shows no web address', (tester) async {
    await applyCondition(tester, _normal);
    // Every e-waste point in the bundle is checked through the rule the rows use.
    final around = AroundSet.fromBundle(jsonDecode(File('../web/data/around.json').readAsStringSync()) as Map<String, dynamic>);
    final linked = [for (final p in around.of('ewaste')) if (p.detail.contains('http')) p];
    expect(linked, isNotEmpty, reason: 'the bundle no longer has a linked e-waste point: pick another case');
    for (final p in linked) {
      expect(withoutWebAddress(p.detail), isNot(contains('http')), reason: p.name);
    }
    // And in a row: the list shows the details without the link, with the distance large.
    final p = linked.first;
    await tester.pumpWidget(pageUnder(
      _normal,
      householdFavorites,
      tuesdayMorning,
      Scaffold(
        body: ListView(children: [
          NearGroup(title: 'E-waste drop-off', icon: Icons.recycling, items: [
            NearItem(name: p.name, detail: p.detail, lat: p.lat, lng: p.lng, distance: 120),
          ]),
        ]),
      ),
    ));
    await settle(tester);
    final row = tester.widget<PlaceRow>(find.byType(PlaceRow));
    expect(p.detail, contains('http'));
    expect(row.subtitle, withoutWebAddress(p.detail));
    expect(row.subtitle, isNot(contains('http')));
    expect((row.figure, row.figureLabel), ('120', 'm'));
    expect(find.textContaining('http'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More: switches lie flat and link tiles are raised; lunch is a tile with its time beside it', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    box.read(shellTabProvider.notifier).state = _tabs['More']!;
    await settle(tester);
    final page = find.byType(MorePage);
    await scrollThrough(tester);

    // Every tile: a shadow only when it opens something (no value), never on a switch.
    final tiles = find.descendant(of: page, matching: find.byType(SettingTile), skipOffstage: false);
    expect(tiles, findsWidgets);
    for (final e in tiles.evaluate()) {
      final tile = e.widget as SettingTile;
      final box = tester.widget<AnimatedContainer>(
          find.descendant(of: find.byWidget(tile, skipOffstage: false), matching: find.byType(AnimatedContainer), skipOffstage: false));
      final shadow = (box.decoration! as BoxDecoration).boxShadow ?? const [];
      expect(shadow.isNotEmpty, tile.value == null, reason: tile.title);
    }
    // No sliding switch and no Delete link on More.
    expect(find.descendant(of: page, matching: find.byType(Switch), skipOffstage: false), findsNothing);
    expect(find.descendant(of: page, matching: find.text(_s.deleteHistory), skipOffstage: false), findsNothing);

    // Lunch: a switch tile; its time appears as a link tile only while it is on.
    Finder titled(String t) => find.descendant(of: page, matching: find.widgetWithText(SettingTile, t), skipOffstage: false);
    expect(tester.widget<SettingTile>(titled(_s.alertLunch)).value, isFalse);
    expect(titled(_s.lunchTimeAt('12.00')), findsNothing);
    box.read(favoritesProvider.notifier).update((f) => f.copyWith(lunchAlerts: true));
    await settle(tester);
    expect(tester.widget<SettingTile>(titled(_s.alertLunch)).value, isTrue);
    expect(tester.widget<SettingTile>(titled(_s.lunchTimeAt('12.00'))).value, isNull);
    // Opened through the tile's own action: after the scroll it may sit under the tab bar.
    tester.widget<SettingTile>(titled(_s.lunchTimeAt('12.00'))).onTap();
    await settle(tester);
    expect(find.text(_s.lunchTimeHelp), findsWidgets);
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('History: Delete all my history asks first, then clears every period and the parked car', (tester) async {
    await applyCondition(tester, _normal);
    await tester.pumpWidget(appUnder(_normal, householdFavorites, tuesdayMorning));
    await settle(tester);
    final box = containerOf(tester);
    // Only an old trip: nothing this week, so the link must show without a list above it.
    await box.read(habitsProvider.notifier).restore(Habits(
      trips: [TripLog(route: 'home>work', start: tuesdayMorning.subtract(const Duration(days: 60)), minutes: 40, mode: 'transit', km: 12)],
    ));
    box.read(shellTabProvider.notifier).state = _tabs['History']!;
    await settle(tester);
    final link = find.descendant(of: find.byType(HistoryPage), matching: find.text(_s.deleteHistory));
    await _scrollTo(tester, link, page: HistoryPage);
    expect(find.text(_s.historyEmpty), findsOneWidget);

    // Cancel keeps everything.
    await tester.tap(link);
    await settle(tester);
    expect(find.text(_s.deleteHistoryAsk), findsOneWidget);
    await tester.tap(find.text(_s.cancel));
    await settle(tester);
    expect(box.read(habitsProvider).trips, hasLength(1));

    await tester.tap(link);
    await settle(tester);
    await tester.tap(find.text(_s.delete));
    await settle(tester);
    expect(box.read(habitsProvider).trips, isEmpty);
    expect(find.descendant(of: find.byType(HistoryPage), matching: find.text(_s.deleteHistory)), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
