import 'dart:async';
// Shared fakes and set-up for the regression tests (see docs/QA.md).
//
// Bundles are read from the committed copies in ../web/data, so screens render with
// real Singapore data. The API, location and storage are faked; nothing touches the network.
import 'dart:convert';
import 'dart:io';

import 'package:dailylah/api.dart';
import 'package:dailylah/data.dart';
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ------------------------------------------------------------------ fixtures

const tampinesInt = BusStop(code: '75009', name: 'Tampines Int', road: 'Tampines Ctrl 1', lat: 1.354076, lng: 103.943391);
const fullertonSq = BusStop(code: '03011', name: 'Fullerton Sq', road: 'Fullerton Rd', lat: 1.285618, lng: 103.853422);

/// A fully set-up household: HDB home in Tampines, office in Raffles Place, a school,
/// a custom place, starred lines, two compared blocks and one watched block.
const householdFavorites = Favorites(
  places: {
    PlaceKind.home: Place(
      kind: PlaceKind.home,
      stops: [tampinesInt],
      address: '156 TAMPINES ST 12',
      postal: '521156',
      addrLat: 1.35159,
      addrLng: 103.94503,
    ),
    PlaceKind.work: Place(
      kind: PlaceKind.work,
      stops: [fullertonSq],
      address: '1 RAFFLES PLACE',
      addrLat: 1.2841,
      addrLng: 103.8514,
      go: TimeOfDayHM(8, 0),
      back: TimeOfDayHM(18, 0),
    ),
    PlaceKind.school: Place(
      kind: PlaceKind.school,
      address: 'TAMPINES PRIMARY SCHOOL',
      addrLat: 1.3496,
      addrLng: 103.9433,
      go: TimeOfDayHM(7, 0),
      back: TimeOfDayHM(13, 30),
    ),
  },
  extraPlaces: [
    Place(kind: PlaceKind.other, name: 'Gym', address: 'TAMPINES HUB', addrLat: 1.3533, addrLng: 103.9402),
  ],
  lines: {'EWL', 'DTL'},
  onboarded: true,
  showPrayer: true,
  showHalal: true,
  evPlug: 'Type 2',
  compareBlocks: ['156|TAMPINES ST 12', '508|TAMPINES CTRL 1'],
  watchedBlocks: {'156|TAMPINES ST 12': 0},
);

/// A few days of logged trips, parking and meals for the History tab.
Habits sampleHabits(DateTime now) => Habits(
      trips: [
        TripLog(route: 'home>work', start: now.subtract(const Duration(days: 1, hours: 1)), minutes: 42, mode: 'transit', km: 18.2),
        TripLog(route: 'work>home', start: now.subtract(const Duration(hours: 13)), minutes: 55, rainy: true, costCents: 219),
        TripLog(route: 'home>school', start: now.subtract(const Duration(days: 9)), minutes: 18, mode: 'car'),
      ],
      parkings: [
        ParkLog(name: 'Tampines Mall Car Park With A Very Long Name', start: now.subtract(const Duration(days: 2)), minutes: 130, costCents: 360),
      ],
      meals: [MealLog(hawkerId: 'unknown-id', at: now.subtract(const Duration(hours: 20)))],
    );

/// Tuesday 07:00, Tuesday 19:00 and Saturday 10:00 (no commute: weekend card).
final tuesdayMorning = DateTime(2026, 10, 20, 7);
final tuesdayEvening = DateTime(2026, 10, 20, 19);
final saturdayMorning = DateTime(2026, 10, 24, 10);

// ------------------------------------------------------------------ fakes

/// Typical live answers: showers in Tampines, all lines normal, buses on the way.
class FakeApi extends DailyLahApi {
  FakeApi({this.disruptedLine});

  /// When set (e.g. 'EWL'), train alerts report a disruption on that line.
  final String? disruptedLine;

