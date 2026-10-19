import 'package:dailylah/api.dart';
import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
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
}

Widget app(Favorites fav, DateTime now) => ProviderScope(
      overrides: [
        initialFavoritesProvider.overrideWithValue(fav),
        apiProvider.overrideWithValue(FakeApi()),
        clockProvider.overrideWith((ref) => Stream.value(now)),
      ],
      child: const DailyLahApp(),
    );

void main() {
  testWidgets('first run shows setup', (tester) async {
    await tester.pumpWidget(app(const Favorites(), DateTime(2026, 10, 20, 7)));
    expect(find.text('Selamat datang di DailyLah'), findsOneWidget);
    expect(find.text('Rumah'), findsOneWidget);
  });

  testWidgets('morning card shows rain, MRT status and bus stop', (tester) async {
    const fav = Favorites(
      places: {PlaceKind.home: Place(kind: PlaceKind.home, stops: [home])},
      lines: {'NSL'},
      onboarded: true,
    );
    await tester.pumpWidget(app(fav, DateTime(2026, 10, 20, 7)));
    await tester.pumpAndSettle();
    expect(find.text('Kartu pagi'), findsOneWidget);
    expect(find.text('Bawa payung'), findsOneWidget);
    expect(find.text('MRT normal'), findsOneWidget);
    expect(find.text('Tampines Int (75009)'), findsOneWidget);
  });
}
