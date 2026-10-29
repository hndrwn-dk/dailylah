// Feature tests: one per user-facing feature, driving the real widgets the way a user
// would (tap, sheet, button) with the fakes in support/harness.dart. Every feature PR adds
// its test here (see CLAUDE.md, "Testing a feature").
import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/bus_sheet.dart';
import 'package:dailylah/ui/history.dart';
import 'package:dailylah/ui/theme.dart';
import 'package:dailylah/ui/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _normal = Condition('normal');
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
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialFavoritesProvider.overrideWithValue(householdFavorites),
        apiProvider.overrideWithValue(GpsApi((stop['la'] as num).toDouble(), (stop['lo'] as num).toDouble())),
        bundleRepoProvider.overrideWithValue(FileBundles()),
        clockProvider.overrideWith((ref) => Stream.value(tuesdayMorning)),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const StopArrivalsPage(stop: tampinesInt)),
    ));
    await settle(tester);

    expect(find.textContaining('Now near ${stop['n']} · 3 stops away', findRichText: true), findsOneWidget);
    expect(find.textContaining('Timetable estimate, no live GPS', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("Tapping a bus opens Where's my bus with the bus on its route", (tester) async {
    final route = ((_bundle('bus_routes') as Map)['10|2'] as List);
    final i = route.indexWhere((r) => (r as List).first == tampinesInt.code);
    final code = (route[i - 3] as List).first as String;
    final stop = (_bundle('bus_stops') as List).cast<Map>().firstWhere((s) => s['c'] == code);

    await applyCondition(tester, _normal);
    await tester.pumpWidget(ProviderScope(
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
    await tester.pumpWidget(ProviderScope(
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
}
