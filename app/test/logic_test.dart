import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/l10n.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:flutter/services.dart' show StandardMessageCodec;
import 'package:flutter_test/flutter_test.dart' hide within;

import 'support/harness.dart' show householdFavorites, saturdayMorning, tuesdayEvening, tuesdayMorning;

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
    expect(const S().loadLabel(etas.first.load), 'Packed');
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

  test('Appearance and the seen version survive a round trip; old saves follow the phone', () {
    const fav = Favorites(theme: 'dark', seenVersion: '1.6.0');
    final back = Favorites.fromJson(fav.toJson());
    expect(back.theme, 'dark');
    expect(back.seenVersion, '1.6.0');
    final old = Favorites.fromJson(const {'onboarded': true});
    expect(old.theme, '');
    expect(old.seenVersion, '');
    expect(appearanceChoices, ['', 'light', 'dark']);
  });

  test("What's new is due once per version, only after setup, never without a release version", () {
    const upgraded = Favorites(onboarded: true, seenVersion: '1.5.0');
    expect(whatsNewDue(upgraded, '1.6.0'), isTrue);
    expect(whatsNewDue(upgraded.copyWith(seenVersion: '1.6.0'), '1.6.0'), isFalse);
    // Saved before this feature existed: nothing recorded yet, so it shows.
    expect(whatsNewDue(const Favorites(onboarded: true), '1.6.0'), isTrue);
    // Still in setup, or a debug/test build without APP_VERSION.
    expect(whatsNewDue(const Favorites(), '1.6.0'), isFalse);
    expect(whatsNewDue(upgraded, ''), isFalse);
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

  test('looksLikeAddress sends numbers and blocks to OneMap, names to place search', () {
    for (final q in ['560201', '201 Ang Mo Kio', 'Blk 201', 'blk201', 'BLOCK 5 Marine Drive', ' 18 Bencoolen']) {
      expect(looksLikeAddress(q), isTrue, reason: q);
    }
    for (final q in ['Putra Minang', 'Jewel', 'Block Cafe', 'blk', 'Blkmart 2', '']) {
      expect(looksLikeAddress(q), isFalse, reason: q);
    }
  });

  test('parsePlaces reads /v1/places: name first, street without "Singapore", no position no hit', () {
    final hits = parsePlaces({
      'fetched_at': 0,
      'data': [
        {
          'name': 'Putra Minang',
          'address': '51 Bencoolen Street, Singapore 189630, Singapore',
          'postal': '189630',
          'lat': 1.29942,
          'lng': 103.85051,
          'type': 'amenity',
        },
        // Same place twice: kept once.
        {'name': 'Putra Minang', 'address': '51 Bencoolen Street, Singapore 189630, Singapore', 'postal': '189630', 'lat': 1.29942, 'lng': 103.85051},
        {'name': 'Singapore Zoo', 'address': 'Singapore Zoo', 'postal': '', 'lat': 1.4043, 'lng': 103.793},
        // Two outlets of one chain on the same street: both kept (the postal code tells them apart).
        {'name': 'Toast Box', 'address': 'Orchard Road, Singapore 238839, Singapore', 'postal': '238839', 'lat': 1.3005, 'lng': 103.8452},
        {'name': 'Toast Box', 'address': 'Orchard Road, Singapore 238801, Singapore', 'postal': '238801', 'lat': 1.3021, 'lng': 103.8371},
        {'name': 'Nowhere', 'address': 'x', 'postal': ''},
        'junk',
      ],
    });
    expect(hits, hasLength(4));
    expect(hits.where((h) => h.label == 'Toast Box, Orchard Road').map((h) => h.postal), ['238839', '238801']);
    final putra = hits.first;
    expect(putra.label, 'Putra Minang, 51 Bencoolen Street');
    expect(putra.name, 'Putra Minang');
    expect(putra.building, 'Putra Minang');
    expect(putra.road, '51 Bencoolen Street');
    expect(putra.block, '');
    expect(putra.postal, '189630');
    expect((putra.lat, putra.lng), (1.29942, 103.85051));
    // The address repeats the name: only the name.
    expect(hits[1].label, 'Singapore Zoo');
    expect(parsePlaces({'data': 'x'}), isEmpty);
    expect(parsePlaces({}), isEmpty);
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
  test('withoutWebAddress: a list row never prints a link', () {
    expect(withoutWebAddress('E-waste accepted: all regulated products at https://go.gov.sg/prod-def-sl'),
        'E-waste accepted: all regulated products');
    expect(withoutWebAddress('https://www.activesgcircle.gov.sg/facilities · 1 Tampines Walk 528523'),
        '1 Tampines Walk 528523');
    expect(withoutWebAddress('See HTTP://example.sg/a for details · Mon - Sun'), 'See for details · Mon - Sun');
    expect(withoutWebAddress('Level 1 Lift Lobby B · Mon - Sun 00:00-23:59'), 'Level 1 Lift Lobby B · Mon - Sun 00:00-23:59');
    expect(withoutWebAddress(''), '');
    // Punctuation after a link stays with the sentence; brackets left empty go.
    expect(withoutWebAddress('Products under First Schedule at https://go.gov.sg/prod-def-sl, Large Household Appliances'),
        'Products under First Schedule, Large Household Appliances');
    expect(withoutWebAddress('Book online (https://x.sg/book). Walk-ins welcome'), 'Book online. Walk-ins welcome');
    // The whole link goes, whatever is in it; nothing of it is left on the row.
    expect(withoutWebAddress('Map https://a.sg/x?ll=1.35,103.94 more'), 'Map more');
    expect(withoutWebAddress('See https://a.sg/p(1) today'), 'See today');
    expect(withoutWebAddress('https://x.sg/a,https://y.sg/b · Blk 1'), 'Blk 1');
    expect(withoutWebAddress('Open daily · https://x.sg. · Blk 1'), 'Open daily · Blk 1');
    expect(withoutWebAddress('(https://x.sg/book).'), '');
    expect(withoutWebAddress('http://'), '');
    expect(withoutWebAddress('See (map at https://a.sg/x).'), 'See (map).');
    for (final odd in ['https://a.sg/x?ll=1,2', 'a https://b.sg/c) d', 'HTTPS://X.SG', 'x · http:// · y']) {
      expect(withoutWebAddress(odd), isNot(contains('http')), reason: odd);
      expect(withoutWebAddress(odd).toLowerCase(), isNot(contains('.sg')), reason: odd);
    }
    // Ordinary text is left alone: words with "at", times.
    expect(withoutWebAddress('Batteries at the lobby · 8:30 - 17:00'), 'Batteries at the lobby · 8:30 - 17:00');
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
    // A starred place comes first even when it is far away.
    final far = places.reduce((a, b) =>
        distanceMeters(1.3620, 103.8538, a.lat, a.lng) > distanceMeters(1.3620, 103.8538, b.lat, b.lng) ? a : b);
    final starred = halalNear(places, 1.3620, 103.8538, favs: {halalPlaceId(far)});
    expect(starred.first.$1.name, far.name);
    expect(starred.where((e) => e.$1.name == far.name), hasLength(1));
  });

  test('halal favourites are per place, not per position (several shops in one mall)', () {
    const mall = [
      EPoint(name: 'The Coffee Bean & Tea Leaf', address: '1000 East Coast Parkway #01-01', lat: 1.301402, lng: 103.912301),
      EPoint(name: 'My Briyani House', address: '1000 East Coast Parkway #01-04', lat: 1.301402, lng: 103.912301),
      EPoint(name: "McDonald's", address: '1000 East Coast Parkway #01-05', lat: 1.301402, lng: 103.912301),
    ];
    expect(mall.map(halalPlaceId).toSet(), hasLength(3));
    final fav = {halalPlaceId(mall[2])};
    final list = halalNear(mall, 1.3015, 103.9124, favs: fav);
    expect(list, hasLength(3));
    expect(list.first.$1.name, "McDonald's");
    expect(list.where((e) => fav.contains(halalPlaceId(e.$1))), hasLength(1));
    // An older position-only save matches none of them (it cannot tell the shops apart).
    expect(mall.where((p) => {mealPlaceId(1.301402, 103.912301)}.contains(halalPlaceId(p))), isEmpty);
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
    // Short forms stay in capitals, wherever a name is title-cased.
    expect(titleCase('TAMPINES MRT STATION'), 'Tampines MRT Station');
    expect(titleCase('Bakau LRT Station'), 'Bakau LRT Station');
    expect(titleCase('(EW2) tampines'), '(EW2) Tampines');
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

  test('trip board: the bus to leave for first, buses too soon to catch dimmed at the end', () {
    const a = BusEta(service: '47', minutes: 2, load: 'SEA'); // too soon for a 4 min walk
    const b = BusEta(service: '12', minutes: 9, load: 'SEA');
    const c = BusEta(service: '36', minutes: 6, load: 'SEA');
    const d = BusEta(service: '3', minutes: 1, load: 'SEA'); // too soon
    final grouped = [(d, null), (a, 12), (c, 15), (b, null)];
    final lb = leaveBy(grouped, null, 4)!;
    expect(lb.service, '36'); // leave in 2 min
    final rows = tripBoard(grouped, lb, 4);
    expect([for (final r in rows) r.eta.service], ['36', '12', '3', '47']);
    expect(rows.last.next, 12); // a bus too soon still shows its next one
    expect([for (final r in rows) r.tooSoon], [false, false, true, true]);
    // Leaving for the next 47 (its first is too soon): the next one on top, the first one dimmed below.
    final only47 = tripBoard([(a, 12)], leaveBy([(a, 12)], null, 4), 4);
    expect([for (final r in only47) (r.eta.service, r.eta.minutes, r.next, r.tooSoon)],
        [('47', 12, null, false), ('47', 2, null, true)]);
    // Wheelchair and deck belong to the first bus: the next one's row does not claim them.
    final wab = tripBoard([(const BusEta(service: '47', minutes: 2, load: 'SEA', wheelchair: true, deck: 'DD'), 12)],
        leaveBy([(a, 12)], null, 4), 4);
    expect((wab.first.eta.wheelchair, wab.first.eta.deck), (false, ''));
    // Start not near the stop: no walk, so nothing is too soon and the order stays.
    final far = tripBoard(grouped, null, null);
    expect([for (final r in far) r.eta.service], ['3', '47', '36', '12']);
    expect(far.any((r) => r.tooSoon), isFalse);
    // At the stop (no walk): the bus there now is the one to catch, not "too soon".
    const now = BusEta(service: '15', minutes: 0, load: 'SEA');
    final atStop = tripBoard([(now, 8)], leaveBy([(now, 8)], null, 0), 0);
    expect((atStop.single.eta.minutes, atStop.single.tooSoon), (0, false));
    expect(leaveBy([(now, 8)], null, 0)!.leaveIn, 0);
  });

  test('trip planner ends: picking the other end swaps, tapping the destination again clears it', () {
    // From Home to Work; picking Work as the start swaps the two.
    expect(pickTripEnd(isFrom: true, key: 'work', from: 'home', to: 'work', fallback: 'here'), (from: 'work', to: 'home'));
    expect(pickTripEnd(isFrom: false, key: 'home', from: 'home', to: 'work', fallback: 'here'), (from: 'work', to: 'home'));
    // No clash: only that end changes.
    expect(pickTripEnd(isFrom: true, key: 'here', from: 'home', to: 'work', fallback: 'here'), (from: 'here', to: 'work'));
    expect(pickTripEnd(isFrom: false, key: 'extra:0', from: 'home', to: 'work', fallback: 'here'),
        (from: 'home', to: 'extra:0'));
    // The start picked as the first destination: the start moves to the fallback.
    expect(pickTripEnd(isFrom: false, key: 'home', from: 'home', to: null, fallback: 'here'), (from: 'here', to: 'home'));
    // Tapping the picked destination again clears it.
    expect(pickTripEnd(isFrom: false, key: 'work', from: 'home', to: 'work', fallback: 'here'), (from: 'home', to: null));
    // A new search on the destination picks it again, never clears it.
    expect(pickTripEnd(isFrom: false, key: 'adhoc', from: 'home', to: 'adhoc', fallback: 'here'), (from: 'home', to: 'adhoc'));
    // Two searched addresses are different places: no swap.
    expect(pickTripEnd(isFrom: true, key: 'adhoc', from: 'home', to: 'adhoc', fallback: 'here'), (from: 'adhoc', to: 'adhoc'));
  });

  test('no orphan: the last two words stay together, so one word never sits alone on a line', () {
    expect(noOrphan('From stop: Marine Pde Stn Exit 6'), 'From stop: Marine Pde Stn Exit 6');
    expect(noOrphan('Alone'), 'Alone');
    const s = S();
    expect(s.leaveInHead('36', 7), 'Leave in 7 min to catch 36');
    expect(s.leaveInHead('36', 0), 'Leave now to catch 36');
    expect(s.walkToStopThenBus(0, 2), "You're at the stop\u00A0· bus\u00A0in\u00A02\u00A0min");
    expect(s.walkToStopThenBus(3, 10), '3 min walk to the stop\u00A0· bus\u00A0in\u00A010\u00A0min');
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
    expect(cleanPlaceName('BLK 65A MARINE DRIVE #01-04'), 'Blk 65A Marine Drive #01-04');
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
    expect(const S().busInfo(e), 'Seats free · ♿ Wheelchair · Single deck');
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

    test('parkTime says it is night when the weather is fine after dark', () {
      DateTime at(int h, int m) => DateTime(2026, 11, 9, h, m);
      expect(isParkNight(at(19, 29)), isFalse);
      expect(isParkNight(at(19, 30)), isTrue);
      expect(isParkNight(at(2, 0)), isTrue);
      expect(isParkNight(at(6, 59)), isTrue);
      expect(isParkNight(at(7, 0)), isFalse);
      expect(parkTime(now: at(19, 29)), ParkTime.good);
      expect(parkTime(now: at(20, 30)), ParkTime.goodNight);
      expect(parkTime(now: at(5, 0)), ParkTime.goodNight);
      // Weather warnings still come first at night.
      expect(parkTime(now: at(21, 0), lightning: true), ParkTime.lightning);
      expect(parkTime(now: at(21, 0), rainMm: 0.4), ParkTime.rain);
      expect(parkTime(now: at(21, 0), air: AirLevel.unhealthy), ParkTime.haze);
      expect(parkTime(now: at(21, 0), showersForecast: true), ParkTime.showers);
      // Heat stress is a daytime tip ("go after 5 pm"), not shown after dark.
      expect(parkTime(now: at(21, 0), heat: 'High'), ParkTime.goodNight);
    });
  });

  test('school alerts only on days with class', () {
    final heat = {
      'data': {
        'data': {
          'records': [
            {
              'item': {
                'readings': [
                  {'location': {'latitude': '1.354', 'longitude': '103.943'}, 'wbgt': '33', 'heatStress': 'High'},
                ],
              },
            },
          ],
        },
      },
    };
    final lightning = {
      'data': {
        'data': {
          'records': [
            {
              'item': {
                'readings': [
                  {'location': {'latitude': '1.354', 'longitude': '103.943'}, 'type': 'C'},
                ],
              },
            },
          ],
        },
      },
    };
    const fav = Favorites(places: {PlaceKind.school: Place(kind: PlaceKind.school, stops: [tampines])});
    final off = DaysOff(school: [SchoolHoliday(DateTime(2026, 11, 21), DateTime(2026, 12, 31), 'Year-end holidays')]);
    List<AlertKind> kinds(DateTime now) => [
          for (final a in todayAlerts(
              fav: fav, now: now, s: const S(), wbgt: heat, lightning: lightning, off: off))
            a.kind,
        ];
    expect(isSchoolDay(fav, DateTime(2026, 10, 26), off), isTrue); // Monday
    expect(kinds(DateTime(2026, 10, 26, 10)), containsAll([AlertKind.heat, AlertKind.lightning]));
    expect(isSchoolDay(fav, DateTime(2026, 10, 24), off), isFalse); // Saturday
    expect(kinds(DateTime(2026, 10, 24, 10)), isEmpty);
    expect(isSchoolDay(fav, DateTime(2026, 11, 23), off), isFalse); // Monday, year-end holidays
    expect(kinds(DateTime(2026, 11, 23, 10)), isEmpty);
  });

  test('bad numbers from upstream are skipped, not thrown', () {
    final body = {
      'data': {
        'data': {
          'records': [
            {
              'item': {
                'readings': [
                  {'location': {'latitude': 'n/a', 'longitude': '103.9'}},
                  {'location': {'latitude': '1.354', 'longitude': '103.943'}},
                ],
              },
            },
          ],
        },
      },
    };
    expect(lightningNear(body, tampines.lat, tampines.lng), isTrue);
    expect(nextPrayerIndex(['xx:yy', '07:00', '13:00'], DateTime(2026, 10, 24, 6)), 1);
  });

  test('Today goes back to the top after 30 minutes away or a new card', () {
    final away = DateTime(2026, 10, 24, 9);
    bool top(DateTime now, [CardKind before = CardKind.morning, CardKind after = CardKind.morning]) =>
        todayBackToTop(awaySince: away, now: now, cardBefore: before, cardNow: after);
    expect(top(DateTime(2026, 10, 24, 9, 10)), isFalse);
    expect(top(DateTime(2026, 10, 24, 9, 30)), isTrue);
    expect(top(DateTime(2026, 10, 24, 9, 5), CardKind.morning, CardKind.evening), isTrue);
  });

  test('wakeEvent wakes inside the radius and spots a passed stop', () {
    expect(wakeEvent(900, 500, null), WakeEvent.none);
    expect(wakeEvent(450, 500, 900), WakeEvent.wake);
    // Came to 600 m (GPS gap, never inside 500 m), now 950 m away: probably passed.
    expect(wakeEvent(950, 500, 600), WakeEvent.passed);
    // Still approaching or a small wobble: nothing.
    expect(wakeEvent(700, 500, 600), WakeEvent.none);
    // Never came close: moving away is not "passed".
    expect(wakeEvent(2000, 500, 1500), WakeEvent.none);
  });

  test('family share: sender picks, receiver keeps their own places', () {
    const home = Place(kind: PlaceKind.home, stops: [tampines]);
    const work = Place(kind: PlaceKind.work, stops: [raffles]);
    const school = Place(kind: PlaceKind.school, addrLat: 1.3353, addrLng: 103.7021);
    const sender = Favorites(
      places: {PlaceKind.home: home, PlaceKind.work: work, PlaceKind.school: school},
      lines: {'EWL'},
      hawkers: {'h1', 'h2'},
    );
    // Default choice: home and school, lines on, hawkers off.
    final imp = readShareCode(encodeShareCode(sender, const ShareChoice()))!;
    expect(imp.places.keys.toSet(), {PlaceKind.home, PlaceKind.school});
    expect(imp.lines, {'EWL'});
    expect(imp.hawkers, isEmpty);

    // Receiver already has their own work and a different school.
    const mySchool = Place(kind: PlaceKind.school, addrLat: 1.40, addrLng: 103.90);
    const myWork = Place(kind: PlaceKind.work, addrLat: 1.28, addrLng: 103.85);
    const me = Favorites(
      places: {PlaceKind.work: myWork, PlaceKind.school: mySchool},
      hawkers: {'h9'},
      showPrayer: true,
    );
    expect(shareConflicts(imp, me), {PlaceKind.school});
    final after = applyShare(me, imp, take: {PlaceKind.home});
    expect(after.places[PlaceKind.home]!.stops.single.code, '75009');
    expect(after.places[PlaceKind.school]!.lat, 1.40); // not replaced
    expect(after.places[PlaceKind.work]!.lat, 1.28); // not in the code, untouched
    expect(after.lines, {'EWL'});
    expect(after.showPrayer, isTrue);

    // Hawkers are added to the receiver's own.
    final withHawkers = readShareCode(encodeShareCode(sender, const ShareChoice(places: {}, lines: false, hawkers: true)))!;
    expect(withHawkers.places, isEmpty);
    expect(withHawkers.lines, isNull);
    expect(applyShare(me, withHawkers, take: const {}).hawkers, {'h1', 'h2', 'h9'});
    // A sender with no starred lines does not clear the receiver's; their times still come along.
    const noLines = Favorites(places: {PlaceKind.home: home}, leaveHome: TimeOfDayHM(8, 15));
    final empty = readShareCode(encodeShareCode(noLines, const ShareChoice()))!;
    expect(empty.lines, isEmpty);
    const starred = Favorites(lines: {'NSL', 'CCL'});
    final kept = applyShare(starred, empty, take: const {});
    expect(kept.lines, {'NSL', 'CCL'});
    expect(kept.leaveHome.toString(), const TimeOfDayHM(8, 15).toString());

    // A code with nothing in it is not a code.
    expect(readShareCode(encodeShareCode(sender, const ShareChoice(places: {}, lines: false))), isNull);
  });

  test('family share: a place with no position is left out of the code', () {
    String code(Object payload) => 'DL1:${base64Url.encode(utf8.encode(jsonEncode(payload)))}';
    const noPoint = {'kind': 'home', 'addr': '1 Nowhere Road'};
    const onlyLat = {'kind': 'work', 'la': 1.3};
    const school = {'kind': 'school', 'la': 1.3353, 'lo': 103.7021};
    const me = Favorites(places: {
      PlaceKind.home: Place(kind: PlaceKind.home, addrLat: 1.37, addrLng: 103.84),
      PlaceKind.school: Place(kind: PlaceKind.school, addrLat: 1.40, addrLng: 103.90),
    });

    // Nothing else in the code: not a code.
    expect(readShareCode(code({'p': [noPoint]})), isNull);
    expect(readShareCode(code({'p': [onlyLat]})), isNull);

    // The rest of the code still counts, and nothing throws for the receiver.
    final imp = readShareCode(code({'p': [noPoint, onlyLat, school], 'k': ['h1']}))!;
    expect(imp.places.keys.toSet(), {PlaceKind.school});
    expect(shareConflicts(imp, me), {PlaceKind.school});
    final after = applyShare(me, imp, take: {PlaceKind.school});
    expect(after.places[PlaceKind.home]!.lat, 1.37);
    expect(after.places[PlaceKind.school]!.lat, 1.3353);
    expect(after.hawkers, {'h1'});

    // A place saved from such a code by an older version is dropped when settings are read.
    final stored = Favorites.fromJson({
      'places': [noPoint, onlyLat, school],
    });
    expect(stored.places.keys.toSet(), {PlaceKind.school});

    // A place the receiver saved without a position counts as different, it does not throw.
    const old = Favorites(places: {PlaceKind.school: Place(kind: PlaceKind.school)});
    expect(shareConflicts(imp, old), {PlaceKind.school});
  });

  test('history: entries by period, day groups and totals', () {
    final now = DateTime(2026, 10, 25, 9); // Sunday
    final h = Habits(
      trips: [
        TripLog(route: 'home>work', start: DateTime(2026, 10, 20, 7, 30), minutes: 40, costCents: 200),
        TripLog(route: 'work>home', start: DateTime(2026, 10, 20, 18), minutes: 50),
        TripLog(route: 'home>work', start: DateTime(2026, 10, 2, 7), minutes: 45),
      ],
      parkings: [ParkLog(name: 'Mall', start: DateTime(2026, 10, 24, 14), minutes: 90, costCents: 300)],
      meals: [MealLog(hawkerId: 'h1', at: DateTime(2026, 10, 25, 8))],
    );
    expect(historySince(HistoryPeriod.week, now), DateTime(2026, 10, 19));
    expect(historySince(HistoryPeriod.month, now), DateTime(2026, 10, 1));
    final week = historyEntries(h, since: historySince(HistoryPeriod.week, now));
    expect(week.map((e) => e.kind), [HistoryKind.meal, HistoryKind.parking, HistoryKind.trip, HistoryKind.trip]);
    final sum = historySummary(week);
    expect((sum.trips, sum.tripMinutes, sum.parkings, sum.parkMinutes, sum.meals, sum.costCents), (2, 90, 1, 90, 1, 500));
    expect(historyEntries(h, since: historySince(HistoryPeriod.month, now)).length, 5);
    final days = historyByDay(week);
    expect(days.map((d) => d.$1), [DateTime(2026, 10, 25), DateTime(2026, 10, 24), DateTime(2026, 10, 20)]);
    expect(days.last.$2.length, 2);
    // Parking under 5 minutes is not kept; a round trip through JSON keeps the new fields.
    expect(parkMinutes(DateTime(2026, 10, 25, 8), DateTime(2026, 10, 25, 8, 3)), isNull);
    final back = Habits.fromJson(Habits(
      trips: [TripLog(route: 'home>work', start: now, minutes: 30, mode: 'transit', km: 12.5, costCents: 189)],
      parkings: [ParkLog(name: 'Mall', start: now, minutes: 60)],
    ).toJson());
    expect((back.trips.single.mode, back.trips.single.km, back.trips.single.costCents), ('transit', 12.5, 189));
    expect(back.parkings.single.minutes, 60);
    // Old saved habits (no new keys) still load.
    expect(Habits.fromJson({'trips': [], 'meals': []}).parkings, isEmpty);
  });

  test('meal date: a late meal moves to the day it was eaten, never into the future', () {
    final now = DateTime(2026, 11, 19, 9, 30, 42);
    // Logged this morning, eaten yesterday at the same time of day.
    expect(mealOnDay(DateTime(2026, 11, 19, 9, 4), DateTime(2026, 11, 18), now), DateTime(2026, 11, 18, 9, 4));
    // Across a month and a year end.
    expect(mealOnDay(DateTime(2026, 11, 1, 12, 15), DateTime(2026, 10, 31), now), DateTime(2026, 10, 31, 12, 15));
    // A dinner moved to today before dinner time becomes now (to the minute).
    expect(mealOnDay(DateTime(2026, 11, 17, 19), DateTime(2026, 11, 19), now), DateTime(2026, 11, 19, 9, 30));
    // The picker goes a year back, or to the meal's own day when that is older.
    expect(mealFirstDay(DateTime(2026, 11, 18, 12), now), DateTime(2025, 11, 19));
    expect(mealFirstDay(DateTime(2025, 3, 2, 12), now), DateTime(2025, 3, 2));
  });

  test('spending chart: bars per day or month by kind, average, top day and last period', () {
    final now = DateTime(2026, 11, 19, 9); // Thursday
    final h = Habits(
      trips: [
        TripLog(route: 'home>work', start: DateTime(2026, 11, 16, 8), minutes: 40, costCents: 200),
        TripLog(route: 'work>home', start: DateTime(2026, 11, 18, 18), minutes: 40, costCents: 150),
        TripLog(route: 'home>work', start: DateTime(2026, 11, 10, 8), minutes: 40, costCents: 300), // last Tuesday
        TripLog(route: 'home>work', start: DateTime(2026, 11, 13, 8), minutes: 40, costCents: 900), // last Friday
      ],
      parkings: [ParkLog(name: 'Mall', start: DateTime(2026, 11, 18, 14), minutes: 90, costCents: 350)],
      meals: [
        MealLog(hawkerId: 'a', at: DateTime(2026, 11, 18, 12), priceCents: 2000),
        MealLog(hawkerId: 'a', at: DateTime(2026, 11, 19, 8)), // no price: not counted
        MealLog(hawkerId: 'a', at: DateTime(2026, 9, 30, 12), priceCents: 500),
      ],
    );
    List<HistoryEntry> of(HistoryPeriod p) => historyEntries(h, since: historySince(p, now));

    final week = historySpendBars(of(HistoryPeriod.week), HistoryPeriod.week, now);
    expect(week.map((b) => b.start.day), [16, 17, 18, 19, 20, 21, 22]);
    expect(week.map((b) => b.cents), [200, 0, 2500, 0, 0, 0, 0]);
    expect((week[2].mealCents, week[2].tripCents, week[2].parkingCents), (2000, 150, 350));
    final prev = historyPreviousCents(h, HistoryPeriod.week, now, {});
    expect(prev, 300, reason: 'last Monday to Thursday, not the Friday after');
    final ins = historySpendInsight(week, HistoryPeriod.week, now, previousCents: prev);
    expect((ins.cents, ins.averageCents, ins.top?.start, ins.previousCents), (2700, 675, DateTime(2026, 11, 18), 300));
    // Same point of the day: last Thursday's lunch does not count at 9:00 this Thursday.
    final lunch = Habits(meals: [MealLog(hawkerId: 'a', at: DateTime(2026, 11, 12, 12), priceCents: 700)]);
    expect(historyPreviousCents(lunch, HistoryPeriod.week, now, {}), 0);
    expect(historyPreviousCents(lunch, HistoryPeriod.week, DateTime(2026, 11, 19, 12), {}), 700);
    // A full trip log that starts after last Monday knows only part of last week: no comparison.
    final full = Habits(trips: [
      for (var i = 0; i < Habits.maxTrips; i++)
        TripLog(route: 'home>work', start: DateTime(2026, 11, 11, 8).add(Duration(hours: i)), minutes: 30, costCents: 100),
    ]);
    expect(historyPreviousCents(full, HistoryPeriod.week, now, {}), isNull);
    expect(historyPreviousCents(full, HistoryPeriod.week, now, {HistoryKind.meal}), 0);
    // Only trips shown: the comparison follows the filter.
    expect(historyPreviousCents(h, HistoryPeriod.week, now, {HistoryKind.meal}), 0);

    final month = historySpendBars(of(HistoryPeriod.month), HistoryPeriod.month, now);
    expect(month.length, 30);
    expect(month.fold(0, (a, b) => a + b.cents), 3900);
    expect(historyPreviousCents(h, HistoryPeriod.month, now, {}), 0, reason: '1 to 19 October');
    expect(historySpendInsight(month, HistoryPeriod.month, now).averageCents, (3900 / 19).round());

    final all = historySpendBars(of(HistoryPeriod.all), HistoryPeriod.all, now);
    expect(all.map((b) => (b.start.month, b.cents)), [(9, 500), (10, 0), (11, 3900)]);
    expect(historyPreviousCents(h, HistoryPeriod.all, now, {}), isNull);
    expect(historySpendInsight(all, HistoryPeriod.all, now).averageCents, (4400 / 3).round());
    // One day with spending has no "most on".
    expect(historySpendInsight([week[0]], HistoryPeriod.week, now).top, isNull);
    // "All" keeps the last 12 months.
    final old = [HistoryEntry(HistoryKind.meal, DateTime(2024, 1, 5), const Object(), costCents: 100)];
    final capped = historySpendBars(old, HistoryPeriod.all, now);
    expect((capped.length, capped.first.start, capped.fold(0, (a, b) => a + b.cents)), (12, DateTime(2025, 12), 0));
  });

  test('meal price: saved as cents, optional, and old meals without one load unchanged', () {
    final at = DateTime(2026, 11, 10, 12, 30);
    final priced = MealLog(hawkerId: 'h1', at: at, priceCents: 550);
    expect(priced.toJson()['c'], 550);
    final back = MealLog.fromJson(priced.toJson());
    expect((back.hawkerId, back.at, back.priceCents), ('h1', at, 550));
    // Without a price nothing new is written, so a 2.2.0 build reads it the same way.
    final plain = MealLog(hawkerId: 'p:1.35000,103.94000', at: at, name: 'Test Kitchen');
    expect(plain.toJson().keys.toSet(), {'h', 'at', 'n'});
    expect(MealLog.fromJson(plain.toJson()).priceCents, isNull);
    // A meal saved by 2.2.0 (no 'c'), and odd values, load without a price instead of failing.
    final old = MealLog.fromJson({'h': 'h1', 'at': '2026-10-27T12:00:00.000'});
    expect((old.hawkerId, old.priceCents, old.name), ('h1', null, null));
    expect(MealLog.fromJson({'h': 'h1', 'at': '2026-10-27T12:00:00.000', 'c': 'x'}).priceCents, isNull);
    expect(MealLog.fromJson({'h': 'h1', 'at': '2026-10-27T12:00:00.000', 'c': -5}).priceCents, isNull);
    // Changing the time keeps the price, and the other way round.
    expect(priced.withTime(at.subtract(const Duration(hours: 1))).priceCents, 550);
    expect(priced.withPrice(null).priceCents, isNull);
    expect(plain.withPrice(400).name, 'Test Kitchen');
    // A whole Habits round trip keeps priced and unpriced meals as they were.
    final h = Habits.fromJson(Habits(meals: [plain, priced]).toJson());
    expect(h.meals.map((m) => m.priceCents), [null, 550]);
  });

  test('meal price: typed amounts, chips and the last price per place', () {
    expect(parseMealCents('5.5'), 550);
    expect(parseMealCents(r'$12.80'), 1280);
    expect(parseMealCents('4,20'), 420);
    expect(parseMealCents('200'), 20000);
    expect(parseMealCents('200.01'), isNull, reason: r'more than $200 is a typo');
    expect(parseMealCents('1.234'), isNull, reason: '2 decimals at most');
    expect(parseMealCents('0'), isNull);
    expect(parseMealCents(''), isNull);
    expect(parseMealCents('abc'), isNull);
    expect(mealPriceChips, [400, 600, 800]);
    expect(const S().moneyShort(400), r'$4');
    expect(const S().moneyShort(550), r'$5.50');

    final t = DateTime(2026, 11, 3, 12);
    final meals = [
      MealLog(hawkerId: 'a', at: t, priceCents: 400),
      MealLog(hawkerId: 'b', at: t.add(const Duration(days: 1)), priceCents: 800),
      MealLog(hawkerId: 'a', at: t.add(const Duration(days: 2)), priceCents: 600),
      // The newest meal at 'a' has no price: the last price paid there is still offered.
      MealLog(hawkerId: 'a', at: t.add(const Duration(days: 3))),
    ];
    expect(lastMealPrice(meals, 'a'), 600);
    expect(lastMealPrice(meals, 'b'), 800);
    expect(lastMealPrice(meals, 'c'), isNull);
    // Order in the list does not matter, only when the meal was eaten.
    expect(lastMealPrice(meals.reversed.toList(), 'a'), 600);
    // Two restaurants on the same point of a food court: only the one with the same name.
    final court = [
      MealLog(hawkerId: 'p:1.30000,103.90000', at: t, name: 'Briyani Shop', priceCents: 1200),
    ];
    expect(lastMealPrice(court, 'p:1.30000,103.90000', name: 'Briyani Shop'), 1200);
    expect(lastMealPrice(court, 'p:1.30000,103.90000', name: 'Coffee Bean'), isNull);
  });

  test('meal price: Ate here offers the price of the meal it corrects, else the last one there', () {
    final t = DateTime(2026, 11, 3, 12);
    final meals = [
      MealLog(hawkerId: 'b', at: t.subtract(const Duration(days: 1)), priceCents: 400),
      MealLog(hawkerId: 'a', at: t, priceCents: 600),
    ];
    // $6 at the wrong place a few minutes ago: the corrected tap at 'b' starts on $6.
    expect(mealPriceToOffer(meals, 'b', t.add(const Duration(minutes: 5))), 600);
    // Later that day it is a new meal: the last price at 'b'.
    expect(mealPriceToOffer(meals, 'b', t.add(const Duration(hours: 5))), 400);
    expect(mealPriceToOffer(meals, 'c', t.add(const Duration(hours: 5))), isNull);
    // A recent meal without a price offers none, so a cleared price stays cleared.
    final cleared = [...meals, MealLog(hawkerId: 'c', at: t.add(const Duration(minutes: 10)))];
    expect(mealPriceToOffer(cleared, 'c', t.add(const Duration(minutes: 12))), isNull);
    // The merge itself keeps exactly what the newer tap says.
    final merged = addMeal(meals, MealLog(hawkerId: 'b', at: t.add(const Duration(minutes: 5))));
    expect(merged.map((m) => (m.hawkerId, m.priceCents)), [('b', 400), ('b', null)]);
  });

  test('History week total counts priced meals only and says how many have a price', () {
    final now = DateTime(2026, 11, 8, 20); // Sunday
    final h = Habits(
      trips: [TripLog(route: 'home>work', start: DateTime(2026, 11, 3, 8), minutes: 40, costCents: 200)],
      meals: [
        MealLog(hawkerId: 'a', at: DateTime(2026, 11, 3, 12), priceCents: 400),
        MealLog(hawkerId: 'b', at: DateTime(2026, 11, 4, 12)),
        MealLog(hawkerId: 'a', at: DateTime(2026, 11, 5, 12), priceCents: 550),
        MealLog(hawkerId: 'c', at: DateTime(2026, 11, 6, 12)),
        MealLog(hawkerId: 'b', at: DateTime(2026, 11, 7, 12), priceCents: 800),
        // Last week: not in this week's total.
        MealLog(hawkerId: 'a', at: DateTime(2026, 10, 30, 12), priceCents: 1000),
      ],
    );
    final week = historyEntries(h, since: historySince(HistoryPeriod.week, now));
    final sum = historySummary(week);
    expect((sum.meals, sum.mealsPriced, sum.mealCents), (5, 3, 1750));
    expect(sum.costCents, 200 + 1750);
    expect(const S().mealsPriced(sum.mealsPriced, sum.meals, sum.mealCents), r'$17.50 · 3 of 5 priced');
    // A meal's row shows its own price, never as an estimate.
    final row = week.firstWhere((e) => e.kind == HistoryKind.meal);
    expect((row.costCents, row.estimated), (800, false));
    expect(week.where((e) => e.kind == HistoryKind.meal && e.costCents == null).length, 2);
    // No priced meal: nothing to add.
    final none = historySummary(historyEntries(Habits(meals: [MealLog(hawkerId: 'a', at: now)])));
    expect((none.meals, none.mealsPriced, none.mealCents, none.costCents), (1, 0, 0, 0));
  });

  test('fares, parking and costs on History', () {
    final oct = DateTime(2026, 10, 25);
    expect(adultCardFare(2.0, oct), 128);
    expect(adultCardFare(3.2, oct), 128);
    expect(adultCardFare(3.3, oct), 138);
    expect(adultCardFare(4.2, oct), 138);
    expect(adultCardFare(10.0, oct), 186);
    expect(adultCardFare(55, oct), 257);
    // From 26 Dec 2026: +12 c up to 3.2 km, +13 c beyond.
    expect(adultCardFare(2.0, DateTime(2026, 12, 26)), 140);
    expect(adultCardFare(10.0, DateTime(2027, 1, 5)), 199);

    final bus = TripLog(route: 'home>work', start: oct, minutes: 40, mode: 'transit', km: 7.0);
    expect(tripFareEstimate(bus), adultCardFare(9.1, oct));
    expect(tripFareEstimate(TripLog(route: 'home>work', start: oct, minutes: 40, mode: 'car', km: 7)), isNull);
    expect(tripFareEstimate(TripLog(route: 'home>work', start: oct, minutes: 40)), isNull);

    // HDB: 15 min free, $0.60 per half hour, central $1.20 Mon-Sat 7am-5pm, caps.
    final mon10 = DateTime(2026, 10, 26, 10);
    expect(hdbParkingCost(mon10, 15), 0);
    expect(hdbParkingCost(mon10, 60), 120);
    expect(hdbParkingCost(mon10, 60, central: true), 240);
    expect(hdbParkingCost(DateTime(2026, 10, 25, 10), 60, central: true), 120); // Sunday
    expect(hdbParkingCost(DateTime(2026, 10, 26, 7), 15 * 60), 1200); // day cap
    expect(hdbParkingCost(DateTime(2026, 10, 26, 23), 7 * 60), 500); // night cap

    final park = ParkLog(name: 'Blk 1', start: mon10, minutes: 90, hdb: true);
    final mall = ParkLog(name: 'Mall', start: mon10, minutes: 90);
    expect(parkingEstimate(park), 180);
    expect(parkingEstimate(mall), isNull);

    // Entered amounts win over estimates; estimates count in the total.
    final h = Habits(trips: [bus, bus.withCost(300)], parkings: [park, mall.withCost(450)]);
    final entries = historyEntries(h);
    expect(entries.where((e) => e.estimated && e.costCents != null).length, 2);
    expect(historySummary(entries).costCents, tripFareEstimate(bus)! + 300 + 180 + 450);
    expect(historyOfKinds(entries, {HistoryKind.parking}).length, 2);

    expect(parseCents('2.19'), 219);
    expect(parseCents(r'$ 2'), 200);
    expect(parseCents('2,5'), 250);
    expect(parseCents('abc'), isNull);
    expect(parseCents(''), isNull);
  });

  test('two Ate here taps within 30 minutes are one meal', () {
    final t = DateTime(2026, 10, 25, 12);
    var meals = addMeal(const [], MealLog(hawkerId: 'a', at: t));
    meals = addMeal(meals, MealLog(hawkerId: 'b', at: t.add(const Duration(minutes: 1))));
    meals = addMeal(meals, MealLog(hawkerId: 'c', at: t.add(const Duration(minutes: 2))));
    expect(meals.map((m) => m.hawkerId), ['c']);
    meals = addMeal(meals, MealLog(hawkerId: 'd', at: t.add(const Duration(hours: 6))));
    expect(meals.map((m) => m.hawkerId), ['c', 'd']);
  });

  test('meals at halal restaurants are logged by place with their name', () {
    final id = mealPlaceId(1.342271, 103.953094);
    expect(id, 'p:1.34227,103.95309');
    final m = MealLog(hawkerId: id, at: DateTime(2026, 10, 27, 13), name: 'Some Halal Kitchen');
    final back = MealLog.fromJson(m.toJson());
    expect(back.hawkerId, id);
    expect(back.name, 'Some Halal Kitchen');
    // Hawker meals keep the old format (no name).
    expect(MealLog(hawkerId: 'a', at: DateTime(2026, 10, 27)).toJson().containsKey('n'), isFalse);
    expect(MealLog.fromJson({'h': 'a', 'at': '2026-10-27T12:00:00.000'}).name, isNull);
    final h = Habits(meals: [m]);
    expect(historyEntries(h).single.source, isA<MealLog>());
    expect(historySummary(historyEntries(h)).meals, 1);
  });

  test('restaurant meals do not hide the hawker nudge', () {
    Hawker hk(String id, double lo) => Hawker.fromBundle({'id': id, 'n': 'H$id', 'a': '', 'la': 1.30, 'lo': lo});
    final all = [hk('a', 103.860), hk('b', 103.865)];
    final now = DateTime(2026, 10, 27, 12);
    final meals = [
      for (var i = 0; i < 5; i++) MealLog(hawkerId: mealPlaceId(1.3, 103.9), at: now.subtract(Duration(days: i)), name: 'R'),
      for (var i = 0; i < 3; i++) MealLog(hawkerId: 'a', at: now.subtract(Duration(days: i, hours: 6))),
    ];
    final n = mealNudge(meals, all, now, 1.30, 103.860)!;
    expect(n.usual.id, 'a');
    expect(n.times, 3);
  });

  test('a meal logged late can be moved to when it was eaten, never into the future', () {
    final logged = DateTime(2026, 10, 27, 20, 15);
    final now = DateTime(2026, 10, 27, 20, 16);
    expect(mealTimeOn(logged, 13, 5, now), DateTime(2026, 10, 27, 13, 5));
    expect(mealTimeOn(logged, 21, 0, now), isNull);
    final m = MealLog(hawkerId: 'p:1,2', at: logged, name: 'R');
    final moved = m.withTime(DateTime(2026, 10, 27, 13, 5));
    expect(moved.name, 'R');
    expect(moved.hawkerId, 'p:1,2');
    expect(moved.at.hour, 13);
  });

  test('a coming bus is placed on its route: near which stop and how many stops away', () {
    final now = DateTime.utc(2026, 10, 27, 8, 0);
    final body = {
      'data': {
        'Services': [
          {
            'ServiceNo': '47',
            'NextBus': {
              'EstimatedArrival': '2026-10-27T16:04:00+08:00',
              'Load': 'SEA',
              'Latitude': '1.3302',
              'Longitude': '103.9601',
              'Monitored': 1,
            },
          },
          {
            'ServiceNo': '20',
            'NextBus': {'EstimatedArrival': '2026-10-27T16:07:00+08:00', 'Load': 'SEA', 'Latitude': '0.0', 'Longitude': '0.0', 'Monitored': 0},
          },
        ],
      },
    };
    final etas = parseBusArrival(body, now);
    final b47 = etas.firstWhere((e) => e.service == '47');
    final b20 = etas.firstWhere((e) => e.service == '20');
    expect(b47.lat, closeTo(1.3302, 1e-9));
    expect(b47.monitored, isTrue);
    expect(b20.lat, isNull);
    expect(b20.monitored, isFalse);

    // Route 47 dir 1: A -> B -> C -> MINE; the bus is next to B.
    const a = BusStop(code: 'A', name: 'Stop A', road: '', lat: 1.3200, lng: 103.9600);
    const b = BusStop(code: 'B', name: 'Blk 201', road: '', lat: 1.3300, lng: 103.9600);
    const c = BusStop(code: 'C', name: 'Stop C', road: '', lat: 1.3350, lng: 103.9600);
    const mine = BusStop(code: 'M', name: 'Opp Changi City Pt', road: '', lat: 1.3400, lng: 103.9600);
    final stops = {for (final x in [a, b, c, mine]) x.code: x};
    const routes = BusRoutes({
      '47|1': [('A', 0.0), ('B', 1.1), ('C', 1.7), ('M', 2.2)],
      '470|1': [('M', 0.0), ('B', 1.0)],
    });
    final w = busWhere(b47, 'M', routes, stops)!;
    expect(w.near!.name, 'Blk 201');
    expect(w.stopsAway, 2);
    const s = S();
    expect(s.busWhereLine(w), 'Now near Blk 201 · 2\u00A0stops\u00A0away');
    expect(s.busLive(b20, busWhere(b20, 'M', routes, stops)), s.busScheduled);

    // Off the route (no stop within 400 m): straight-line distance instead.
    const far = BusEta(service: '47', minutes: 9, load: 'SEA', lat: 1.3700, lng: 103.9600);
    final w2 = busWhere(far, 'M', routes, stops)!;
    expect(w2.stopsAway, isNull);
    expect(s.busWhereLine(w2), 'Now 3.3\u00A0km\u00A0away');
    // At the rider's stop.
    const atStop = BusEta(service: '47', minutes: 0, load: 'SEA', lat: 1.3400, lng: 103.9601);
    expect(s.busWhereLine(busWhere(atStop, 'M', routes, stops)!), 'At your stop now');
  });

  test("Where's my bus: the stops left to the rider's stop, with the bus on them", () {
    const a = BusStop(code: 'A', name: 'Stop A', road: '', lat: 1.3200, lng: 103.9600);
    const b = BusStop(code: 'B', name: 'Blk 201', road: '', lat: 1.3300, lng: 103.9600);
    const c = BusStop(code: 'C', name: 'Stop C', road: '', lat: 1.3350, lng: 103.9600);
    const mine = BusStop(code: 'M', name: 'Mine', road: '', lat: 1.3400, lng: 103.9600);
    const z = BusStop(code: 'Z', name: 'Before A', road: '', lat: 1.3100, lng: 103.9600);
    final stops = {for (final x in [z, a, b, c, mine]) x.code: x};
    const routes = BusRoutes({
      '47|1': [('Z', 0.0), ('A', 0.5), ('B', 1.1), ('C', 1.7), ('M', 2.2)],
    });
    // Bus next to B: one passed stop (A) above it, then B (bus), C, Mine.
    const gps = BusEta(service: '47', minutes: 4, load: 'SEA', lat: 1.3301, lng: 103.9600);
    final st = busStrip(gps, 'M', routes, stops)!;
    expect(st.stops.map((x) => x.code), ['A', 'B', 'C', 'M']);
    expect(st.busAt, 1);
    // No position: the last stops before the rider's stop, no bus.
    const blind = BusEta(service: '47', minutes: 4, load: 'SEA', monitored: false);
    final st2 = busStrip(blind, 'M', routes, stops)!;
    expect(st2.stops.map((x) => x.code), ['Z', 'A', 'B', 'C', 'M']);
    expect(st2.busAt, isNull);
    // Other services and unknown stops give nothing.
    expect(busStrip(const BusEta(service: '470', minutes: 1, load: ''), 'M', routes, stops), isNull);
    // Tapping the second arrival opens on it; refreshed times pick the nearest; no tap, the next bus.
    const two = [BusEta(service: '47', minutes: 1, load: ''), BusEta(service: '47', minutes: 15, load: '')];
    expect(busPick(two, 15), 1);
    expect(busPick(two, 16), 1);
    expect(busPick(two, 1), 0);
    expect(busPick(two, null), 0);
    expect(busPick(const [], 15), 0);
    const s = S();
    expect(s.loadLabel('SEA'), 'Seats free');
    expect(s.loadLabel('LSD'), 'Packed');
    expect(s.youTag(0), 'YOU · Arr');
    expect(s.stopsTag(1), '1 stop');
  });

  test("Where's my bus: a bus on a long stretch between two stops is drawn between them", () {
    // Like bus 36 on the ECP: 5.2 km by road from the stop before to the rider's stop, no stop near.
    const a = BusStop(code: 'A', name: 'Stop A', road: '', lat: 1.3000, lng: 103.9000);
    const b = BusStop(code: 'B', name: 'Before the expressway', road: '', lat: 1.3020, lng: 103.9000);
    const mine = BusStop(code: 'M', name: 'Mine', road: '', lat: 1.3400, lng: 103.9000);
    final stops = {for (final x in [a, b, mine]) x.code: x};
    const routes = BusRoutes({
      '36|1': [('A', 0.0), ('B', 0.3), ('M', 5.5)],
    });
    // 1.5 km before the rider's stop, a little off the straight line (the road bends).
    const onWay = BusEta(service: '36', minutes: 1, load: 'SEA', lat: 1.3266, lng: 103.9030);
    final st = busStrip(onWay, 'M', routes, stops)!;
    expect(st.stops.map((x) => x.code), ['B', 'M']);
    expect(st.busAt, 0);
    expect(st.between, isTrue);
    expect(st.metres, closeTo(1530, 60));
    expect(const S().busOnTheWay(st.metres), 'On the way · 1.5\u00A0km from your\u00A0stop');
    expect(const S().busOnTheWay(420), 'On the way · 400\u00A0m from your\u00A0stop');
    // Next to a stop it is drawn at that stop, as before.
    const atB = BusEta(service: '36', minutes: 9, load: 'SEA', lat: 1.3021, lng: 103.9000);
    final st2 = busStrip(atB, 'M', routes, stops)!;
    expect(st2.between, isFalse);
    expect(st2.stops[st2.busAt!].code, 'B');
    // Far from the road between any two stops: no bus on the strip.
    const lost = BusEta(service: '36', minutes: 9, load: 'SEA', lat: 1.3200, lng: 103.9600);
    final st3 = busStrip(lost, 'M', routes, stops)!;
    expect(st3.busAt, isNull);
    expect(st3.between, isFalse);
  });

  test('EV chargers: plug matching, nearest sites with the plug, and live free counts', () {
    expect(evPlugMatches('Type 2', 'Type 2'), isTrue);
    expect(evPlugMatches('CCS 2', 'CCS2'), isTrue);
    expect(evPlugMatches('CCS2', 'CCS2'), isTrue);
    expect(evPlugMatches('CHAdeMO', 'Type 2'), isFalse);
    expect(evPlugMatches('CHAdeMO', 'any'), isTrue);

    EvSite site(String id, double lat, List<Map<String, dynamic>> pl) => EvSite.fromBundle({
          'id': id,
          'n': 'BLK 65A MARINE DRIVE MULTI STOREY CAR PARK',
          'a': '65A MARINE DRIVE SINGAPORE 441065',
          'pc': '441065',
          'la': lat,
          'lo': 103.91,
          'op': ['STRIDES YTL PTE. LTD.'],
          'pl': pl,
        });
    final type2 = {'t': 'Type 2', 'c': 'AC', 'kw': 7.4, 'p': 0.698, 'pu': 'kWh', 'n': 2};
    final ccs = {'t': 'CCS2', 'c': 'DC', 'kw': 50, 'p': 0.8, 'pu': 'kWh', 'n': 1};
    final sites = [site('A', 1.302, [type2]), site('B', 1.303, [ccs]), site('C', 1.40, [type2])];
    expect(sites.first.name, 'Blk 65A Marine Drive Multi Storey Car Park'); // 65A keeps its capital
    expect(evNear(sites, 1.302, 103.91, 'Type 2').map((e) => e.$1.id), ['A']); // C is too far
    expect(evNear(sites, 1.302, 103.91, 'any').map((e) => e.$1.id), ['A', 'B']);

    final live = EvLive.fromApi({
      'data': [
        {
          'id': 'A',
          'pl': [type2..['a'] = 1, ccs..['a'] = 0],
        },
        {
          'id': 'Z',
          'pl': [
            {'t': 'Type 2', 'kw': 22, 'n': 4, 'a': 4},
          ],
        },
      ],
    });
    expect(evFree(sites[0], live, 'Type 2'), (1, 2));
    expect(evFree(sites[0], live, 'any'), (1, 3));
    expect(evFree(sites[1], live, 'CCS2'), isNull); // B is not in this answer
    const s = S();
    expect(s.evKw(7.4), '7.4 kW');
    expect(s.evKw(50), '50 kW');
    expect(s.evPlugLine(EvPlug.fromJson(type2)), 'Type 2 AC 7.4 kW · \$0.70/kWh');
    expect(s.evPlugFree(EvPlug.fromJson(type2)), '1 of 2 free');
    expect(const Favorites().drivesEv, isFalse);
    expect(Favorites.fromJson(const Favorites(evPlug: 'CCS2').toJson()).evPlug, 'CCS2');
  });

  test('EV live status is matched by name when the daily list has no location ids', () {
    final site = EvSite.fromBundle({
      'id': '',
      'n': 'BLK 65A MARINE DRIVE MULTI STOREY CAR PARK',
      'pc': '441065',
      'la': 1.30297,
      'lo': 103.90991,
      'pl': [
        {'t': 'Type 2', 'c': 'AC', 'kw': 7.4, 'n': 2},
      ],
    });
    final live = EvLive.fromApi({
      'data': [
        {
          'id': '909914441065',
          'n': 'BLK 65A MARINE DRIVE MULTI STOREY CAR PARK',
          'pl': [
            {'t': 'Type 2', 'c': 'AC', 'kw': 7.4, 'n': 2, 'a': 1},
          ],
        },
        {
          'id': '909914441066',
          'n': 'SOMETHING ELSE AT THE SAME POSTAL CODE',
          'pl': [
            {'t': 'Type 2', 'c': 'AC', 'kw': 22, 'n': 4, 'a': 4},
          ],
        },
      ],
    });
    expect(evLiveFor(site, live).single.id, '909914441065');
    expect(evFree(site, live, 'Type 2'), (1, 2));
  });

  test('Trip keys keep home/work/school and use names for other places', () {
    expect(tripRouteKey('home', 'work'), 'home>work');
    expect(tripRouteKey('Near Bugis station', 'ION > Orchard'), 'Near Bugis station>ION › Orchard');
    expect(tripRouteEnds('Near Bugis station>ION › Orchard'), ('Near Bugis station', 'ION › Orchard'));
    expect(tripRouteEnds('nonsense'), isNull);
    expect(const S().routeEnd('work'), 'Work');
    expect(const S().routeEnd('ION Orchard'), 'ION Orchard');
    // Trips logged before the position had a name.
    expect(const S().routeEnd('Here'), 'Current location');
  });

  test("A trip end at the phone's position is named after what is beside it", () {
    const bugis = MrtStation(name: 'Bugis', codes: ['EW12', 'DT14'], lat: 1.3009, lng: 103.8559);
    const stop = BusStop(code: '01113', name: 'Bugis Stn Exit B', road: 'Victoria St', lat: 1.3003, lng: 103.8562);
    const far = BusStop(code: '01559', name: 'Aft Sultan Mque', road: 'Nth Bridge Rd', lat: 1.3030, lng: 103.8600);
    ({PlaceKind? saved, String? station, String? stop}) at(double lat, double lng,
            {List<MrtStation> stations = const [bugis], List<BusStop> stops = const [stop, far]}) =>
        hereName(lat, lng, fav: householdFavorites, stations: stations, stops: stops);
    // A station within 300 m wins over a nearer bus stop.
    expect(at(1.3004, 103.8562), (saved: null, station: 'Bugis', stop: null));
    // No station that near: the nearest bus stop.
    expect(at(1.3031, 103.8601), (saved: null, station: null, stop: 'Aft Sultan Mque'));
    expect(at(1.3004, 103.8562, stations: const []), (saved: null, station: null, stop: 'Bugis Stn Exit B'));
    // Nothing within 300 m, or the bundles not loaded yet.
    expect(at(1.3200, 103.9000), (saved: null, station: null, stop: null));
    expect(at(1.3004, 103.8562, stations: const [], stops: const []), (saved: null, station: null, stop: null));
    // At a saved place: that place, whatever else is near.
    final home = householdFavorites.places[PlaceKind.home]!;
    expect(hereName(home.addrLat!, home.addrLng!, fav: householdFavorites, stations: [
      MrtStation(name: 'X', codes: const ['X1'], lat: home.addrLat!, lng: home.addrLng!),
    ]).saved, PlaceKind.home);
    // A trip to that same saved place is not "Home → Home": the station or stop instead.
    expect(
        hereName(home.addrLat!, home.addrLng!, fav: householdFavorites, otherEnd: PlaceKind.home, stops: [
          BusStop(code: '1', name: 'Blk 156', road: 'Tampines St 12', lat: home.addrLat!, lng: home.addrLng!),
        ]),
        (saved: null, station: null, stop: 'Blk 156'));
    expect(const S().nearPlace(const S().stationName('Bugis')), 'Near Bugis station');
  });

  test('Taxi ease, taxis around a stand and compass direction', () {
    expect(taxiEase(0, 0), 0);
    expect(taxiEase(0, 1), 1);
    expect(taxiEase(1, 4), 2);
    expect(taxiEase(2, 5), 3);
    expect(taxiEase(1, 9), 3);
    expect(taxiEase(5, 6), 4);
    expect(taxiEase(0, 20), 4);
    final pts = [(1.3000, 103.8000), (1.3010, 103.8000), (1.3100, 103.8000)];
    expect(taxisAround(pts, 1.3, 103.8), 2); // 0 m and about 110 m, not 1.1 km
    expect(compass8(0, 100), 0);
    expect(compass8(100, 100), 1);
    expect(compass8(100, 0), 2);
    expect(compass8(0, -100), 4);
    expect(compass8(-100, 0), 6);
    expect(compass8(-100, 100), 7);
    expect(const S().freeTaxiAt(180, 7), 'Free taxi · 180 m north-west · 3 min walk');
  });

  test('MRT ride: stations in order, estimated position, alert and change of line', () {
    const st = [
      MrtStation(name: 'Tampines', codes: ['EW2', 'DT32'], lat: 1.3533, lng: 103.9452),
      MrtStation(name: 'Simei', codes: ['EW3'], lat: 1.3432, lng: 103.9533),
      MrtStation(name: 'Tanah Merah', codes: ['EW4'], lat: 1.3272, lng: 103.9465),
      MrtStation(name: 'Bedok', codes: ['EW5'], lat: 1.324, lng: 103.93),
      MrtStation(name: 'Expo', codes: ['CG1', 'DT35'], lat: 1.3346, lng: 103.9617),
      MrtStation(name: 'Upper Changi', codes: ['DT34'], lat: 1.3417, lng: 103.9613),
      MrtStation(name: 'Tampines East', codes: ['DT33'], lat: 1.3562, lng: 103.9551),
    ];
    final leg = mrtLeg(st, st[3], st[0])!;
    expect(leg.map((x) => x.name), ['Bedok', 'Tanah Merah', 'Simei', 'Tampines']);
    expect(mrtLeg(st, st[1], st[5]), isNull); // no shared line

    const plan = MrtPlan(board: MrtStation(name: 'Tampines', codes: ['EW2', 'DT32'], lat: 1.3533, lng: 103.9452),
        walkToBoard: 300, alight: MrtStation(name: 'Bedok', codes: ['EW5'], lat: 1.324, lng: 103.93), walkFromAlight: 200,
        line: 'EWL', stops: 3);
    final ride = mrtRide(st, plan)!;
    expect(ride.stops, 3);
    expect(ride.lines, {'EWL', 'DTL'});
    expect(rideLineAt(ride, 0), 'EWL');
    final t0 = DateTime(2026, 10, 31, 8);
    expect(rideIndexAt(ride, t0, t0), 0);
    expect(rideIndexAt(ride, t0, t0.add(const Duration(minutes: 3))), 1);
    expect(rideIndexAt(ride, t0, t0.add(const Duration(minutes: 30))), 3);
    expect(rideEta(ride, t0, t0), t0.add(const Duration(minutes: 6)));
    expect(rideAlertDue(ride, 1), isFalse);
    expect(rideAlertDue(ride, 2), isTrue);
    // A GPS fix at Simei (index 1) right after boarding moves the estimate on.
    final fixAt = t0.add(const Duration(seconds: 30));
    expect(rideFixIndex(ride, 1.3432, 103.9533), 1);
    expect(rideIndexAt(ride, t0, fixAt, fixIndex: 1, fixAt: fixAt), 1);
    expect(rideEta(ride, t0, fixAt, fixIndex: 1, fixAt: fixAt), fixAt.add(const Duration(minutes: 4)));

    // With a change of line, the change adds its minutes after the change station.
    const via = MrtPlan(board: MrtStation(name: 'Bedok', codes: ['EW5'], lat: 1.324, lng: 103.93), walkToBoard: 100,
        alight: MrtStation(name: 'Upper Changi', codes: ['DT34'], lat: 1.3417, lng: 103.9613), walkFromAlight: 100,
        via: MrtStation(name: 'Tampines', codes: ['EW2', 'DT32'], lat: 1.3533, lng: 103.9452));
    final r2 = mrtRide(st, via)!;
    expect(r2.stations.map((x) => x.name), ['Bedok', 'Tanah Merah', 'Simei', 'Tampines', 'Tampines East', 'Upper Changi']);
    expect(r2.viaIndex, 3);
    expect(rideMinutesTo(r2, 3), 6);
    expect(rideMinutesTo(r2, 4), 13);
    expect(rideLineAt(r2, 3), 'DTL');
  });

  group('home screen widget', () {
    const s = S();
    Map<String, dynamic> train({String? line}) => {
          'data': {
            'value': line == null
                ? {'Status': 1, 'AffectedSegments': [], 'Message': []}
                : {
                    'Status': 2,
                    'AffectedSegments': [
                      {'Line': line, 'Stations': 'PSR,TAM', 'FreePublicBus': '', 'FreeMRTShuttle': ''},
                    ],
                    'Message': [],
                  },
          },
        };

    test('forecast text and icon key', () {
      expect(shortForecast('Partly Cloudy (Night)'), 'Partly Cloudy');
      expect(shortForecast('Thundery Showers'), 'Thundery Showers');
      final noon = DateTime(2026, 10, 20, 12);
      final night = DateTime(2026, 10, 20, 22);
      expect(weatherKind('Thundery Showers', noon), 'thunder');
      expect(weatherKind('Light Rain', noon), 'rain');
      expect(weatherKind('Passing Showers', night), 'rain');
      expect(weatherKind('Hazy', noon), 'haze');
      expect(weatherKind('Windy', noon), 'wind');
      expect(weatherKind('Cloudy', noon), 'cloud');
      expect(weatherKind('Partly Cloudy (Day)', night), 'partly_day');
      expect(weatherKind('Partly Cloudy (Night)', noon), 'partly_night');
      expect(weatherKind('Fair', noon), 'sun');
      expect(weatherKind('Fair', night), 'moon');
    });

    test('morning: weather, MRT, the trip to work and the top alert', () {
      final here = forecastNear(forecastBody(), tampines.lat, tampines.lng);
      final d = widgetData(
        s: s,
        fav: householdFavorites,
        now: tuesdayMorning,
        here: here,
        lines: lineStatuses(train(), {'EWL', 'DTL'}),
        alerts: const [
          TodayAlert(AlertKind.mrt, 'ignored, MRT has its own row'),
          TodayAlert(AlertKind.rain, 'Rain expected near Work'),
          TodayAlert(AlertKind.lightning, 'Lightning nearby. Stay indoors.'),
          TodayAlert(AlertKind.hawker, 'Hawker closed tomorrow'),
          TodayAlert(AlertKind.dengue, 'Dengue near Home'),
        ],
      );
      expect(d['dl_card'], 'Morning');
      expect(d['dl_place'], 'Tampines');
      expect(d['dl_wx'], 'Thundery Showers');
      expect(d['dl_wx_kind'], 'thunder');
      expect(d['dl_wx_note'], 'Rain expected near Work');
      expect(d['dl_mrt'], 'MRT running normally');
      expect(d['dl_mrt_bad'], '0');
      expect(d['dl_trip'], 'To Work · usual 08.00');
      expect(d['dl_alert'], 'Lightning nearby. Stay indoors.');
      expect(d['dl_alert_more'], '+2 more');
      expect(d['dl_updated'], '${tuesdayMorning.millisecondsSinceEpoch}');
      // The app never checks the bus, so it leaves the background pass's bus alone.
      expect(d.containsKey('dl_bus'), isFalse);
    });

    test('unknown parts are left out, so an update never blanks them', () {
      final d = widgetData(s: s, fav: householdFavorites, now: tuesdayMorning);
      for (final k in ['dl_wx', 'dl_place', 'dl_mrt', 'dl_alert', 'dl_wx_note', 'dl_bus']) {
        expect(d.containsKey(k), isFalse, reason: k);
      }
    });

    test('disruption, evening trip home, and a day off', () {
      final evening = widgetData(
        s: s,
        fav: householdFavorites,
        now: tuesdayEvening,
        lines: lineStatuses(train(line: 'EWL'), {'EWL', 'DTL'}),
        alerts: const [],
      );
      expect(evening['dl_card'], 'Evening');
      expect(evening['dl_mrt'], 'EWL disrupted');
      expect(evening['dl_mrt_bad'], '1');
      expect(evening['dl_trip'], 'Home · usual 18.00');
      expect(evening['dl_alert'], '');
      expect(evening['dl_alert_more'], '');
      expect(widgetData(s: s, fav: householdFavorites, now: saturdayMorning)['dl_trip'], '');
    });

    test('the bus to leave for is a clock time, cleared when the background finds none', () {
      final at = DateTime(2026, 10, 20, 7, 50);
      final d = widgetData(
        s: s,
        fav: householdFavorites,
        now: at,
        bus: const LeaveBy('15', 4, 3),
        busChecked: true,
      );
      expect(d['dl_bus'], 'Bus 15 · leave by 07.54');
      expect(d['dl_bus_at'], '${DateTime(2026, 10, 20, 7, 54).millisecondsSinceEpoch}');
      final none = widgetData(s: s, fav: householdFavorites, now: at, busChecked: true);
      expect(none['dl_bus'], '');
      expect(none['dl_bus_at'], '');
    });

    test('widget taps open Today, Nearby or Home', () {
      expect(tabForWidgetUri(Uri.parse('dailylah://today')), 0);
      expect(tabForWidgetUri(Uri.parse('dailylah://nearby')), 1);
      expect(tabForWidgetUri(Uri.parse('dailylah://home')), 2);
      expect(tabForWidgetUri(Uri.parse('dailylah://more')), isNull);
      expect(tabForWidgetUri(Uri.parse('https://dailylah.sg')), isNull);
      expect(tabForWidgetUri(null), isNull);
      // The lunch suggestion opens Nearby on Eat.
      expect(tabForWidgetUri(Uri.parse('dailylah://nearby/eat')), 1);
      expect(nearbySectionForUri(Uri.parse('dailylah://nearby/eat')), 'eat');
      expect(nearbySectionForUri(Uri.parse('dailylah://nearby')), isNull);
      expect(nearbySectionForUri(Uri.parse('dailylah://today/eat')), isNull);
      expect(nearbySectionForUri(null), isNull);
    });
  });

  group('pick a line for today', () {
    final stations = [
      for (final j in jsonDecode(File('../web/data/mrt_stations.json').readAsStringSync()) as List)
        MrtStation.fromBundle(j as Map<String, dynamic>),
    ];
    const home = Place(kind: PlaceKind.home, addrLat: 1.3030, addrLng: 103.9060); // Marine Parade
    const office = Place(kind: PlaceKind.work, addrLat: 1.2935, addrLng: 103.8612); // Promenade

    test('the usual route comes first and a station keeps only the picked line', () {
      final choices = mrtChoices(stations, home, office);
      expect(choices.first.line, isNull);
      expect(choices.first.plan.board.name, 'Marine Parade');
      expect(stationOnLine(const MrtStation(name: 'Tampines', codes: ['DT32', 'EW2'], lat: 1, lng: 1), 'EWL').codes,
          ['EW2']);
      // The usual line itself is never offered again.
      expect(choices.skip(1).map((c) => c.line), isNot(contains('TEL')));
    });

    test('a station too far to walk needs a direct bus to it', () {
      expect(lineMrtChoice(stations, home, office, 'EWL'), isNull); // Eunos, 1.9 km, no bus data
      final eunos = stations.firstWhere((x) => x.name == 'Eunos');
      const nearHome = BusStop(code: 'A', name: 'Opp Marine Parade Stn', road: 'R', lat: 1.3032, lng: 103.9062);
      const midway = BusStop(code: 'M', name: 'Midway', road: 'R', lat: 1.311, lng: 103.904);
      final atEunos = BusStop(code: 'B', name: 'Eunos Stn', road: 'R', lat: eunos.lat + 0.0005, lng: eunos.lng);
      const routes = BusRoutes({
        '15|1': [('A', 0.0), ('M', 0.9), ('B', 1.9)],
      });
      final c = lineMrtChoice(stations, home, office, 'EWL', routes: routes, stops: [nearHome, midway, atEunos])!;
      expect(c.line, 'EWL');
      expect(c.plan.board.name, 'Eunos');
      expect(c.plan.board.codes, ['EW7']);
      expect(c.feeder!.ride.service, '15');
      expect(c.feeder!.ride.stops, 2);
      expect(c.ride!.alight.name, 'Promenade');
      expect(c.changes, 1);
      // walk 1 + wait 5 + bus 2 stops + train + walk at the end
      expect(c.minutes, greaterThan(1 + feederWaitMinutes + 2 * feederMinutesPerStop));
      expect(mrtChoices(stations, home, office, routes: routes, stops: [nearHome, midway, atEunos]).map((x) => x.line),
          contains('EWL'));
    });

    test('a line from the same station is offered when the ride differs', () {
      const tampines = Place(kind: PlaceKind.home, addrLat: 1.35159, addrLng: 103.94503);
      const raffles = Place(kind: PlaceKind.work, addrLat: 1.2841, addrLng: 103.8514);
      expect(mrtPlan(stations, tampines, raffles)!.line, 'EWL');
      final dtl = lineMrtChoice(stations, tampines, raffles, 'DTL')!;
      expect(dtl.plan.board.codes, ['DT32']);
      expect(dtl.feeder, isNull);
      expect(dtl.ride!.stations.length, greaterThan(2));
      expect(lineMrtChoice(stations, tampines, raffles, 'EWL'), isNull); // that is the usual ride
    });

    test('station crowd levels and plain words', () {
      final crowd = stationCrowd({
        'data': {
          'value': [
            {'Station': 'EW7', 'CrowdLevel': 'l'},
            {'Station': 'EW8', 'CrowdLevel': 'h'},
            {'Station': 'EW9', 'CrowdLevel': 'NA'},
          ],
        },
      });
      expect(crowd, {'EW7': 'l', 'EW8': 'h'});
      expect(stationCrowd({'data': {}}), isEmpty);
      const s = S();
      expect(s.crowdNow('Paya Lebar', 'h'), 'Paya Lebar now: packed');
      expect(s.todayOnLine('EWL'), 'Today: Green line (East-West)');
      expect(s.choiceSummary(31, 1, s.choiceBus('15', 'Eunos')), '~31 min · bus 15 to Eunos · 1 change');
      expect(s.choiceWalk('Tampines', 400), 'walk 5 min to Tampines');
    });

    test('the picked line is saved per trip and survives a restart', () {
      const fav = Favorites(mrtLines: {'home>work': 'EWL'});
      expect(Favorites.fromJson(fav.toJson()).mrtLines, {'home>work': 'EWL'});
      expect(const Favorites().toJson().containsKey('mrtLines'), isFalse);
    });
  });

  group('places shared from Google Maps', () {
    test('name and postal code from a Google Maps share', () {
      final p = parseSharedPlace(
          'Putra Minang Restaurant Bencoolen\n51 Bencoolen St, #01-05, Singapore 189630\n\nhttps://maps.app.goo.gl/AbC123456789')!;
      expect(p.name, 'Putra Minang Restaurant Bencoolen');
      expect(p.postal, '189630');
      expect(p.hasPoint, isFalse);
    });

    test('name and address on one line', () {
      final p = parseSharedPlace('Putra Minang Restaurant · 51 Bencoolen St, Singapore 189630 https://maps.app.goo.gl/x')!;
      expect(p.name, 'Putra Minang Restaurant');
      expect(p.postal, '189630');
    });

    test('digits in the link or the unit number are not a postal code', () {
      final p = parseSharedPlace('Some Cafe\nhttps://maps.app.goo.gl/123456789012\n#01-123456')!;
      expect(p.name, 'Some Cafe');
      expect(p.postal, isNull);
    });

    test('the code after Singapore wins over other 6 digits', () {
      expect(parseSharedPlace('Shop 888888 Deals\n10 Bayfront Ave, Singapore 018956')!.postal, '018956');
    });

    test('an address alone has no name', () {
      final p = parseSharedPlace('51 Bencoolen St, Singapore 189630\nhttps://maps.app.goo.gl/x')!;
      expect(p.name, isNull);
      expect(p.postal, '189630');
    });

    test('a dropped pin gives a point inside Singapore', () {
      final p = parseSharedPlace('Dropped pin\nhttps://maps.google.com/?q=1.29661,103.85220')!;
      expect(p.name, isNull);
      expect(p.lat, closeTo(1.29661, 1e-6));
      expect(p.lng, closeTo(103.8522, 1e-6));
      final paris = parseSharedPlace('https://maps.google.com/?q=48.85837,2.29448')!;
      expect(paris.hasPoint, isFalse); // outside Singapore: no point, only the link
      expect(mapsLinkPlace(paris.link!), isNull);
    });

    test('the subject can carry the name', () {
      final p = parseSharedPlace('51 Bencoolen St, Singapore 189630', subject: 'Putra Minang Restaurant Bencoolen')!;
      expect(p.name, 'Putra Minang Restaurant Bencoolen');
      expect(p.postal, '189630');
    });

    test('nothing to go on', () {
      expect(parseSharedPlace(null), isNull);
      expect(parseSharedPlace('   \n  '), isNull);
    });
  });

  group('Google Maps links', () {
    // Real redirect of a route shared from Google Maps (Your location → Putra Minang), Nov 2026.
    const routeUrl = 'https://www.google.com/maps/dir/1.3015204,103.9050613/Putra+Minang+Restaurant+Bencoolen/'
        'data=!4m12!4m11!1m1!4e1!1m5!1m4!1s0x31da19faa330d147:0x815145de046b9fd8!8m2!3d1.2994204999999999'
        '!4d103.85050939999999!2m1!11b1!3e2?g_st=ac&skid=46bc1625-4926-456e-8742-240d489288a0';

    test('a shared route is only a link, not a place called "Shared route"', () {
      final p = parseSharedPlace('https://maps.app.goo.gl/oseWUrfHe23uqLKZ7?g_st=ac', subject: 'Shared route')!;
      expect(p.name, isNull);
      expect(p.postal, isNull);
      expect(p.link, 'https://maps.app.goo.gl/oseWUrfHe23uqLKZ7?g_st=ac');
      expect(p.needsLink, isTrue);
    });

    test('links outside Google Maps are not opened', () {
      expect(mapsLinkIn('see https://evil.example/maps.app.goo.gl/x'), isNull);
      expect(mapsLinkIn('http://maps.app.goo.gl/x'), isNull); // not https
      expect(mapsLinkIn('https://www.google.com/url?q=https://evil.example'), isNull);
      expect(mapsLinkIn('Putra Minang Restaurant Bencoolen https://share.google/HNv5xr5XDLISCfUZa'),
          'https://share.google/HNv5xr5XDLISCfUZa'); // a place shared from Google Search in Chrome
      expect(mapsLinkIn('https://maps.app.goo.gl/x'), 'https://maps.app.goo.gl/x');
    });

    test('directions: the last stop and its pin, not where you started', () {
      final p = mapsLinkPlace(routeUrl)!;
      expect(p.name, 'Putra Minang Restaurant Bencoolen');
      expect(p.lat, closeTo(1.29942, 1e-4));
      expect(p.lng, closeTo(103.85051, 1e-4));
    });

    test('a place page with its address', () {
      final p = mapsLinkPlace('https://www.google.com/maps/place/Putra+Minang+Restaurant+Bencoolen,'
          '+51+Bencoolen+St,+%2301-05,+Singapore+189630/@1.2994,103.8505,17z/data=!3m1!4b1!4m6!3m5!8m2'
          '!3d1.2994205!4d103.8505094')!;
      expect(p.name, 'Putra Minang Restaurant Bencoolen');
      expect(p.postal, '189630');
      expect(p.lat, closeTo(1.29942, 1e-4));
    });

    test('a Google Search place result with its address', () {
      final p = mapsLinkPlace('https://www.google.com/search?q=Putra+Minang+Restaurant+Bencoolen,'
          '+51+Bencoolen+St,+%2301-05,+Singapore+189630&kgmid=/g/11x')!;
      expect(p.name, 'Putra Minang Restaurant Bencoolen');
      expect(p.postal, '189630');
    });

    test('a link to a point or nothing', () {
      expect(mapsLinkPlace('https://maps.google.com/?q=1.29661,103.85220')!.lat, closeTo(1.29661, 1e-6));
      expect(mapsLinkPlace('https://www.google.com/maps/@1.3,103.8,15z'), isNull); // just a map view
      expect(mapsLinkPlace('https://example.com/maps/place/X'), isNull);
      expect(mapsLinkPlace('https://maps.google.com/?q=48.85837,2.29448'), isNull); // Paris: not a name either
    });

    test('what the link led to fills the share', () {
      const shared = SharedPlace(link: 'https://maps.app.goo.gl/x');
      final p = shared.merge(mapsLinkPlace(routeUrl)!);
      expect(p.name, 'Putra Minang Restaurant Bencoolen');
      expect(p.hasPoint, isTrue);
      expect(p.needsLink, isFalse);
    });
  });

  group('public holidays switch off work and school trips', () {
    // Monday 9 Nov 2026 is Deepavali (Observed); Monday 23 Nov is in the MOE year-end holidays.
    final off = DaysOff(
      holidays: Holiday.fromBundle([
        {'d': '2026-11-08', 'n': 'Deepavali'},
        {'d': '2026-11-09', 'n': 'Deepavali (Observed)'},
      ]),
      school: [SchoolHoliday(DateTime(2026, 11, 21), DateTime(2026, 12, 31), 'Year-end holidays')],
    );
    const work = Place(kind: PlaceKind.work, stops: [raffles], go: TimeOfDayHM(8, 0), back: TimeOfDayHM(18, 0));
    const school = Place(kind: PlaceKind.school, stops: [raffles], go: TimeOfDayHM(7, 0));
    const home = Place(kind: PlaceKind.home, stops: [tampines]);
    const workOnly = Favorites(places: {PlaceKind.home: home, PlaceKind.work: work});
    const both = Favorites(places: {PlaceKind.home: home, PlaceKind.work: work, PlaceKind.school: school});
    const schoolOnly = Favorites(places: {PlaceKind.home: home, PlaceKind.school: school});
    final deepavali = DateTime(2026, 11, 9, 7, 45);
    final yearEnd = DateTime(2026, 11, 23, 7, 45);
    final normal = DateTime(2026, 11, 10, 7, 45);

    test('DaysOff.isOff: public holidays stop work and school, school holidays only school', () {
      expect(off.publicOn(deepavali)!.name, 'Deepavali (Observed)');
      expect(off.publicOn(normal), isNull);
      expect(off.isOff(work, deepavali), isTrue);
      expect(off.isOff(school, deepavali), isTrue);
      expect(off.isOff(school, yearEnd), isTrue);
      expect(off.isOff(work, yearEnd), isFalse);
      expect(off.isOff(work, normal), isFalse);
      expect(off.isOff(school, normal), isFalse);
      // Home and custom places never have a day off.
      expect(off.isOff(home, deepavali), isFalse);
      expect(const DaysOff().isOff(work, deepavali), isFalse);
    });

    test('commutePlace skips places that are off today', () {
      expect(commutePlace(both, deepavali, off), isNull);
      expect(commutePlace(both, yearEnd, off)!.kind, PlaceKind.work);
      expect(commutePlace(schoolOnly, yearEnd, off), isNull);
      expect(commutePlace(both, normal, off)!.kind, PlaceKind.work);
      // Without DaysOff nothing changes.
      expect(commutePlace(both, deepavali)!.kind, PlaceKind.work);
      expect(isCommuteDay(both, deepavali, off), isFalse);
      expect(isCommuteDay(both, deepavali), isTrue);
      // The usual times stay, so the morning/evening card does not move.
      expect(commuteTimes(both, deepavali), (const TimeOfDayHM(8, 0), const TimeOfDayHM(18, 0)));
    });

    test('no trip, destination or widget trip on a public holiday', () {
      const s = S();
      expect(widgetTrip(s, both, deepavali, off: off), '');
      expect(widgetTrip(s, schoolOnly, yearEnd, off: off), '');
      expect(widgetTrip(s, both, normal, off: off), isNotEmpty);
      expect(widgetData(s: s, fav: both, now: deepavali, off: off)['dl_trip'], '');
      expect(destinationFor(CardKind.morning, both, deepavali, off), isNull);
      expect(destinationFor(CardKind.morning, both, deepavali), PlaceKind.work);
      expect(originFor(CardKind.evening, both, DateTime(2026, 11, 9, 18), off), PlaceKind.home);
      expect(isSchoolDay(schoolOnly, deepavali, off), isFalse);
      expect(isSchoolDay(schoolOnly, yearEnd, off), isFalse);
      expect(isSchoolDay(schoolOnly, normal, off), isTrue);
    });

    test('holidayNote: name, weather near home and the 2 nearest events today', () {
      const s = S();
      PublicEvent ev(String n, double lat, double lng, {String day = '2026-11-09'}) =>
          PublicEvent.fromBundle({'n': n, 'u': 'https://x', 's': '$day 10:00', 'e': '$day 18:00', 'la': lat, 'lo': lng})!;
      final events = [
        ev('Lights walk', 1.360, 103.950),
        ev('Bazaar', 1.355, 103.944),
        ev('Far fair', 1.354, 104.100), // about 17 km away
        ev('Tomorrow fair', 1.354, 103.943, day: '2026-11-10'),
      ];
      const weather = AreaForecast(area: 'Tampines', forecast: 'Partly Cloudy (Day)');
      final note = holidayNote(s, workOnly, deepavali, off, homeWeather: weather, events: events)!;
      expect(note.$1, contains('Deepavali (Observed)'));
      expect(note.$1, s.holidayTitle('Deepavali (Observed)'));
      final lines = note.$2.split('\n');
      expect(lines, hasLength(3));
      expect(lines.first, 'Tampines: Partly Cloudy (Day)');
      expect(lines[1], startsWith('Bazaar · '));
      expect(lines[2], startsWith('Lights walk · '));
      expect(note.$2, isNot(contains('Far fair')));
      expect(note.$2, isNot(contains('Tomorrow fair')));

      // Weather only when there is no event; a friendly line when there is nothing at all.
      expect(holidayNote(s, workOnly, deepavali, off, homeWeather: weather)!.$2, 'Tampines: Partly Cloudy (Day)');
      expect(holidayNote(s, workOnly, deepavali, off)!.$2, s.holidayEnjoy);
      // Sunday (no trip anyway), a school holiday, a normal day: no holiday notification.
      expect(holidayNote(s, workOnly, DateTime(2026, 11, 8, 7, 45), off, homeWeather: weather), isNull);
      expect(holidayNote(s, both, yearEnd, off, homeWeather: weather), isNull);
      expect(holidayNote(s, workOnly, normal, off, homeWeather: weather), isNull);
      expect(holidayNote(s, workOnly, deepavali, const DaysOff(), homeWeather: weather), isNull);
    });

    test('Today banner text for a public holiday', () {
      const s = S();
      expect(s.publicHolidayToday('Deepavali (Observed)'),
          'Deepavali (Observed): public holiday, no work or school trip today.');
      expect(s.holidayTitle('Deepavali (Observed)'), 'Happy Deepavali (Observed) · no commute today');
      expect(s.eventNearby('Bazaar', '850 m'), 'Bazaar · 850 m');
    });
  });

  group('need a toilet', () {
    BusStop stop(String code, int k) =>
        BusStop(code: code, name: 'Stop $code', road: 'Road', lat: 1.30 + k * 0.005, lng: 103.80);
    final line = [for (final (k, c) in ['A', 'B', 'C', 'D', 'E', 'F'].indexed) stop(c, k)];
    final byCode = {for (final s in line) s.code: s};
    final routes = BusRoutes({
      '10|1': [for (final (k, s) in line.indexed) (s.code, k * 0.5)],
      '10|2': [for (final (k, s) in line.reversed.indexed) (s.code, k * 0.5)],
      '99|1': [for (final (k, s) in line.indexed) (s.code, k * 0.5)],
    });
    Toilet near(BusStop s, double dLat, String name, ToiletKind kind) =>
        Toilet(name: name, lat: s.lat + dLat, lng: s.lng, kind: kind);

    test('Toilet.fromBundle reads name, position and kind', () {
      final t = Toilet.fromBundle({'n': 'Jurong Point', 'la': 1.3399, 'lo': 103.7065, 'k': 'mall'});
      expect((t.name, t.lat, t.lng, t.kind), ('Jurong Point', 1.3399, 103.7065, ToiletKind.mall));
      expect(Toilet.fromBundle({'n': 'X', 'la': 1, 'lo': 2, 'k': 'spaceport'}).kind, ToiletKind.other);
      expect(Toilet.fromBundle({'n': 'X', 'la': 1, 'lo': 2}).kind, ToiletKind.other);
    });

    test('bus: the stops ahead up to the alight stop, in order, stops without a toilet skipped', () {
      final toilets = [
        near(byCode['A']!, 0.0003, 'Behind us', ToiletKind.mall), // before boarding
        near(byCode['B']!, 0.0003, 'At boarding', ToiletKind.mall), // the stop we left
        near(byCode['C']!, 0.001, 'Junction C', ToiletKind.mall), // ~111 m
        near(byCode['E']!, 0.00045, 'Toilet', ToiletKind.other), // ~50 m
        near(byCode['E']!, -0.0011, 'E Food Centre', ToiletKind.hawker), // ~120 m
        near(byCode['F']!, 0.0003, 'Past the stop', ToiletKind.mall), // after alighting
      ];
      final out = toiletsAheadBus(routes, '10', byCode['B']!, byCode['E']!, byCode, toilets);
      expect([for (final t in out) t.at], ['Stop C', 'Stop E']);
      expect(out[0].toilet!.name, 'Junction C');
      expect(out[0].rideMinutes, 2); // one stop at ~2 min a stop
      expect(out[0].walkMinutes, walkMinutesTo(out[0].metres));
      expect(out[0].minutes, out[0].rideMinutes + out[0].walkMinutes);
      expect(out[1].toilet!.name, 'Toilet'); // the nearest toilet at that stop
      expect(out[1].rideMinutes, 6);
      expect(out.every((t) => !t.assumed), isTrue);
    });

    test('bus: the GPS fix moves the start; nothing ahead, wrong way or unknown stops give none', () {
      final toilets = [
        near(byCode['C']!, 0.0005, 'C mall', ToiletKind.mall),
        near(byCode['E']!, 0.0005, 'E mall', ToiletKind.mall),
      ];
      final d = byCode['D']!;
      final out = toiletsAheadBus(routes, '10', byCode['B']!, byCode['E']!, byCode, toilets, lat: d.lat, lng: d.lng);
      expect([for (final t in out) t.at], ['Stop E']);
      expect(out.single.rideMinutes, 2);
      // Too far from the route: the fix is ignored.
      expect(toiletsAheadBus(routes, '10', byCode['B']!, byCode['E']!, byCode, toilets, lat: 1.45, lng: 103.9),
          hasLength(2));
      expect(toiletsAheadBus(routes, '10', byCode['E']!, byCode['E']!, byCode, toilets), isEmpty);
      expect(toiletsAheadBus(routes, '12', byCode['B']!, byCode['E']!, byCode, toilets), isEmpty);
      expect(toiletsAheadBus(BusRoutes.empty, '10', byCode['B']!, byCode['E']!, byCode, toilets), isEmpty);
      // Direction 2 runs F to A: from E to B it passes D, C and B.
      expect([for (final t in toiletsAheadBus(routes, '10', byCode['E']!, byCode['B']!, byCode, toilets)) t.at],
          ['Stop C']);
    });

    test('bus: a fix before the nearest stop keeps that stop ahead', () {
      final toilets = [
        near(byCode['D']!, 0.0003, 'D mall', ToiletKind.mall),
        near(byCode['E']!, 0.0003, 'E mall', ToiletKind.mall),
      ];
      // 60% of the way from C to D: nearest to D, but the bus has not reached it yet.
      final c = byCode['C']!, d = byCode['D']!;
      final lat = c.lat + (d.lat - c.lat) * 0.6;
      final out = toiletsAheadBus(routes, '10', byCode['B']!, byCode['E']!, byCode, toilets, lat: lat, lng: d.lng);
      expect([for (final t in out) t.at], ['Stop D', 'Stop E']);
      expect(out.first.rideMinutes, 2);
      // Just before the alight stop: it is still ahead.
      final e = byCode['E']!;
      final late = toiletsAheadBus(routes, '10', byCode['B']!, e, byCode, toilets, lat: e.lat - 0.0005, lng: e.lng);
      expect([for (final t in late) t.at], ['Stop E']);
    });

    test('bus: at most [limit] stops, the soonest first', () {
      final toilets = [for (final s in line) near(s, 0.0003, 'T ${s.code}', ToiletKind.other)];
      final out = toiletsAheadBus(routes, '10', byCode['A']!, byCode['F']!, byCode, toilets);
      expect([for (final t in out) t.at], ['Stop B', 'Stop C', 'Stop D']);
      expect(toiletsAheadBus(routes, '10', byCode['A']!, byCode['F']!, byCode, toilets, limit: 1), hasLength(1));
    });

    final stations = [
      for (var i = 0; i < 4; i++) MrtStation(name: 'S$i', codes: ['NS${10 + i}'], lat: 1.35 + i * 0.01, lng: 103.85),
    ];
    final ride = MrtRide(stations: stations, lines: const {'NSL'});

    test('train: a toilet near the station, else "stations usually have a toilet"', () {
      final toilets = [
        Toilet(name: 'S2 Mall', lat: stations[2].lat + 0.0009, lng: 103.85, kind: ToiletKind.mall), // ~100 m
        Toilet(name: 'Too far', lat: stations[1].lat + 0.0036, lng: 103.85), // ~400 m
      ];
      final out = toiletsAheadMrt(ride, 0, toilets);
      expect([for (final t in out) t.at], ['S1', 'S2', 'S3']);
      expect(out[0].assumed, isTrue);
      expect(out[0].toilet, isNull);
      expect(out[0].minutes, rideMinutesTo(ride, 1));
      expect(out[1].toilet!.name, 'S2 Mall');
      expect(out[1].minutes, rideMinutesTo(ride, 2) + walkMinutesTo(out[1].metres));
      // S2 (mall) and S3 (assumed station) both take 6 min: the mall comes first.
      expect(out[1].minutes, out[2].minutes);
      expect(out[2].assumed, isTrue);
      // Further along the ride only what is still ahead; at the last station, nothing.
      expect([for (final t in toiletsAheadMrt(ride, 2, toilets)) t.at], ['S3']);
      expect(toiletsAheadMrt(ride, 2, toilets).single.rideMinutes, rideMinutesPerStop);
      expect(toiletsAheadMrt(ride, 3, toilets), isEmpty);
      expect(toiletsAheadMrt(ride, 0, toilets, limit: 2), hasLength(2));
    });

    test('train: minutes include the change of line', () {
      final via = MrtRide(stations: stations, lines: const {'NSL', 'EWL'}, viaIndex: 1);
      expect(toiletsAheadMrt(via, 0, const []).last.rideMinutes, rideMinutesTo(via, 3));
      expect(rideMinutesTo(via, 3), 3 * rideMinutesPerStop + rideTransferMinutes);
    });

    test('near me: the three best, by walk then kind then distance', () {
      const lat = 1.30, lng = 103.80;
      final toilets = [
        const Toilet(name: 'Far', lat: lat + 0.02, lng: lng),
        const Toilet(name: 'Other 45 m', lat: lat + 0.0004, lng: lng),
        const Toilet(name: 'Mall 60 m', lat: lat - 0.00055, lng: lng, kind: ToiletKind.mall),
        const Toilet(name: 'Park 500 m', lat: lat + 0.0045, lng: lng, kind: ToiletKind.park),
      ];
      final out = toiletsNear(toilets, lat, lng);
      // 45 m and 60 m are both a 1 min walk: the mall first.
      expect([for (final (t, _) in out) t.name], ['Mall 60 m', 'Other 45 m', 'Park 500 m']);
      expect(out.first.$2, closeTo(61, 2));
      expect(toiletsNear(toilets, lat, lng, limit: 1), hasLength(1));
      expect(toiletsNear(const [], lat, lng), isEmpty);
    });

    test('toiletRank: sooner first, then mall, hawker, station, then nearer', () {
      ToiletStop at(int ride, ToiletKind k, double m) =>
          ToiletStop(at: '', rideMinutes: ride, toilet: Toilet(name: k.name, lat: 0, lng: 0, kind: k), metres: m);
      const assumed = ToiletStop(at: 'Station', rideMinutes: 5, assumed: true); // 5 min, no walk
      final list = [
        at(4, ToiletKind.other, 10),
        at(4, ToiletKind.hawker, 10),
        assumed,
        at(4, ToiletKind.mall, 70),
        at(2, ToiletKind.park, 10),
        at(4, ToiletKind.mall, 30),
      ]..sort(toiletRank);
      expect([for (final t in list) t.assumed ? 'assumed' : '${t.toilet!.name} ${t.metres.round()}'], [
        'park 10',
        'mall 30',
        'mall 70',
        'hawker 10',
        'assumed',
        'other 10',
      ]);
    });

    test('toilet strings', () {
      const s = S();
      expect(s.toiletNeed, 'Need a toilet?');
      expect(s.toiletGetOff('Bishan Int', 6), 'Get off at Bishan Int (in about 6 min)');
      expect(s.toiletWalk('Junction 8', 2), 'Junction 8, 2 min walk');
      expect(s.toiletAssumed, 'Stations usually have a toilet');
      expect(s.nearbySection('toilet'), 'Toilets');
    });
  });

  group('short trips: Walk by default, honest bus comparison, plurals', () {
    test('Walk is the default up to a 1 km walking route or 12 minutes, not beyond', () {
      // The route is the straight line x 1.3: 555 m straight is a 722 m, 9 minute walk.
      expect(walkIsDefault(555), isTrue);
      expect(routeMetres(769), lessThanOrEqualTo(walkDefaultMaxMetres));
      expect(walkIsDefault(769), isTrue);
      expect(walkMinutesTo(771), greaterThan(walkDefaultMaxMinutes));
      expect(walkIsDefault(771), isFalse);
      expect(walkIsDefault(2000), isFalse);
      expect(walkDefaultMaxMetres, 1000);
      expect(walkDefaultMaxMinutes, 12);
    });

    test('a short planned trip opens on Walk; the commute and longer trips keep the saved mode', () {
      expect(defaultTripMode(TravelMode.transit, 555), TravelMode.walk);
      expect(defaultTripMode(TravelMode.car, 555), TravelMode.walk);
      expect(defaultTripMode(TravelMode.car, 555, commute: true), TravelMode.car);
      expect(defaultTripMode(TravelMode.transit, 5000), TravelMode.transit);
      expect(defaultTripMode(TravelMode.taxi, 5000), TravelMode.taxi);
    });

    test('mode chips: Walk first, then the saved modes in their order, then the rest, each once', () {
      expect(tripModes(const [TravelMode.transit]).first, TravelMode.walk);
      final chips = tripModes(const [TravelMode.car, TravelMode.transit]);
      expect(chips.take(3), [TravelMode.walk, TravelMode.car, TravelMode.transit]);
      expect(chips.toSet().length, TravelMode.values.length);
      expect(chips.length, TravelMode.values.length);
      // Setup offers every mode but Walk.
      expect(savedTravelModes, isNot(contains(TravelMode.walk)));
      expect(savedTravelModes.length, TravelMode.values.length - 1);
    });

    test('a mode picked in the planner is kept per trip, apart from the commute keys', () {
      const a = Place(kind: PlaceKind.other, addrLat: 1.3139, addrLng: 103.9317);
      const b = Place(kind: PlaceKind.other, addrLat: 1.3130, addrLng: 103.9279);
      const c = Place(kind: PlaceKind.other, addrLat: 1.3093, addrLng: 103.9143);
      expect(plannedModeKey(a, b), isNot(plannedModeKey(a, c)));
      expect(plannedModeKey(a, b), isNot(plannedModeKey(b, a)));
      expect(plannedModeKey(a, b), startsWith('plan:'));
    });

    test('door to door by bus: walk and wait, the ride, the walk from the alighting stop', () {
      // The case from the phone: 3 min walk, the bus comes in 6, 1 stop, 3 min walk after.
      expect(busDoorToDoor(walkToStop: 3, busIn: 6, stops: 1, alightMetres: 180), 6 + 2 + 3);
      // At the stop already and alighting at the door.
      expect(busDoorToDoor(walkToStop: 0, busIn: 4, stops: 5, alightMetres: 20), 4 + 10);
      // The walk is longer than the wait: the walk counts.
      expect(busDoorToDoor(walkToStop: 8, busIn: 8, stops: 3, alightMetres: 0), 8 + 6);
    });

    test('the bus is folded away for one stop on a walkable trip, or when walking is as quick', () {
      // 555 m: a 9 minute walk. One stop: never the hero card, however quick.
      expect(busNotFaster(stops: 1, doorToDoor: 4, straightMetres: 555), isTrue);
      // Door to door 11 min against 9 on foot.
      expect(busNotFaster(stops: 2, doorToDoor: 11, straightMetres: 555), isTrue);
      // Equal is not faster.
      expect(busNotFaster(stops: 3, doorToDoor: walkMinutesTo(900), straightMetres: 900), isTrue);
      // The normal case: 5 km is an 81 minute walk, the bus takes 25.
      expect(busNotFaster(stops: 12, doorToDoor: 25, straightMetres: 5000), isFalse);
      // One stop on a long trip (an express service) is still a real ride.
      expect(busNotFaster(stops: 1, doorToDoor: 15, straightMetres: 5000), isFalse);
      // A bus that takes longer than walking a long way is folded too.
      expect(busNotFaster(stops: 4, doorToDoor: 40, straightMetres: 2000), isTrue);
    });

    test('rough minutes per mode: 15 km/h by bicycle, 30 km/h by car, motorbike or taxi', () {
      // 5 km straight is a 6.5 km route.
      expect(modeMinutes(TravelMode.bicycle, 5000), 26);
      expect(modeMinutes(TravelMode.car, 5000), 13);
      expect(modeMinutes(TravelMode.motorcycle, 5000), 13);
      expect(modeMinutes(TravelMode.taxi, 5000), 13);
      expect(modeMinutes(TravelMode.walk, 555), walkMinutesTo(555));
      expect(modeMinutes(TravelMode.transit, 5000), isNull);
      expect(modeMinutes(TravelMode.car, 10), 1); // never "0 min"
    });

    test('weather tips for Walk never mention a bus stop', () {
      expect(tripAdvice(mode: TravelMode.walk, lightning: true, rainy: true),
          [TripAdvice.lightningOnFoot, TripAdvice.rainWalk]);
      expect(tripAdvice(mode: TravelMode.walk, highHeat: true), [TripAdvice.heat]);
      expect(tripAdvice(mode: TravelMode.transit, lightning: true), [TripAdvice.lightningWalk]);
      const s = S();
      for (final a in [TripAdvice.lightningOnFoot, TripAdvice.rainWalk]) {
        expect(s.tripAdvice(a), isNot(contains('stop')));
      }
    });

    test('plurals: 1 stop, 2 stops on the trip card, the MRT card and the folded bus line', () {
      const s = S();
      expect(s.rideInfo(1, 0.3, 'Blk 1'), '1 stop · 0.3 km · get off at Blk 1');
      expect(s.rideInfo(2, 0.8, 'Blk 1'), '2 stops · 0.8 km · get off at Blk 1');
      expect(s.rideLine('Green line', 1), 'Ride Green line · ~1 stop');
      expect(s.rideLine('Green line', 4), 'Ride Green line · ~4 stops');
      expect(s.busNotFaster('196', 1), 'Bus 196 · 1 stop · not faster than walking');
      expect(s.busNotFaster('196', 3), 'Bus 196 · 3 stops · not faster than walking');
      expect(s.feederStep('10', 'A', 'B', 1), contains('1 stop'));
      expect(s.stopsTag(1), '1 stop');
      // The walking card shows the minutes the bus is compared with.
      expect(s.walkMin(walkMinutesTo(1010)), '16 min walk');
      expect(s.modeLabel('walk'), 'Walk');
      expect(s.modeEta('bicycle', 10, '2.4 km'), 'About 10 min by bicycle · 2.4 km');
      expect(s.modeEta('car', 8, '3.1 km'), 'About 8 min by car · 3.1 km');
    });
  });

  group('live LTA details per mode', () {
    test('the point is sent with 4 decimals', () {
      expect(extrasCoord(1.36912345), 1.3691);
      expect(extrasCoord(103.84545678), 103.8455);
    });

    test('an answer that is not this mode, or has no list, is no answer', () {
      expect(parseTripExtras({'data': null}, TravelMode.car), isNull);
      expect(parseTripExtras({'fetched_at': 1, 'data': {'mode': 'car'}}, TravelMode.car), isNull);
      expect(parseTripExtras({'data': {'mode': 'taxi', 'radius': 500}}, TravelMode.taxi), isNull);
      final x = parseTripExtras({
        'fetched_at': 1793850000,
        'data': {
          'mode': 'car',
          'radius': 1000,
          'items': [
            {'name': 'A', 'la': 1.3, 'lo': 103.8, 'm': 10, 'lots': 0, 'agency': 'URA'},
            {'name': 'no point'},
          ],
        },
      }, TravelMode.car)!;
      expect(x.spots.single.lots, 0);
      expect(x.asOf, DateTime.fromMillisecondsSinceEpoch(1793850000 * 1000));
    });

    test('for the phone\'s own position the phone filters the public lists itself', () {
      const lat = 1.3691, lng = 103.8454;
      final parking = {
        'fetched_at': 1793850000,
        'data': [
          ['A', 'HDB', 1.3692, 103.8455, 'C', 40, 'BLK A'],
          ['A', 'HDB', 1.3692, 103.8455, 'Y', 6, 'BLK A'],
          ['B', 'URA', 1.3760, 103.8454, 'C', 5, ''],
          ['FAR', 'HDB', 1.3900, 103.8454, 'C', 500, 'FAR'],
        ],
      };
      final car = localTripExtras(TravelMode.car, lat, lng, parking: parking);
      expect(car.spots.map((p) => (p.name, p.lots)), [('BLK A', 40), ('B', 5)]);
      expect(car.asOf, isNotNull);
      expect(localTripExtras(TravelMode.motorcycle, lat, lng, parking: parking).spots.single.lots, 6);
      final taxi = localTripExtras(TravelMode.taxi, lat, lng, taxis: {
        'data': [
          [1.3692, 103.8455],
          [1.3745, 103.8454],
        ],
      });
      expect((taxi.taxis, taxi.radius), (1, 500));
      const racks = [
        EPoint(name: '12 bicycle racks · sheltered', lat: 1.3693, lng: 103.8456),
        EPoint(name: 'far', lat: 1.38, lng: 103.8454),
      ];
      final bike = localTripExtras(TravelMode.bicycle, lat, lng, racks: racks);
      expect(bike.spots.single.name, '12 bicycle racks · sheltered');
      expect(bike.asOf, isNull);
    });

    test('strings: lots, taxis and racks in singular and plural', () {
      const s = S();
      expect(s.lotsLabel(1, motorbike: false), 'car lot');
      expect(s.lotsLabel(0, motorbike: true), 'motorbike lots');
      expect(s.taxisInRadius(0, 500), '0 taxis within 500 m');
      expect(s.rackLine('', null, null), '');
      expect(s.rackLine('Racks', 1, false), 'Racks · 1 rack · not sheltered');
      // LTA's own spellings, as seen on the live API.
      expect(s.rackLine('HDB_RACKS', 15, true), 'HDB racks · 15 racks · sheltered');
      expect(s.rackType('MRT_RACKS'), 'MRT racks');
      expect(s.rackType('Yellow Box'), 'Yellow Box');
      expect(s.rackName('560201-2'), 'Racks at postal code 560201');
      expect(s.rackName('TAMPINES MRT B'), 'TAMPINES MRT B');
      expect(s.rackName('CAPITASPRING-1'), 'CAPITASPRING-1');
      expect(s.lotsAsOf('8:05'), 'Lots as of 8:05');
    });
  });

  group('rich notes', () {
    const s = S();
    List<String> texts(RichNote n) => [for (final p in n.pills) p.text];
    List<PillTone> tones(RichNote n) => [for (final p in n.pills) p.tone];

    test('rain: place, area and forecast, umbrella pill and the forecast window', () {
      final n = rainNote(s,
          placeKind: 'work', f: const AreaForecast(area: 'Bishan', forecast: 'Showers', validText: '12 PM to 2 PM'));
      expect(n.id, 2);
      expect(n.title, 'Rain before you leave.');
      expect(n.body, 'Rain near your office (Bishan): Showers. Bring an umbrella.');
      expect(texts(n), ['☂ Rain near Work', 'Forecast 12 PM to 2 PM']);
      expect(tones(n), [PillTone.amber, PillTone.sky]);
      expect(n.art, NoteArt.rain);
      expect(n.link, 'dailylah://today');
    });

    test('rain without a forecast window has only the umbrella pill', () {
      final n = rainNote(s, placeKind: 'home', f: const AreaForecast(area: 'Tampines', forecast: 'Thundery Showers'));
      expect(n.body, 'Rain near home (Tampines): Thundery Showers. Bring an umbrella.');
      expect(texts(n), ['☂ Rain near Home']);
    });

    test('haze: PSI pill in red and the marker on the bar', () {
      final n = hazeNote(s, const AirQuality(region: 'east', psi24: 128, pm25: 40, level: AirLevel.unhealthy));
      expect(n.id, 8);
      expect(n.title, 'Haze: unhealthy');
      expect(n.body, s.airAdviceShort(AirLevel.unhealthy));
      expect(texts(n), ['PSI 128 Unhealthy']);
      expect(tones(n), [PillTone.red]);
      expect(n.art, NoteArt.psi);
      expect(n.artValue, closeTo(128 / 300, 1e-9));
      expect(n.link, 'dailylah://today');
    });

    test('PSI 420 caps the marker at 1', () {
      final n = hazeNote(s, const AirQuality(region: 'east', psi24: 420, level: AirLevel.hazardous));
      expect(n.artValue, 1);
      expect(texts(n), ['PSI 420 Hazardous']);
    });

    test('PM2.5 62 with PSI 80 shows the PM2.5 pill', () {
      final n = hazeNote(s, const AirQuality(region: 'east', psi24: 80, pm25: 62, level: AirLevel.unhealthy));
      expect(texts(n), ['PM2.5 62 Unhealthy']);
      expect(n.artValue, closeTo(80 / 300, 1e-9));
    });

    test('haze with no PSI reading has the PM2.5 pill and no bar', () {
      final n = hazeNote(s, const AirQuality(region: 'east', pm25: 160, level: AirLevel.veryUnhealthy));
      expect(texts(n), ['PM2.5 160 Very unhealthy']);
      expect(n.art, NoteArt.none);
    });

    test('leave by: the bus, when to leave and the usual trip time', () {
      final n = leaveNote(s, const LeaveBy('36', 6, 4), usualMinutes: 38);
      expect(n.id, 9);
      expect(n.title, 'Time to go');
      expect(n.body, s.leaveIn('36', 6, 4));
      expect(texts(n), ['36', 'Leave in 6 min', 'Usually 38 min']);
      expect(tones(n), [PillTone.board, PillTone.teal, PillTone.sky]);
      expect(n.link, 'dailylah://today');
    });

    test('no usual time leaves the sky pill out, and 0 minutes says Leave now', () {
      final n = leaveNote(s, const LeaveBy('36', 0, 4));
      expect(texts(n), ['36', 'Leave now']);
    });

    test('leave by for a custom place keeps its id and names the place', () {
      final n = leaveNote(s, const LeaveBy('12', 3, 2), id: 14, placeName: 'Piano');
      expect(n.id, 14);
      expect(n.body, s.leaveForPlace('Piano', s.leaveIn('12', 3, 2)));
    });

    const ewl = LineStatus(line: 'EWL', disrupted: true, detail: 'No train service between Bugis and Lavender.');
    test('MRT: the line in its colour, Disrupted and the plan B bus', () {
      final n = mrtNote(s, const [ewl, LineStatus(line: 'DTL', disrupted: true)], planB: (line: 'EWL', bus: '858'));
      expect(n.id, 1);
      expect(n.title, 'Disruption on EWL, DTL');
      expect(n.body, 'No train service between Bugis and Lavender.');
      expect(texts(n), ['EWL', 'Disrupted', '858']);
      expect(tones(n), [PillTone.line, PillTone.red, PillTone.board]);
      expect(n.pills.first.lineColor, 0x009645);
      expect(n.link, 'dailylah://today');
    });

    test('MRT without a plan B bus or LTA text', () {
      final n = mrtNote(s, const [LineStatus(line: 'NSL', disrupted: true)]);
      expect(n.body, s.checkAlternatives);
      expect(texts(n), ['NSL', 'Disrupted']);
    });

    const expo = MrtStation(name: 'Expo', codes: ['CG1', 'DT35'], lat: 1.334, lng: 103.961);
    const segar = MrtStation(name: 'Segar', codes: ['BP11'], lat: 1.387, lng: 103.769);
    const plan = MrtPlan(board: expo, walkToBoard: 300, alight: segar, walkFromAlight: 400);
    Map<String, dynamic> disrupted(String line) => {
          'data': {
            'value': {
              'Status': 2,
              'AffectedSegments': [
                {'Line': line, 'Stations': 'X1,X2'},
              ],
              'Message': [],
            },
          },
        };

    test('planBBus is the first direct bus, with the disrupted line of the trip', () {
      final b = planBBus(plan: plan, alerts: disrupted('DTL'), directServices: ['858', '36'], disruptedLines: ['DTL'])!;
      expect(b.bus, '858');
      expect(b.line, 'DTL');
    });

    test('planBBus is null when the disrupted line is not on the plan', () {
      expect(planBBus(plan: plan, alerts: disrupted('NEL'), directServices: ['858'], disruptedLines: ['NEL']), isNull);
    });

    test('planBBus is null with no direct service, no plan or no alerts', () {
      expect(planBBus(plan: plan, alerts: disrupted('DTL'), directServices: const [], disruptedLines: ['DTL']), isNull);
      expect(planBBus(plan: null, alerts: disrupted('DTL'), directServices: ['858'], disruptedLines: ['DTL']), isNull);
      expect(planBBus(plan: plan, alerts: null, directServices: ['858'], disruptedLines: ['DTL']), isNull);
    });

    test('planBBus is null when the trip line is disrupted but is not one the alert is about', () {
      // NSL is starred and disrupted; the trip rides DTL, also disrupted but not watched.
      expect(planBBus(plan: plan, alerts: disrupted('DTL'), directServices: ['858'], disruptedLines: ['NSL']), isNull);
    });

    test('MRT: the line pill is the line the bus goes around, not just the first disrupted one', () {
      const nsl = LineStatus(line: 'NSL', disrupted: true, detail: 'NSL delayed.');
      const dtl = LineStatus(line: 'DTL', disrupted: true, detail: 'DTL: no service at Expo.');
      final n = mrtNote(s, const [nsl, dtl], planB: (line: 'DTL', bus: '858'));
      expect(n.title, 'Disruption on NSL, DTL');
      expect(texts(n), ['DTL', 'Disrupted', '858']);
      expect(n.pills.first.lineColor, 0x005EC4);
      expect(n.body, 'DTL: no service at Expo.');
    });

    test('wake: your stop is next in amber, may have passed in red, no tab link', () {
      final n = wakeNote(s, WakeEvent.wake, 'Blk 123');
      expect(n.id, 10);
      expect(n.title, s.wakeTitle);
      expect(n.body, s.wakeNowAt('Blk 123'));
      expect(texts(n), ['Your stop is next']);
      expect(tones(n), [PillTone.amber]);
      expect(n.art, NoteArt.phone);
      expect(n.link, isNull);
      final p = wakeNote(s, WakeEvent.passed, 'Blk 123');
      expect(p.body, s.wakePassed('Blk 123'));
      expect(texts(p), ['May have passed']);
      expect(tones(p), [PillTone.red]);
    });

    test('hawker: closed tomorrow and where is open, opens Nearby', () {
      final n = hawkerNote(s, 'Maxwell Food Centre', altName: 'Amoy Street Food Centre', altMetres: 400);
      expect(n.id, 3);
      expect(n.title, s.hawkerTomorrowTitle);
      expect(n.body,
          '${s.hawkerClosedTomorrow('Maxwell Food Centre')}. ${s.tryInstead('Amoy Street Food Centre', '400 m')}');
      expect(texts(n), ['Closed tomorrow', 'Open: Amoy Street Food Centre, 400 m']);
      expect(tones(n), [PillTone.red, PillTone.mint]);
      expect(n.link, 'dailylah://nearby');
      final alone = hawkerNote(s, 'Maxwell Food Centre');
      expect(alone.body, s.hawkerClosedTomorrow('Maxwell Food Centre'));
      expect(texts(alone), ['Closed tomorrow']);
    });

    test('heat: level and UV pills with the thermometer', () {
      final n = heatNote(s, place: 'School', level: 'High', uv: 11);
      expect(n.id, 5);
      expect(n.title, 'Heat stress high.');
      expect(n.body, 'Near School. Bring water and take the sheltered way.');
      expect(texts(n), ['Heat stress High', 'UV 11']);
      expect(tones(n), [PillTone.red, PillTone.amber]);
      expect(n.art, NoteArt.heat);
      expect(n.artValue, 1);
    });

    test('uv 0 and null leave the UV pill out', () {
      expect(texts(heatNote(s, place: 'Home', level: 'High', uv: 0)), ['Heat stress High']);
      expect(texts(heatNote(s, place: 'Home', level: 'High')), ['Heat stress High']);
    });

    test('digest: the lines, the week in bars and what it cost', () {
      final n = digestNote(s, ['Maxwell closed Mon', 'Holiday on Fri'],
          weekCents: 2460, tripsPerDay: [1, 2, 0, 4, 2, 0, 0]);
      expect(n.id, 12);
      expect(n.title, s.digestTitle);
      expect(n.body, 'Maxwell closed Mon\nHoliday on Fri');
      expect(texts(n), ['≈ \$24.60 this week']);
      expect(tones(n), [PillTone.sky]);
      expect(n.art, NoteArt.week);
      expect(n.bars, [0.25, 0.5, 0, 1, 0.5, 0, 0]);
    });

    test('digest with no trips has no art, and no cost no pill', () {
      final n = digestNote(s, ['Holiday on Fri'], weekCents: 0, tripsPerDay: [0, 0, 0, 0, 0, 0, 0]);
      expect(n.art, NoteArt.none);
      expect(n.bars, isEmpty);
      expect(n.pills, isEmpty);
      expect(digestNote(s, ['x']).pills, isEmpty);
    });

    test('parking time: time is up, and where the car is', () {
      final n = parkNote(s, 'Blk 156 Tampines St 12');
      expect(n.id, 11);
      expect(n.title, s.parkTitle);
      expect(n.body, s.parkReminder('Blk 156 Tampines St 12'));
      expect(texts(n), ['Time is up', 'Blk 156 Tampines St 12']);
      expect(tones(n), [PillTone.amber, PillTone.sky]);
    });

    test('dengue: the number of cases in red and the place it is near, opens Home', () {
      final n = dengueNote(s, locality: 'Tampines St 11', cases: 12, placeKind: 'school');
      expect(n.id, 4);
      expect(n.title, s.dengueTitle);
      expect(n.body, 'Tampines St 11 · 12 cases');
      expect(texts(n), ['12 cases', 'Near School']);
      expect(tones(n), [PillTone.red, PillTone.sky]);
      expect(n.link, 'dailylah://home');
    });

    test('lightning: its own title, stay indoors and where', () {
      final n = lightningNote(s, place: 'School');
      expect(n.id, 6);
      expect(n.title, 'Lightning nearby.');
      expect(n.body, 'Near School. Stay indoors.');
      expect(texts(n), ['⚡ Lightning nearby', 'Stay indoors']);
      expect(tones(n), [PillTone.red, PillTone.amber]);
      expect(n.link, 'dailylah://today');
    });

    test('resale: how many new sales at which block, opens Home', () {
      final n = homesNote(s, block: '156 TAMPINES ST 12', count: 2);
      expect(n.id, 7);
      expect(n.body, s.newSales('156 TAMPINES ST 12', 2));
      expect(texts(n), ['2 new sales', '156 TAMPINES ST 12']);
      expect(tones(n), [PillTone.mint, PillTone.sky]);
      expect(n.link, 'dailylah://home');
      expect(texts(homesNote(s, block: 'X', count: 1)).first, '1 new sale');
    });

    test('public holiday: the holiday note with one pill, so its events keep their lines', () {
      final n = holidayRichNote(s, 'Happy Deepavali', 'No commute today. Sunny near home.');
      expect(n.id, 20);
      expect(n.title, 'Happy Deepavali');
      expect(n.body, 'No commute today. Sunny near home.');
      // One pill: a second one needs a second row, which costs the events in the body two lines.
      expect(texts(n), ['Public holiday']);
      expect(tones(n), [PillTone.mint]);
      expect(n.link, 'dailylah://today');
    });

    test('MRT ride: next stop like Wake me, under its own id', () {
      final n = rideNextNote(s, 'Raffles Place');
      expect(n.id, 21, reason: 'not 11, which is the parking reminder');
      expect(n.title, s.rideTitle);
      expect(n.body, s.rideNextStop('Raffles Place'));
      expect(texts(n), ['Your stop is next']);
      expect(n.art, NoteArt.phone);
    });

    test('MRT ride: a disruption shows the line in its colour, under its own id', () {
      final n = rideDisruptedNote(s, 'EWL');
      expect(n.id, 22, reason: 'not 12, which is the Sunday digest');
      expect(n.body, s.rideDisrupted(s.lineName('EWL')));
      expect(texts(n), ['EWL', 'Disrupted']);
      expect(n.pills.first.lineColor, 0x009645);
      expect(n.link, 'dailylah://today');
    });

    test('watching for the stop: the bus, how far, on the location service notification', () {
      final n = wakeWatchNote(s, service: '36', stop: 'Suntec Twr Three', metresLeft: 872);
      expect(n.id, locationServiceNoteId);
      expect(n.title, s.wakeTitle);
      expect(n.body, 'Watching for your stop: Suntec Twr Three');
      expect(texts(n), ['36', '850 m to go']);
      expect(tones(n), [PillTone.board, PillTone.amber]);
      // Before the first fix there is no distance to show.
      expect(texts(wakeWatchNote(s, service: '36', stop: 'X')), ['36']);
      // Rounded, so the notification is not rewritten at every fix.
      expect(texts(wakeWatchNote(s, service: '36', stop: 'X', metresLeft: 2140)).last, '2.1 km to go');
      expect(texts(wakeWatchNote(s, service: '36', stop: 'X', metresLeft: 20)).last, '50 m to go');
    });

    test('riding to: the line and the stops to go, on the location service notification', () {
      final n = rideWatchNote(s, station: 'Raffles Place', line: 'EWL', stopsLeft: 3);
      expect(n.id, locationServiceNoteId);
      expect(n.title, s.rideTitle);
      expect(n.body, s.rideRunning('Raffles Place'));
      expect(texts(n), ['EWL', '3 stops to go']);
      expect(n.pills.first.lineColor, 0x009645);
      expect(texts(rideWatchNote(s, station: 'X', line: 'EWL', stopsLeft: 1)).last, '1 stop to go');
      expect(texts(rideWatchNote(s, station: 'X', line: null, stopsLeft: 0)), isEmpty);
    });

    test('the location plugin is the version whose notification id and channel we overwrite', () {
      // wakeWatchNote and rideWatchNote replace the content of geolocator_android's foreground
      // service notification, by its private id and channel (GeolocatorLocationService.java:
      // ONGOING_NOTIFICATION_ID, CHANNEL_ID). When this fails after an upgrade, read those two
      // constants in the new version, update locationServiceNoteId / locationServiceChannel if
      // they changed, then locationServicePluginVersion.
      final lock = File('pubspec.lock').readAsStringSync();
      final m = RegExp(r'geolocator_android:\n(?:    .*\n)*?    version: "([^"]+)"').firstMatch(lock);
      expect(m?.group(1), locationServicePluginVersion);
      expect(locationServiceNoteId, 75415);
      expect(locationServiceChannel, 'geolocator_channel_01');
    });

    test('no two alerts share a notification id', () {
      final ids = [for (final n in sampleNotes(s)) n.id - 100];
      expect(ids.toSet().length, ids.length);
      // Custom-place leave-by reminders take 13 to 17 (13 + i, five places at most).
      expect(ids.where((i) => i >= 13 && i <= 17), isEmpty);
    });

    test('sampleNotes has every alert under its own id', () {
      final notes = sampleNotes(s);
      // Their own ids (the alert's id + 100), so a sample never replaces a real alert in the shade.
      expect([for (final n in notes) n.id], [102, 108, 109, 101, 110, 103, 105, 112, 106, 104, 111, 107, 120, 121, 122, 123]);
      expect(notes.every((n) => n.pills.isNotEmpty && n.pills.length <= 3), isTrue);
      // A sample must not read like a real disruption or haze warning.
      expect(notes.every((n) => n.title.startsWith('Example: ')), isTrue);
      expect(notes.first.title, 'Example: Rain before you leave.');
    });

    test('toMap is plain data a method channel can carry', () {
      for (final n in sampleNotes(s)) {
        final m = n.toMap();
        final back = const StandardMessageCodec().decodeMessage(const StandardMessageCodec().encodeMessage(m)) as Map;
        expect(back['id'], n.id);
        expect(back['title'], n.title);
        expect(back['art'], n.art.name);
        expect((back['pills'] as List).length, n.pills.length);
        expect(((back['pills'] as List).first as Map)['tone'], n.pills.first.tone.name);
      }
      final mrt = mrtNote(s, const [ewl]).toMap();
      expect(((mrt['pills'] as List).first as Map)['lineColor'], 0x009645);
    });

    test('weekHabits: the last seven days of trips, oldest first, and what the week cost', () {
      final sunday = DateTime(2026, 10, 25, 19);
      TripLog trip(DateTime at, {int? cents}) => TripLog(route: 'home>work', start: at, minutes: 30, costCents: cents);
      final h = Habits(trips: [
        trip(DateTime(2026, 10, 19, 8), cents: 200), // Monday
        trip(DateTime(2026, 10, 19, 18), cents: 210),
        trip(DateTime(2026, 10, 23, 8), cents: 150), // Friday
        trip(DateTime(2026, 10, 18, 8), cents: 999), // the Sunday before: not this week
      ]);
      final w = weekHabits(h, sunday);
      expect(w.tripsPerDay, [2, 0, 0, 0, 1, 0, 0]);
      expect(w.cents, 560);
      expect(weekHabits(const Habits(), sunday).tripsPerDay, [0, 0, 0, 0, 0, 0, 0]);
      expect(weekHabits(const Habits(), sunday).cents, 0);
    });

    test('every MRT line has its colour in pure Dart', () {
      expect(mrtLineColors.keys, containsAll(['NSL', 'EWL', 'CCL', 'DTL', 'NEL', 'TEL', 'BPL', 'SLRT', 'PLRT']));
    });
  });

  group("already there: Today greets instead of showing the trip", () {
    const fav = Favorites(places: {
      PlaceKind.home: Place(kind: PlaceKind.home, addrLat: 1.3516, addrLng: 103.9450),
      PlaceKind.work: Place(
          kind: PlaceKind.work, addrLat: 1.2841, addrLng: 103.8514, go: TimeOfDayHM(8, 0), back: TimeOfDayHM(18, 0)),
    });
    DateTime tue(int h, [int m = 0]) => DateTime(2026, 10, 20, h, m);

    test('the saved place the phone is at: within 150 m of its address, the nearest', () {
      expect(savedPlaceAt(fav, 1.3516, 103.9450), PlaceKind.home);
      expect(savedPlaceAt(fav, 1.2850, 103.8514), PlaceKind.work); // 100 m north of the office
      expect(savedPlaceAt(fav, 1.2860, 103.8514), isNull); // 210 m
      // The edge itself (`arrivedMetres`, 150 m): a metre or two inside counts, outside does not.
      expect(distanceMeters(1.2841, 103.8514, 1.2841 + 0.00133, 103.8514), inInclusiveRange(147, 149.9));
      expect(savedPlaceAt(fav, 1.2841 + 0.00133, 103.8514), PlaceKind.work);
      expect(distanceMeters(1.2841, 103.8514, 1.2841 + 0.00137, 103.8514), inInclusiveRange(150.1, 153));
      expect(savedPlaceAt(fav, 1.2841 + 0.00137, 103.8514), isNull);
      expect(arrivedMetres, 150);
      // A place saved with bus stops only has no address to be at.
      const stopsOnly = Favorites(places: {
        PlaceKind.home: Place(kind: PlaceKind.home, stops: [BusStop(code: 'A', name: 'A', road: '', lat: 1.3, lng: 103.8)]),
      });
      expect(savedPlaceAt(stopsOnly, 1.3, 103.8), isNull);
    });

    test('arrived at work, still at work, about to leave, back home', () {
      // Morning card: at the office is arrived; at home the trip to work shows.
      expect(restingAt(CardKind.morning, fav, tue(9), PlaceKind.work), PlaceKind.work);
      expect(restingAt(CardKind.morning, fav, tue(7), PlaceKind.home), isNull);
      // Evening card (from 13:00): still working until an hour before the usual 18:00.
      expect(restingAt(CardKind.evening, fav, tue(15), PlaceKind.work), PlaceKind.work);
      expect(restingAt(CardKind.evening, fav, tue(16, 59), PlaceKind.work), PlaceKind.work);
      expect(restingAt(CardKind.evening, fav, tue(17), PlaceKind.work), isNull);
      expect(restingAt(CardKind.evening, fav, tue(19), PlaceKind.work), isNull);
      // Back home in the evening.
      expect(restingAt(CardKind.evening, fav, tue(19), PlaceKind.home), PlaceKind.home);
      // Elsewhere, or a day without a commute (Saturday): the usual card.
      expect(restingAt(CardKind.evening, fav, tue(19), null), isNull);
      expect(restingAt(CardKind.evening, fav, DateTime(2026, 10, 24, 19), PlaceKind.home), isNull);
    });

    test('a trip ended by being there is logged only when its time can be trusted', () {
      final start = tue(18);
      expect(arrivalLogMinutes(start, tue(18, 40), 38), 40);
      expect(arrivalLogMinutes(start, tue(18, 53), 38), 53);
      // Opened the app long after getting home, or no usual time yet: dropped, not logged.
      expect(arrivalLogMinutes(start, tue(19, 30), 38), isNull);
      expect(arrivalLogMinutes(start, tue(18, 40), null), isNull);
      expect(arrivalLogMinutes(start, tue(18, 2), 38), isNull);
    });

    test('the greeting', () {
      const s = S();
      expect(s.atPlaceTitle('work'), 'Have a good day at work');
      expect(s.atPlaceTitle('school'), 'Have a good day at school');
      expect(s.atPlaceTitle('home'), "You're home. Take a rest.");
      expect(s.atPlaceSub('work', '18.00'), contains('You usually leave at 18.00'));
    });
  });

  group('lunch suggestion', () {
    const s = S();
    Hawker h(String id, double lat, {List<Closure> closed = const []}) =>
        Hawker(id: id, name: 'Hawker $id', address: '', lat: lat, lng: 103.8514, closures: closed);
    final tue = DateTime(2026, 10, 20);
    // 110 m, 330 m and 2.2 km north of the office.
    final near = h('near', 1.2851);
    final far = h('far', 1.2871);
    final tooFar = h('toofar', 1.3041);
    const work = Place(
        kind: PlaceKind.work, addrLat: 1.2841, addrLng: 103.8514, go: TimeOfDayHM(8, 0), back: TimeOfDayHM(18, 0));
    const fav = Favorites(
      places: {PlaceKind.home: Place(kind: PlaceKind.home, addrLat: 1.3516, addrLng: 103.9450), PlaceKind.work: work},
      lunchAlerts: true,
    );

    test('the nearest open hawker centre, a starred one first, none beyond 1 km', () {
      expect(lunchPick([far, near, tooFar], const {}, 1.2841, 103.8514, tue)!.hawker.id, 'near');
      final starred = lunchPick([far, near], const {'far'}, 1.2841, 103.8514, tue)!;
      expect(starred.hawker.id, 'far');
      expect(starred.starred, isTrue);
      expect(starred.metres, closeTo(330, 15));
      // Closed today: the next one.
      final shut = h('near', 1.2851, closed: [Closure(tue, tue, 'Cleaning')]);
      expect(lunchPick([shut, far], const {'near'}, 1.2841, 103.8514, tue)!.hawker.id, 'far');
      expect(lunchPick([tooFar], const {}, 1.2841, 103.8514, tue), isNull);
    });

    test('only when switched on, on a work or school day, around the time set', () {
      expect(lunchPlace(fav, DateTime(2026, 10, 20, 12))!.kind, PlaceKind.work);
      expect(lunchPlace(fav, DateTime(2026, 10, 24, 12)), isNull, reason: 'Saturday');
      expect(lunchPlace(fav.copyWith(lunchAlerts: false), DateTime(2026, 10, 20, 12)), isNull);
      expect(const Favorites().lunchAlerts, isFalse);
      const at = TimeOfDayHM(12, 0);
      expect(inLunchWindow(DateTime(2026, 10, 20, 11, 59), at), isFalse);
      expect(inLunchWindow(DateTime(2026, 10, 20, 12), at), isTrue);
      expect(inLunchWindow(DateTime(2026, 10, 20, 12, 44), at), isTrue);
      expect(inLunchWindow(DateTime(2026, 10, 20, 12, 45), at), isFalse);
      expect(lunchCardDue(DateTime(2026, 10, 20, 11, 30), at), isTrue);
      expect(lunchCardDue(DateTime(2026, 10, 20, 11, 29), at), isFalse);
      expect(lunchCardDue(DateTime(2026, 10, 20, 14), at), isFalse);
    });

    test('the setting survives saving and loading', () {
      final back = Favorites.fromJson(fav.copyWith(lunchAt: const TimeOfDayHM(12, 30)).toJson());
      expect(back.lunchAlerts, isTrue);
      expect(back.lunchAt.minutes, 12 * 60 + 30);
      // Saved before this setting existed: off, at 12:00.
      final old = Favorites.fromJson(fav.toJson()..remove('lunchAlerts')..remove('lunchAt'));
      expect(old.lunchAlerts, isFalse);
      expect(old.lunchAt.minutes, 12 * 60);
    });

    test('alertsOn counts the nine alerts More can switch', () {
      expect(alertsOn(const Favorites()), lessThanOrEqualTo(alertKinds));
      final all = const Favorites().copyWith(
          mrtAlerts: true, rainAlerts: true, leaveAlerts: true, heatAlerts: true, dengueAlerts: true,
          homesAlerts: true, hawkerAlerts: true, digestAlerts: true, lunchAlerts: true);
      expect(alertsOn(all), alertKinds);
      expect(alertsOn(all.copyWith(lunchAlerts: false, rainAlerts: false)), alertKinds - 2);
    });

    test('the note names the place, never says where the user is, and opens Nearby on Eat', () {
      final n = lunchNote(s, place: 'Work', pick: LunchPick(near, 110, starred: true), rainy: true);
      expect(n.id, 23);
      expect(n.title, 'Lunch time');
      expect(n.body, 'Near Work: Hawker near, 110 m, open today. Tap to see what is near you now.');
      expect([for (final p in n.pills) p.text], ['Hawker near, 110 m', 'Your favourite', 'Rain expected']);
      expect(n.link, 'dailylah://nearby/eat');
      final none = lunchNote(s, place: 'Work');
      expect(none.body, 'Tap to see where to eat near you now.');
      // Never a plain notification: the picture and one pill even with no hawker centre to name.
      expect([for (final p in none.pills) p.text], ['Where to eat']);
      expect(none.art, NoteArt.lunch);
      expect(n.art, NoteArt.lunch);
    });
  });
}
