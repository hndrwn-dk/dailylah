import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dailylah/transit.dart';
import 'package:flutter_test/flutter_test.dart' hide within;

dynamic _bundle(String name) => jsonDecode(File('../web/data/$name').readAsStringSync());

void main() {
  final stops = [for (final j in _bundle('bus_stops.json') as List) BusStop.fromBundle(j as Map<String, dynamic>)];
  final routes = BusRoutes.fromBundle(_bundle('bus_routes.json') as Map<String, dynamic>);
  final stations = [
    for (final j in _bundle('mrt_stations.json') as List) MrtStation.fromBundle(j as Map<String, dynamic>),
  ];
  final net = TransitNet.build(stops, routes, stations);

  group('transit net', () {
    test('the net has every bus stop that a route uses and one node per MRT station', () {
      expect(net.nodeCount, greaterThan(5000));
      expect(net.hasNode('92271'), isTrue);
      expect(net.hasNode('mrt:Marine Parade'), isTrue);
      expect(net.isEmpty, isFalse);
    });

    test('MRT neighbours are on the same prefix', () {
      expect(net.mrtNext('mrt:Marine Parade', 'TE'), containsAll(['mrt:Marine Terrace', 'mrt:Tanjong Katong']));
      final dtStations = {
        for (final s in stations)
          if (s.codes.any((c) => c.startsWith('DT'))) 'mrt:${s.name}',
      };
      // Bukit Panjang is on both BP and DT: its BP neighbours are LRT stations only.
      final bp = net.mrtNext('mrt:Bukit Panjang', 'BP');
      expect(bp, isNotEmpty);
      expect(bp.where((n) => dtStations.contains(n) && n != 'mrt:Bukit Panjang'), isEmpty);
    });

    test('walk links stay within 250 m', () {
      final links = net.walkLinks('92271');
      expect(links.every((l) => l.$2 <= transferWalkMetres), isTrue);
      expect(links.map((l) => l.$1), contains('92279'));
    });

    test('empty bundles give an empty net', () {
      expect(TransitNet.build(const [], BusRoutes.empty, const []).isEmpty, isTrue);
    });
  });

  group('transit options', () {
    const marineParade = Place(kind: PlaceKind.other, addrLat: 1.3050, addrLng: 103.9085);
    const stEngineeringHub = Place(kind: PlaceKind.other, addrLat: 1.3917, addrLng: 103.8480);
    final options = transitOptions(net, marineParade, stEngineeringHub);

    test('Marine Parade to ST Engineering Hub has a bus option with a change and an MRT option', () {
      expect(options, hasLength(3));
      expect(options.any((o) => o.changes >= 1 && o.rides.every((r) => r.kind == LegKind.bus)), isTrue);
      expect(options.any((o) => o.rides.any((r) => r.kind == LegKind.mrt && r.service == 'TEL')), isTrue);
      expect(options.map((o) => o.signature).toSet(), hasLength(3));
      for (var i = 1; i < options.length; i++) {
        expect(options[i].minutes, greaterThanOrEqualTo(options[i - 1].minutes));
      }
    });

    test('a trip with a direct bus puts a one-ride option first or second', () {
      const dEcosia = Place(kind: PlaceKind.other, addrLat: 1.306338, addrLng: 103.909649);
      const bendemeer = Place(kind: PlaceKind.other, addrLat: 1.326856, addrLng: 103.86951);
      final top = transitOptions(net, dEcosia, bendemeer).take(2);
      expect(top.any((o) => o.rides.length == 1 && o.rides.single.service == '966'), isTrue);
    });

    test('peak-hour and night services are left out', () {
      expect(peakOnlyService('196e'), isTrue);
      expect(peakOnlyService('670'), isTrue);
      expect(peakOnlyService('NR6'), isTrue);
      expect(peakOnlyService('966'), isFalse);
      expect(peakOnlyService('857B'), isFalse);
      expect(peakOnlyService('70M'), isFalse);
      for (final o in options) {
        expect(o.rides.where((r) => peakOnlyService(r.service!)), isEmpty, reason: o.signature);
      }
    });

    test('no option rides back to where the start could walk to', () {
      for (final o in options) {
        expect(o.rides.skip(1).any((r) => r.from == 'mrt:Marine Parade' || r.from.startsWith('920')), isFalse,
            reason: o.signature);
      }
    });

    test('a station over 1 km away can be reached by a feeder bus', () {
      const gulCircle = Place(kind: PlaceKind.other, addrLat: 1.31796, addrLng: 103.676608); // 1.1 km from the station
      const rafflesPlace = Place(kind: PlaceKind.other, addrLat: 1.2837, addrLng: 103.8515);
      final found = transitOptions(net, gulCircle, rafflesPlace);
      expect(
        found.any((o) => o.rides.first.kind == LegKind.bus && o.rides.skip(1).any((r) => r.kind == LegKind.mrt)),
        isTrue,
        reason: found.map((o) => o.signature).join(', '),
      );
    });

    test('the same place gives no options', () {
      expect(transitOptions(net, marineParade, marineParade), isEmpty);
    });

    test('an empty net gives no options', () {
      final empty = TransitNet.build(const [], BusRoutes.empty, const []);
      expect(transitOptions(empty, marineParade, stEngineeringHub), isEmpty);
    });

    test('a ride never goes backwards on a loop', () {
      for (final o in options) {
        for (final r in o.rides.where((r) => r.kind == LegKind.bus)) {
          final codes = [for (final (c, _) in routes.routes[r.routeKey]!) c];
          final i = codes.indexOf(r.from);
          expect(i, isNonNegative);
          expect(codes.indexOf(r.to, i + 1), greaterThan(i), reason: '${r.service} ${r.from}>${r.to}');
          expect(r.stops, greaterThan(0));
        }
      }
    });

    test('legs add up and run from door to door', () {
      for (final o in options) {
        expect(o.minutes, o.legs.fold<int>(0, (s, l) => s + l.minutes));
        expect(o.legs.first.from, '');
        expect(o.legs.last.to, '');
        for (var i = 1; i < o.legs.length; i++) {
          expect(o.legs[i].from, o.legs[i - 1].to);
          expect(o.legs[i].kind == LegKind.walk && o.legs[i - 1].kind == LegKind.walk, isFalse);
        }
      }
    });

    test('fast enough', () {
      final watch = Stopwatch()..start();
      transitOptions(net, marineParade, stEngineeringHub);
      expect(watch.elapsedMilliseconds, lessThan(1500));
    });
  });

  test('the options provider finds the Marine Parade trip once the net is built', () async {
    final box = ProviderContainer(retry: noRetry, overrides: [
      busStopsProvider.overrideWith((ref) async => stops),
      busRoutesProvider.overrideWith((ref) async => routes),
      mrtStationsProvider.overrideWith((ref) async => stations),
    ]);
    addTearDown(box.dispose);
    const ends = (1.3050, 103.9085, 1.3917, 103.8480);
    final sub = box.listen(transitOptionsProvider(ends), (_, __) {});
    expect(sub.read(), isEmpty);
    await box.read(transitNetProvider.future);
    expect(box.read(transitOptionsProvider(ends)), hasLength(3));
    sub.close();
  });
}
