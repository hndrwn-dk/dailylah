import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
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
}
