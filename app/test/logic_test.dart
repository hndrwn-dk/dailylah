import 'package:dailylah/data.dart';
import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:flutter_test/flutter_test.dart' hide within;

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
    expect(originFor(CardKind.morning, fav, morning), PlaceKind.home);
    expect(originFor(CardKind.evening, fav, evening), PlaceKind.work);
    expect(destinationFor(CardKind.morning, fav, morning), PlaceKind.work);
    // Days off: everything is about home.
    final saturday = DateTime(2026, 10, 24, 17, 30);
    expect(originFor(CardKind.evening, fav, saturday), PlaceKind.home);
    expect(destinationFor(CardKind.morning, fav, saturday), isNull);
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
    final back = decodeShareCode(code, const Favorites(showPrayer: true))!;
    expect(back.places[PlaceKind.home]!.stops.single.code, '75009');
    expect(back.lines, {'EWL'});
    expect(back.leaveHome.format(), '06.45');
    expect(back.showPrayer, isTrue); // keeps the receiver's own settings
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

  test('strings', () {
    const s = S();
    expect(s.tabToday, 'Today');
    expect(s.greeting(7), 'Good morning');
    expect(s.newSales('123 BEDOK', 2), contains('2 new'));
  });

  test('OneMap results and postal matching', () {
    final hits = parseOneMap({
      'results': [
        {'BLK_NO': '66', 'ROAD_NAME': 'MARINE DRIVE', 'BUILDING': 'NIL', 'POSTAL': '440066', 'LATITUDE': '1.3036', 'LONGITUDE': '103.9087'},
        {'BLK_NO': '66', 'ROAD_NAME': 'MARINE DRIVE', 'BUILDING': 'NIL', 'POSTAL': '440066', 'LATITUDE': '1.3036', 'LONGITUDE': '103.9087'},
        {'BLK_NO': '1', 'ROAD_NAME': 'RAFFLES PLACE', 'BUILDING': 'ONE RAFFLES PLACE', 'POSTAL': '048616', 'LATITUDE': '1.284', 'LONGITUDE': '103.851'},
      ],
    });
    expect(hits, hasLength(2));
    expect(hits.first.label, '66 Marine Drive');
    expect(hits.last.label, '1 Raffles Place (One Raffles Place)');
    expect(isPostalCode('440066'), isTrue);
    expect(isPostalCode('44006'), isFalse);
    const blocks = [
      HdbBlock(block: '66', street: 'MARINE DR', town: 'MARINE PARADE', yearCompleted: 1975, floors: 12, lat: 1.3037, lng: 103.9088, postal: '440066'),
    ];
    expect(searchBlocks(blocks, '440066').single.street, 'MARINE DR');
    expect(blockForAddress(blocks, hits.first)?.postal, '440066');
    expect(blockForAddress(blocks, hits.last), isNull);
    const place = Place(kind: PlaceKind.home, address: '66 Marine Drive', postal: '440066', addrLat: 1.3036, addrLng: 103.9087);
    final back = Place.fromJson(place.toJson());
    expect(back.lat, 1.3036);
    expect(back.stops, isEmpty);
    expect(back.label, '66 Marine Drive');
  });

  test('weather details and hawker alternatives', () {
    final rain = {
      'data': {
        'data': {
          'stations': [
            {'id': 'S1', 'name': 'Tampines Ave 5', 'location': {'latitude': 1.354, 'longitude': 103.943}},
            {'id': 'S2', 'name': 'Raffles', 'location': {'latitude': 1.284, 'longitude': 103.851}},
          ],
          'readings': [
            {
              'timestamp': '2026-10-20T13:00:00+08:00',
              'data': [
                {'stationId': 'S1', 'value': 0.4},
                {'stationId': 'S2', 'value': 0},
              ],
            },
          ],
        },
      },
    };
    final r = rainfallNear(rain, 1.355, 103.944)!;
    expect(r.$1, 'Tampines Ave 5');
    expect(r.$2, 0.4);
    final uv = {
      'data': {
        'data': {
          'records': [
            {
              'index': [
                {'hour': '2026-10-20T12:00:00+08:00', 'value': 9},
                {'hour': '2026-10-20T11:00:00+08:00', 'value': 7},
              ],
            },
          ],
        },
      },
    };
    expect(uvIndex(uv), 9);
    final wbgt = {
      'data': {
        'data': {
          'records': [
            {
              'item': {
                'readings': [
                  {'location': {'latitude': '1.36', 'longitude': '103.94'}, 'wbgt': '31.5', 'heatStress': 'High'},
                ],
              },
            },
          ],
        },
      },
    };
    expect(wbgtNear(wbgt, 1.35, 103.94), (31.5, 'High'));

    Hawker h(String id, double lat, List<List<String>> c) =>
        Hawker.fromBundle({'id': id, 'n': id, 'la': lat, 'lo': 103.9, 'c': c});
    final a = h('a', 1.30, [
      ['2026-10-20', '2026-10-21', 'cleaning'],
    ]);
    final b = h('b', 1.301, [
      ['2026-10-20', '2026-10-20', 'cleaning'],
    ]);
    final c = h('c', 1.305, []);
    final alt = openAlternatives([a, b, c], a, DateTime(2026, 10, 20));
    expect(alt.single.$1.id, 'c');
    expect(openAlternatives([a, b, c], a, DateTime(2026, 10, 21)).first.$1.id, 'b');

    const pois = [
      Poi(name: 'Near', lat: 1.3005, lng: 103.9),
      Poi(name: 'Mid', lat: 1.312, lng: 103.9),
      Poi(name: 'Far', lat: 1.4, lng: 103.9),
    ];
    final (near, far) = schoolsByBand(pois, 1.30, 103.9);
    expect(near.single.$1.name, 'Near');
    expect(far.single.$1.name, 'Mid');
  });

  test('air quality picks the nearest region and the worse band', () {
    Map<String, dynamic> wrap(Map<String, dynamic> readings) => {
          'data': {
            'data': {
              'regionMetadata': [
                {'name': 'east', 'labelLocation': {'latitude': 1.35735, 'longitude': 103.94}},
                {'name': 'west', 'labelLocation': {'latitude': 1.35735, 'longitude': 103.7}},
              ],
              'items': [
                {'readings': readings},
              ],
            },
          },
        };
    final psi = wrap({
      'psi_twenty_four_hourly': {'east': 106, 'west': 140},
    });
    final pm = wrap({
      'pm25_one_hourly': {'east': 51, 'west': 160},
    });
    final east = airNear(psi, pm, 1.354, 103.943)!;
    expect(east.region, 'east');
    expect(east.psi24, 106);
    expect(east.level, AirLevel.unhealthy);
    final west = airNear(psi, pm, 1.35, 103.70)!;
    expect(west.level, AirLevel.veryUnhealthy); // PM2.5 band III beats PSI 140
    expect(psiLevel(45), AirLevel.good);
    expect(psiLevel(301), AirLevel.hazardous);
    expect(airNear(null, null, 1.3, 103.8), isNull);
  });

  test('taxi bands and radar offsets', () {
    final pts = taxiPoints({
      'data': [
        [1.3000, 103.8000],
        [1.3025, 103.8000],
        [1.3080, 103.8000],
        'bad',
      ],
    });
    expect(pts, hasLength(3));
    expect(taxiBands(pts, 1.3, 103.8), (1, 2, 3));
    final (e, n) = offsetMetres(1.3, 103.8, 1.301, 103.801);
    expect(n, closeTo(110.5, 1));
    expect(e, closeTo(111.2, 1));
  });

  test('routines: card switch, commute days, extras, direct buses', () {
    const fav = Favorites(
      places: {
        PlaceKind.home: Place(kind: PlaceKind.home, stops: [tampines]),
        PlaceKind.work: Place(
          kind: PlaceKind.work,
          stops: [raffles],
          modes: [TravelMode.car, TravelMode.transit],
          go: TimeOfDayHM(8, 0),
          back: TimeOfDayHM(20, 0),
        ),
        PlaceKind.school: Place(kind: PlaceKind.school, stops: [raffles], days: {6}),
      },
      extraPlaces: [
        Place(kind: PlaceKind.other, name: 'Makan', addrLat: 1.3, addrLng: 103.85, when: PlaceWhen.weekends),
        Place(kind: PlaceKind.other, name: 'Gym', addrLat: 1.31, addrLng: 103.86),
      ],
    );
    // Halfway between 08:00 and 20:00 is 14:00.
    expect(cardFor(DateTime(2026, 10, 20, 13, 59), fav), CardKind.morning);
    expect(cardFor(DateTime(2026, 10, 20, 14, 0), fav), CardKind.evening);
    expect(isCommuteDay(fav, DateTime(2026, 10, 20)), isTrue); // Tuesday
    expect(isCommuteDay(fav, DateTime(2026, 10, 25)), isFalse); // Sunday
    expect(commutePlace(fav, DateTime(2026, 10, 24))!.kind, PlaceKind.school); // Saturday school
    expect(destinationFor(CardKind.morning, fav, DateTime(2026, 10, 24)), PlaceKind.school);
    expect(watchedLines(const Favorites()).length, trainLines.length);
    expect(watchedLines(const Favorites(lines: {'NSL'})), {'NSL'});
    expect(extrasForToday(fav, DateTime(2026, 10, 20)), [1]);
    expect(extrasForToday(fav, DateTime(2026, 10, 24)), [0, 1]);
    final back = Favorites.fromJson(fav.toJson());
    expect(back.places[PlaceKind.work]!.mode, TravelMode.car);
    expect(back.extraPlaces.first.when, PlaceWhen.weekends);
    expect(back.places[PlaceKind.work]!.go!.format(), '08.00');
    expect(back.places[PlaceKind.school]!.days, {6});

    final routes = BusRoutes.fromBundle({
      '10|1': [
        ['A', 0.0],
        ['B', 1.0],
        ['C', 2.5],
      ],
      '10|2': [
        ['C', 0.0],
        ['A', 2.5],
      ],
      '20|1': [
        ['B', 0.0],
        ['A', 1.0],
      ],
    });
    final rides = directRides(routes, 'A', {'C'});
    expect(rides.keys, ['10']);
    expect(rides['10']!.stops, 2);
    expect(rides['10']!.km, 2.5);
    expect(directRides(routes, 'C', {'A'})['10']!.alightAt, 'A');
    expect(directRides(routes, 'B', {'C', 'A'}).keys.toSet(), {'10', '20'});
  });

  test('parking and incidents on the way', () {
    final lots = parseParking({
      'data': [
        ['1', 'LTA', 1.3005, 103.8, 'C', 120, 'Mall'],
        ['2', 'HDB', 1.3006, 103.8, 'Y', 8, 'Blk 1'],
        ['3', 'LTA', 1.4, 103.8, 'C', 50, 'Far'],
      ],
    });
    expect(parkingNear(lots, 1.3, 103.8, 'C').single.$1.name, 'Mall');
    expect(parkingNear(lots, 1.3, 103.8, 'Y').single.$1.available, 8);
    const a = Place(kind: PlaceKind.home, addrLat: 1.30, addrLng: 103.80);
    const b = Place(kind: PlaceKind.work, addrLat: 1.30, addrLng: 103.90);
    final hits = incidentsOnTrip({
      'data': [
        ['Accident', 1.301, 103.85, 'On the way'],
        ['Roadwork', 1.40, 103.85, 'Far away'],
      ],
    }, a, b);
    expect(hits.single.$2, 'On the way');
  });

  test('station codes map to lines', () {
    expect(lineOfCode('TE26'), 'TEL');
    expect(lineOfCode('CG1'), 'EWL');
    expect(lineOfCode('STC'), 'SLRT');
    expect(lineOfCode('XX1'), isNull);
  });

  test('mrt plan finds a direct line and stop count', () {
    const stations = [
      MrtStation(name: 'Marine Parade', codes: ['TE26'], lat: 1.3027, lng: 103.9066),
      MrtStation(name: 'Marina Bay', codes: ['NS27', 'CE2', 'TE20'], lat: 1.2762, lng: 103.8546),
      MrtStation(name: 'Promenade', codes: ['CC4', 'DT15'], lat: 1.2931, lng: 103.8610),
    ];
    const home = Place(kind: PlaceKind.home, addrLat: 1.3030, addrLng: 103.9060);
    const office = Place(kind: PlaceKind.work, addrLat: 1.2765, addrLng: 103.8550);
    final plan = mrtPlan(stations, home, office)!;
    expect(plan.board.name, 'Marine Parade');
    expect(plan.alight.name, 'Marina Bay');
    expect(plan.line, 'TEL');
    expect(plan.stops, 6);
    const temasek = Place(kind: PlaceKind.work, addrLat: 1.2935, addrLng: 103.8612);
    expect(mrtPlan(stations, home, temasek)!.direct, isFalse);
  });

  test('trip start stops keep the side with a direct bus, or suggest one nearby', () {
    const towardWork = BusStop(code: '92059', name: 'A', road: 'R', lat: 1.3, lng: 103.9);
    const towardHome = BusStop(code: '92051', name: 'B', road: 'R', lat: 1.3001, lng: 103.9001);
    const further = BusStop(code: '92071', name: 'C', road: 'R2', lat: 1.3030, lng: 103.9);
    const office = BusStop(code: '02151', name: 'D', road: 'R3', lat: 1.29, lng: 103.86);
    const officeBack = BusStop(code: '02159', name: 'E', road: 'R3', lat: 1.2901, lng: 103.8601);
    final all = [towardWork, towardHome, further, office, officeBack];
    const home = Place(kind: PlaceKind.home, addrLat: 1.3, addrLng: 103.9, stops: [towardWork, towardHome]);
    const work = Place(kind: PlaceKind.work, addrLat: 1.29, addrLng: 103.86);
    final routes = BusRoutes.fromBundle({
      '36|1': [['92059', 0], ['02151', 5]],
      '36|2': [['02159', 0], ['92051', 5]],
      '77|1': [['92071', 0], ['02151', 6]],
    });
    expect(tripStops(home.stops, all, routes, home, work).stops.map((x) => x.code), ['92059']);
    // Only the stop further away has a direct bus: suggest it.
    const home2 = Place(kind: PlaceKind.home, addrLat: 1.3, addrLng: 103.9, stops: [towardHome]);
    final t = tripStops(home2.stops, all, routes, home2, work);
    expect(t.suggested, isTrue);
    expect(t.stops.map((x) => x.code), ['92059', '92071']);
    expect(tripStops(home.stops, all, BusRoutes.empty, home, work).stops.length, 2);
  });

  test('loop services that go the long way are not direct', () {
    const a = BusStop(code: 'A', name: 'A', road: 'R', lat: 1.36, lng: 103.85);
    const clinic = Place(kind: PlaceKind.other, addrLat: 1.37, addrLng: 103.85);
    final routes = BusRoutes.fromBundle({
      '162|1': [['A', 0], ['B', 17.6]],
      '50|1': [['A', 0], ['B', 1.3]],
    });
    expect(tripRides(routes, a, clinic, {'B'}).keys, ['50']);
  });

  test('arrivals are grouped per service', () {
    const etas = [
      BusEta(service: '50', minutes: 0, load: 'SEA'),
      BusEta(service: '159', minutes: 2, load: 'SEA'),
      BusEta(service: '50', minutes: 6, load: 'SDA'),
      BusEta(service: '50', minutes: 15, load: 'SEA'),
    ];
    final g = groupEtas(etas);
    expect(g.map((x) => x.$1.service), ['50', '159']);
    expect(g.first.$2, 6);
    expect(g.last.$2, isNull);
  });

  test('mrt plan names the interchange', () {
    const stations = [
      MrtStation(name: 'Bukit Batok', codes: ['NS2'], lat: 1.3490, lng: 103.7496),
      MrtStation(name: 'Jurong East', codes: ['NS1', 'EW24'], lat: 1.3332, lng: 103.7422),
      MrtStation(name: 'Boon Lay', codes: ['EW27'], lat: 1.3386, lng: 103.7058),
    ];
    const home = Place(kind: PlaceKind.home, addrLat: 1.3477, addrLng: 103.7440);
    const school = Place(kind: PlaceKind.school, addrLat: 1.3353, addrLng: 103.7021);
    final plan = mrtPlan(stations, home, school)!;
    expect(plan.direct, isFalse);
    expect(plan.via!.name, 'Jurong East');
  });

  test('short names for hawker centres', () {
    expect(shortPlaceName('Tampines Street 11 Blk 137 (Tampines Round Market and Food Centre)'),
        'Tampines Round Market and Food Centre');
    expect(shortPlaceName('Maxwell Food Centre'), 'Maxwell Food Centre');
  });

  test('home block by postal code, else nearest within 40 m', () {
    const b66 = HdbBlock(block: '66', street: 'MARINE DR', town: 'MARINE PARADE', yearCompleted: 1975, floors: 16, lat: 1.30392, lng: 103.90973, postal: '440066');
    const b67 = HdbBlock(block: '67', street: 'MARINE DR', town: 'MARINE PARADE', yearCompleted: 1975, floors: 16, lat: 1.30420, lng: 103.91010, postal: '440067');
    const byPostal = Place(kind: PlaceKind.home, postal: '440066', addrLat: 1.3042, addrLng: 103.9101);
    expect(homeBlock([b66, b67], byPostal)!.block, '66');
    const condo = Place(kind: PlaceKind.home, addrLat: 1.3100, addrLng: 103.9200);
    expect(homeBlock([b66, b67], condo), isNull);
  });

  test('works near home, upgrading at the block first', () {
    const lup = Project(kind: 'lup', name: 'Marine Drive (MP12)', lat: 1.30392, lng: 103.90973, radius: 25);
    const road = Project(kind: 'road', name: 'Road works', lat: 1.3080, lng: 103.9097, radius: 50);
    const far = Project(kind: 'rail', name: 'Far away', lat: 1.35, lng: 103.95, radius: 100);
    final near = projectsNear([far, road, lup], 1.30395, 103.90975);
    expect(near.map((x) => x.$1.name), ['Marine Drive (MP12)', 'Road works']);
    expect(near.first.$2, 0);
    expect(upgradingAtHome(near).single.kind, 'lup');
  });

  test('hawker closures in the next 30 days near home', () {
    final h = Hawker(id: '1', name: 'X (Marine Parade Central)', address: 'a', lat: 1.3022, lng: 103.9067, closures: [
      Closure(DateTime(2026, 9, 1), DateTime(2026, 9, 3), 'cleaning'),
      Closure(DateTime(2026, 11, 16), DateTime(2026, 11, 18), 'cleaning'),
    ]);
    final out = upcomingClosures([h], 1.3039, 103.9097, DateTime(2026, 10, 21));
    expect(out.single.$2.from, DateTime(2026, 11, 16));
    expect(upcomingClosures([h], 1.3039, 103.9097, DateTime(2026, 10, 1)), isEmpty);
  });

  test('around bundle parses projects and points', () {
    final a = AroundSet.fromBundle({
      'projects': [
        {'k': 'lup', 'n': 'A', 's': 'Under construction', 'to': '4Q 2027', 'la': 1.3, 'lo': 103.9, 'r': 20},
      ],
      'points': {
        'police': [
          {'n': 'NPC', 'la': 1.3, 'lo': 103.9, 't': '64404123'},
        ],
      },
    });
    expect(a.projects.single.isUpgrading, isTrue);
    expect(a.of('police').single.tel, '64404123');
    expect(a.of('none'), isEmpty);
  });
}
