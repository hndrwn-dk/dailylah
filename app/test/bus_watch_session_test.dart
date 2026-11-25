// Bus arriving: the session that watches one bus of the running trip (busWatchProvider),
// driven poll by poll the way the timer drives it.
import 'dart:async';

import 'package:dailylah/bus_watch.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/wake_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

final _t0 = DateTime(2026, 11, 22, 12, 10);
DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

/// Arrivals at the stop as minutes from the time of the call, per service.
class _Api extends FakeApi {
  Map<String, List<int>> arrivals = {'197': [5]};
  bool fail = false;
  int calls = 0;
  DateTime now = _t0;

  @override
  Future<Map<String, dynamic>> busArrival(String stopCode) async {
    calls++;
    if (fail) throw StateError('offline (test)');
    Map<String, dynamic> bus(int m) => {
          'EstimatedArrival': now.add(Duration(minutes: m, seconds: 10)).toIso8601String(),
          'Load': 'SEA',
          'Feature': 'WAB',
          'Type': 'SD',
        };
    return {
      'data': {
        'Services': [
          for (final e in arrivals.entries)
            {
              'ServiceNo': e.key,
              for (final (i, m) in e.value.indexed) ['NextBus', 'NextBus2', 'NextBus3'][i]: bus(m),
            },
        ],
      },
    };
  }
}

class _Geo extends FakeGeolocator {
  _Geo(super.permission);
  int asked = 0;
  int streams = 0;

  /// Position streams being listened to now: each one keeps the location service running.
  int listening = 0;

  /// When set, the permission check waits for it (a prompt that is still open).
  Completer<void>? prompt;

  @override
  Future<LocationPermission> checkPermission() async {
    if (prompt case final g?) await g.future;
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    asked++;
    return permission;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streams++;
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      return super.getPositionStream(locationSettings: locationSettings);
    }
    late final StreamController<Position> out;
    out = StreamController<Position>(
      onListen: () async {
        listening++;
        out.add(await getCurrentPosition());
      },
      onCancel: () => listening--,
    );
    return out.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dailylah/notify');
  final shown = <Map<Object?, Object?>>[];
  final ongoing = <Map<Object?, Object?>>[];
  late _Api api;
  late _Geo geo;
  late ProviderContainer box;

  List<Object?> pills(Map<Object?, Object?> note) => [for (final p in note['pills'] as List) (p as Map)['text']];

  Future<void> open({
    LocationPermission permission = LocationPermission.whileInUse,
    Favorites fav = const Favorites(learnHabits: true),
  }) async {
    SharedPreferences.setMockInitialValues({});
    shown.clear();
    ongoing.clear();
    api = _Api();
    geo = _Geo(permission);
    GeolocatorPlatform.instance = geo;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final note = ((call.arguments as Map)['note'] as Map).cast<Object?, Object?>();
      (call.method == 'showOngoing' ? ongoing : shown).add(note);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    box = ProviderContainer(retry: noRetry, overrides: [
      apiProvider.overrideWithValue(api),
      initialFavoritesProvider.overrideWithValue(fav),
      busRoutesProvider.overrideWith((ref) async => BusRoutes.empty),
      busStopsProvider.overrideWith((ref) async => const [tampinesInt, fullertonSq]),
    ]);
    addTearDown(box.dispose);
    box.read(habitsProvider);
    await Future<void>.delayed(Duration.zero);
    await box.read(habitsProvider.notifier).startTrip('Home>Bugis Junction', _t0,
        to: const Place(kind: PlaceKind.other, name: 'Bugis Junction', addrLat: 1.2996, addrLng: 103.8554),
        stop: tampinesInt.code);
  }

  Future<void> watch(String service, int minutes, {bool ask = false}) => box.read(busWatchProvider.notifier).start(
        stop: tampinesInt,
        service: service,
        minutes: minutes,
        alight: fullertonSq,
        toLabel: 'Bugis Junction',
        ask: ask,
        now: _t0,
      );

  Future<void> poll(int seconds) {
    api.now = _at(seconds);
    return box.read(busWatchProvider.notifier).pollAt(_at(seconds));
  }

  BusWatchState? state() => box.read(busWatchProvider);

  test('counts down and alerts once at 2 min and once on arriving', () async {
    await open();
    await watch('197', 5);
    expect(state()?.eta?.minutes, 5);
    expect(state()?.background, isTrue);
    expect(box.read(habitsProvider).tripBus, '197');
    await poll(20);
    expect(shown, isEmpty);
    final written = ongoing.length;
    await poll(40);
    expect(ongoing, hasLength(written), reason: 'the same pills are not written again');
    expect(pills(ongoing.last), ['197', '5 min', 'At the stop']);

    api.arrivals = {'197': [2]};
    await poll(180);
    await poll(200);
    expect(shown, hasLength(1));
    expect(shown.single['title'], '197 in 2 min');
    expect(shown.single['id'], 24);

    api.arrivals = {'197': [0]};
    await poll(300);
    await poll(320);
    expect(shown, hasLength(2));
    expect(shown.last['title'], '197 is arriving');
    expect(pills(shown.last), contains('Get off at Fullerton Sq'));
  });

