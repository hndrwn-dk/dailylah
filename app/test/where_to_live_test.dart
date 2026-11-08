// "Where to live?" in the app: the bundle model and the ranking/compare rules ported from
// web/where-to-live/logic.js (web/tests/logic.test.mjs has the same cases for the site).
import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> cell(int median, [String quarter = '2026-Q3']) => {'median': median, 'quarter': quarter};

/// The same small data set as web/tests/logic.test.mjs.
Map<String, Object?> fixture() => {
      'generated_at': '2026-11-07T13:39:45Z',
      'rent_quarter': '2026-Q3',
      'resale_quarter': '2026-Q2',
      'areas': [
        {'id': 'cbd', 'name': 'CBD (Raffles Place)', 'station': 'Raffles Place', 'lat': 1.28, 'lng': 103.85},
        {'id': 'jurong-east', 'name': 'Jurong East', 'station': 'Jurong East', 'lat': 1.33, 'lng': 103.74},
      ],
      'towns': [
        {
          'id': 'bishan', 'name': 'Bishan', 'station': 'Bishan', 'lat': 1.35, 'lng': 103.85,
          'rent': {'3-ROOM': cell(3000), '4-ROOM': cell(3700)},
          'resale': {'4-ROOM': cell(700000, '2026-Q2')},
          'commute': {
            'cbd': {'min': 20, 'transfers': 0},
            'jurong-east': {'min': 40, 'transfers': 1},
          },
        },
        {
          'id': 'punggol', 'name': 'Punggol', 'station': 'Punggol', 'lat': 1.4, 'lng': 103.9,
          'rent': {'3-ROOM': cell(2850), '4-ROOM': cell(3300, '2026-Q1')},
          'resale': {'4-ROOM': cell(610000, '2026-Q2')},
          'commute': {
            'cbd': {'min': 45, 'transfers': 1},
            'jurong-east': {'min': 70, 'transfers': 2},
          },
        },
        {
          'id': 'jurong-east', 'name': 'Jurong East', 'station': 'Jurong East', 'lat': 1.33, 'lng': 103.74,
          'rent': {'3-ROOM': cell(2700), '4-ROOM': null},
          'resale': {'4-ROOM': cell(560000, '2026-Q2')},
          'commute': {
            'cbd': {'min': 35, 'transfers': 0},
            'jurong-east': {'min': null, 'transfers': null, 'same_area': true},
          },
        },
        {
          'id': 'central', 'name': 'Central Area', 'station': 'Tanjong Pagar', 'lat': 1.27, 'lng': 103.84,
          'rent': {'3-ROOM': cell(3500), '4-ROOM': cell(4200)},
          'resale': <String, Object?>{},
          'commute': {'cbd': null, 'jurong-east': {'min': 30, 'transfers': 0}},
        },
      ],
    };

WhereToLive data([void Function(Map<String, Object?> j)? edit]) {
  final j = jsonDecode(jsonEncode(fixture())) as Map<String, dynamic>;
  edit?.call(j);
  return WhereToLive.fromBundle(j);
}

Map<String, dynamic> town(Map<String, Object?> j, String id) =>
    (j['towns'] as List).cast<Map<String, dynamic>>().firstWhere((t) => t['id'] == id);

void setFare(Map<String, Object?> j, String id, String area, int cents) =>
    (town(j, id)['commute'] as Map)[area]['fare'] = cents;

List<String> ids(List<WtlRow> rows) => [for (final r in rows) r.town.id];
WtlLine line(({List<WtlTown> towns, List<WtlLine> lines}) t, WtlLineKey k) => t.lines.firstWhere((l) => l.key == k);
List<bool> bests(WtlLine l) => [for (final c in l.cells) c.best];
List<WtlCellKind> kinds(WtlLine l) => [for (final c in l.cells) c.kind];
List<int?> shown(WtlLine l) => [for (final c in l.cells) c.shown];