  @override
  Future<Map<String, dynamic>> forecast() async => {
        'fetched_at': 0,
        'data': {
          'data': {
            'area_metadata': [
              {'name': 'Tampines', 'label_location': {'latitude': 1.345, 'longitude': 103.944}},
              {'name': 'City', 'label_location': {'latitude': 1.292, 'longitude': 103.844}},
            ],
            'items': [
              {
                'valid_period': {'text': '7 to 9 AM'},
                'forecasts': [
                  {'area': 'Tampines', 'forecast': 'Thundery Showers'},
                  {'area': 'City', 'forecast': 'Partly Cloudy (Day)'},
                ],
              },
            ],
          },
        },
      };

  @override
  Future<Map<String, dynamic>> trainAlerts() async => disruptedLine == null
      ? {
          'data': {'value': {'Status': 1, 'AffectedSegments': [], 'Message': []}},
        }
      : {
          'data': {
            'value': {
              'Status': 2,
              'AffectedSegments': [
                {
                  'Line': disruptedLine,
                  'Direction': 'Pasir Ris',
                  'Stations': 'EW1,EW2,EW3',
                  'FreePublicBus': 'EW1,EW2,EW3',
                  'FreeMRTShuttle': 'EW1,EW3',
                  'MRTShuttleDirection': 'Both',
                },
              ],
              'Message': [
                {'Content': 'Train service delayed between Pasir Ris and Simei.', 'CreatedDate': '2026-10-20 06:50:00'},
              ],
            },
          },
        };