  test('failed fetch: the last reading stays, goes stale after 90 s and comes back', () async {
    await open();
    await watch('197', 5);
    api.fail = true;
    await poll(30);
    expect(state()?.eta?.minutes, 5);
    expect(state()?.stale, isFalse);
    api.arrivals = {'197': [0]};
    await poll(120);
    expect(state()?.stale, isTrue);
    expect(shown, isEmpty, reason: 'no alert from an old reading');
    expect(pills(ongoing.last)[1], 'Updated 12:10');
    api
      ..fail = false
      ..arrivals = {'197': [3]};
    await poll(150);
    expect(state()?.stale, isFalse);
    expect(state()?.eta?.minutes, 3);
  });

  test('switch resets alerts: another bus gets its own', () async {
    await open();
    api.arrivals = {'197': [2], '48': [9]};
    await watch('197', 2);
    expect(shown.single['title'], '197 in 2 min');
    await watch('48', 9);
    expect(box.read(habitsProvider).tripBus, '48');
    api.arrivals = {'197': [1], '48': [2]};
    await poll(420);
    expect(shown, hasLength(2));
    expect(shown.last['title'], '48 in 2 min');
  });

  test('gone: the watch is done, stops asking and stays for the Wake me offer', () async {
    await open();
    api.arrivals = {'197': [2]};
    await watch('197', 2);
    api.arrivals = {'197': [14]};
    await poll(60);
    expect(state()?.done, isFalse, reason: 'one reading without it is not enough');
    await poll(90);
    expect(state()?.done, isTrue);
    expect(state()?.service, '197');
    expect(geo.listening, 0, reason: 'the location service is released');
    final calls = api.calls;
    await poll(120);
    expect(api.calls, calls);
  });

  test('limit: ends by itself after 45 minutes', () async {
    await open();
    await watch('197', 5);
    api.arrivals = {'197': [9]};
    await poll(45 * 60);
    expect(state(), isNull);
  });

  test('one watcher: not beside Wake me at my stop', () async {
    await open();
    await box.read(wakeProvider.notifier).start('197', fullertonSq, null);
    await watch('197', 5);
    expect(state(), isNull, reason: 'a ride is already watched');
    box.read(wakeProvider.notifier).stop();

    await watch('197', 5);
    expect(state(), isNotNull);
    await box.read(wakeProvider.notifier).start('197', fullertonSq, null);
    expect(state(), isNull, reason: 'Wake me takes over');
  });

  test('no permission, no ask: counts down in the app only and never prompts', () async {
    await open(permission: LocationPermission.denied);
    await watch('197', 5);
    expect(state()?.eta?.minutes, 5);
    expect(state()?.background, isFalse);
    expect(geo.asked, 0);
    expect(geo.streams, 0);
    expect(ongoing, isEmpty);

    await watch('197', 5, ask: true);
    expect(geo.asked, 1, reason: 'a bell tap may ask');
    expect(state()?.background, isFalse);
  });

  test('no arrival for the bus: the minutes go, they do not freeze', () async {
    await open();
    await watch('197', 5);
    expect(state()?.eta?.minutes, 5);
    api.arrivals = {'48': [3]};
    await poll(30);
    expect(state()?.eta, isNull);
    expect(state()?.stale, isFalse);
    expect(pills(ongoing.last).take(2), ['197', 'No arrival time']);
  });

  test('a second pick while the first is still starting leaves one stream, and stop ends it', () async {
    await open();
    geo.prompt = Completer<void>();
    final first = watch('197', 5);
    final second = watch('48', 9);
    geo.prompt!.complete();
    await Future.wait([first, second]);
    await Future<void>.delayed(Duration.zero);
    expect(state()?.service, '48');
    expect(geo.listening, 1);
    box.read(busWatchProvider.notifier).stop();
    await Future<void>.delayed(Duration.zero);
    expect(geo.listening, 0, reason: 'nothing keeps the location service running');
  });

  test('stopped while the permission prompt is open: nothing starts afterwards', () async {
    await open();
    geo.prompt = Completer<void>();
    final starting = watch('197', 5, ask: true);
    await Future<void>.delayed(Duration.zero);
    box.read(busWatchProvider.notifier).stop();
    geo.prompt!.complete();
    await starting;
    await Future<void>.delayed(Duration.zero);
    expect(state(), isNull);
    expect(geo.listening, 0);
  });

  test('no trip running: nothing is watched (an Undo tapped after Arrived)', () async {
    await open();
    await box.read(habitsProvider.notifier).cancelTrip();
    await watch('197', 5, ask: true);
    expect(state(), isNull);
    expect(geo.streams, 0);
    expect(api.calls, 0);
  });

  test('switch off: nothing is watched', () async {
    await open(fav: const Favorites(learnHabits: true, busAlerts: false));
    await watch('197', 5);
    expect(state(), isNull);
    expect(api.calls, 0);
  });

  test('the watch ends with the trip', () async {
    await open();
    await watch('197', 5);
    await box.read(habitsProvider.notifier).cancelTrip();
    expect(state(), isNull);
  });
}