void main() {
  group('bundle', () {
    test('reads areas, towns, prices with their quarter and trips', () {
      final d = data();
      expect(d.areas.map((a) => a.id), ['cbd', 'jurong-east']);
      final bishan = d.towns.first;
      expect(bishan.rent['4-ROOM']!.median, 3700);
      expect(bishan.rent['4-ROOM']!.quarter, '2026-Q3');
      expect(bishan.commute['cbd']!.min, 20);
      expect(d.towns[2].rent['4-ROOM'], isNull); // not enough data
      expect(d.towns[2].commute['jurong-east']!.sameArea, isTrue);
      expect(d.towns[3].commute['cbd'], isNull); // no route data
    });

    test('skips towns with an id the site would not serve, and bad shapes', () {
      final d = data((j) {
        (j['towns'] as List).add({'id': '../evil', 'name': 'X', 'lat': 1, 'lng': 2});
        (j['towns'] as List).add({'id': 'no-position', 'name': 'Y'});
        (j['towns'] as List).add('not a town');
      });
      expect(d.towns.map((t) => t.id), ['bishan', 'punggol', 'jurong-east', 'central']);
      expect(WhereToLive.fromBundle(const {}).isEmpty, isTrue);
    });

    test('numbers too big for a double are left out, not a crash', () {
      final huge = jsonDecode('1e400') as num; // Infinity
      final d = data((j) {
        town(j, 'bishan')['rent']['4-ROOM'] = {'median': huge, 'quarter': '2026-Q3'};
        (town(j, 'punggol')['commute'] as Map)['cbd'] = {'min': huge, 'transfers': 0};
        town(j, 'central')['lat'] = huge;
      });
      expect(d.towns.firstWhere((t) => t.id == 'bishan').rent['4-ROOM'], isNull);
      expect(d.towns.firstWhere((t) => t.id == 'punggol').commute['cbd'], isNull);
      expect(d.towns.map((t) => t.id), isNot(contains('central')));
    });

    test('the committed web/data/where-to-live.json reads in full', () {
      final raw = File('../web/data/where-to-live.json').readAsStringSync();
      final d = WhereToLive.fromBundle(jsonDecode(raw) as Map<String, dynamic>);
      expect(d.areas, hasLength(6));
      expect(d.towns.length, greaterThanOrEqualTo(20));
      final woodlands = d.towns.firstWhere((t) => t.id == 'woodlands');
      expect(woodlands.commute['woodlands']!.sameArea, isTrue);
    });
  });

  group('choices', () {
    test('flat types with prices for the mode, smallest first', () {
      expect(wtlFlatTypes(data(), WtlMode.rent), ['3-ROOM', '4-ROOM']);
      expect(wtlFlatTypes(data(), WtlMode.buy), ['4-ROOM']);
    });

    test('unknown choices fall back to defaults, compare ids from the data only', () {
      final c = wtlChecked(
        data(),
        const WtlChoice(area: 'mars', mode: WtlMode.buy, flat: '3-ROOM', budget: -5, maxMinutes: 44, compare: ['punggol', 'x', 'punggol']),
      );
      expect(c.area, 'cbd');
      expect(c.flat, '4-ROOM'); // no 3-room resale prices
      expect(c.budget, isNull);
      expect(c.maxMinutes, isNull);
      expect(c.compare, ['punggol']);
    });

    test('switching rent / buy drops the budget; budgets have a ceiling', () {
      final d = data();
      const rent = WtlChoice(area: 'cbd', budget: 3500, flat: '3-ROOM');
      final buy = wtlChangeMode(d, rent, WtlMode.buy);
      expect(buy.mode, WtlMode.buy);
      expect(buy.budget, isNull); // a rent of 3500 is not a resale budget of $3,500
      expect(buy.flat, '4-ROOM'); // no 3-room resale prices
      expect(wtlChangeMode(d, rent, WtlMode.rent), same(rent));
      final back = wtlChangeMode(d, const WtlChoice(area: 'cbd', mode: WtlMode.buy, budget: 650000), WtlMode.rent);
      expect(back.budget, isNull);
      expect(wtlChecked(d, const WtlChoice(area: 'cbd', budget: 100001)).budget, isNull);
      expect(wtlChecked(d, const WtlChoice(area: 'cbd', budget: 100000)).budget, 100000);
      expect(wtlChecked(d, const WtlChoice(area: 'cbd', mode: WtlMode.buy, budget: 650000)).budget, 650000);
      expect(wtlChecked(d, const WtlChoice(area: 'cbd', mode: WtlMode.buy, budget: 10000001)).budget, isNull);
    });

    test('the nearest office area to a saved place, within 5 km', () {
      final d = data();
      final near = wtlNearestArea(d, 1.285, 103.851)!;
      expect(near.area.id, 'cbd');
      expect(near.meters, lessThan(1000));
      expect(wtlNearestArea(d, 1.45, 104.0), isNull); // far from both: the user picks
    });

    test('ranks for work, else school, when the place has a position', () {
      const school = Place(kind: PlaceKind.school, addrLat: 1.3, addrLng: 103.8);
      const work = Place(kind: PlaceKind.work, addrLat: 1.28, addrLng: 103.85);
      expect(wtlAnchorPlace({PlaceKind.school: school, PlaceKind.work: work}), same(work));
      expect(wtlAnchorPlace({PlaceKind.school: school}), same(school));
      expect(wtlAnchorPlace({PlaceKind.work: const Place(kind: PlaceKind.work)}), isNull);
    });
  });

  group('rank', () {
    test('groups by fit, sorted by time then price', () {
      final g = wtlRank(data(), const WtlChoice(area: 'cbd'));
      expect(ids(g[WtlGroup.match]!), ['bishan', 'jurong-east', 'punggol']);
      expect(ids(g[WtlGroup.other]!), ['central']);
      expect(g[WtlGroup.other]!.single.reason, WtlReason.route);
    });

    test('time limit and budget', () {
      final g = wtlRank(data(), const WtlChoice(area: 'cbd', budget: 3500, maxMinutes: 30));
      expect(ids(g[WtlGroup.match]!), []); // bishan over budget, the rest too far
      expect(ids(g[WtlGroup.noPrice]!), []);
      final g2 = wtlRank(data(), const WtlChoice(area: 'cbd', budget: 3500));
      expect(ids(g2[WtlGroup.match]!), ['punggol']);
      expect(ids(g2[WtlGroup.noPrice]!), ['jurong-east']);
      expect({for (final r in g2[WtlGroup.other]!) r.town.id: r.reason}, {'bishan': WtlReason.budget, 'central': WtlReason.route});
    });

    test("the office area's own town comes first", () {
      final g = wtlRank(data(), const WtlChoice(area: 'jurong-east'));
      expect(ids(g[WtlGroup.match]!).first, 'jurong-east');
      expect(g[WtlGroup.match]!.first.minutes, 0);
    });

    test('monthly fares, hours and all-in', () {
      final d = data((j) => setFare(j, 'punggol', 'cbd', 211));
      final row = wtlRank(d, const WtlChoice(area: 'cbd'))[WtlGroup.match]!.firstWhere((r) => r.town.id == 'punggol');
      final m = wtlMonthly(const WtlChoice(area: 'cbd'), row)!;
      expect(m.fares, 93); // 2.11 x 2 x 22 = 92.84
      expect(m.hours, 33);
      expect(m.total, 3393);
      expect(wtlMonthly(const WtlChoice(area: 'cbd', mode: WtlMode.buy), row)!.total, isNull);
    });

    test('fastest and best value among towns that fit', () {
      // CBD, 4-room rent: Bishan 20 min $3,700; Jurong East 35 (no price); Punggol 45 $3,300.
      // Priced candidates: 20 and 45 -> median 32.5, so only Bishan is at or under it.
      final h = wtlHighlights(wtlRank(data(), const WtlChoice(area: 'cbd')))!;
      expect(h.fastest.town.id, 'bishan');
      expect(h.value.town.id, 'bishan');
      // 3-room: Bishan 20 $3,000, Jurong East 35 $2,700, Punggol 45 $2,850 -> median 35:
      // Bishan and Jurong East qualify (at or under), and Jurong East is cheaper.
      final h3 = wtlHighlights(wtlRank(data(), const WtlChoice(area: 'cbd', flat: '3-ROOM')))!;
      expect(h3.fastest.town.id, 'bishan');
      expect(h3.value.town.id, 'jurong-east');
    });

    test('highlights: the office area own town, buying, and nothing that fits', () {
      final same = wtlHighlights(wtlRank(data(), const WtlChoice(area: 'jurong-east', flat: '3-ROOM')))!;
      expect(same.fastest.town.id, 'jurong-east');
      expect(same.fastest.minutes, 0);
      final buy = wtlHighlights(wtlRank(data(), const WtlChoice(area: 'cbd', mode: WtlMode.buy)))!;
      expect(buy.fastest.town.id, 'bishan');
      expect(buy.fastest.price!.median, 700000);
      expect(wtlHighlights(wtlRank(data(), const WtlChoice(area: 'cbd', budget: 1000))), isNull);
      expect(wtlHighlights(wtlRank(data(), const WtlChoice(area: 'jurong-east', maxMinutes: 30)))!.fastest.town.id, 'central');
    });
  });

  group('compare', () {
    test('ids and toggling stop at three', () {
      expect(wtlCompareIds(['punggol', 'punggol', 'nowhere', 'bishan', 'central', 'jurong-east'], data()), ['punggol', 'bishan', 'central']);
      expect(wtlToggleCompare([], 'punggol'), ['punggol']);
      expect(wtlToggleCompare(['punggol', 'bishan'], 'punggol'), ['bishan']);
      final full = ['punggol', 'bishan', 'central'];
      expect(wtlToggleCompare(full, 'jurong-east'), same(full));
    });

    test('a column per town and the best value in each line', () {
      final d = data((j) {
        setFare(j, 'bishan', 'cbd', 160);
        setFare(j, 'punggol', 'cbd', 211);
      });
      final t = wtlCompareTable(d, const WtlChoice(area: 'cbd', compare: ['punggol', 'bishan']));
      expect(t.towns.map((x) => x.id), ['punggol', 'bishan']);
      expect(shown(line(t, WtlLineKey.time)), [45, 20]);
      expect(bests(line(t, WtlLineKey.time)), [false, true]);
      expect(shown(line(t, WtlLineKey.fare)), [211, 160]);
      expect(line(t, WtlLineKey.price).cells.first.quarter, '2026-Q1');
      expect(bests(line(t, WtlLineKey.price)), [true, false]);
      expect(shown(line(t, WtlLineKey.allIn)), [3393, 3770]);
      expect(bests(line(t, WtlLineKey.allIn)), [true, false]);
      expect(shown(line(t, WtlLineKey.hours)), [33, 15]);
    });

    test('ties are all best, unknowns never are, one value marks nothing', () {
      final d = data((j) => (town(j, 'punggol')['commute'] as Map)['cbd'] = {'min': 20, 'transfers': 0});
      final t = wtlCompareTable(d, const WtlChoice(area: 'cbd', compare: ['bishan', 'punggol', 'jurong-east']));
      expect(bests(line(t, WtlLineKey.time)), [true, true, false]);
      expect(kinds(line(t, WtlLineKey.fare)), [WtlCellKind.unknown, WtlCellKind.unknown, WtlCellKind.unknown]);
      expect(bests(line(t, WtlLineKey.fare)), [false, false, false]);
      expect(line(t, WtlLineKey.price).cells[2].kind, WtlCellKind.unknown);
      final one = wtlCompareTable(data(), const WtlChoice(area: 'cbd', compare: ['central', 'bishan']));
      expect(line(one, WtlLineKey.time).cells.first.kind, WtlCellKind.noRoute);
      expect(bests(line(one, WtlLineKey.time)), [false, false]);
    });

    test("the office area's town: in this area, no best in all-in and hours while compared", () {
      final d = data((j) {
        setFare(j, 'bishan', 'jurong-east', 190);
        setFare(j, 'punggol', 'jurong-east', 245);
      });
      const c = WtlChoice(area: 'jurong-east', compare: ['jurong-east', 'bishan', 'punggol']);
      final t = wtlCompareTable(d, c);
      for (final k in [WtlLineKey.time, WtlLineKey.transfers, WtlLineKey.fare, WtlLineKey.hours]) {
        expect(line(t, k).cells.first.kind, WtlCellKind.inArea, reason: '$k');
        expect(line(t, k).cells.first.best, isFalse, reason: '$k');
      }
      // No 4-room rent for Jurong East here: its all-in cell is "in this area" too.
      expect(line(t, WtlLineKey.allIn).cells.first.kind, WtlCellKind.inArea);
      expect(bests(line(t, WtlLineKey.time)), [false, true, false]);
      expect(bests(line(t, WtlLineKey.fare)), [false, true, false]);
      expect(bests(line(t, WtlLineKey.allIn)), [false, false, false]);
      expect(bests(line(t, WtlLineKey.hours)), [false, false, false]);
      // Without it, all-in and hours mark their best again.
      final others = wtlCompareTable(d, c.copyWith(compare: ['bishan', 'punggol']));
      expect(bests(line(others, WtlLineKey.allIn)), [false, true]);
      expect(bests(line(others, WtlLineKey.hours)), [true, false]);
      // Buy mode: fares a month instead of all-in, same rule.
      final buy = wtlCompareTable(d, c.copyWith(mode: WtlMode.buy));
      expect(line(buy, WtlLineKey.faresMonth).cells.first.kind, WtlCellKind.inArea);
      expect(bests(line(buy, WtlLineKey.faresMonth)), [false, false, false]);
      expect(bests(line(buy, WtlLineKey.price)), [true, false, false]); // 560k, 700k, 610k
    });

    test('Woodlands to Woodlands on the real data: rent with no fare estimate', () {
      final real = WhereToLive.fromBundle(
        jsonDecode(File('../web/data/where-to-live.json').readAsStringSync()) as Map<String, dynamic>,
      );
      final t = wtlCompareTable(real, const WtlChoice(area: 'woodlands', compare: ['woodlands', 'ang-mo-kio', 'bedok']));
      final wood = real.towns.firstWhere((x) => x.id == 'woodlands');
      final rent = wood.rent['4-ROOM'];
      final allIn = line(t, WtlLineKey.allIn).cells.first;
      // The data is rebuilt weekly: without a 4-room rent the cell is "in this area".
      expect(allIn.kind, rent == null ? WtlCellKind.inArea : WtlCellKind.inAreaRent);
      expect(allIn.shown, rent?.median);
      expect(allIn.score, isNull);
      expect(bests(line(t, WtlLineKey.allIn)), [false, false, false]);
      expect(bests(line(t, WtlLineKey.hours)), [false, false, false]);
      expect(line(t, WtlLineKey.time).cells.first.best, isFalse);
    });
  });

  group('block page', () {
    test('an HDB town name finds its where-to-live town', () {
      final d = data();
      expect(wtlTownFor(d, 'BISHAN')?.id, 'bishan');
      expect(wtlTownFor(d, 'CENTRAL AREA')?.id, 'central');
      expect(wtlTownFor(d, ' jurong east ')?.id, 'jurong-east');
      expect(wtlTownFor(d, 'TENGAH'), isNull);
    });

    test('rents: the quarterly medians when the town is in the data, one source per town', () {
      const six = RentData(period: '2026-05 – 2026-10', towns: {
        'BISHAN': {'4-ROOM': 3650, '3-ROOM': 2950, 'EXECUTIVE': 4800},
        'TENGAH': {'4-ROOM': 3300},
      });
      final r = townRents(data(), six, 'BISHAN');
      // Not 3650: the six-month figure is not mixed in, nor its executive rent.
      expect(r.keys, ['3-ROOM', '4-ROOM']);
      expect(r['4-ROOM'], (median: 3700, period: '2026-Q3', quarterly: true));
      // A town the bundle lacks keeps the six-month median, with its period.
      expect(
          townRents(data(), six, 'TENGAH'), {'4-ROOM': (median: 3300, period: '2026-05 – 2026-10', quarterly: false)});
      // No where-to-live bundle at all.
      expect(townRents(null, six, 'BISHAN')['4-ROOM']!.median, 3650);
      expect(townRents(null, null, 'BISHAN'), isEmpty);
    });

    test('the rent quoted for a block: its flat type, else the smallest one', () {
      final r = townRents(data(), null, 'BISHAN');
      expect(townRentFor(r, '4 ROOM')!.$1, '4-ROOM');
      expect(townRentFor(r, 'EXECUTIVE')!.$1, '3-ROOM');
      expect(townRentFor(const {}, '4-ROOM'), isNull);
    });

    test('the area nearest the saved work place, unless one was picked', () {
      final d = data();
      const work = Place(kind: PlaceKind.work, address: 'RAFFLES PLACE', addrLat: 1.2801, addrLng: 103.8501);
      const fav = Favorites(places: {PlaceKind.work: work});
      final near = wtlChoiceFor(d, fav);
      expect(near.choice.area, 'cbd');
      expect(near.anchor, same(work));
      final picked = wtlChoiceFor(d, fav.copyWith(wtlArea: 'jurong-east', wtlMode: 'buy', wtlFlat: '3-ROOM'));
      expect(picked.choice.area, 'jurong-east');
      expect(picked.anchor, isNull);
      expect(picked.choice.mode, WtlMode.buy);
      // No 3-room resale in the data: back to 4-room.
      expect(picked.choice.flat, '4-ROOM');
      expect(wtlChoiceFor(d, const Favorites()).choice.area, 'cbd');
    });

    test('sort by price: cheapest first, no price last, then by time', () {
      final g = wtlRank(data(), const WtlChoice(area: 'cbd'));
      final all = [...g[WtlGroup.match]!, ...g[WtlGroup.other]!];
      expect(ids(wtlSorted(all, WtlSort.time)), ids(all));
      expect(ids(wtlSorted(all, WtlSort.price)), ['punggol', 'bishan', 'central', 'jurong-east']);
    });
  });

  group('block compare', () {
    test('each block takes its town column; two blocks in one town share it', () {
      final d = data();
      final lines = wtlBlockLines(d, const WtlChoice(area: 'cbd'), ['BISHAN', 'PUNGGOL', 'BISHAN']);
      expect(lines.map((l) => l.key),
          [WtlLineKey.time, WtlLineKey.transfers, WtlLineKey.fare, WtlLineKey.allIn, WtlLineKey.hours]);
      final time = lines.first;
      expect(shown(time), [20, 45, 20]);
      expect(bests(time), [true, false, true]);
    });

    test('a block whose town is not in the data is unknown and takes no part in best', () {
      final lines = wtlBlockLines(data(), const WtlChoice(area: 'cbd'), ['TENGAH', 'BISHAN']);
      expect(kinds(lines.first), [WtlCellKind.unknown, WtlCellKind.value]);
      expect(bests(lines.first), [false, false]);
    });

    test('the office area town: in this area, its rent with no fare estimate, no best in all-in and hours', () {
      final d = data((j) {
        setFare(j, 'bishan', 'jurong-east', 200);
        setFare(j, 'punggol', 'jurong-east', 250);
      });
      final lines =
          wtlBlockLines(d, const WtlChoice(area: 'jurong-east', flat: '3-ROOM'), ['JURONG EAST', 'BISHAN', 'PUNGGOL']);
      WtlLine of(WtlLineKey k) => lines.firstWhere((l) => l.key == k);
      expect(kinds(of(WtlLineKey.time)), [WtlCellKind.inArea, WtlCellKind.value, WtlCellKind.value]);
      expect(bests(of(WtlLineKey.time)), [false, true, false]);
      expect(kinds(of(WtlLineKey.allIn)).first, WtlCellKind.inAreaRent);
      expect(shown(of(WtlLineKey.allIn)).first, 2700);
      expect(bests(of(WtlLineKey.allIn)), [false, false, false]);
      expect(bests(of(WtlLineKey.hours)), [false, false, false]);
    });

    test('buying: fares a month instead of all-in', () {
      final lines = wtlBlockLines(data(), const WtlChoice(area: 'cbd', mode: WtlMode.buy), ['BISHAN']);
      expect(lines.map((l) => l.key), contains(WtlLineKey.faresMonth));
      expect(lines.map((l) => l.key), isNot(contains(WtlLineKey.allIn)));
    });
  });
}
