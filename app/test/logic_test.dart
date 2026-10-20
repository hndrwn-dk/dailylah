import 'package:dailylah/data.dart';
import 'package:dailylah/l10n.dart';
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

  test('share code round trip and rejection', () {
    const fav = Favorites(
      places: {PlaceKind.home: Place(kind: PlaceKind.home, stops: [tampines])},
      lines: {'EWL'},
      leaveHome: TimeOfDayHM(6, 45),
    );
    final code = encodeShareCode(fav);
    expect(code, startsWith('DL1:'));
    final back = decodeShareCode(code, const Favorites(lang: 'id'))!;
    expect(back.places[PlaceKind.home]!.stops.single.code, '75009');
    expect(back.lines, {'EWL'});
    expect(back.leaveHome.format(), '06.45');
    expect(back.lang, 'id'); // keeps the receiver's own settings
    expect(decodeShareCode('hello', const Favorites()), isNull);
    expect(decodeShareCode('DL1:!!!', const Favorites()), isNull);
  });

  test('hawker closures', () {
    final h = Hawker.fromBundle({
      'id': 'h1',
      'n': 'Old Airport Road',
      'a': '51 Old Airport Rd',
      'la': 1.308,
      'lo': 103.885,
      'c': [
        ['2026-10-19', '2026-10-21', 'cleaning'],
        ['2026-12-01', '2026-12-31', 'other works'],
      ],
    });
    expect(h.closureOn(DateTime(2026, 10, 20))?.reason, 'cleaning');
    expect(h.closureOn(DateTime(2026, 10, 22)), isNull);
    expect(h.nextClosure(DateTime(2026, 10, 22))?.reason, 'other works');
  });

  test('distance helpers, dengue and taxis', () {
    const stops = [tampines, raffles];
    final w = within(stops, 1.354, 103.943, 1000, latOf: (s) => s.lat, lngOf: (s) => s.lng);
    expect(w.single.$1.code, '75009');
    expect(nearest(stops, 1.28, 103.85, latOf: (s) => s.lat, lngOf: (s) => s.lng)!.$1.code, '03011');
    final c = DengueCluster.fromBundle({'loc': 'Tampines St 81', 'n': 12, 'la': 1.356, 'lo': 103.944, 'r': 150});
    expect(dengueNear([c], 1.354, 103.943, km: 1), hasLength(1));
    expect(dengueNear([c], 1.284, 103.851, km: 1), isEmpty);
    expect(
        taxisWithin({
          'data': [
            [1.3541, 103.9431],
            [1.30, 103.80],
          ],
        }, 1.354, 103.943),
        1);
    expect(carparkLots({'data': {'HE12': [105, 7]}})['HE12'], (105, 7));
  });

  test('prayer and money formatting', () {
    final times = ['05:40', '07:00', '13:05', '16:20', '19:05', '20:15'];
    expect(nextPrayerIndex(times, DateTime(2026, 10, 20, 12, 0)), 2);
    expect(nextPrayerIndex(times, DateTime(2026, 10, 20, 21, 0)), isNull);
    expect(sgd(612000), r'S$612,000');
    expect(sgd(612000, compact: true), r'S$612k');
    expect(sgd(1050000, compact: true), r'S$1.05M');
    expect(monthLabel('2026-08'), 'Aug 2026');
  });

  test('block search and resale stats', () {
    const blocks = [
      HdbBlock(block: '123', street: 'BEDOK NTH ST 2', town: 'BEDOK', yearCompleted: 1980, floors: 12, lat: 1.33, lng: 103.93),
      HdbBlock(block: '45', street: 'TAMPINES AVE 9', town: 'TAMPINES', yearCompleted: 2001, floors: 16, lat: 1.35, lng: 103.94),
    ];
    expect(searchBlocks(blocks, '123 bedok north').single.block, '123');
    expect(searchBlocks(blocks, 'tampines').single.block, '45');
    expect(blocks.first.leaseLeft(2026), 53);
    final r = ResaleData.fromBundle({
      'from': '2024-10',
      'to': '2026-09',
      'blocks': {
        '123|BEDOK NTH ST 2': {
          '4 ROOM': [480000, 5, '2026-08', 500000],
        },
      },
      'towns': {
        'BEDOK': {'4 ROOM': 520000},
      },
    });
    expect(r.countFor('123|BEDOK NTH ST 2'), 5);
    expect(r.blocks['123|BEDOK NTH ST 2']!.single.median, 480000);
    expect(r.towns['BEDOK']!['4 ROOM'], 520000);
  });

  test('strings exist in both languages', () {
    const en = S(AppLang.en);
    const id = S(AppLang.id);
    expect(en.tabToday, 'Today');
    expect(id.tabToday, 'Hari ini');
    expect(id.greeting(7), 'Selamat pagi');
    expect(en.newSales('123 BEDOK', 2), contains('2 new'));
    expect(langFromCode('id'), AppLang.id);
    expect(langFromCode('zh'), AppLang.en);
  });
}
