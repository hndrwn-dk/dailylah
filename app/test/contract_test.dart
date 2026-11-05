// Contract between the app and the backend (docs/QA.md, "Contract tests").
//
// contracts/v1 holds one example response per /v1/* endpoint. backend/tests/test_contracts.py
// checks the server still answers with that structure; this file checks the app's parsers still
// read the same examples. A changed response updates the example, and both sides run on it.
import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:flutter_test/flutter_test.dart' hide within;

/// Blk 201 Ang Mo Kio Ave 3, the home in the examples.
const lat = 1.3691;
const lng = 103.8454;

Map<String, dynamic> response(String name) {
  final file = File('../contracts/v1/$name.json');
  return (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['response'] as Map<String, dynamic>;
}

/// Every example and the test below that reads it; a new example needs a check here.
final checks = <String, void Function(Map<String, dynamic>)>{
  'weather_forecast': (body) {
    final f = forecastNear(body, lat, lng)!;
    expect(f.area, 'Ang Mo Kio');
    expect(f.forecast, 'Thundery Showers');
  },
  'weather_rainfall': (body) {
    final r = rainfallNear(body, lat, lng)!;
    expect(r.$1, 'Ang Mo Kio Avenue 5');
    expect(r.$2, 0.4);
  },
  'weather_psi': (body) {
    final a = airNear(body, null, lat, lng)!;
    expect(a.region, 'central');
    expect(a.psi24, 48);
  },
  'weather_pm25': (body) {
    final a = airNear(null, body, lat, lng)!;
    expect(a.region, 'central');
    expect(a.pm25, 14);
  },
  'weather_uv': (body) => expect(uvIndex(body), 8),
  'weather_wbgt': (body) {
    expect(wbgtNear(body, lat, lng), (30.2, 'Moderate'));
    expect(heatStressNear(body, lat, lng), isNotNull);
  },
  'weather_lightning': (body) => expect(lightningNear(body, lat, lng), isTrue),
  'train_alerts': (body) {
    final lines = lineStatuses(body, {'NSL', 'EWL'});
    final nsl = lines.firstWhere((l) => l.line == 'NSL');
    expect(nsl.disrupted, isTrue);
    expect(nsl.freeBus, isTrue);
    expect(lines.firstWhere((l) => l.line == 'EWL').disrupted, isFalse);
  },
  'bus_arrival': (body) {
    final etas = parseBusArrival(body, DateTime.parse('2026-11-05T12:00:00+08:00'));
    expect(etas.map((e) => (e.service, e.minutes)), [('73', 4), ('73', 15)]);
    expect(etas.first.load, 'SEA');
    expect(etas.first.wheelchair, isTrue);
    expect(etas.first.lat, isNotNull); // live position
    expect(etas.last.lat, isNull); // LTA sends 0.0 without a position
  },
  'ev': (body) {
    final live = EvLive.fromApi(body);
    expect(live.single.id, 'AMK201');
    final plug = live.single.plugs.single;
    expect((plug.type, plug.kw, plug.total, plug.free), ('Type 2', 7.4, 2, 1));
  },
  'crowd': (body) {
    expect(stationCrowd(body), {'NS16': 'h', 'NS17': 'l'});
    expect(highCrowdShare(body), 0.5);
  },
  'carpark': (body) => expect(carparkLots(body), {'AM14': (305, 102)}),
  'taxi': (body) {
    expect(taxiPoints(body), hasLength(2));
    expect(taxisWithin(body, lat, lng), 1);
  },
  'parking': (body) {
    final lots = parseParking(body);
    expect(lots.map((l) => (l.id, l.lotType, l.available)), [('AM14', 'C', 102), ('AM14', 'Y', 8)]);
  },
  'traffic_incidents': (body) {
    const home = Place(kind: PlaceKind.home, addrLat: lat, addrLng: lng);
    const work = Place(kind: PlaceKind.work, addrLat: 1.3344, addrLng: 103.8500);
    final hits = incidentsOnTrip(body, home, work);
    expect(hits.single.$1, 'Accident');
    expect(hits.single.$2, contains('CTE'));
  },
  'search': (body) {
    // ApiClient.search hands the app the OneMap body inside "data".
    final hit = parseOneMap(body['data'] as Map<String, dynamic>).single;
    expect(hit.postal, '560201');
    expect(hit.label, '201 Ang Mo Kio Avenue 3 (Ang Mo Kio View)');
  },
  'agent': (body) {
    // Read by _AgentResult in ui/homes.dart.
    final a = (body['data'] as List).first as Map;
    for (final k in ['name', 'registration_no', 'agency', 'agency_licence', 'start', 'end']) {
      expect(a[k], isA<String>(), reason: k);
    }
  },
};

void main() {
  test('every example in contracts/v1 is checked here', () {
    final names = Directory('../contracts/v1')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
        .toSet();
    expect(names, checks.keys.toSet());
  });

  for (final MapEntry(key: name, value: check) in checks.entries) {
    test('app reads contracts/v1/$name.json', () {
      final body = response(name);
      expect(body['fetched_at'], isA<num>()); // liveStaleSince reads it
      check(body);
    });
  }
}
