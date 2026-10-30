import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'address_picker.dart';
import 'place_sheet.dart';
import 'stop_picker.dart';
import 'theme.dart';
import 'today.dart';
import 'wake.dart';
import 'bus_sheet.dart';
import 'ev.dart';
import 'widgets.dart';

IconData modeIcon(TravelMode m) => switch (m) {
      TravelMode.transit => Icons.directions_bus_outlined,
      TravelMode.car => Icons.directions_car_outlined,
      TravelMode.motorcycle => Icons.two_wheeler,
      TravelMode.bicycle => Icons.pedal_bike,
      TravelMode.taxi => Icons.local_taxi_outlined,
    };

/// One trip on Today: "Home → Work" with a mode switch and what matters for that mode.
class TripSection extends ConsumerWidget {
  const TripSection({
    super.key,
    required this.fromKey,
    required this.from,
    required this.to,
    required this.modeKey,
    required this.modePlace,
    this.fromLabel,
    this.commute = false,
  });

  /// The daily trip to work or school (its History key is "home>work"). Every trip has
  /// I'm leaving; the running trip and Arrived live in [TripBanner] above the tabs.
  final bool commute;

  /// Key of the start place for editing its stops ("home", "work", "extra:0"), or null for "here".
  final String? fromKey;
  final Place from;
  final Place to;

  /// Whose travel mode applies (the non-home end of a commute, or the destination).
  final String modeKey;
  final Place modePlace;
  final String? fromLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final override = ref.watch(modeOverrideProvider)[modeKey];
    final mode = override ?? modePlace.mode;
    final toLabel = placeTitle(s.placeLabel, to);
    final title = s.tripTitle(fromLabel ?? placeTitle(s.placeLabel, from), toLabel);
    // Modes the user picked first, then the rest.
    final modes = [...modePlace.modes, ...TravelMode.values.where((m) => !modePlace.modes.contains(m))];

    final body = switch (mode) {
      TravelMode.transit => _TransitBlock(fromKey: fromKey, from: from, to: to, toLabel: toLabel),
      TravelMode.car => _DriveBlock(from: from, to: to, toLabel: toLabel, lotType: 'C'),
      TravelMode.motorcycle => _DriveBlock(from: from, to: to, toLabel: toLabel, lotType: 'Y'),
      TravelMode.bicycle => _CycleBlock(to: to, toLabel: toLabel),
      TravelMode.taxi => _TaxiBlock(from: from),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Text(title, style: t.titleLarge),
        ),
        for (final a in _advice(ref, mode, from))
          AlertBanner(icon: _adviceIcon(a), text: s.tripAdvice(a)),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PillRow(
            items: [for (final m in modes) (m.name, modeIcon(m), s.modeLabel(m.name))],
            selected: mode.name,
            onTap: (k) => ref.read(modeOverrideProvider.notifier).state = {
              ...ref.read(modeOverrideProvider),
              modeKey: TravelMode.values.byName(k),
            },
          ),
        ),
        _TripTimer(
          route: commute
              ? tripRouteKey(from.kind.name, to.kind.name)
              : tripRouteKey(
                  fromLabel ?? (from.kind == PlaceKind.other ? placeTitle(s.placeLabel, from) : from.kind.name),
                  to.kind == PlaceKind.other ? toLabel : to.kind.name),
          from: from,
          to: to,
          mode: mode,
        ),
        body,
      ],
    );
  }
}

