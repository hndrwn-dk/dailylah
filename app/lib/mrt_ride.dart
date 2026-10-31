import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'background.dart';
import 'logic.dart';
import 'providers.dart';

/// One "I'm on the train" ride. Lives in a provider (like [WakeNotifier]) so it keeps going
/// when the rider leaves the page; [RideBanner] above the tabs shows it.
class RideState {
  const RideState({
    required this.ride,
    required this.start,
    this.fixIndex,
    this.fixAt,
    this.alertOn = true,
    this.alerted = false,
    this.alerts,
    this.checkedAt,
    this.toldDisrupted = false,
  });
  final MrtRide ride;
  final DateTime start;

  /// Station of the last GPS fix near the ride (above ground only), and when.
  final int? fixIndex;
  final DateTime? fixAt;

  /// "Alert me one stop before", and whether that alert went out.
  final bool alertOn;
  final bool alerted;

  /// The latest LTA train alerts, checked every [rideCheckEvery] while riding.
  final Map<String, dynamic>? alerts;
  final DateTime? checkedAt;
  final bool toldDisrupted;

  int indexAt(DateTime now) => rideIndexAt(ride, start, now, fixIndex: fixIndex, fixAt: fixAt);
  DateTime eta(DateTime now) => rideEta(ride, start, now, fixIndex: fixIndex, fixAt: fixAt);
  List<LineStatus> get disrupted =>
      alerts == null ? const [] : [for (final l in lineStatuses(alerts!, ride.lines)) if (l.disrupted) l];

  RideState copyWith({
    int? fixIndex,
    DateTime? fixAt,
    bool? alertOn,
    bool? alerted,
    Map<String, dynamic>? alerts,
    DateTime? checkedAt,
    bool? toldDisrupted,
  }) =>
      RideState(
        ride: ride,
        start: start,
        fixIndex: fixIndex ?? this.fixIndex,
        fixAt: fixAt ?? this.fixAt,
        alertOn: alertOn ?? this.alertOn,
        alerted: alerted ?? this.alerted,
        alerts: alerts ?? this.alerts,
        checkedAt: checkedAt ?? this.checkedAt,
        toldDisrupted: toldDisrupted ?? this.toldDisrupted,
      );
}

const rideCheckEvery = Duration(minutes: 2);

class RideNotifier extends Notifier<RideState?> {
  StreamSubscription<Position>? _sub;
  Timer? _tick;
  Timer? _limit;
  DateTime? _lastCheck;

  @override
  RideState? build() {
    ref.onDispose(_cancel);
    return null;
  }

  void _cancel() {
    _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
    _limit?.cancel();
    _limit = null;
    _lastCheck = null;
  }

  /// Starts a ride now; replaces one already running. Location, when allowed, keeps the app
  /// awake for the alert (foreground notification) and corrects the estimate above ground.
  Future<void> start(MrtRide ride, {DateTime? now}) async {
    _cancel();
    state = RideState(ride: ride, start: now ?? DateTime.now());
    _limit = Timer(const Duration(hours: 2), stop);
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => _onTick(DateTime.now()));
    unawaited(_check());
    try {
      await requestNotificationPermission();
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
      final s = ref.read(stringsProvider);
      _sub = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100,
          intervalDuration: const Duration(seconds: 20),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: s.rideTitle,
            notificationText: s.rideRunning(ride.alight.name),
            enableWakeLock: true,
          ),
        ),
      ).listen((p) {
        final st = state;
        if (st == null) return;
        final i = rideFixIndex(st.ride, p.latitude, p.longitude);
        if (i != null && i >= (st.fixIndex ?? 0)) state = st.copyWith(fixIndex: i, fixAt: DateTime.now());
      }, onError: (_) {});
    } on Object {
      // No location: the time estimate still runs while the app is open.
    }
  }

  /// Checks the line status (every [rideCheckEvery]) and the one-stop-before alert.
  Future<void> _onTick(DateTime now) async {
    final st = state;
    if (st == null) return;
    if (_lastCheck == null || now.difference(_lastCheck!) >= rideCheckEvery) await _check();
    final cur = state;
    if (cur == null || !cur.alertOn || cur.alerted || !rideAlertDue(cur.ride, cur.indexAt(now))) return;
    state = cur.copyWith(alerted: true);
    final s = ref.read(stringsProvider);
    await _notify(11, s.rideTitle, s.rideNextStop(cur.ride.alight.name), buzz: true);
  }

  Future<void> _check() async {
    _lastCheck = DateTime.now();
    try {
      final body = await ref.read(apiProvider).trainAlerts();
      final st = state;
      if (st == null) return;
      final next = st.copyWith(alerts: body, checkedAt: DateTime.now());
      state = next;
      final bad = next.disrupted;
      if (bad.isNotEmpty && !next.toldDisrupted) {
        state = next.copyWith(toldDisrupted: true);
        final s = ref.read(stringsProvider);
        await _notify(12, s.rideTitle, s.rideDisrupted(s.lineName(bad.first.line)), buzz: true);
      }
    } on Object {
      // Offline underground: try again at the next check.
    }
  }

  Future<void> _notify(int id, String title, String body, {bool buzz = false}) async {
    try {
      if (buzz) await HapticFeedback.heavyImpact();
      await notifyNow(id, title, body);
    } on Object {
      // No notification plugin (tests) or notifications off: the banner still shows it.
    }
  }

  void setAlert(bool on) => state = state?.copyWith(alertOn: on);

  /// For tests: run one tick at [now].
  Future<void> tickAt(DateTime now) => _onTick(now);

  void stop() {
    _cancel();
    state = null;
  }
}

final rideProvider = NotifierProvider<RideNotifier, RideState?>(RideNotifier.new);
