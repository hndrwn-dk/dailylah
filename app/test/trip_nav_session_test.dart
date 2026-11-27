// Trip navigation: the navigator runs each step's tool (Bus arriving, Wake me, the train ride)
// and moves to the next step, driven the way its listeners and timer drive it.
import 'dart:convert';
import 'dart:io';

import 'package:dailylah/bus_watch.dart';
import 'package:dailylah/data.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/mrt_ride.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/trip_nav.dart';
import 'package:dailylah/wake_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide within;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

final _t0 = DateTime(2026, 11, 27, 8);
const _mid = BusStop(code: '99999', name: 'Mid Stop', road: 'Mid Rd', lat: 1.32, lng: 103.9);

const _busTrip = [
  TripStep(kind: StepKind.walk, from: '', to: '75009', fromName: '', toName: 'Tampines Int', minutes: 4),
  TripStep(
      kind: StepKind.bus,
      from: '75009',
      to: '03011',
      fromName: 'Tampines Int',
      toName: 'Fullerton Sq',
      service: '10',
      stops: 2,
      minutes: 20,
      routeKey: '10|1'),
  TripStep(kind: StepKind.walk, from: '03011', to: '', fromName: 'Fullerton Sq', toName: '', minutes: 3),
];

const _mrtTrip = [
  TripStep(kind: StepKind.walk, from: '', to: 'mrt:Marine Parade', fromName: '', toName: 'Marine Parade', minutes: 4),
  TripStep(
      kind: StepKind.mrt,
      from: 'mrt:Marine Parade',
      to: 'mrt:Marina Bay',
      fromName: 'Marine Parade',
      toName: 'Marina Bay',
      service: 'TEL',
      stops: 5,
      minutes: 13),
  TripStep(
      kind: StepKind.mrt,
      from: 'mrt:Marina Bay',
      to: 'mrt:Yio Chu Kang',
      fromName: 'Marina Bay',
      toName: 'Yio Chu Kang',
      service: 'NSL',
      stops: 12,
      minutes: 29),
  TripStep(kind: StepKind.walk, from: 'mrt:Yio Chu Kang', to: '', fromName: 'Yio Chu Kang', toName: '', minutes: 16),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dailylah/notify');
  final shown = <Map<Object?, Object?>>[];
  late ProviderContainer box;
  final stations = [
    for (final j in jsonDecode(File('../web/data/mrt_stations.json').readAsStringSync()) as List)
      MrtStation.fromBundle(j as Map<String, dynamic>),
  ];

  Future<void> open(List<TripStep> steps,
      {bool on = true, LocationPermission permission = LocationPermission.whileInUse}) async {
    SharedPreferences.setMockInitialValues({});
    shown.clear();
    GeolocatorPlatform.instance = FakeGeolocator(permission);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'showOngoing') shown.add(((call.arguments as Map)['note'] as Map).cast<Object?, Object?>());
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    box = ProviderContainer(retry: noRetry, overrides: [
      apiProvider.overrideWithValue(FakeApi()),
      initialFavoritesProvider.overrideWithValue(const Favorites(learnHabits: true)),
      tripNavigationOnProvider.overrideWithValue(on),
      busRoutesProvider.overrideWith((ref) async => const BusRoutes({
            '10|1': [('75009', 0.0), ('99999', 5.0), ('03011', 10.0)],
          })),
      busStopsProvider.overrideWith((ref) async => const [tampinesInt, _mid, fullertonSq]),
      mrtStationsProvider.overrideWith((ref) async => stations),
    ]);
    addTearDown(box.dispose);
    await box.read(busStopsProvider.future);
    await box.read(busRoutesProvider.future);
    await box.read(mrtStationsProvider.future);
    box.read(habitsProvider);
    await Future<void>.delayed(Duration.zero);
    box.listen(tripNavProvider, (_, __) {});
    await box.read(habitsProvider.notifier).startTrip('Home>Office', _t0,
        mode: TravelMode.transit.name,
        to: const Place(kind: PlaceKind.other, name: 'Office', addrLat: 1.2856, addrLng: 103.8534),
        steps: steps);
    await pumpEventQueue();
  }

  TripNavigator nav() => box.read(tripNavProvider.notifier);
  int step() => box.read(habitsProvider).tripStepIndex;

  test('off: a trip with steps starts no tool', () async {
    await open(_busTrip, on: false);
    expect(box.read(tripNavProvider), isNull);
    expect(box.read(busWatchProvider), isNull);
  });

  test('walking to the stop watches the first bus; on the bus Wake me takes over', () async {
    await open(_busTrip);
    expect(box.read(tripNavProvider), 0);
    expect(box.read(busWatchProvider)?.service, '10');
    expect(box.read(busWatchProvider)?.stop.code, '75009');

    await nav().next(now: _t0.add(const Duration(minutes: 5)));
    await pumpEventQueue();
    expect(step(), 1);
    expect(box.read(wakeProvider)?.alight.code, '03011');
    expect(box.read(busWatchProvider), isNull);

    nav().wakeChanged(const WakeState(service: '10', alight: fullertonSq, event: WakeEvent.wake));
    await pumpEventQueue();
    expect(step(), 2);
    expect(box.read(wakeProvider), isNull);
    await nav().next();
    expect(step(), 2, reason: 'the last step stays');
  });

  test('Bus arriving ending without the rider leaving the stop does not guess', () async {
    await open(_busTrip);
    final w = box.read(busWatchProvider)!;
    nav().watchChanged(w.copyWith(done: true, metresToStop: 40));
    await pumpEventQueue();
    expect(step(), 0);
    nav().watchChanged(w.copyWith(done: true, metresToStop: 600));
    await pumpEventQueue();
    expect(step(), 1);
  });

  test('without location: no Wake me, one get-off note by the estimate', () async {
    await open(_busTrip, permission: LocationPermission.denied);
    await nav().next(now: _t0);
    await pumpEventQueue();
    expect(box.read(wakeProvider), isNull);
    shown.clear(); // Bus arriving's own notes from the walk to the stop
    await nav().tick(_t0.add(const Duration(minutes: 10)));
    expect(shown, isEmpty);
    await nav().tick(_t0.add(const Duration(minutes: 18)));
    await nav().tick(_t0.add(const Duration(minutes: 19)));
    expect(shown, hasLength(1));
    expect(shown.single['id'], 10);
  });

  test('a train run rides both lines and ends by time at the last walk', () async {
    await open(_mrtTrip);
    expect(box.read(rideProvider), isNull, reason: 'walking to the station runs nothing');
    await nav().next(now: _t0);
    await pumpEventQueue();
    final ride = box.read(rideProvider)!.ride;
    expect(ride.board.name, 'Marine Parade');
    expect(ride.alight.name, 'Yio Chu Kang');
    expect(ride.lines, {'TEL', 'NSL'});
    await nav().tick(_t0.add(const Duration(minutes: 30)));
    expect(step(), 1);
    await nav().tick(_t0.add(const Duration(minutes: 43)));
    await pumpEventQueue();
    expect(step(), 3);
    expect(box.read(rideProvider), isNull);
  });

  test('Arrived ends the steps and every tool', () async {
    await open(_busTrip);
    expect(box.read(busWatchProvider), isNotNull);
    await box.read(habitsProvider.notifier).finishTrip(_t0.add(const Duration(minutes: 30)));
    await pumpEventQueue();
    expect(box.read(busWatchProvider), isNull);
    expect(box.read(tripNavProvider), isNull);
  });

  test('a step with a stop that is not known starts nothing and does not crash', () async {
    await open([
      _busTrip[0].copyWithTo('00000'),
      const TripStep(kind: StepKind.bus, from: '00000', to: '03011', fromName: '?', toName: 'Fullerton Sq', service: '10'),
    ]);
    expect(box.read(busWatchProvider), isNull);
  });
}

extension on TripStep {
  TripStep copyWithTo(String to) =>
      TripStep(kind: kind, from: from, to: to, fromName: fromName, toName: toName, minutes: minutes);
}