/// Know me: "I'm leaving" starts timing this trip (bus/MRT, car, taxi... with its distance
/// for the fare estimate); [TripBanner] shows it on every tab until Arrived, and it lands
/// in History. After a few trips the card says how long this trip usually takes.
class _TripTimer extends ConsumerWidget {
  const _TripTimer({required this.route, required this.from, required this.to, required this.mode});
  final String route;
  final Place from;
  final Place to;
  final TravelMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(favoritesProvider.select((f) => f.learnHabits))) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final h = ref.watch(habitsProvider);
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    // One trip at a time. The running one is in the banner above the tabs; on a page pushed
    // over the tabs (the trip planner) the tabs are hidden, so it shows here instead.
    if (h.tripStart != null) {
      return (ModalRoute.of(context)?.isFirst ?? true) ? const SizedBox.shrink() : const TripBanner();
    }
    final rain = ref.watch(rainfallProvider).valueOrNull;
    final forecast = ref.watch(forecastProvider).valueOrNull;
    final rainy = (rain != null && (rainfallNear(rain, from.lat, from.lng)?.$2 ?? 0) > 0) ||
        (forecast != null && (forecastNear(forecast, from.lat, from.lng)?.isRainy ?? false));

    final stats = tripStats(h.trips, route);
    final usual = rainy ? (stats.rainy ?? stats.usual) : stats.usual;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              stats.usual == null
                  ? s.tripLearnHint
                  : [
                      s.usualTrip(stats.usual!, stats.count),
                      if (stats.rainy != null) s.rainyTrip(stats.rainy!),
                      if (usual != null) s.arriveAbout(clockLabel(now.add(Duration(minutes: usual)))),
                    ].join(' '),
              style: stats.usual == null ? t.bodySmall : t.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.timer_outlined),
            onPressed: () => ref.read(habitsProvider.notifier).startTrip(
                  route,
                  DateTime.now(),
                  rainy: rainy,
                  mode: mode.name,
                  km: distanceMeters(from.lat, from.lng, to.lat, to.lng) / 1000,
                ),
            label: Text(s.imLeaving),
          ),
        ],
      ),
    );
  }
}

/// Weather tips for this trip and mode, from the live NEA readings near the start.
List<TripAdvice> _advice(WidgetRef ref, TravelMode mode, Place from) {
  final lightning = ref.watch(lightningProvider).valueOrNull;
  final wbgt = ref.watch(wbgtProvider).valueOrNull;
  final forecast = ref.watch(forecastProvider).valueOrNull;
  final rain = ref.watch(rainfallProvider).valueOrNull;
  final air = airNear(ref.watch(psiProvider).valueOrNull, ref.watch(pm25Provider).valueOrNull, from.lat, from.lng);
  final raining = rain == null ? 0.0 : (rainfallNear(rain, from.lat, from.lng)?.$2 ?? 0);
  return tripAdvice(
    mode: mode,
    lightning: lightning != null && lightningNear(lightning, from.lat, from.lng),
    highHeat: wbgt != null && isHighHeat(heatStressNear(wbgt, from.lat, from.lng)),
    air: air?.level,
    rainy: raining > 0 || (forecast != null && (forecastNear(forecast, from.lat, from.lng)?.isRainy ?? false)),
  );
}

IconData _adviceIcon(TripAdvice a) => switch (a) {
      TripAdvice.lightningRide || TripAdvice.lightningWalk => Icons.bolt,
      TripAdvice.rainRide || TripAdvice.rainDrive || TripAdvice.rainTaxi => Icons.umbrella_outlined,
      TripAdvice.heat => Icons.wb_sunny_outlined,
      TripAdvice.haze => Icons.masks_outlined,
    };

// ---------------------------------------------------------------- bus / MRT

class _TransitBlock extends ConsumerWidget {
  const _TransitBlock({required this.fromKey, required this.from, required this.to, required this.toLabel});
  final String? fromKey;
  final Place from;
  final Place to;
  final String toLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(busStopsProvider).valueOrNull ?? const <BusStop>[];
    final routes = ref.watch(busRoutesProvider).valueOrNull ?? BusRoutes.empty;
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final trip = tripStops(usableStops(from), all, routes, from, to);
    final destStops = destinationStops(to, all);
    final anyDirect = routes.routes.isNotEmpty &&
        trip.stops.any((st) => tripRides(routes, st, to, destStops).isNotEmpty);
    final straight = distanceMeters(from.lat, from.lng, to.lat, to.lng);

