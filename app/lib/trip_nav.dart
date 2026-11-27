// Trip navigation: runs the existing tool each step of a trip with changes needs (Bus arriving
// while walking to a bus, Wake me on a bus, the train ride on MRT) and moves to the next step.
// Everything stays on the phone; it never asks for location.
import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'background.dart' show showNote;
import 'bus_watch.dart';
import 'data.dart';
import 'logic.dart';
import 'models.dart';
import 'mrt_ride.dart';
import 'providers.dart';
import 'transit.dart';
import 'wake_session.dart';

/// Trip navigation is on (the trip bar and page show and change the steps); tests turn it off.
final tripNavigationOnProvider = Provider<bool>((ref) => true);

/// A faster way from where the rider waits, offered on the trip page (null: none now).
final betterWayProvider = StateProvider<TransitOption?>((ref) => null);

/// What [TripNavigator.switchToBetter] replaced, for Undo.
typedef TripPlanBefore = ({List<TripStep> steps, int index, DateTime? at});

/// The step the navigator drives (null when there is no trip with changes or it is off).
final tripNavProvider = NotifierProvider<TripNavigator, int?>(TripNavigator.new);

class TripNavigator extends Notifier<int?> {
  Timer? _tick;

  /// The trip and step whose tool was started (and which tool), so it starts once per step
  /// and the right one is stopped when the step or the trip changes.
  (DateTime, int)? _started;
  NavTool _tool = NavTool.none;

  /// The get-off note without location went out for this trip and step.
  (DateTime, int)? _toldGetOff;

  /// The faster-way alert went out, or the rider kept their way, for this trip and step.
  (DateTime, int)? _toldBetter;
  (DateTime, int)? _keptMine;

