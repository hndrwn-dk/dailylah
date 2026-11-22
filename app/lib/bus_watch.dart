import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'background.dart';
import 'logic.dart';
import 'models.dart';
import 'mrt_ride.dart';
import 'providers.dart';
import 'wake_session.dart';

/// "Bus arriving": one bus of the running trip, watched at the boarding stop. Lives in a
/// provider, like the Wake me ride, so it keeps watching when the screen changes; the trip
/// banner shows it.
class BusWatchState {
  const BusWatchState({
    required this.stop,
    required this.service,
    required this.toLabel,
    required this.track,
    required this.started,
    this.alight,
    this.eta,
    this.fetchedAt,
    this.stopsAway,
    this.metresToStop,
    this.background = false,
    this.done = false,
    this.stale = false,
  });

  /// The boarding stop and the bus watched there.
  final BusStop stop;
  final String service;

  /// Where that bus is left for the trip's destination, when known, and the destination as shown.
  final BusStop? alight;
  final String toLabel;

  final BusTrack track;
  final DateTime started;

  /// The arrival followed at the last good reading, and when that reading was taken.
  final BusEta? eta;
  final DateTime? fetchedAt;

  /// Stops between the bus and the boarding stop, when LTA sends the bus's position.
  final int? stopsAway;

  /// The rider's distance to the boarding stop at the last fix, in memory only (never stored
  /// or sent); null without location.
  final double? metresToStop;

  /// The location service runs, so the watch goes on with the screen off.
  final bool background;

  /// The bus has come and gone, or the rider has left the stop: nothing is watched any more.
  final bool done;

  /// The last reading is too old to act on ([busStaleAfter]).
  final bool stale;

  BusWatchState copyWith({
    BusTrack? track,
    BusEta? eta,
    DateTime? fetchedAt,
    int? stopsAway,
    bool clearStopsAway = false,
    double? metresToStop,
    bool? background,
    bool? done,
    bool? stale,
  }) =>
      BusWatchState(
        stop: stop,
        service: service,
        toLabel: toLabel,
        alight: alight,
        started: started,
        track: track ?? this.track,
        eta: eta ?? this.eta,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        stopsAway: clearStopsAway ? null : (stopsAway ?? this.stopsAway),
        metresToStop: metresToStop ?? this.metresToStop,
        background: background ?? this.background,
        done: done ?? this.done,
        stale: stale ?? this.stale,
      );
}

class BusWatchNotifier extends Notifier<BusWatchState?> {
  StreamSubscription<Position>? _sub;
  Timer? _tick;
  Timer? _limit;

  /// Every arrival at the stop from the last good reading.
  List<BusEta> _etas = const [];

  /// What the ongoing notification shows now, so it is only rewritten when that changes.
  String? _watchShown;

  @override
  BusWatchState? build() {
    ref.onDispose(_cancel);
    // The watch belongs to the running trip, and only one ride is watched at a time.
    ref.listen(habitsProvider.select((h) => h.tripStart), (_, start) {
      if (start == null) stop();
    });
    ref.listen(wakeProvider, (_, wake) {
      if (wake != null) stop();
    });
    ref.listen(rideProvider, (_, ride) {
      if (ride != null) stop();
    });
    return null;
  }

  void _cancel() {
    _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
    _limit?.cancel();
    _limit = null;
    _watchShown = null;
  }