    final buses = <Widget>[
      if (trip.stops.isEmpty)
        Panel(
          child: EmptyNote(s.noDirectBus,
              action: TextButton(onPressed: () => openDirections(to.lat, to.lng), child: Text(s.routeInMaps))),
        ),
      for (final st in trip.stops)
        TripBusCard(
          stop: st,
          fromKey: fromKey,
          to: to,
          toLabel: toLabel,
          suggestedMetres: trip.suggested ? distanceMeters(from.lat, from.lng, st.lat, st.lng) : null,
          from: from,
        ),
    ];
    final mrt = _MrtOption(from: from, to: to);
    // Plan B: when the train on this trip is disrupted, buses come first with a note.
    final stations = ref.watch(mrtStationsProvider).valueOrNull ?? const <MrtStation>[];
    final plan = stations.isEmpty ? null : mrtPlan(stations, from, to);
    final bad = planDisruption(plan, ref.watch(trainAlertsProvider).valueOrNull);

    // Already there (e.g. "Here" after the ride): no walk or buses to suggest.
    if (fromKey == null && straight < arrivedMetres) {
      return Panel(
        color: DL.mint,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.where_to_vote_outlined, color: DL.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.youAreHere, style: t.titleMedium?.copyWith(color: DL.ink)),
                    Text(s.arrivedAt(toLabel), style: t.bodyMedium?.copyWith(color: DL.ink)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (straight < walkInsteadMetres)
          Panel(
            color: DL.mint,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.directions_walk, color: DL.ink),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s.walkIsQuicker(s.walkMinutes(straight * 1.3), s.metres(straight)),
                            style: t.titleMedium?.copyWith(color: DL.ink)),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: DL.ink),
                    onPressed: () => openDirections(to.lat, to.lng, mode: 'walking'),
                    icon: const Icon(Icons.map_outlined),
                    label: Text(s.walkingRoute),
                  ),
                ],
              ),
            ),
          ),
        // No direct bus anywhere near: the train is the real answer, so show it first.
        // Within walking distance the train is never the better answer.
        if (bad.lines.isNotEmpty && straight >= walkInsteadMetres) ...[
          AlertBanner(
            icon: Icons.alt_route,
            text: s.planB(bad.lines.map(s.lineName).join(', '), busOk: anyDirect, freeBus: bad.freeBus),
          ),
          if (!anyDirect)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.local_taxi_outlined),
                label: Text(s.taxiInstead),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => TaxiSheet(origin: from),
                ),
              ),
            ),
        ],
        if (straight < walkInsteadMetres)
          ...buses
        else if (anyDirect || bad.lines.isNotEmpty)
          ...[...buses, mrt]
        else
          ...[mrt, ...buses],
      ],
    );
  }
}

/// Nearest MRT/LRT station at each end, with the line if no change is needed.
class _MrtOption extends ConsumerWidget {
  const _MrtOption({required this.from, required this.to});
  final Place from;
  final Place to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(mrtStationsProvider).valueOrNull ?? const <MrtStation>[];
    if (stations.isEmpty) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final plan = mrtPlan(stations, from, to);
    if (plan == null) return const SizedBox.shrink();
    final alerts = ref.watch(trainAlertsProvider).valueOrNull;
    final lines = {
      for (final c in [...plan.board.codes, ...plan.alight.codes])
          if (lineOfCode(c) case final l?) l,
    };
    final disrupted = alerts == null
        ? const <String>[]
        : [for (final l in lineStatuses(alerts, lines)) if (l.disrupted) l.line];
    final resting = transitResting(ref.watch(clockProvider).valueOrNull ?? DateTime.now());