  @override
  int? build() {
    ref.onDispose(_cancel);
    if (!ref.watch(tripNavigationOnProvider)) return null;
    ref.listen(habitsProvider.select((h) => (h.tripStart, h.tripSteps.length, h.tripStepIndex)), (_, __) => _drive());
    ref.listen(busWatchProvider, (_, w) => watchChanged(w));
    ref.listen(wakeProvider, (_, w) => wakeChanged(w));
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => tick(DateTime.now()));
    // A navigator built mid-trip (the app reopened) picks the trip up after this build.
    Future.microtask(_drive);
    return _running ? _h.tripStepIndex : null;
  }

  void _cancel() {
    _tick?.cancel();
    _tick = null;
  }

  Habits get _h => ref.read(habitsProvider);

  bool get _running => _h.tripStart != null && _h.tripSteps.isNotEmpty && _h.tripStepIndex < _h.tripSteps.length;

  /// Stops the tool this navigator started (Bus arriving and the ride also stop themselves when
  /// the trip ends; Wake me does not, as it also runs on its own).
  void _stopTool() {
    switch (_tool) {
      case NavTool.watchBus:
        ref.read(busWatchProvider.notifier).stop();
      case NavTool.wake:
        ref.read(wakeProvider.notifier).stop();
      case NavTool.ride:
        ref.read(rideProvider.notifier).stop();
      case NavTool.none:
        break;
    }
    _tool = NavTool.none;
  }

  /// Starts the tool of the active step once.
  void _drive() {
    if (!_running) {
      ref.read(betterWayProvider.notifier).state = null;
      if (_started != null) _stopTool();
      _started = null;
      _toldGetOff = null;
      state = null;
      return;
    }
    final i = _h.tripStepIndex;
    final key = (_h.tripStart!, i);
    state = i;
    if (_started == key) return;
    ref.read(betterWayProvider.notifier).state = null;
    // A new trip over a running one: its tool goes before the new one starts.
    if (_started != null && _started!.$1 != key.$1) _stopTool();
    _started = key;
    final steps = _h.tripSteps;
    final (:tool, :at) = navToolFor(steps, i);
    final stops = ref.read(busStopsByCodeProvider);
    switch (tool) {
      case NavTool.none:
        return;
      case NavTool.watchBus:
        final ride = steps[at];
        final stop = stops[ride.from];
        if (stop == null || ride.service == null) return;
        _tool = tool;
        unawaited(ref.read(busWatchProvider.notifier).start(
              stop: stop,
              service: ride.service!,
              minutes: steps[i].minutes,
              alight: stops[ride.to],
              toLabel: ride.toName,
              ask: false,
            ));
      case NavTool.wake:
        final ride = steps[at];
        final alight = stops[ride.to];
        if (alight == null || ride.service == null) return;
        final route = ref.read(busRoutesProvider).value?.routes[ride.routeKey];
        final j = route?.indexWhere((s) => s.$1 == ride.to) ?? -1;
        final before = j > 0 ? stops[route![j - 1].$1] : null;
        _tool = tool;
        unawaited(ref.read(wakeProvider.notifier).start(ride.service!, alight, before, from: stops[ride.from], ask: false));
      case NavTool.ride:
        final mrtRide = _rideFor(steps, at);
        if (mrtRide == null) return;
        _tool = tool;
        unawaited(ref.read(rideProvider.notifier).start(mrtRide));
    }
  }

  /// One train ride over the MRT run from step [i], stations by name; null when a leg is not known.
  MrtRide? _rideFor(List<TripStep> steps, int i) {
    final all = ref.read(mrtStationsProvider).value ?? const <MrtStation>[];
    MrtStation? station(String id) {
      final name = id.startsWith('mrt:') ? id.substring(4) : id;
      for (final s in all) {
        if (s.name == name) return s;
      }
      return null;
    }

    final stations = <MrtStation>[];
    final lines = <String>{};
    int? via;
    for (var j = i; j <= mrtRunEnd(steps, i); j++) {
      final a = station(steps[j].from), b = station(steps[j].to);
      if (a == null || b == null) return null;
      final leg = mrtLeg(all, a, b);
      if (leg == null) return null;
      if (stations.isNotEmpty) via ??= stations.length - 1;
      stations.addAll(stations.isEmpty ? leg : leg.skip(1));
      if (steps[j].service case final line?) lines.add(line);
    }
    return stations.length < 2 ? null : MrtRide(stations: stations, lines: lines, viaIndex: via);
  }

  /// Moves to step [i], stopping the tool of the step left.
  Future<void> _go(int i, DateTime now) async {
    _stopTool();
    await ref.read(habitsProvider.notifier).setTripStep(i, now);
  }

  /// The rider says they are on the next step (I'm on 966, Got off, On the train).
  Future<void> next({DateTime? now}) async {
    if (!_running) return;
    final steps = _h.tripSteps;
    final i = _h.tripStepIndex;
    final last = steps[i].kind == StepKind.mrt ? mrtRunEnd(steps, i) : i;
    if (last + 1 >= steps.length) return;
    await _go(last + 1, now ?? DateTime.now());
  }

  /// Bus arriving changed: when it ended with the rider well away from the stop, they are on the bus.
  void watchChanged(BusWatchState? w) {
    if (!_running || w == null || !w.done) return;
    final steps = _h.tripSteps;
    final i = _h.tripStepIndex;
    final (:tool, :at) = navToolFor(steps, i);
    if (tool != NavTool.watchBus || steps[at].service != w.service) return;
    // Seen at the stop, then well away from it: on the bus (the rule Bus arriving's "left" uses).
    if (!w.track.wasAtStop || (w.metresToStop ?? 0) < busLeftStopMetres) return;
    _tool = NavTool.none; // Bus arriving has ended by itself
    unawaited(ref.read(habitsProvider.notifier).setTripStep(at, DateTime.now()));
  }

  /// Wake me changed: at (or past) the stop to get off, the next step begins.
  void wakeChanged(WakeState? w) {
    if (!_running || w == null || !w.done) return;
    final steps = _h.tripSteps;
    final i = _h.tripStepIndex;
    // On the bus step, or still on the walk to it when Wake me was started by hand from its card.
    final (:tool, :at) = navToolFor(steps, i);
    final bus = steps[i].kind == StepKind.bus ? i : (tool == NavTool.watchBus ? at : null);
    if (bus == null || steps[bus].service != w.service) return;
    if (bus + 1 < steps.length) unawaited(_go(bus + 1, DateTime.now()));
    // On the last step nothing follows: Wake me has said its piece and stops with the trip.
  }

  /// While walking to the next ride or waiting for it: is there a way from that stop to the
  /// destination at least [betterWayMinutes] sooner? Offered on the trip page; in the background
  /// one alert a step. Worked out on the phone; never switches by itself.
  Future<void> checkBetter(DateTime now, {bool? inBackground}) async {
    if (!_running) return;
    final h = _h;
    final i = h.tripStepIndex;
    final key = (h.tripStart!, i);
    final steps = h.tripSteps;
    final to = h.tripTo;
    final net = ref.read(transitNetProvider).value;
    final j = nextRideIndex(steps, i);
    if (to == null || net == null || j == null || _keptMine == key || steps[i].kind != StepKind.walk) {
      ref.read(betterWayProvider.notifier).state = null;
      return;
    }
    // From the stop or station of the next ride (where the rider waits or is walking to).
    final id = steps[j].from;
    double? lat, lng;
    if (id.startsWith('mrt:')) {
      for (final st in ref.read(mrtStationsProvider).value ?? const <MrtStation>[]) {
        if ('mrt:${st.name}' == id) (lat, lng) = (st.lat, st.lng);
      }
    } else if (ref.read(busStopsByCodeProvider)[id] case final stop?) {
      (lat, lng) = (stop.lat, stop.lng);
    }
    if (lat == null || lng == null) return;
    // The plan from that stop on: what is left of it after the walk there.
    final planned = [...steps.sublist(j)];
    final options = transitOptions(net, Place(kind: PlaceKind.other, addrLat: lat, addrLng: lng), to);
    final better = betterWay(
        [TripStep(kind: StepKind.walk, from: '', to: id, fromName: '', toName: steps[j].fromName, minutes: 0), ...planned],
        0,
        options);
    ref.read(betterWayProvider.notifier).state = better;
    if (better == null || _toldBetter == key) return;
    final background = inBackground ?? WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    if (!background) return;
    _toldBetter = key;
    final s = ref.read(stringsProvider);
    await showNote(
        betterWayNote(s,
            first: better.rides.first.service ?? '',
            rides: better.rides.map((r) => r.service).join(' > '),
            saved: remainingMinutes(planned, 0) - better.minutes),
        s: s);
  }

  /// The rider takes the faster way: the rest of the trip becomes its steps (from the walk to its
  /// first ride). Returns what was replaced, for Undo.
  Future<TripPlanBefore?> switchToBetter({DateTime? now}) async {
    final better = ref.read(betterWayProvider);
    if (!_running || better == null) return null;
    final h = _h;
    final before = (steps: h.tripSteps, index: h.tripStepIndex, at: h.tripStepAt);
    _stopTool();
    ref.read(betterWayProvider.notifier).state = null;
    await ref.read(habitsProvider.notifier).replaceTripSteps(stepsOf(better), 0, now ?? DateTime.now());
    return before;
  }

  /// Undo of [switchToBetter]: the earlier plan again, and no offer of the same way for that step.
  Future<void> undoSwitch(TripPlanBefore before) async {
    if (!_running) return;
    _stopTool();
    await ref.read(habitsProvider.notifier).replaceTripSteps(before.steps, before.index, before.at ?? DateTime.now());
    keepMine();
  }

  /// The rider keeps their way: no faster way is offered again on this step.
  void keepMine() {
    if (!_running) return;
    _keptMine = (_h.tripStart!, _h.tripStepIndex);
    ref.read(betterWayProvider.notifier).state = null;
  }

  /// Estimates without location: the get-off note on a bus, the end of a train run.
  Future<void> tick(DateTime now) async {
    if (!_running) return;
    await checkBetter(now);
    if (!_running) return;
    final h = _h;
    final steps = h.tripSteps;
    final i = h.tripStepIndex;
    final at = h.tripStepAt ?? h.tripStart!;
    final step = steps[i];
    final key = (h.tripStart!, i);
    if (step.kind == StepKind.bus && ref.read(wakeProvider) == null && _toldGetOff != key && navGetOffDue(step, at, now)) {
      _toldGetOff = key;
      final s = ref.read(stringsProvider);
      await showNote(wakeNote(s, WakeEvent.wake, step.toName), s: s);
    } else if (step.kind == StepKind.mrt && navRideOver(steps, i, at, now)) {
      final end = mrtRunEnd(steps, i);
      if (end + 1 < steps.length) await _go(end + 1, now);
    }
  }
}
