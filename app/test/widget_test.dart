import 'package:dailylah/api.dart';
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/about.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const home = BusStop(code: '75009', name: 'Tampines Int', road: 'Tampines Ctrl 1', lat: 1.354, lng: 103.943);

class FakeApi extends DailyLahApi {
  @override
  Future<Map<String, dynamic>> forecast() async => {
        'data': {
          'data': {
            'area_metadata': [
              {'name': 'Tampines', 'label_location': {'latitude': 1.345, 'longitude': 103.944}},
            ],
            'items': [
              {
                'forecasts': [
                  {'area': 'Tampines', 'forecast': 'Showers'},
                ],
              },
            ],
          },
        },
      };

  @override
  Future<Map<String, dynamic>> trainAlerts() async => {
        'data': {'value': {'Status': 1, 'AffectedSegments': [], 'Message': []}},
      };

  @override
  Future<Map<String, dynamic>> busArrival(String stopCode) async => {
        'data': {'Services': []},
      };

  @override
  Future<Map<String, dynamic>> weather(String kind) async => {'data': {}};

  @override
  Future<Map<String, dynamic>> carparks() async => {'data': {}};

  @override
  Future<Map<String, dynamic>> taxis() async => {
        'data': [
          [1.354, 103.943],
          [1.3541, 103.9431],
        ],
      };

  @override
  Future<Map<String, dynamic>> crowd(String line, {String kind = 'realtime'}) async => {'data': {}};
}

/// No static bundles in tests (no network, no app directory).
class FakeBundles extends BundleRepository {
  @override
  Future<Object?> load(String name) async => null;
}

Widget app(Favorites fav, DateTime now) => ProviderScope(
      overrides: [
        initialFavoritesProvider.overrideWithValue(fav),
        apiProvider.overrideWithValue(FakeApi()),
        bundleRepoProvider.overrideWithValue(FakeBundles()),
        clockProvider.overrideWith((ref) => Stream.value(now)),
      ],
      child: const DailyLahApp(),
    );

void main() {
  testWidgets('first run shows setup in the chosen language', (tester) async {
    await tester.pumpWidget(app(const Favorites(lang: 'id'), DateTime(2026, 10, 20, 7)));
    await tester.pumpAndSettle();
    expect(find.text('Selamat datang di DailyLah'), findsOneWidget);
    expect(find.text('Rumah'), findsOneWidget);
  });

  testWidgets('first run in English', (tester) async {
    await tester.pumpWidget(app(const Favorites(lang: 'en'), DateTime(2026, 10, 20, 7)));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to DailyLah'), findsOneWidget);
  });

  testWidgets('morning card shows rain, MRT status, bus stop and taxis', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const fav = Favorites(
      places: {PlaceKind.home: Place(kind: PlaceKind.home, stops: [home])},
      lines: {'NSL'},
      onboarded: true,
      lang: 'id',
    );
    await tester.pumpWidget(app(fav, DateTime(2026, 10, 20, 7)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kartu pagi'), findsOneWidget);
    expect(find.text('Selamat pagi'), findsOneWidget);
    expect(find.text('Bawa payung'), findsOneWidget);
    expect(find.text('Berjalan normal'), findsOneWidget);
    expect(find.text('Tampines Int · 75009'), findsOneWidget);
    expect(find.text('Taksi di sekitar'), findsOneWidget);
    // Bottom navigation with four tabs.
    expect(find.text('Sekitar'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);
  });

  testWidgets('tabs open Nearby, Homes and More', (tester) async {
    const fav = Favorites(
      places: {PlaceKind.home: Place(kind: PlaceKind.home, stops: [home])},
      onboarded: true,
      lang: 'en',
    );
    await tester.pumpWidget(app(fav, DateTime(2026, 10, 20, 19)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Homes'));
    await tester.pumpAndSettle();
    expect(find.text('HDB homes'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Share with family'), findsOneWidget);
  });

  testWidgets('about page shows legal links and data attribution', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [initialFavoritesProvider.overrideWithValue(const Favorites(lang: 'id'))],
      child: const MaterialApp(home: AboutDailyLahPage()),
    ));
    expect(find.text('Kebijakan privasi'), findsOneWidget);
    expect(find.text('Ketentuan layanan'), findsOneWidget);
    expect(find.textContaining('Singapore Open Data Licence'), findsWidgets);
    expect(find.textContaining('tidak berafiliasi'), findsOneWidget);
  });
}