  /// Watches [service] at [stop], following the arrival due in [minutes]; replaces a bus already
  /// watched. [ask]: a bell tap may raise the location and notification prompts; I'm leaving
  /// never does. Without location the watch runs while the app is open only.
  Future<void> start({
    required BusStop stop,
    required String service,
    required int minutes,
    BusStop? alight,
    required String toLabel,
    required bool ask,
    DateTime? now,
  }) async {
    if (!ref.read(favoritesProvider).busAlerts) return;
    if (ref.read(wakeProvider) != null || ref.read(rideProvider) != null) return;
    _cancel();
    _etas = const [];
    final at = now ?? DateTime.now();
    state = BusWatchState(
      stop: stop,
      service: service,
      alight: alight,
      toLabel: toLabel,
      started: at,
      track: BusTrack(service: service, due: at.add(Duration(minutes: minutes))),
    );
    await ref.read(habitsProvider.notifier).setTripBus(stop.code, service);
    _limit = Timer(busWatchLimit, this.stop);
    _tick = Timer.periodic(busRefreshEvery, (_) => pollAt(DateTime.now()));
    try {
      var perm = await Geolocator.checkPermission();
      if (ask && perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        if (ask) await requestNotificationPermission();
        final s = ref.read(stringsProvider);
        _sub = Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 50,
            intervalDuration: const Duration(seconds: 20),
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: s.busAlertTitle,
              notificationText: s.busAtStop(stop.name),
              enableWakeLock: true,
            ),
          ),
        ).listen(_onFix, onError: (_) {});
        if (state?.service == service) state = state?.copyWith(background: true);
      }
    } on Object {
      // No location: the countdown still runs while the app is open.
    }
    await pollAt(at);
  }

  /// A fix: only how far the rider is from the boarding stop is kept, in memory.
  Future<void> _onFix(Position p) async {
    final st = state;
    if (st == null || st.done) return;
    state = st.copyWith(metresToStop: distanceMeters(p.latitude, p.longitude, st.stop.lat, st.stop.lng));
    await _step(DateTime.now());
  }

  /// Reads the stop's arrivals and acts on them (the timer's tick; also called by tests).
  Future<void> pollAt(DateTime now) async {
    final st = state;
    if (st == null || st.done) return;
    if (now.difference(st.started) >= busWatchLimit) return stop();
    try {
      final body = await ref.read(apiProvider).busArrival(st.stop.code);
      final cur = state;
      // Another bus was picked, or the watch ended, while the answer was on its way.
      if (cur == null || cur.done || cur.service != st.service || cur.stop.code != st.stop.code) return;
      _etas = parseBusArrival(body, now, perService: 3);
      state = cur.copyWith(fetchedAt: now);
    } on Object {
      // Offline or the server asleep: the last reading stays until it is too old.
    }
    await _step(now);
  }

  Future<void> _step(DateTime now) async {
    final st = state;
    // Nothing to say before the first reading (a fix can come first).
    if (st == null || st.done || st.fetchedAt == null) return;
    final r = busWatchStep(st.track, _etas, now, fetchedAt: st.fetchedAt, metresToStop: st.metresToStop);
    final s = ref.read(stringsProvider);
    switch (r.event) {
      case BusWatchEvent.stale:
        state = st.copyWith(track: r.track, stale: true);
      case BusWatchEvent.gone || BusWatchEvent.left:
        _cancel();
        state = st.copyWith(track: r.track, done: true, background: false);
        return;
      case BusWatchEvent.none || BusWatchEvent.near || BusWatchEvent.arriving:
        final eta = r.eta;
        final where = eta == null
            ? null
            : busWhere(eta, st.stop.code, ref.read(busRoutesProvider).value ?? BusRoutes.empty,
                ref.read(busStopsByCodeProvider));
        state = st.copyWith(
          track: r.track,
          eta: eta,
          stale: false,
          stopsAway: where?.stopsAway,
          clearStopsAway: where?.stopsAway == null,
        );
        if (eta != null && r.event == BusWatchEvent.near) {
          await _notify(busNearNote(s,
              service: st.service,
              stop: st.stop.name,
              to: st.toLabel,
              minutes: eta.minutes,
              load: eta.load,
              monitored: eta.monitored));
        } else if (eta != null && r.event == BusWatchEvent.arriving) {
          await _notify(busArrivingNote(s,
              service: st.service,
              stop: st.stop.name,
              to: st.toLabel,
              alight: st.alight?.name,
              monitored: eta.monitored));
        }
    }
    await _showWatching();
  }

  /// The ongoing notification, only while the location service shows one.
  Future<void> _showWatching() async {
    final st = state;
    if (st == null || st.done || !st.background) return;
    final note = busWatchNote(
      ref.read(stringsProvider),
      service: st.service,
      stop: st.stop.name,
      minutes: st.eta?.minutes,
      staleSince: st.stale ? (st.fetchedAt ?? st.started) : null,
      stopsAway: st.stopsAway,
      metresToStop: st.metresToStop,
    );
    final shown = note.pills.map((p) => p.text).join('|');
    if (shown == _watchShown) return;
    // Marked before the post: a fix and a poll can come at the same moment with the same pills.
    _watchShown = shown;
    var posted = false;
    try {
      posted = await showOngoingNote(note);
    } on Object {
      // No plugin (tests): the location service's plain notification stays.
    }
    // Not on screen yet (the service is still starting): written at the next look.
    if (!posted && _watchShown == shown) _watchShown = null;
  }

  Future<void> _notify(RichNote note) async {
    try {
      await HapticFeedback.heavyImpact();
      await showNote(note, s: ref.read(stringsProvider));
    } on Object {
      // No notification plugin (tests) or notifications off: the banner still shows it.
    }
  }

  /// Ends the watch (the bell, the trip ending, another ride starting, or the time limit).
  void stop() {
    _cancel();
    state = null;
  }
}

final busWatchProvider = NotifierProvider<BusWatchNotifier, BusWatchState?>(BusWatchNotifier.new);
