import 'dart:convert';
import 'dart:io';

import 'package:dailylah/data.dart';
import 'package:dailylah/l10n.dart';
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

  group('which tool runs on each step', () {
    const bus2 = [
      TripStep(kind: StepKind.walk, from: '', to: 'A', fromName: '', toName: 'A', minutes: 3),
      TripStep(kind: StepKind.bus, from: 'A', to: 'B', fromName: 'A', toName: 'B', service: '966', stops: 8, minutes: 21),
      TripStep(kind: StepKind.bus, from: 'B', to: 'C', fromName: 'B', toName: 'C', service: '857', stops: 3, minutes: 12),
      TripStep(kind: StepKind.walk, from: 'C', to: '', fromName: 'C', toName: '', minutes: 2),
    ];
    const mrt2 = [
      TripStep(kind: StepKind.walk, from: '', to: 'mrt:Marine Parade', fromName: '', toName: 'Marine Parade', minutes: 4),
      TripStep(kind: StepKind.mrt, from: 'mrt:Marine Parade', to: 'mrt:Marina Bay', fromName: 'Marine Parade', toName: 'Marina Bay', service: 'TEL', stops: 5, minutes: 13),
      TripStep(kind: StepKind.mrt, from: 'mrt:Marina Bay', to: 'mrt:Yio Chu Kang', fromName: 'Marina Bay', toName: 'Yio Chu Kang', service: 'NSL', stops: 12, minutes: 29),
      TripStep(kind: StepKind.walk, from: 'mrt:Yio Chu Kang', to: '', fromName: 'Yio Chu Kang', toName: '', minutes: 16),
    ];
    final at = DateTime(2026, 11, 27, 8);

    test('walking to a bus watches it, a bus wakes at its stop, a train rides, the last walk has none', () {
      expect(navToolFor(bus2, 0), (tool: NavTool.watchBus, at: 1));
      expect(navToolFor(bus2, 1), (tool: NavTool.wake, at: 1));
      expect(navToolFor(bus2, 2), (tool: NavTool.wake, at: 2));
      expect(navToolFor(bus2, 3), (tool: NavTool.none, at: 3));
      expect(navToolFor(mrt2, 0), (tool: NavTool.none, at: 0));
      expect(navToolFor(mrt2, 1), (tool: NavTool.ride, at: 1));
      expect(navToolFor(const [], 0), (tool: NavTool.none, at: 0));
    });

    test('a train run covers the MRT steps that follow on', () {
      expect(mrtRunEnd(mrt2, 1), 2);
      expect(mrtRunEnd(mrt2, 2), 2);
      expect(mrtRunEnd(bus2, 1), 1);
    });

    test('get off one stop before the bus is due at its stop, and a run is over after its minutes', () {
      expect(navGetOffDue(bus2[1], at, at.add(const Duration(minutes: 18))), isFalse);
      expect(navGetOffDue(bus2[1], at, at.add(const Duration(minutes: 19))), isTrue);
      expect(navRideOver(mrt2, 1, at, at.add(const Duration(minutes: 41))), isFalse);
      expect(navRideOver(mrt2, 1, at, at.add(const Duration(minutes: 42))), isTrue);
    });

    test('the step clock is kept with the trip', () {
      final h = Habits(tripRoute: 'a>b', tripStart: at, tripSteps: bus2, tripStepIndex: 1, tripStepAt: at);
      final back = Habits.fromJson(h.toJson());
      expect(back.tripStepAt, at);
      expect(back.copyWith(clearTrip: true).tripStepAt, isNull);
    });
  });

  group('what each step says and asks', () {
    const s = S();
    const bus = [
      TripStep(kind: StepKind.walk, from: '', to: 'A', fromName: '', toName: "Opp D'Ecosia", minutes: 3),
      TripStep(kind: StepKind.bus, from: 'A', to: 'B', fromName: "Opp D'Ecosia", toName: "Opp St. Andrew's Village", service: '966', minutes: 21),
      TripStep(kind: StepKind.walk, from: 'B', to: 'C', fromName: 'x', toName: 'Bef Ang Mo Kio St 64', minutes: 1),
      TripStep(kind: StepKind.mrt, from: 'mrt:Yio Chu Kang', to: 'mrt:Khatib', fromName: 'Yio Chu Kang', toName: 'Khatib', service: 'NSL', minutes: 4),
      TripStep(kind: StepKind.walk, from: 'C', to: '', fromName: 'Khatib', toName: '', minutes: 2),
    ];

    test('the button on each step', () {
      expect(stepAction(bus, 0), StepAction.onBus);
      expect(stepAction(bus, 1), StepAction.gotOff);
      expect(stepAction(bus, 2), StepAction.onTrain);
      expect(stepAction(bus, 3), StepAction.gotOff);
      expect(stepAction(bus, 4), StepAction.none);
      expect(stepAction(const [], 0), StepAction.none);
    });

    test('the words for each step', () {
      expect(stepLabel(s, bus[0]), "Walk to Opp\u00a0D'Ecosia");
      expect(stepLabel(s, bus[1]), "Bus 966 to Opp St. Andrew's\u00a0Village");
      expect(stepLabel(s, bus[3]), 'NSL to\u00a0Khatib');
      expect(stepLabel(s, bus[4]), 'Walk the rest of the way');
      expect(s.stepOf(2, 5), 'Step 2 of 5');
    });
  });

  group('a faster way while waiting', () {
    const slow = [
      TripStep(kind: StepKind.walk, from: '', to: 'A', fromName: '', toName: 'A', minutes: 3),
      TripStep(kind: StepKind.bus, from: 'A', to: 'B', fromName: 'A', toName: 'B', service: '966', minutes: 40),
      TripStep(kind: StepKind.walk, from: 'B', to: '', fromName: 'B', toName: '', minutes: 2),
    ];
    TransitOption way(String service, int minutes) => TransitOption([
          const TransitLeg(kind: LegKind.walk, from: '', to: 'A', fromName: '', toName: 'A', minutes: 1),
          TransitLeg(
              kind: LegKind.bus, from: 'A', to: 'C', fromName: 'A', toName: 'C', service: service, minutes: minutes - 2),
          const TransitLeg(kind: LegKind.walk, from: 'C', to: '', fromName: 'C', toName: '', minutes: 1),
        ]);

    test('offers a way at least 5 min quicker than the rest of the trip, not the same buses', () {
      expect(betterWay(slow, 0, [way('966', 20)]), isNull, reason: 'the same bus is not another way');
      expect(betterWay(slow, 0, [way('70', 41)]), isNull, reason: 'only 4 min quicker');
      expect(betterWay(slow, 0, [way('70', 40), way('854', 30)])?.signature, '854', reason: 'the fastest one');
    });

    test('only while walking to the first ride or waiting for it, never on a ride', () {
      expect(betterWay(slow, 1, [way('70', 10)]), isNull);
      expect(betterWay(slow, 2, [way('70', 1)]), isNull);
      expect(betterWay(const [], 0, [way('70', 1)]), isNull);
    });

    test('its alert says the bus and the minutes saved', () {
      final n = betterWayNote(const S(), first: '70', rides: '70', saved: 15);
      expect(n.id, betterWayNoteId);
      expect(n.pills.map((p) => p.text), ['70', '15 min sooner']);
    });
  });

  test('a way that is only quicker because of a shorter wait at the change is not a faster way', () {
    const plan = [
      TripStep(kind: StepKind.walk, from: '', to: 'A', fromName: '', toName: 'A', minutes: 0),
      TripStep(kind: StepKind.bus, from: 'A', to: 'B', fromName: 'A', toName: 'B', service: '966', minutes: 20),
      TripStep(kind: StepKind.walk, from: 'B', to: '', fromName: 'B', toName: '', minutes: 0),
    ];
    final o = TransitOption(const [
      TransitLeg(kind: LegKind.walk, from: '', to: 'A', fromName: '', toName: 'A', minutes: 0),
      TransitLeg(kind: LegKind.bus, from: 'A', to: 'C', fromName: 'A', toName: 'C', service: '70', minutes: 15),
      TransitLeg(kind: LegKind.walk, from: 'C', to: '', fromName: 'C', toName: '', minutes: 0),
    ]);
    expect(betterWay(plan, 0, [o])?.signature, '70');
    // Waiting 6 min at a change in the plan against 5 for a first bus: the option is one minute
    // nearer than it looks, so 15 against 20 no longer clears the 5-minute bar.
    expect(betterWay(plan, 0, [o], extraMinutes: 1), isNull);
  });

  test('a way over a disrupted MRT line is left out, by the planner and by the faster-way offer alike', () {
    final train = TransitOption(const [
      TransitLeg(kind: LegKind.walk, from: '', to: 'mrt:A', fromName: '', toName: 'A', minutes: 1),
      TransitLeg(kind: LegKind.mrt, from: 'mrt:A', to: 'mrt:B', fromName: 'A', toName: 'B', service: 'TEL', minutes: 10),
      TransitLeg(kind: LegKind.walk, from: 'mrt:B', to: '', fromName: 'B', toName: '', minutes: 1),
    ]);
    final bus = TransitOption(const [
      TransitLeg(kind: LegKind.walk, from: '', to: 'X', fromName: '', toName: 'X', minutes: 1),
      TransitLeg(kind: LegKind.bus, from: 'X', to: 'Y', fromName: 'X', toName: 'Y', service: '70', minutes: 20),
      TransitLeg(kind: LegKind.walk, from: 'Y', to: '', fromName: 'Y', toName: '', minutes: 1),
    ]);
    Map<String, dynamic> down(String line) => {
          'data': {
            'value': {
              'Status': 2,
              'AffectedSegments': [
                {'Line': line, 'Direction': 'x', 'Stations': 'TE1', 'FreePublicBus': '', 'FreeMRTShuttle': ''},
              ],
              'Message': [],
            },
          },
        };
    expect(withoutDisrupted([train, bus], null), [train, bus]);
    expect(withoutDisrupted([train, bus], down('TEL')), [bus]);
    expect(withoutDisrupted([train, bus], down('NSL')), [train, bus]);
  });
}