    Widget stationRow(IconData icon, String text, MrtStation st) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [Text(text, style: t.bodyMedium), for (final c in st.codes) StationChip(c)],
                ),
              ),
            ],
          ),
        );

    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.subway_outlined),
              const SizedBox(width: 8),
              Text(s.mrtOption, style: t.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          if (resting) AlertBanner(icon: Icons.bedtime_outlined, text: s.trainsResting, tone: AlertTone.info),
          ...[
            stationRow(Icons.directions_walk, s.walkTo(plan.board.name, s.metres(plan.walkToBoard)), plan.board),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(plan.direct ? Icons.trending_flat : Icons.swap_horiz, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        plan.direct
                            ? s.rideLine(s.lineName(plan.line!), plan.stops)
                            : plan.via == null
                                ? s.changeTrains
                                : s.changeAt(plan.via!.name),
                        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            stationRow(Icons.place_outlined, s.alightAt(plan.alight.name, s.metres(plan.walkFromAlight)), plan.alight),
            for (final l in disrupted)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(s.mrtLineDisrupted(s.lineName(l)), style: t.bodySmall?.copyWith(color: DL.stop)),
              ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => openRoute(from.lat, from.lng, to.lat, to.lng),
              icon: const Icon(Icons.map_outlined),
              label: Text(s.mrtRouteInMaps),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Buses at one stop, split into those that go to the destination and the rest.
class TripBusCard extends ConsumerWidget {
  const TripBusCard({
    super.key,
    required this.stop,
    required this.fromKey,
    required this.to,
    required this.toLabel,
    this.suggestedMetres,
    this.from,
  });

  /// Where the trip starts, for "leave in N min" (walk to the stop plus live arrivals).
  final Place? from;

  /// Set when this is a nearby stop suggested instead of the saved ones.
  final double? suggestedMetres;
  final BusStop stop;
  final String? fromKey;
  final Place to;
  final String toLabel;

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final picked = await Navigator.of(context).push<BusStop>(
      MaterialPageRoute(builder: (_) => StopPickerPage(title: s.changeStop)),
    );
    if (picked != null && fromKey != null) {
      await ref.read(favoritesProvider.notifier).replaceStop(fromKey!, stop.code, picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final etas = ref.watch(busArrivalProvider(stop.code));
    final routes = ref.watch(busRoutesProvider).valueOrNull ?? BusRoutes.empty;
    final all = ref.watch(busStopsProvider).valueOrNull ?? const <BusStop>[];
    final names = {for (final x in all) x.code: x.name};
    final byCode = ref.watch(busStopsByCodeProvider);
    String? live(BusEta e) => s.busLive(e, busWhere(e, stop.code, routes, byCode));
    final rides = routes.routes.isEmpty ? null : tripRides(routes, stop, to, destinationStops(to, all));
    final fromName = fromKey == null ? s.hereNow : s.placeLabel(fromKey!);

    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rides == null ? s.busFrom(stop.name) : s.busesTo(toLabel), style: t.titleMedium),
                      Text(stop.name, style: t.bodyMedium),
                      if (suggestedMetres != null)
                        Text(s.suggestedStop(s.metres(suggestedMetres!), fromName), style: t.bodySmall),
                    ],
                  ),
                ),
                if (fromKey != null && suggestedMetres == null)
                  IconButton(
                    tooltip: s.changeStop,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _change(context, ref),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: etas.when(
                loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
                error: (_, __) => EmptyNote(s.busesUnavailable),
                data: (list) {
                  // Nothing at the stop (late at night, or a gap): say so, not "no direct bus".
                  if (list.isEmpty) {
                    return EmptyNote(transitResting(ref.watch(clockProvider).valueOrNull ?? DateTime.now()) ? s.busesResting : s.noBusesNow);
                  }
                  if (rides == null) {
                    // Route data not downloaded yet: show every bus, as before.
                    return list.isEmpty
                        ? EmptyNote(s.noBusesNow)
                        : Column(children: [
                            for (final (i, (e, next)) in groupEtas(list).take(8).indexed)
                              BusRow(
                                eta: e,
                                next: next,
                                pulse: i == 0 && e.minutes == 0,
                                live: live(e),
                                onTap: () => showWhereBus(context, stop: stop, service: e.service),
                              ),
                          ]);
                  }
                  final grouped = groupEtas(list);
                  final direct = grouped.where((e) => rides.containsKey(e.$1.service)).toList();
                  final others = grouped.where((e) => !rides.containsKey(e.$1.service)).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (direct.isEmpty)
                        EmptyNote(
                          s.noDirectBus,
                          action: TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: () => openDirections(to.lat, to.lng),
                            child: Text(s.routeInMaps),
                          ),
                        ),
                      if (direct.isNotEmpty && from != null)
                        if (leaveBy(direct, null, walkMinutesTo(distanceMeters(from!.lat, from!.lng, stop.lat, stop.lng))) case final lb?
                            when distanceMeters(from!.lat, from!.lng, stop.lat, stop.lng) < 1500)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.directions_walk, size: 20, color: DL.tealText),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                      direct.first.$1.service != lb.service && direct.first.$1.minutes < lb.walk
                                          ? s.tooSoonThen(direct.first.$1.service, s.leaveIn(lb.service, lb.leaveIn, lb.walk))
                                          : s.leaveIn(lb.service, lb.leaveIn, lb.walk),
                                      style: t.titleSmall?.copyWith(color: DL.tealText)),
                                ),
                              ],
                            ),
                          ),
                      if (direct.isNotEmpty)
                        BusBoard(
                          arrLabel: s.minutesAway(0),
                          minLabel: s.min,
                          thenLabel: s.thenIn,
                          hint: s.tapBusHint,
                          rows: [
                            for (final (e, next) in direct.take(6))
                              BoardRow(
                                service: e.service,
                                minutes: e.minutes,
                                next: next,
                                live: live(e),
                                load: e.load,
                                info: [s.loadLabel(e.load), s.busExtras(e)].where((x) => x.isNotEmpty).join(' · '),
                                note: s.rideInfo(
                                  rides[e.service]!.stops,
                                  rides[e.service]!.km,
                                  names[rides[e.service]!.alightAt] ?? rides[e.service]!.alightAt,
                                ),
                                onTap: () => showWhereBus(context,
                                    stop: stop,
                                    service: e.service,
                                    toName: names[rides[e.service]!.alightAt] ?? ''),
                              ),
                          ],
                        ),
                      if (direct.isNotEmpty)
                        Builder(builder: (context) {
                          // One choice per direct service: the rider picks the bus they boarded,
                          // which may not be the first one shown.
                          final byCode = {for (final x in all) x.code: x};
                          final choices = <(String, BusStop, BusStop?)>[
                            for (final (e, _) in direct)
                              if (byCode[rides[e.service]!.alightAt] case final alight?)
                                (e.service, alight, byCode[stopBefore(routes, rides[e.service]!)]),
                          ];
                          if (choices.isEmpty) return const SizedBox.shrink();
                          void open((String, BusStop, BusStop?) c) => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => WakeMePage(service: c.$1, alight: c.$2, before: c.$3),
                              ));
                          final stops = {for (final c in choices) c.$2.code};
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.notifications_active_outlined),
                              label: Text(stops.length == 1 ? s.wakeMeAt(choices.first.$2.name) : s.wakeTitle),
                              onPressed: () => choices.length == 1
                                  ? open(choices.first)
                                  : showModalBottomSheet<void>(
                                      context: context,
                                      showDragHandle: true,
                                      builder: (sheet) => SafeArea(
                                        child: ListView(
                                          shrinkWrap: true,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                              child: Text(s.wakePickBus, style: t.titleMedium),
                                            ),
                                            for (final c in choices)
                                              ListTile(
                                                leading: ConstrainedBox(
                                                  constraints: const BoxConstraints(maxWidth: 96),
                                                  child: BusPlate(c.$1),
                                                ),
                                                title: Text(s.wakeMeAt(c.$2.name)),
                                                onTap: () {
                                                  Navigator.of(sheet).pop();
                                                  open(c);
                                                },
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          );
                        }),
                      if (others.isNotEmpty)
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text('${s.otherBuses} (${others.length})', style: t.labelLarge),
                            children: [for (final (e, next) in others.take(10))
                                BusRow(
                                  eta: e,
                                  next: next,
                                  pulse: false,
                                  live: live(e),
                                  onTap: () => showWhereBus(context, stop: stop, service: e.service),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (suggestedMetres != null && fromKey != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.push_pin_outlined),
                  label: Text(s.useThisStop),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await ref.read(favoritesProvider.notifier).useStop(fromKey!, stop);
                    messenger.showSnackBar(SnackBar(content: Text(s.stopSaved(stop.name))));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- car / motorbike

class _DriveBlock extends ConsumerWidget {
  const _DriveBlock({required this.from, required this.to, required this.toLabel, required this.lotType});
  final Place from;
  final Place to;
  final String toLabel;
  final String lotType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final parking = ref.watch(parkingLiveProvider);
    final incidents = incidentsOnTrip(ref.watch(incidentsProvider).valueOrNull, from, to);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.parkingNearPlace(toLabel), padding: const EdgeInsets.fromLTRB(4, 0, 4, 10)),
        Panel(
          child: parking.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (_, __) => EmptyNote(s.serverWaking),
            data: (all) {
              final near = parkingNear(all, to.lat, to.lng, lotType);
              if (near.isEmpty) return EmptyNote(s.noParkingData);
              return Column(
                children: [
                  for (final (p, d) in near)
                    ListTile(
                      leading: Icon(lotType == 'Y' ? Icons.two_wheeler : Icons.local_parking),
                      title: Text(p.name.isEmpty ? p.id : p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${s.metres(d)} · ${p.agency}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${p.available}',
                              style: t.displaySmall?.copyWith(fontSize: 24, color: p.available == 0 ? DL.stop : null)),
                          Text(lotType == 'Y' ? s.bikeLots : s.carLots, style: t.labelSmall),
                        ],
                      ),
                      onTap: () => showPlaceSheet(context,
                          s: s, title: p.name.isEmpty ? p.id : p.name, lat: p.lat, lng: p.lng, distance: d),
                    ),
                ],
              );
            },
          ),
        ),
        if (lotType == 'C' && ref.watch(favoritesProvider.select((f) => f.drivesEv)))
          EvChargers(lat: to.lat, lng: to.lng, title: s.evChargersNear(toLabel)),
        SectionTitle(s.trafficOnWay, padding: const EdgeInsets.fromLTRB(4, 0, 4, 10)),
        if (incidents.isEmpty)
          Panel(child: EmptyNote(s.noIncidents, icon: Icons.check_circle_outline))
        else
          for (final (type, msg) in incidents.take(4))
            AlertBanner(icon: Icons.warning_amber_rounded, text: '$type: $msg'),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: FilledButton.icon(
            icon: const Icon(Icons.directions_car),
            label: Text(s.driveInMaps),
            onPressed: () => openDirections(to.lat, to.lng, mode: 'driving'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- bicycle

class _CycleBlock extends ConsumerWidget {
  const _CycleBlock({required this.to, required this.toLabel});
  final Place to;
  final String toLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final racks = ref.watch(bicycleRacksProvider).valueOrNull ?? const <EPoint>[];
    final near = within(racks, to.lat, to.lng, 800, latOf: (p) => p.lat, lngOf: (p) => p.lng, limit: 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AlertBanner(icon: Icons.wb_cloudy_outlined, text: s.cycleWeatherTip, tone: AlertTone.info),
        SectionTitle('${s.bicycleParking} $toLabel', padding: const EdgeInsets.fromLTRB(4, 0, 4, 10)),
        Panel(
          child: Column(
            children: [
              if (near.isEmpty) EmptyNote(racks.isEmpty ? s.bundlesLoading : s.noRacks),
              for (final (p, d) in near)
                ListTile(
                  leading: const Icon(Icons.pedal_bike),
                  title: Text(p.name),
                  subtitle: Text(s.metres(d)),
                  onTap: () => showPlaceSheet(context, s: s, title: p.name, lat: p.lat, lng: p.lng, distance: d),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: FilledButton.icon(
            icon: const Icon(Icons.pedal_bike),
            label: Text(s.rideInMaps),
            onPressed: () => openDirections(to.lat, to.lng, mode: 'bicycling'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- taxi

class _TaxiBlock extends ConsumerWidget {
  const _TaxiBlock({required this.from});
  final Place from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final body = ref.watch(taxiProvider).valueOrNull;
    final n = body == null ? null : taxiBands(taxiPoints(body), from.lat, from.lng).$2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: BentoTile(
        icon: Icons.local_taxi_outlined,
        value: n == null ? '–' : '$n',
        caption: '${s.taxisNear(placeTitle(s.placeLabel, from))} · 500 m',
        tint: n == 0 ? DL.attention : null,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => TaxiSheet(origin: from),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- go somewhere

/// Pick any saved place and see how to get there now, from Home or from where you are.
class GoSomewhere extends ConsumerWidget {
  const GoSomewhere({super.key, this.showTitle = true});
  final bool showTitle;

  Future<void> _useHere(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        messenger.showSnackBar(SnackBar(content: Text(s.locationDenied)));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      ref.read(goFromHereProvider.notifier).state = Place(
        kind: PlaceKind.other,
        name: s.hereNow,
        addrLat: pos.latitude,
        addrLng: pos.longitude,
      );
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(s.locationUnavailable)));
    }
  }

  Future<void> _search(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final hit = await Navigator.of(context).push<AddressHit>(
      MaterialPageRoute(builder: (_) => AddressPickerPage(title: s.searchPlace)),
    );
    if (hit == null) return;
    ref.read(goAdhocDestProvider.notifier).state = Place(
      kind: PlaceKind.other,
      name: shortAddress(hit.label),
      address: hit.label,
      postal: hit.postal.isEmpty ? null : hit.postal,
      addrLat: hit.lat,
      addrLng: hit.lng,
    );
    ref.read(goKeyProvider.notifier).state = 'adhoc';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final fav = ref.watch(favoritesProvider);
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final key = ref.watch(goKeyProvider);
    final here = ref.watch(goFromHereProvider);
    final adhoc = ref.watch(goAdhocDestProvider);
    var fromKey = ref.watch(goFromKeyProvider);

    final options = <(String, IconData, String)>[
      for (final i in extrasForToday(fav, now)) ('extra:$i', Icons.star_outline, placeTitle(s.placeLabel, fav.extraPlaces[i])),
      for (final k in [PlaceKind.work, PlaceKind.school, PlaceKind.home])
        if (fav.places[k] != null) (k.name, PlaceSelector.iconOf(k), s.placeLabel(k.name)),
      if (adhoc != null) ('adhoc', Icons.place_outlined, adhoc.name ?? s.anyAddress),
      ('search', Icons.search, s.anyAddress),
    ];
    Place? dest;
    if (key == 'adhoc') {
      dest = adhoc;
    } else if (key != null && key.startsWith('extra:')) {
      final i = int.tryParse(key.substring(6)) ?? -1;
      if (i >= 0 && i < fav.extraPlaces.length) dest = fav.extraPlaces[i];
    } else if (key != null) {
      dest = fav.places[PlaceKind.values.byName(key)];
    }

    // Where the trip starts: a saved place (not the destination itself) or "here".
    // "Here" first: away from home, starting from where you are is the usual case.
    final starts = <(String, IconData, String)>[
      ('here', Icons.my_location, s.hereNow),
      for (final k in [PlaceKind.home, PlaceKind.work, PlaceKind.school])
        if (fav.places[k] != null && k.name != key) (k.name, PlaceSelector.iconOf(k), s.placeLabel(k.name)),
    ];
    if (!starts.any((o) => o.$1 == fromKey) || (fromKey == 'here' && here == null)) {
      fromKey = starts.length > 1 && here == null ? starts[1].$1 : starts.first.$1;
    }
    final from = fromKey == 'here' ? here : fav.places[PlaceKind.values.byName(fromKey)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Text(s.goSomewhere, style: t.titleLarge),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(fav.extraPlaces.isEmpty ? s.addPlacesHint : s.goSomewhereHint, style: t.bodySmall),
        ),
        _Label(s.to),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PillRow(
            items: options,
            selected: key ?? '',
            onTap: (k) {
              if (k == 'search') {
                _search(context, ref);
              } else {
                ref.read(goKeyProvider.notifier).state = key == k ? null : k;
              }
            },
          ),
        ),
        if (dest != null) ...[
          _Label(s.from),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PillRow(
              items: starts,
              selected: fromKey,
              onTap: (k) {
                ref.read(goFromKeyProvider.notifier).state = k;
                if (k == 'here') _useHere(context, ref);
              },
            ),
          ),
          if (from != null)
            TripSection(
              fromKey: fromKey == 'here' ? null : fromKey,
              from: from,
              fromLabel: fromKey == 'here' ? s.hereNow : null,
              to: dest,
              modeKey: key!,
              modePlace: dest,
            ),
        ],
      ],
    );
  }
}

/// Trip planner on its own page, so it is not mixed up with the daily trip on Today.
/// Starts from "Here" when location is already allowed.
class TripPlannerPage extends ConsumerStatefulWidget {
  const TripPlannerPage({super.key});

  @override
  ConsumerState<TripPlannerPage> createState() => _TripPlannerPageState();
}

class _TripPlannerPageState extends ConsumerState<TripPlannerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final perm = await Geolocator.checkPermission();
        if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (!mounted) return;
        ref.read(goFromHereProvider.notifier).state =
            Place(kind: PlaceKind.other, name: ref.read(stringsProvider).hereNow, addrLat: pos.latitude, addrLng: pos.longitude);
        ref.read(goFromKeyProvider.notifier).state = 'here';
      } on Object {
        // No location: the planner starts from a saved place.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.planTrip)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: const [GoSomewhere(showTitle: false)],
      ),
    );
  }
}

/// Today's entry to the trip planner.
class PlanTripCard extends ConsumerWidget {
  const PlanTripCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Panel(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TripPlannerPage())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.alt_route),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.planTrip, style: t.titleMedium),
                    Text(s.planTripSub, style: t.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}

