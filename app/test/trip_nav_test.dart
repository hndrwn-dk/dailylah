import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/transit.dart';
import 'package:flutter_test/flutter_test.dart' hide within;

const _steps = [
  TripStep(kind: StepKind.walk, from: '', to: '92271', fromName: '', toName: "Opp D'Ecosia", minutes: 3, metres: 180),
  TripStep(
      kind: StepKind.bus,
      from: '92271',
      to: '60089',
      fromName: "Opp D'Ecosia",
      toName: "Opp St. Andrew's Village",
      service: '966',
      stops: 8,
      minutes: 21,
      routeKey: '966|1'),
  TripStep(
      kind: StepKind.bus,
      from: '60089',
      to: '55059',
      fromName: "Opp St. Andrew's Village",
      toName: 'ST Engineering',
      service: '857',
      stops: 3,
      minutes: 12,
      routeKey: '857|1'),
  TripStep(kind: StepKind.walk, from: '55059', to: '', fromName: 'ST Engineering', toName: '', minutes: 2, metres: 90),
];

void main() {
  group('trip steps', () {
    test('a trip with steps survives a save and load', () {
      final h = Habits(tripRoute: 'a>b', tripStart: DateTime(2026, 11, 26, 7, 40), tripSteps: _steps, tripStepIndex: 2);
      final back = Habits.fromJson(h.toJson());
      expect(back.tripStepIndex, 2);
      expect([for (final s in back.tripSteps) s.toJson()], [for (final s in _steps) s.toJson()]);
      expect(back.tripSteps[1].service, '966');
      expect(back.tripSteps[0].metres, 180);
    });

    test('older saves have no steps, and a step of an unknown kind is dropped', () {
      final old = Habits.fromJson({'trips': [], 'meals': [], 'tr': 'a>b', 'ts': '2026-11-26T07:40:00.000'});
      expect(old.tripSteps, isEmpty);
      expect(old.tripStepIndex, 0);
      final odd = Habits.fromJson({
        'trips': [],
        'meals': [],
        'st': [
          {'k': 'boat', 'f': 'a', 't': 'b'},
          _steps[1].toJson(),
        ],
      });
      expect(odd.tripSteps.map((s) => s.service), ['966']);
    });

    test('ending the trip clears its steps', () {
      final h = const Habits().copyWith(tripRoute: 'a>b', tripSteps: _steps, tripStepIndex: 1);
      final cleared = h.copyWith(clearTrip: true);
      expect(cleared.tripSteps, isEmpty);
      expect(cleared.tripStepIndex, 0);
    });
  });

  group('steps of a way with changes', () {
    dynamic bundle(String name) => jsonDecode(File('../web/data/$name').readAsStringSync());
    final net = TransitNet.build(
      [for (final j in bundle('bus_stops.json') as List) BusStop.fromBundle(j as Map<String, dynamic>)],
      BusRoutes.fromBundle(bundle('bus_routes.json') as Map<String, dynamic>),
      [for (final j in bundle('mrt_stations.json') as List) MrtStation.fromBundle(j as Map<String, dynamic>)],
    );
    final option = transitOptions(net, const Place(kind: PlaceKind.other, addrLat: 1.3050, addrLng: 103.9085),
            const Place(kind: PlaceKind.other, addrLat: 1.3917, addrLng: 103.8480))
        .first;
    final steps = stepsOf(option);

    test('one step per leg, in order, with its values', () {
      expect(steps, hasLength(option.legs.length));
      expect(steps.map((s) => s.kind), [StepKind.walk, StepKind.bus, StepKind.bus, StepKind.walk]);
      expect(steps.map((s) => s.service).whereType<String>(), ['966', '857']);
      expect(steps[1].from, option.legs[1].from);
      expect(steps[1].stops, option.legs[1].stops);
    });

    test('minutes left, the next step and the next ride', () {
      expect(remainingMinutes(steps, 0), option.minutes);
      expect(remainingMinutes(steps, 3), steps[3].minutes);
      expect(stepAfter(steps, 0), 1);
      expect(stepAfter(steps, 3), 3);
      expect(nextRideIndex(steps, 0), 1);
      expect(nextRideIndex(steps, 2), 2);
      expect(nextRideIndex(steps, 3), isNull);
      expect(remainingMinutes(const [], 0), 0);
    });
  });
}
