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
    expect(const S().loadLabel(etas.first.load), 'Full');
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
    expect(s.first.detail, contains('Free bridging buses'));
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
    const ended = Project(kind: 'road', name: 'Done', lat: 1.3039, lng: 103.9097, to: '2Q 2026');
    const big = Project(kind: 'road', name: 'Town-wide', lat: 1.36, lng: 103.89, radius: 8000, points: [(1.36, 103.89), (1.32, 103.93)]);
    final near = projectsNear([far, road, lup, ended, big], 1.30395, 103.90975, now: DateTime(2026, 10, 21));
    expect(near.map((x) => x.$1.name), ['Marine Drive (MP12)', 'Road works']);
    expect(near.first.$2, 0);
    expect(upgradingAtHome(near).single.kind, 'lup');
    expect(projectEnded('4Q 2026', DateTime(2026, 10, 21)), isFalse);
    expect(projectEnded('2026-09', DateTime(2026, 10, 21)), isTrue);
    expect(rentFor({'3-ROOM': 3000, '5-ROOM': 4300}, '3 ROOM'), ('3-ROOM', 3000));
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

  test('halal places near, with keyword search', () {
    const places = [
      EPoint(name: 'Wingstop', address: '53 Ang Mo Kio Avenue 3 AMK Hub', lat: 1.3690, lng: 103.8482),
      EPoint(name: 'Nasi Padang Sabar Menanti', address: '48 Kandahar St', lat: 1.3021, lng: 103.8594),
      EPoint(name: 'Prata Cafe', address: '400 Ang Mo Kio Ave 10', lat: 1.3625, lng: 103.8540),
    ];
    final near = halalNear(places, 1.3620, 103.8538);
    expect(near.map((x) => x.$1.name), ['Prata Cafe', 'Wingstop']);
    expect(halalNear(places, 1.3620, 103.8538, query: 'nasi padang').single.$1.name, 'Nasi Padang Sabar Menanti');
    expect(halalNear(places, 1.3620, 103.8538, query: 'ang mo kio cafe').single.$1.name, 'Prata Cafe');
  });

  test('private project at a home and its bundle', () {
    final p = PrivateProject.fromBundle({
      'n': 'Taipan Grand', 's': 'Marine Parade Road', 'la': 1.3020, 'lo': 103.9120,
      'ten': 'Freehold', 'pt': 'Condominium', 'psf': 1100, 'pc': 2,
      'tx': [['2026-08', 1076390, 100, '06-10']],
      'rent': {'3': 4600}, 'rc': 3,
    });
    expect(p.recent.single.$2, 1076390);
    expect(p.rent['3'], 4600);
    const near = Place(kind: PlaceKind.home, addrLat: 1.3025, addrLng: 103.9122);
    const far = Place(kind: PlaceKind.home, addrLat: 1.3100, addrLng: 103.9200);
    expect(privateProjectFor([p], near)!.name, 'Taipan Grand');
    expect(privateProjectFor([p], far), isNull);
    expect(titleCase('BT BATOK ST 11'), 'Bt Batok St 11');
  });

  test('order in: rain, then haze, then a closed hawker', () {
    expect(orderInReason(), isNull);
    expect(orderInReason(rainMm: 0, air: AirLevel.moderate), isNull);
    expect(orderInReason(rainMm: 0.2, air: AirLevel.hazardous, nearestHawkerClosed: true), OrderInReason.rain);
    expect(orderInReason(air: AirLevel.unhealthy, nearestHawkerClosed: true), OrderInReason.haze);
    expect(orderInReason(nearestHawkerClosed: true), OrderInReason.hawkerClosed);
  });

  test('trains and buses rest between 1:00 and 5:30 am', () {
    expect(transitResting(DateTime(2026, 10, 22, 0, 45)), isFalse);
    expect(transitResting(DateTime(2026, 10, 22, 1, 0)), isTrue);
    expect(transitResting(DateTime(2026, 10, 22, 3, 43)), isTrue);
    expect(transitResting(DateTime(2026, 10, 22, 5, 29)), isTrue);
    expect(transitResting(DateTime(2026, 10, 22, 5, 30)), isFalse);
  });

  test('stops follow the address when a place moves', () {
    const marine = BusStop(code: '92049', name: 'Marine Pde Stn', road: 'Marine Pde Rd', lat: 1.3029, lng: 103.9054);
    const segar = BusStop(code: '44641', name: 'Blk 476', road: 'Segar Rd', lat: 1.3880, lng: 103.7700);
    const moved = Place(kind: PlaceKind.home, stops: [marine], address: '476 Segar Rd', addrLat: 1.3878, addrLng: 103.7702);
    expect(usableStops(moved), isEmpty);
    expect(destinationStops(moved, const [segar, marine]), {'44641'});
    final (stops, picked) = stopsForNewAddress(const [marine], const [segar, marine], 1.3878, 103.7702);
    expect(stops.map((s) => s.code), ['44641']);
    expect(picked, isTrue);
    final (kept, picked2) = stopsForNewAddress(const [marine], const [segar, marine], 1.3031, 103.9056);
    expect(kept.single.code, '92049');
    expect(picked2, isFalse);
  });

  test('a new address keeps the routine', () {
    const work = Place(kind: PlaceKind.work, modes: [TravelMode.car], days: {1, 3}, go: TimeOfDayHM(8, 15));
    final p = work.withAddress(address: 'Changi', lat: 1.33, lng: 103.96, stops: const []);
    expect(p.modes, [TravelMode.car]);
    expect(p.days, {1, 3});
    expect(p.go, const TimeOfDayHM(8, 15));
    expect(p.address, 'Changi');
  });

  test('plan B: disrupted lines on the MRT plan, with free bridging buses', () {
    const a = MrtStation(name: 'Expo', codes: ['CG1', 'DT35'], lat: 1.334, lng: 103.961);
    const b = MrtStation(name: 'Segar', codes: ['BP11'], lat: 1.387, lng: 103.769);
    const plan = MrtPlan(board: a, walkToBoard: 300, alight: b, walkFromAlight: 400);
    expect(mrtPlanLines(plan), containsAll(['EWL', 'DTL', 'BPL']));
    final alerts = {
      'data': {
        'value': {
          'Status': 2,
          'AffectedSegments': [
            {'Line': 'DTL', 'Stations': 'DT30,DT31', 'FreePublicBus': 'DT30,DT31'},
          ],
          'Message': [],
        },
      },
    };
    final r = planDisruption(plan, alerts);
    expect(r.lines, ['DTL']);
    expect(r.freeBus, isTrue);
    expect(planDisruption(plan, {'data': {'value': {'Status': 1}}}).lines, isEmpty);
    expect(lineStatuses(alerts, {'DTL'}).single.detail, contains('Free bridging buses'));
  });

  test('leave by: first bus still catchable after the walk', () {
    const a = BusEta(service: '47', minutes: 2, load: 'SEA');
    const b = BusEta(service: '12', minutes: 9, load: 'SEA');
    final grouped = [(a, 12), (b, null)];
    final lb = leaveBy(grouped, null, 4)!;
    expect(lb.service, '12');
    expect(lb.leaveIn, 5);
    expect(leaveBy(grouped, {'47'}, 4)!.leaveIn, 8); // the next 47
    expect(leaveBy(grouped, {'99'}, 4), isNull);
    expect(walkMinutesTo(300), 5);
    expect(inLeaveWindow(DateTime(2026, 10, 22, 7, 40), const TimeOfDayHM(8, 0)), isTrue);
    expect(inLeaveWindow(DateTime(2026, 10, 22, 7, 30), const TimeOfDayHM(8, 0)), isFalse);
  });

  test('wake me: stop before the alight stop and the wake radius', () {
    const routes = BusRoutes({
      '47|1': [('A', 0.0), ('B', 1.0), ('C', 1.6)],
    });
    final ride = directRides(routes, 'A', {'C'})['47']!;
    expect(ride.routeKey, '47|1');
    expect(stopBefore(routes, ride), 'B');
    const b = BusStop(code: 'B', name: 'B', road: '', lat: 1.3000, lng: 103.8000);
    const c = BusStop(code: 'C', name: 'C', road: '', lat: 1.3054, lng: 103.8000);
    expect(wakeRadius(b, c), closeTo(700, 15));
    expect(wakeRadius(null, c), 500);
  });

  test('weekly digest: hawker closures, dengue and holidays in the next week', () {
    final now = DateTime(2026, 10, 25, 19); // Sunday evening
    expect(inDigestWindow(now), isTrue);
    expect(inDigestWindow(DateTime(2026, 10, 24, 19)), isFalse);
    final h = Hawker.fromBundle({
      'id': 'h1', 'n': 'Golden Mile', 'a': '', 'la': 1.30, 'lo': 103.86,
      'c': [['2026-10-27', '2026-10-30', 'cleaning']],
    });
    const fav = Favorites(
      hawkers: {'h1'},
      places: {PlaceKind.home: Place(kind: PlaceKind.home, address: 'Home', addrLat: 1.30, addrLng: 103.86)},
    );
    final holidays = Holiday.fromBundle([{'d': '2026-10-28', 'n': 'Test Day'}, {'d': '2026-12-25', 'n': 'Christmas Day'}]);
    final lines = weeklyDigest(s: const S(), fav: fav, now: now, hawkers: [h], holidays: holidays);
    expect(lines.any((l) => l.contains('Golden Mile')), isTrue);
    expect(lines.any((l) => l.contains('Test Day') && l.contains('Wed')), isTrue);
    expect(lines.any((l) => l.contains('Christmas')), isFalse);
    expect(weeklyDigest(s: const S(), fav: const Favorites(), now: now), isEmpty);
  });

  test('weather advice depends on how you travel', () {
    expect(tripAdvice(mode: TravelMode.bicycle, lightning: true, rainy: true),
        [TripAdvice.lightningRide, TripAdvice.rainRide]);
    expect(tripAdvice(mode: TravelMode.car, lightning: true, highHeat: true), isEmpty);
    expect(tripAdvice(mode: TravelMode.car, rainy: true), [TripAdvice.rainDrive]);
    expect(tripAdvice(mode: TravelMode.transit, highHeat: true, air: AirLevel.unhealthy),
        [TripAdvice.heat, TripAdvice.haze]);
    expect(tripAdvice(mode: TravelMode.taxi, air: AirLevel.hazardous), isEmpty);
  });

  test('know me: trip stats, trip minutes and meal nudge', () {
    TripLog trip(int m, {bool rainy = false}) =>
        TripLog(route: 'home>work', start: DateTime(2026, 10, 20, 8), minutes: m, rainy: rainy);
    expect(tripStats([trip(40), trip(44)], 'home>work').usual, isNull);
    final st = tripStats([trip(40), trip(44), trip(42), trip(52, rainy: true), trip(50, rainy: true)], 'home>work');
    expect(st.usual, 44);
    expect(st.rainy, 52);
    expect(st.count, 5);
    expect(tripMinutes(DateTime(2026, 1, 1, 8), DateTime(2026, 1, 1, 8, 2)), isNull);
    expect(tripMinutes(DateTime(2026, 1, 1, 8), DateTime(2026, 1, 1, 8, 41)), 41);

    Hawker hk(String id, double lo) => Hawker.fromBundle({'id': id, 'n': 'H$id', 'a': '', 'la': 1.30, 'lo': lo});
    final all = [hk('a', 103.860), hk('b', 103.865), hk('c', 103.950)];
    final now = DateTime(2026, 10, 22, 12);
    final meals = [for (var i = 0; i < 3; i++) MealLog(hawkerId: 'a', at: now.subtract(Duration(days: i)))];
    final n = mealNudge(meals, all, now, 1.30, 103.860)!;
    expect(n.usual.id, 'a');
    expect(n.times, 3);
    expect(n.instead.id, 'b');
    expect(mealNudge(meals.take(2).toList(), all, now, 1.30, 103.860), isNull);
    expect(clockLabel(DateTime(2026, 1, 1, 8, 5)), '8:05');
  });

  test('habits round-trip through JSON and park reminder', () {
    final h = Habits(
      parked: ParkedCar(name: 'Blk 65A', lat: 1.3, lng: 103.9, at: DateTime(2026, 10, 22, 9), level: '3', remindMinutes: 120),
      trips: [TripLog(route: 'home>work', start: DateTime(2026, 10, 22, 8), minutes: 41, rainy: true)],
      meals: [MealLog(hawkerId: 'a', at: DateTime(2026, 10, 22, 12))],
    );
    final back = Habits.fromJson(h.toJson());
    expect(back.parked!.level, '3');
    expect(back.trips.single.rainy, isTrue);
    expect(back.meals.single.hawkerId, 'a');
    expect(parkReminderDue(back.parked!, DateTime(2026, 10, 22, 10, 59)), isFalse);
    expect(parkReminderDue(back.parked!, DateTime(2026, 10, 22, 11)), isTrue);
  });

  test('persona fixes: names, details, closed places, duplicates, since label', () {
    expect(cleanPlaceName('1 MEDICAL TECK GHEE'), '1 Medical Teck Ghee');
    expect(cleanPlaceName('NEA Producer Responsibility Scheme - ALBA E-waste Recycling Programme'),
        'ALBA E-waste Recycling Programme');
    expect(cleanPlaceName('McDonald\'s'), "McDonald's");
    expect(cleanDetail('Manned collection; ; ; E-waste accepted: Batteries'), 'Manned collection; E-waste accepted: Batteries');
    const open = EPoint(name: 'Ang Mo Kio NPC', lat: 1.3700, lng: 103.85);
    const closed = EPoint(name: 'Teck Ghee NPP (Temporarily Closed)', lat: 1.3621, lng: 103.854);
    expect(nearestPoints([closed, open], 1.362, 103.854, limit: 1).single.$1.name, 'Ang Mo Kio NPC');
    final d = dedupePlaces<String>([('PCF Sparkletots Preschool @ Bukit Batok Blk 148 (KN', 186.0), ('PCF Sparkletots Preschool @ Bukit Batok Blk 148 (KN)', 186.0), ('Just Kids', 179.0)],
        nameOf: (n) => n, latOf: (_) => 1.35, lngOf: (_) => 103.75);
    expect(d.length, 2);
    final now = DateTime(2026, 10, 23, 10, 30);
    expect(sinceLabel(DateTime(2026, 10, 23, 9, 10), now), '9:10');
    expect(sinceLabel(DateTime(2026, 10, 22, 9, 10), now), 'yesterday 9:10');
    expect(sinceLabel(DateTime(2026, 10, 20, 9, 10), now), 'Tue 9:10');
    expect(const S().dengueNear('Home', 1), '1 dengue cluster near Home');
  });

  test('services that go straight home from a stop', () {
    const routes = BusRoutes({
      '47|1': [('A', 0.0), ('B', 1.0), ('H', 3.0)],
      '12|1': [('A', 0.0), ('W', 2.0)],
    });
    const a = BusStop(code: 'A', name: 'A', road: '', lat: 1.3, lng: 103.8);
    final m = servicesToPlaces(routes, a, {'Home': {'H'}, 'Work': {'W'}});
    expect(m['47'], ['Home']);
    expect(m['12'], ['Work']);
    expect(servicesToPlaces(routes, a, {'Home': {'A'}}), isEmpty);
    expect(const S().toPlaces(['Home']), 'to Home');
  });

  test('bus arrivals carry wheelchair access and bus type', () {
    final now = DateTime.utc(2026, 10, 23, 1);
    final body = {
      'data': {
        'Services': [
          {
            'ServiceNo': '162',
            'NextBus': {'EstimatedArrival': now.add(const Duration(minutes: 4)).toIso8601String(), 'Load': 'SEA', 'Feature': 'WAB', 'Type': 'SD'},
          },
        ],
      },
    };
    final e = parseBusArrival(body, now).single;
    expect(e.wheelchair, isTrue);
    expect(e.deck, 'SD');
    expect(const S().busInfo(e), 'Seats · ♿ Wheelchair · Single deck');
  });

  test('MOE school holidays', () {
    final all = SchoolHoliday.fromBundle([
      {'f': '2026-11-21', 't': '2026-12-31', 'n': 'Year-end holidays'},
      {'f': 'bad', 't': '2026-01-01', 'n': 'x'},
    ]);
    expect(all, hasLength(1));
    expect(schoolHolidayOn(all, DateTime(2026, 11, 23, 7))!.name, 'Year-end holidays');
    expect(schoolHolidayOn(all, DateTime(2026, 11, 20, 7)), isNull);
  });

  test('custom places with a usual time are due in their leave window', () {
    const fav = Favorites(extraPlaces: [
      Place(kind: PlaceKind.other, name: 'Pick-up', addrLat: 1.3, addrLng: 103.8, when: PlaceWhen.weekdays, go: TimeOfDayHM(13, 0)),
      Place(kind: PlaceKind.other, name: 'Market', addrLat: 1.3, addrLng: 103.8),
    ]);
    expect(extrasDueNow(fav, DateTime(2026, 10, 23, 12, 45)), [0]); // Friday
    expect(extrasDueNow(fav, DateTime(2026, 10, 24, 12, 45)), isEmpty); // Saturday
    expect(extrasDueNow(fav, DateTime(2026, 10, 23, 12, 0)), isEmpty);
    expect(fav.extraPlaces.first.copyWith(clearGo: true).go, isNull);
  });

  test('trip planner names and weekend picks', () {
    expect(shortAddress('451 Marine Parade Road (Kampung Siglap Mosque Kindergarten)'), '451 Marine Parade Road');
    expect(shortAddress('1 Raffles Quay'), '1 Raffles Quay');
    final kinds = {
      'museum': [const EPoint(name: 'Museum', lat: 1.301, lng: 103.90)],
      'park': [const EPoint(name: 'Park', lat: 1.302, lng: 103.90)],
      'bbq': [const EPoint(name: 'Far BBQ', lat: 1.50, lng: 103.90)],
    };
    expect(weekendPicks(kinds, 1.30, 103.90, indoor: true).first.$1, 'museum');
    final out = weekendPicks(kinds, 1.30, 103.90, indoor: false);
    expect(out.first.$1, 'park');
    expect(out.any((e) => e.$1 == 'bbq'), isFalse); // more than 5 km away
  });

  test('events near home this weekend, one-off events first', () {
    PublicEvent ev(String n, String s, String e, {double lng = 103.90}) =>
        PublicEvent.fromBundle({'n': n, 'u': 'https://x', 's': s, 'e': e, 'la': 1.30, 'lo': lng})!;
    final now = DateTime(2026, 10, 24, 10); // Saturday
    expect(daysToWeekendEnd(now), 2);
    final all = [
      ev('Long show', '2026-08-01 20:00', '2026-12-30 22:00'),
      ev('Fair', '2026-10-25 10:00', '2026-10-25 18:00'),
      ev('Next week', '2026-10-28 10:00', '2026-10-28 18:00'),
      ev('Far fair', '2026-10-24 10:00', '2026-10-24 18:00', lng: 104.2),
    ];
    final out = eventsNear(all, 1.30, 103.90, now, days: daysToWeekendEnd(now));
    expect(out.map((e) => e.$1.name), ['Fair', 'Long show']);
  });

  group('parks', () {
    test('expandPlaceName spells out short forms', () {
      expect(expandPlaceName('Jln Kebaya Pg'), 'Jalan Kebaya Playground');
      expect(expandPlaceName('Hazel Pk Os'), 'Hazel Park Open Space');
      expect(expandPlaceName('Siglap Linear Pk (Jln B\'Wan-Upp Ec Rd)'), 'Siglap Linear Park (Jalan B\'Wan-Upper East Coast Road)');
      expect(expandPlaceName('Sunrise Dr Pg Ii'), 'Sunrise Drive Playground II');
      expect(expandPlaceName('St Anne\'S Wood Pg'), 'St Anne\'s Wood Playground');
      expect(expandPlaceName('St. Nicholas View Playground'), 'St. Nicholas View Playground');
      expect(expandPlaceName('Pasir Ris Park'), 'Pasir Ris Park');
    });

    test('park bundle carries facilities and expanded names', () {
      final set = PoiSet.fromBundle({
        'park': [
          {'n': 'Bishan Pk', 'la': 1.3, 'lo': 103.8, 'f': ['Playground', 'Toilet']},
        ],
        'library': [
          {'n': 'Bishan Pk Library', 'la': 1.3, 'lo': 103.8},
        ],
      });
      expect(set.of(PoiKind.park).single.name, 'Bishan Park');
      expect(set.of(PoiKind.park).single.facilities, ['Playground', 'Toilet']);
      expect(set.of(PoiKind.library).single.name, 'Bishan Pk Library');
      expect(set.of(PoiKind.library).single.facilities, isEmpty);
    });

    test('parkTime picks the most pressing reason', () {
      final noon = DateTime(2026, 10, 24, 12);
      expect(parkTime(now: noon), ParkTime.good);
      expect(parkTime(now: noon, lightning: true, rainMm: 2), ParkTime.lightning);
      expect(parkTime(now: noon, rainMm: 0.2, air: AirLevel.unhealthy), ParkTime.rain);
      expect(parkTime(now: noon, air: AirLevel.unhealthy, heat: 'High'), ParkTime.haze);
      expect(parkTime(now: noon, air: AirLevel.moderate, heat: 'High'), ParkTime.heat);
      expect(parkTime(now: noon, uv: 9), ParkTime.uv);
      expect(parkTime(now: DateTime(2026, 10, 24, 17), uv: 9), ParkTime.good);
      expect(parkTime(now: noon, uv: 5, showersForecast: true), ParkTime.showers);
    });
  });
}