  @override
  Future<Map<String, dynamic>> busArrival(String stopCode) async {
    String at(int min) => DateTime(2026, 10, 20, 7, min).toIso8601String();
    return {
      'data': {
        'Services': [
          {
            'ServiceNo': '10',
            'NextBus': {'EstimatedArrival': at(3), 'Load': 'SEA', 'Feature': 'WAB', 'Type': 'DD'},
            'NextBus2': {'EstimatedArrival': at(12), 'Load': 'SDA', 'Feature': 'WAB', 'Type': 'DD'},
          },
          {
            'ServiceNo': '858A',
            'NextBus': {'EstimatedArrival': at(7), 'Load': 'LSD', 'Feature': '', 'Type': 'SD'},
          },
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> weather(String kind) async => {'fetched_at': 0, 'data': {}};

  @override
  Future<Map<String, dynamic>> carparks() async => {'data': {}};

  @override
  Future<Map<String, dynamic>> taxis() async => {
        'data': [
          [1.354, 103.943],
          [1.3541, 103.9431],
          [1.3525, 103.9450],
        ],
      };

  @override
  Future<Map<String, dynamic>> parking() async => {'data': []};

  @override
  Future<Map<String, dynamic>> trafficIncidents() async => {'data': []};

  /// Every point /v1/trip-extras was asked for, as (mode, lat, lng).
  final List<(String, double, double)> extrasAsked = [];

  /// Set to make /v1/trip-extras fail, or to answer with no places.
  bool extrasDown = false;
  bool extrasEmpty = false;

  @override
  Future<Map<String, dynamic>> tripExtras(String mode, double lat, double lng) async {
    extrasAsked.add((mode, lat, lng));
    if (extrasDown) throw StateError('LTA down');
    const at = 1793850000; // 5 Nov 2026 02:20 UTC
    return {
      'fetched_at': at,
      'data': switch (mode) {
        'taxi' => {'mode': mode, 'radius': 500, 'count': 12},
        'bicycle' => {
            'mode': mode,
            'radius': 500,
            'items': extrasEmpty
                ? const <Object>[]
                : [
                    {'name': 'SIGLAP SOUTH CC', 'type': 'Yellow Box', 'racks': 24, 'sheltered': true, 'la': lat, 'lo': lng, 'm': 40},
                    {'name': 'BLK 1 RACKS', 'type': 'Racks', 'racks': 1, 'sheltered': false, 'la': lat, 'lo': lng, 'm': 210},
                  ],
          },
        _ => {
            'mode': mode,
            'radius': 1000,
            'items': extrasEmpty
                ? const <Object>[]
                : [
                    {'id': 'A1', 'name': 'BLK 1 CAR PARK', 'agency': 'HDB', 'lots': mode == 'car' ? 102 : 1, 'm': 120, 'la': lat, 'lo': lng},
                    {'id': 'U2', 'name': 'EAST COAST RD', 'agency': 'URA', 'lots': 0, 'm': 480, 'la': lat, 'lo': lng},
                  ],
          },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> crowd(String line, {String kind = 'realtime'}) async => {'data': {}};

  @override
  Future<Map<String, dynamic>> agent(String regNo) async => {'data': {}};

  /// One EV location (id "EV1") at every postal code: Type 2, 1 of 2 chargers free.
  @override
  Future<Map<String, dynamic>> ev(String postal) async => {
        'fetched_at': 0,
        'data': [
          {
            'id': 'EV1',
            'n': 'Test car park',
            'pl': [
              {'t': 'Type 2', 'c': 'AC', 'kw': 7.4, 'p': 0.698, 'pu': 'kWh', 'n': 2, 'a': 1},
            ],
          },
        ],
      };
}

/// No network at all: every call fails the way dio fails without a connection.
class OfflineApi extends FakeApi {
  Never _down(String path) => throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        message: 'offline (test)',
      );

  @override
  Future<Map<String, dynamic>> forecast() async => _down('/v1/weather/forecast');
  @override
  Future<Map<String, dynamic>> trainAlerts() async => _down('/v1/train-alerts');
  @override
  Future<Map<String, dynamic>> busArrival(String stopCode) async => _down('/v1/bus-arrival');
  @override
  Future<Map<String, dynamic>> weather(String kind) async => _down('/v1/weather/$kind');
  @override
  Future<Map<String, dynamic>> carparks() async => _down('/v1/carpark');
  @override
  Future<Map<String, dynamic>> taxis() async => _down('/v1/taxi');
  @override
  Future<Map<String, dynamic>> parking() async => _down('/v1/parking');
  @override
  Future<Map<String, dynamic>> trafficIncidents() async => _down('/v1/traffic-incidents');
  @override
  Future<Map<String, dynamic>> tripExtras(String mode, double lat, double lng) async => _down('/v1/trip-extras');
  @override
  Future<Map<String, dynamic>> crowd(String line, {String kind = 'realtime'}) async => _down('/v1/crowd');
  @override
  Future<Map<String, dynamic>> agent(String regNo) async => _down('/v1/agent');
  @override
  Future<Map<String, dynamic>> ev(String postal) async => _down('/v1/ev');
}

/// Bundles from the committed web/data folder, parsed once per test run.
class FileBundles extends BundleRepository {
  static final _cache = <String, Object?>{};

  @override
  Future<Object?> load(String name) async => _cache.putIfAbsent(name, () {
        final f = File('../web/data/$name.json');
        return f.existsSync() ? jsonDecode(f.readAsStringSync()) : null;
      });
}

/// First install with no network: no bundle has ever been downloaded.
class NoBundles extends BundleRepository {
  @override
  Future<Object?> load(String name) async => null;
}

/// Location with a chosen permission answer. Granted = standing at Tampines Int.
class FakeGeolocator extends GeolocatorPlatform {
  FakeGeolocator(this.permission, {this.gate});
  final LocationPermission permission;

  /// When set, the current position comes only once the test completes it (a slow GPS fix).
  final Completer<void>? gate;

  Position get _here => Position.fromMap({
        'latitude': tampinesInt.lat,
        'longitude': tampinesInt.lng,
        'timestamp': DateTime(2026, 10, 20, 7).millisecondsSinceEpoch,
        'accuracy': 10.0,
      });

  bool get _ok => permission == LocationPermission.always || permission == LocationPermission.whileInUse;

  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async => permission;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async => _ok ? _here : null;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    if (!_ok) throw const PermissionDeniedException('denied (test)');
    if (gate case final g?) await g.future;
    return _here;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _ok ? Stream.value(_here) : Stream.error(const PermissionDeniedException('denied (test)'));
}

// ------------------------------------------------------------------ conditions

/// One row of the "special conditions" table in docs/QA.md, section 4.
class Condition {
  const Condition(
    this.name, {
    this.offline = false,
    this.cachedBundles = true,
    this.location = LocationPermission.whileInUse,
    this.textScale = 1.0,
    this.size = const Size(412, 915),
    this.dark = false,
  });

  final String name;
  final bool offline;
  final bool cachedBundles;
  final LocationPermission location;
  final double textScale;
  final Size size; // logical pixels
  final bool dark;
}

const conditions = [
  Condition('normal'),
  Condition('offline with cache', offline: true),
  Condition('offline first install', offline: true, cachedBundles: false),
  Condition('location denied forever', location: LocationPermission.deniedForever),
  Condition('text 200%', textScale: 2.0, size: Size(360, 780)),
  Condition('dark mode', dark: true),
  Condition('small screen 320dp', size: Size(320, 568)),
  Condition('text 200% on 320dp', textScale: 2.0, size: Size(320, 640)),
  // A Galaxy Z Fold opened flat and held on its side: wide and short.
  Condition('foldable landscape 880dp', size: Size(880, 600)),
];

/// Applies a condition to the test view and fakes. Call at the start of each test.
Future<void> applyCondition(WidgetTester tester, Condition c, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  GeolocatorPlatform.instance = FakeGeolocator(c.location);
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = c.size * 3;
  tester.platformDispatcher.textScaleFactorTestValue = c.textScale;
  tester.platformDispatcher.platformBrightnessTestValue = c.dark ? Brightness.dark : Brightness.light;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// Toilets for the tests ("Need a toilet?"), fixed so the tests do not change with the daily
/// `toilets` bundle: around Tampines Int, along bus 10 towards Changi General Hospital, and at Bedok.
const harnessToilets = [
  Toilet(name: 'Our Tampines Hub', lat: 1.35325, lng: 103.94060, kind: ToiletKind.mall),
  Toilet(name: 'Tampines Mall', lat: 1.35260, lng: 103.94480, kind: ToiletKind.mall),
  Toilet(name: 'Tampines Round Market', lat: 1.35350, lng: 103.94280, kind: ToiletKind.hawker),
  Toilet(name: 'Toilet, Simei Street 3', lat: 1.34020, lng: 103.94850),
  Toilet(name: 'Bedok Mall', lat: 1.32480, lng: 103.92920, kind: ToiletKind.mall),
];

List<Override> overridesFor(Condition c, Favorites fav, DateTime now, {String? disruptedLine}) => [
      toiletsProvider.overrideWith((ref) async => c.cachedBundles ? harnessToilets : const <Toilet>[]),
      initialFavoritesProvider.overrideWithValue(fav),
      apiProvider.overrideWithValue(c.offline ? OfflineApi() : FakeApi(disruptedLine: disruptedLine)),
      bundleRepoProvider.overrideWithValue(c.cachedBundles ? FileBundles() : NoBundles()),
      clockProvider.overrideWith((ref) => Stream.value(now)),
    ];

/// The whole app (setup or tabs, depending on [fav.onboarded]).
Widget appUnder(Condition c, Favorites fav, DateTime now, {String? disruptedLine}) => ProviderScope(retry: noRetry,
      overrides: overridesFor(c, fav, now, disruptedLine: disruptedLine),
      child: const DailyLahApp(),
    );

/// A single page, themed like the app.
Widget pageUnder(Condition c, Favorites fav, DateTime now, Widget page) => ProviderScope(retry: noRetry,
      overrides: overridesFor(c, fav, now),
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: page,
      ),
    );

/// Lets futures, bundle parsing and first animations finish without waiting for
/// repeating timers (live bus refresh, pulses) that would make pumpAndSettle time out.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// Scrolls the main list to the end so every widget below the fold is built and laid out.
Future<void> scrollThrough(WidgetTester tester, {int times = 8}) async {
  final lists = find.byType(Scrollable).hitTestable();
  if (lists.evaluate().isEmpty) return;
  for (var i = 0; i < times; i++) {
    await tester.drag(lists.first, const Offset(0, -600), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
}