/// The trip being timed, above the tabs on every screen (like [WakeBanner]): where to, since
/// when, Arrived (logs it to History) and Stop timing.
class TripBanner extends ConsumerWidget {
  const TripBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(habitsProvider);
    final start = h.tripStart;
    final ends = h.tripRoute == null ? null : tripRouteEnds(h.tripRoute!);
    if (start == null || ends == null) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final notifier = ref.read(habitsProvider.notifier);
    return Panel(
      margin: const EdgeInsets.only(bottom: 10),
      color: DL.mint,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined, color: DL.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.routeLabel(s.routeEnd(ends.$1), s.routeEnd(ends.$2)),
                      style: t.titleSmall?.copyWith(color: DL.ink), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(s.onTheWay(clockLabel(start), s.durationShort(now.difference(start).inMinutes)),
                      style: t.bodySmall?.copyWith(color: DL.ink)),
                ],
              ),
            ),
            IconButton(
              tooltip: s.tripCancel,
              icon: const Icon(Icons.close, color: DL.ink),
              onPressed: notifier.cancelTrip,
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final m = await notifier.finishTrip(DateTime.now());
                messenger.showSnackBar(SnackBar(content: Text(m == null ? s.tripTooShort : s.tripLogged(m))));
              },
              child: Text(s.arrived),
            ),
          ],
        ),
      ),
    );
  }
}
