import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:flutter_test/flutter_test.dart';

const tampines = BusStop(code: '75009', name: 'Tampines Int', road: 'Tampines Ctrl 1', lat: 1.354, lng: 103.943);
const raffles = BusStop(code: '03011', name: 'Raffles Pl', road: 'Collyer Quay', lat: 1.284, lng: 103.851);

Map<String, dynamic> forecastBody() => {
      'fetched_at': 0,
      'data': {
        'code': 0,
        'data': {
          'area_metadata': [
            {'name': 'Tampines', 'label_location': {'latitude': 1.345, 'longitude': 103.944}},
            {'name': 'City', 'label_location': {'latitude': 1.292, 'longitude': 103.844}},
          ],
          'items': [
            {
              'valid_period': {'text': '10 to 12 PM'},
              'forecasts': [
                {'area': 'Tampines', 'forecast': 'Thundery Showers'},
                {'area': 'City', 'forecast': 'Partly Cloudy (Night)'},
              ],
            },
          ],
        },
      },
    };

void main() {
  test('forecastNear picks the closest area and detects rain', () {
    final t = forecastNear(forecastBody(), tampines.lat, tampines.lng)!;
    expect(t.area, 'Tampines');
    expect(t.isRainy, isTrue);
    expect(t.validText, '10 to 12 PM');
    final c = forecastNear(forecastBody(), raffles.lat, raffles.lng)!;
    expect(c.area, 'City');
    expect(c.isRainy, isFalse);
  });

  test('forecastNear tolerates missing data', () {
    expect(forecastNear({'data': null}, 1.3, 103.8), isNull);
    expect(forecastNear({'data': {'data': {'area_metadata': [], 'items': []}}}, 1.3, 103.8), isNull);
  });

  test('parseBusArrival returns next buses sorted with load', () {
    final now = DateTime.parse('2026-10-19T22:00:00+08:00');
    final body = {
      'data': {
        'Services': [
          {
            'ServiceNo': '15',
            'NextBus': {'EstimatedArrival': '2026-10-19T22:07:30+08:00', 'Load': 'SDA'},
            'NextBus2': {'EstimatedArrival': '2026-10-19T22:15:00+08:00', 'Load': 'SEA'},
            'NextBus3': {'EstimatedArrival': '2026-10-19T22:25:00+08:00', 'Load': 'SEA'},
          },
          {
            'ServiceNo': '39',
            'NextBus': {'EstimatedArrival': '2026-10-19T21:59:50+08:00', 'Load': 'LSD'},
            'NextBus2': {'EstimatedArrival': '', 'Load': ''},
          },
        ],
      },
    };
    final etas = parseBusArrival(body, now);
    expect(etas.map((e) => '${e.service}:${e.minutes}'), ['39:0', '15:7', '15:15']);
    expect(loadLabel(etas.first.load), 'Penuh');
  });

  test('lineStatuses flags only affected chosen lines', () {
    final normal = {'data': {'value': {'Status': 1, 'AffectedSegments': [], 'Message': []}}};
    expect(lineStatuses(normal, {'NSL'}).single.disrupted, isFalse);

    final bad = {
      'data': {
        'value': {
          'Status': 2,
          'AffectedSegments': [
            {'Line': 'EWL', 'Stations': 'EW1,EW2', 'FreePublicBus': 'EW1,EW2', 'FreeMRTShuttle': ''},
          ],
          'Message': [{'Content': 'Train fault'}],
        },
      },
    };
    final s = lineStatuses(bad, {'NSL', 'EWL'});
    expect(s.map((x) => x.line), ['EWL', 'NSL']);
    expect(s.first.disrupted, isTrue);
    expect(s.first.detail, contains('Bus gratis'));
    expect(s.last.disrupted, isFalse);
  });

  test('highCrowdShare ignores NA', () {
    final body = {
      'data': {
        'value': [
          {'Station': 'NS1', 'CrowdLevel': 'h'},
          {'Station': 'NS2', 'CrowdLevel': 'l'},
          {'Station': 'NS3', 'CrowdLevel': 'NA'},
        ],
      },
    };
    expect(highCrowdShare(body), 0.5);
    expect(highCrowdShare({'data': {'value': []}}), isNull);
  });

  test('card, origin and alert windows', () {
    const fav = Favorites(places: {
      PlaceKind.home: Place(kind: PlaceKind.home, stops: [tampines]),
      PlaceKind.work: Place(kind: PlaceKind.work, stops: [raffles]),
    });
    final morning = DateTime(2026, 10, 20, 7, 0);
    final evening = DateTime(2026, 10, 20, 17, 30);
    expect(cardFor(morning), CardKind.morning);
    expect(cardFor(evening), CardKind.evening);
    expect(originFor(CardKind.morning, fav), PlaceKind.home);
    expect(originFor(CardKind.evening, fav), PlaceKind.work);
    expect(destinationFor(CardKind.morning, fav), PlaceKind.work);
    expect(inRainWindow(DateTime(2026, 10, 20, 6, 45), const TimeOfDayHM(7, 30)), isTrue);
    expect(inRainWindow(DateTime(2026, 10, 20, 6, 15), const TimeOfDayHM(7, 30)), isFalse);
    expect(isQuietHour(DateTime(2026, 10, 20, 23)), isTrue);
    expect(isQuietHour(DateTime(2026, 10, 20, 6)), isFalse);
  });

  test('search and nearest stops', () {
    const all = [tampines, raffles];
    expect(searchStops(all, 'raffles').single.code, '03011');
    expect(searchStops(all, '750').single.code, '75009');
    expect(searchStops(all, ' '), isEmpty);
    expect(nearestStops(all, 1.28, 103.85, limit: 1).single.code, '03011');
  });

  test('Favorites survive a JSON round trip', () {
    const fav = Favorites(
      places: {PlaceKind.home: Place(kind: PlaceKind.home, stops: [tampines])},
      lines: {'NSL', 'DTL'},
      leaveHome: TimeOfDayHM(8, 5),
      onboarded: true,
    );
    final back = Favorites.fromJson(fav.toJson());
    expect(back.places[PlaceKind.home]!.stops.single.code, '75009');
    expect(back.lines, {'NSL', 'DTL'});
    expect(back.leaveHome.format(), '08.05');
    expect(back.onboarded, isTrue);
    expect(Favorites.fromJson(const {}).isSetUp, isFalse);
  });
}
