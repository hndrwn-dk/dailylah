import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'background.dart';
import 'logic.dart';
import 'models.dart';
import 'providers.dart';

/// One "Wake me at my stop" ride. Lives in a provider, not in the page, so it keeps
/// watching when the user leaves the screen; a banner above the tabs shows it and stops it.
class WakeState {
  const WakeState({
    required this.service,
    required this.alight,
    this.from,
    this.lat,
    this.lng,
    this.left,
    this.closest,
    this.event = WakeEvent.none,
    this.error,
  });
  final String service;
  final BusStop alight;

  /// The stop the rider boarded at, when known (for "Need a toilet?": the stops ahead).
  final BusStop? from;

  /// The last GPS fix, in memory only while the ride runs (never stored or sent).
  final double? lat;
  final double? lng;

  /// Metres to the alight stop at the last fix, and the closest so far.
  final double? left;
  final double? closest;
  final WakeEvent event;
  final String? error;

  bool get done => event != WakeEvent.none;

  WakeState copyWith({double? lat, double? lng, double? left, double? closest, WakeEvent? event, String? error}) =>
      WakeState(
        service: service,
        alight: alight,
        from: from,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        left: left ?? this.left,
        closest: closest ?? this.closest,
        event: event ?? this.event,
        error: error ?? this.error,
      );
}

class WakeNotifier extends Notifier<WakeState?> {
  StreamSubscription<Position>? _sub;
  Timer? _limit;

  @override
  WakeState? build() {
    ref.onDispose(_cancel);
    return null;
  }

  void _cancel() {
    _sub?.cancel();
    _sub = null;
    _limit?.cancel();
    _limit = null;
  }

  /// Starts watching for [alight] on bus [service]; replaces any ride already running.
  Future<void> start(String service, BusStop alight, BusStop? before, {BusStop? from}) async {
    _cancel();
    final s = ref.read(stringsProvider);
    state = WakeState(service: service, alight: alight, from: from);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        state = state?.copyWith(error: s.locationDenied);
        return;
      }
      await requestNotificationPermission();
      final radius = wakeRadius(before, alight);
      // A ride never lasts this long; stop the GPS so it cannot run all day by mistake.
      _limit = Timer(const Duration(hours: 2), stop);
      _sub = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: s.wakeTitle,
            notificationText: '${s.wakeRunning}: ${alight.name}',
            enableWakeLock: true,
          ),
        ),
      ).listen((p) => _onFix(p, radius), onError: (_) {
        state = state?.copyWith(error: s.locationUnavailable);
      });
    } on Object {
      state = state?.copyWith(error: s.locationUnavailable);
    }
  }

  Future<void> _onFix(Position p, double radius) async {
    final st = state;
    if (st == null || st.done) return;
    final d = distanceMeters(p.latitude, p.longitude, st.alight.lat, st.alight.lng);
    final ev = wakeEvent(d, radius, st.closest);
    state = st.copyWith(
        lat: p.latitude, lng: p.longitude, left: d, closest: math.min(st.closest ?? d, d), event: ev);
    if (ev == WakeEvent.none) return;
    _cancel();
    final s = ref.read(stringsProvider);
    await HapticFeedback.heavyImpact();
    await notifyNow(
      10,
      s.wakeTitle,
      ev == WakeEvent.wake ? s.wakeNowAt(st.alight.name) : s.wakePassed(st.alight.name),
    );
  }

  /// Ends the ride (button on the page or the banner).
  void stop() {
    _cancel();
    state = null;
  }
}

final wakeProvider = NotifierProvider<WakeNotifier, WakeState?>(WakeNotifier.new);

/// "Need a toilet?" on the bus: the stops ahead with a toilet ([toiletsAheadBus]), null while
/// the bundles load or when no ride runs or its boarding stop is unknown.
final busToiletsProvider = Provider.autoDispose<List<ToiletStop>?>((ref) {
  final w = ref.watch(wakeProvider);
  final from = w?.from;
  if (w == null || from == null) return null;
  final routes = ref.watch(busRoutesProvider).value;
  final toilets = ref.watch(toiletsProvider).value;
  if (routes == null || toilets == null) return null;
  return toiletsAheadBus(routes, w.service, from, w.alight, ref.watch(busStopsByCodeProvider), toilets,
      lat: w.lat, lng: w.lng);
});
