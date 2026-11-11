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
import 'mrt_ride.dart';
import '../mrt_ride.dart';
import 'widgets.dart';

IconData modeIcon(TravelMode m) => switch (m) {
      TravelMode.transit => Icons.directions_bus_outlined,
      TravelMode.car => Icons.directions_car_outlined,
      TravelMode.motorcycle => Icons.two_wheeler,
      TravelMode.bicycle => Icons.pedal_bike,
      TravelMode.taxi => Icons.local_taxi_outlined,
      TravelMode.walk => Icons.directions_walk,
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
    this.startsHere = false,
    this.endsHere = false,
  });

  /// The destination is the phone's location: like [startsHere], it is never sent to the server.
  final bool endsHere;

  /// The trip starts from the phone's location: within [arrivedMetres] it says "You're here".
  final bool startsHere;

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
    final straight = distanceMeters(from.lat, from.lng, to.lat, to.lng);
    // A mode picked by hand wins; otherwise a short planned trip opens on Walk.
    final override = ref.watch(modeOverrideProvider)[modeKey];
    final mode = override ?? defaultTripMode(modePlace.mode, straight, commute: commute);
    final toLabel = placeTitle(s.placeLabel, to);
    final title = s.tripTitle(fromLabel ?? placeTitle(s.placeLabel, from), toLabel);
    final modes = tripModes(modePlace.modes);

    final body = switch (mode) {
      TravelMode.transit => _TransitBlock(
          fromKey: fromKey,
          from: from,
          fromName: fromLabel ?? placeTitle(s.placeLabel, from),
          to: to,
          toLabel: toLabel,
          startsHere: startsHere),
      TravelMode.car => _DriveBlock(from: from, to: to, toLabel: toLabel, lotType: 'C', endsHere: endsHere),
      TravelMode.motorcycle => _DriveBlock(from: from, to: to, toLabel: toLabel, lotType: 'Y', endsHere: endsHere),
      TravelMode.bicycle => _CycleBlock(from: from, to: to, toLabel: toLabel, endsHere: endsHere),
      TravelMode.taxi => _TaxiBlock(from: from, to: to, startsHere: startsHere),
      TravelMode.walk => startsHere && straight < arrivedMetres
          ? _ThereNote(title: s.youAreHere, sub: s.arrivedAt(toLabel))
          : _WalkCard(to: to, straight: straight),
    };

    final heading = Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(title, style: t.titleLarge),
    );
    final timer = _TripTimer(
      route: commute
          ? tripRouteKey(from.kind.name, to.kind.name)
          : tripRouteKey(
              fromLabel ?? (from.kind == PlaceKind.other ? placeTitle(s.placeLabel, from) : from.kind.name),
              to.kind == PlaceKind.other ? toLabel : to.kind.name),
      from: from,
      to: to,
      mode: mode,
    );
    // From and To at the same spot (e.g. a searched start that is the destination): nothing to plan,
    // no "0 min walk · 0 m" or buses. A trip being timed still shows, with Arrived.
    if (straight < samePlaceMetres) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          if (ref.watch(habitsProvider).tripStart != null) timer,
          _ThereNote(title: s.alreadyThere, sub: s.arrivedAt(toLabel)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
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
        timer,
        body,
      ],
    );
  }
}

/// Walking the whole way: minutes and distance, with the route in Google Maps as a button.
/// The card of the Walk mode, and the first card of a bus trip short enough to walk.
class _WalkCard extends ConsumerWidget {
  const _WalkCard({required this.to, required this.straight});
  final Place to;
  final double straight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Panel(
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
                  child: Text(s.walkIsQuicker(s.walkMinutes(routeMetres(straight)), s.metres(straight)),
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
    );
  }
}

/// A mode's own card: the rough time and distance first, then the way out to Google Maps as an
/// explicit button. Nothing leaves the app until that button is tapped.
class _ModeCard extends ConsumerWidget {
  const _ModeCard({required this.mode, required this.from, required this.to, required this.mapsLabel, required this.mapsMode});
  final TravelMode mode;
  final Place from;
  final Place to;
  final String mapsLabel;

  /// Google Maps' travelmode for the button.
  final String mapsMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final straight = distanceMeters(from.lat, from.lng, to.lat, to.lng);
    final minutes = modeMinutes(mode, straight);
    return Panel(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(modeIcon(mode))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (minutes != null)
                        Text(s.modeEta(mode.name, minutes, s.metres(routeMetres(straight))), style: t.titleMedium),
                      Text(s.modeEtaNote, style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(mapsLabel),
              onPressed: () => openDirections(to.lat, to.lng, mode: mapsMode),
            ),
          ],
        ),
      ),
    );
  }
}

/// "You're here" / "You're already there": the trip needs no planning.
class _ThereNote extends StatelessWidget {
  const _ThereNote({required this.title, required this.sub});
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
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
                  Text(title, style: t.titleMedium?.copyWith(color: DL.ink)),
                  Text(sub, style: t.bodyMedium?.copyWith(color: DL.ink)),
                ],
              ),
            ),
          ],
        ),
      ),
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
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    // One trip at a time. The running one is in the banner above the tabs; on a page pushed
    // over the tabs (the trip planner) the tabs are hidden, so it shows here instead.
    if (h.tripStart != null) {
      if (ModalRoute.of(context)?.isFirst ?? true) return const SizedBox.shrink();
      return ref.watch(rideProvider) != null ? const RideBanner() : const TripBanner();
    }
    final rain = ref.watch(rainfallProvider).value;
    final forecast = ref.watch(forecastProvider).value;
    final rainy = (rain != null && (rainfallNear(rain, from.lat, from.lng)?.$2 ?? 0) > 0) ||
        (forecast != null && (forecastNear(forecast, from.lat, from.lng)?.isRainy ?? false));

    final stats = tripStats(h.trips, route);
    final usual = rainy ? (stats.rainy ?? stats.usual) : stats.usual;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stats.usual != null) ...[
            Text(
              [
                s.usualTrip(stats.usual!, stats.count),
                if (stats.rainy != null) s.rainyTrip(stats.rainy!),
                if (usual != null) s.arriveAbout(clockLabel(now.add(Duration(minutes: usual)))),
              ].join(' '),
              style: t.bodyMedium,
            ),
            const SizedBox(height: 8),
          ],
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
          // How it works, small and under the button, until this trip has been learned.
          if (stats.usual == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(s.tripLearnHint, style: t.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Weather tips for this trip and mode, from the live NEA readings near the start.
List<TripAdvice> _advice(WidgetRef ref, TravelMode mode, Place from) {
  final lightning = ref.watch(lightningProvider).value;
  final wbgt = ref.watch(wbgtProvider).value;
  final forecast = ref.watch(forecastProvider).value;
  final rain = ref.watch(rainfallProvider).value;
  final air = airNear(ref.watch(psiProvider).value, ref.watch(pm25Provider).value, from.lat, from.lng);
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
      TripAdvice.lightningRide || TripAdvice.lightningWalk || TripAdvice.lightningOnFoot => Icons.bolt,
      TripAdvice.rainRide || TripAdvice.rainWalk || TripAdvice.rainDrive || TripAdvice.rainTaxi => Icons.umbrella_outlined,
      TripAdvice.heat => Icons.wb_sunny_outlined,
      TripAdvice.haze => Icons.masks_outlined,
    };

// ---------------------------------------------------------------- bus / MRT

class _TransitBlock extends ConsumerWidget {
  const _TransitBlock({
    required this.fromKey,
    required this.from,
    required this.fromName,
    required this.to,
    required this.toLabel,
    required this.startsHere,
  });
  final bool startsHere;
  final String? fromKey;
  final Place from;
  final String fromName;
  final Place to;
  final String toLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(busStopsProvider).value ?? const <BusStop>[];
    final routes = ref.watch(busRoutesProvider).value ?? BusRoutes.empty;
    final s = ref.watch(stringsProvider);
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
          fromName: fromName,
        ),
    ];
    final mrt = _MrtOption(from: from, to: to);
    // Plan B: when the train on this trip is disrupted, buses come first with a note.
    final stations = ref.watch(mrtStationsProvider).value ?? const <MrtStation>[];
    final plan = stations.isEmpty ? null : mrtPlan(stations, from, to);
    final bad = planDisruption(plan, ref.watch(trainAlertsProvider).value);

    // Already there (e.g. "Here" after the ride): no walk or buses to suggest.
    if (startsHere && straight < arrivedMetres) return _ThereNote(title: s.youAreHere, sub: s.arrivedAt(toLabel));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (straight < walkInsteadMetres) _WalkCard(to: to, straight: straight),
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
    final stations = ref.watch(mrtStationsProvider).value ?? const <MrtStation>[];
    if (stations.isEmpty) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final usual = mrtPlan(stations, from, to);
    if (usual == null) return const SizedBox.shrink();
    final key = mrtRouteKey(s, from, to);
    final picked = ref.watch(favoritesProvider.select((f) => f.mrtLines[key]));
    final choice = picked == null
        ? null
        : lineMrtChoice(stations, from, to, picked,
            routes: ref.watch(busRoutesProvider).value ?? BusRoutes.empty,
            stops: ref.watch(busStopsProvider).value ?? const <BusStop>[]);
    final plan = choice?.plan ?? usual;
    final feeder = choice?.feeder;
    final alerts = ref.watch(trainAlertsProvider).value;
    final lines = {
      for (final c in [...plan.board.codes, ...plan.alight.codes])
          if (lineOfCode(c) case final l?) l,
    };
    final disrupted = alerts == null
        ? const <String>[]
        : [for (final l in lineStatuses(alerts, lines)) if (l.disrupted) l.line];
    final resting = transitResting(ref.watch(clockProvider).value ?? DateTime.now());
    final ride = choice?.ride ?? mrtRide(stations, plan);
    final riding = ref.watch(rideProvider);
    // How busy the boarding station is now (LTA platform crowd, every 10 min).
    final boardLine = ride != null ? rideLineAt(ride, 0) : (plan.line ?? lineOfCode(plan.board.codes.firstOrNull ?? ''));
    final boardCode = [for (final c in plan.board.codes) if (lineOfCode(c) == boardLine) c].firstOrNull;
    final crowd = boardLine == null || boardCode == null || resting
        ? null
        : ref.watch(stationCrowdProvider(boardLine)).value?[boardCode];

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
          if (choice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  LineChip(choice.line!),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.todayOnLine(choice.line!), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                  TextButton(
                    onPressed: () => showMrtLineSheet(context, from: from, to: to),
                    child: Text(s.changeChoice),
                  ),
                ],
              ),
            ),
          if (alerts != null && disrupted.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: DL.goText(context), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [for (final l in lines) s.lineRunningNormally(s.lineName(l))].join(' · '),
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ...[
            if (feeder != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.directions_bus_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.feederStep(feeder.ride.service, feeder.stop.name, plan.board.name, feeder.ride.stops),
                        style: t.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              stationRow(Icons.subway_outlined, s.boardAt(plan.board.name), plan.board),
            ] else
              stationRow(Icons.directions_walk, s.walkTo(plan.board.name, s.metres(plan.walkToBoard)), plan.board),
            if (crowd != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CrowdPeople(crowd),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.crowdNow(plan.board.name, crowd), style: t.bodyMedium)),
                  ],
                ),
              ),
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
                child: Text(s.mrtLineDisrupted(s.lineName(l)), style: t.bodySmall?.copyWith(color: DL.stopText(context))),
              ),
          ],
          if (ride != null) ...[
            const SizedBox(height: 4),
            if (riding == null)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.subway),
                label: Text(s.imOnTrain),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final fav = ref.read(favoritesProvider);
                  if (fav.learnHabits && ref.read(habitsProvider).tripStart == null) {
                    await ref.read(habitsProvider.notifier).startTrip(
                          key,
                          DateTime.now(),
                          mode: TravelMode.transit.name,
                          km: distanceMeters(from.lat, from.lng, to.lat, to.lng) / 1000,
                        );
                  }
                  await ref.read(rideProvider.notifier).start(ride);
                  await nav.push(MaterialPageRoute<void>(builder: (_) => const MrtRidePage()));
                },
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.subway),
                label: Text(s.rideTo(riding.ride.alight.name)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MrtRidePage())),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(s.imOnTrainSub, style: t.bodySmall, textAlign: TextAlign.center),
            ),
          ],
          if (riding == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.swap_horiz),
                label: Text(s.changeLine),
                onPressed: () => showMrtLineSheet(context, from: from, to: to),
              ),
            ),
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

/// The trip key a picked line is saved under (the same key History uses).
String mrtRouteKey(S s, Place from, Place to) => tripRouteKey(
      from.kind == PlaceKind.other ? placeTitle(s.placeLabel, from) : from.kind.name,
      to.kind == PlaceKind.other ? placeTitle(s.placeLabel, to) : to.kind.name,
    );

/// "How do you want to go today?": the usual route or a line to start on.
Future<void> showMrtLineSheet(BuildContext context, {required Place from, required Place to}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MrtLineSheet(from: from, to: to),
    );

class MrtLineSheet extends ConsumerWidget {
  const MrtLineSheet({super.key, required this.from, required this.to});
  final Place from;
  final Place to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final stations = ref.watch(mrtStationsProvider).value ?? const <MrtStation>[];
    final choices = mrtChoices(stations, from, to,
        routes: ref.watch(busRoutesProvider).value ?? BusRoutes.empty,
        stops: ref.watch(busStopsProvider).value ?? const <BusStop>[]);
    final key = mrtRouteKey(s, from, to);
    final picked = ref.watch(favoritesProvider.select((f) => f.mrtLines[key]));
    final current = choices.any((c) => c.line == picked) ? picked : null;

    String start(MrtChoice c) => c.feeder != null
        ? s.choiceBus(c.feeder!.ride.service, c.plan.board.name)
        : s.choiceWalk(c.plan.board.name, c.plan.walkToBoard);

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(s.changeLineTitle, style: t.titleLarge),
          const SizedBox(height: 4),
          Text(s.changeLineSub, style: t.bodyMedium?.copyWith(color: DL.muted(context))),
          const SizedBox(height: 14),
          for (final c in choices)
            Panel(
              margin: const EdgeInsets.only(bottom: 12),
              color: c.line == current ? DL.mint : null,
              child: InkWell(
                onTap: () async {
                  final nav = Navigator.of(context);
                  await ref.read(favoritesProvider.notifier).setMrtLine(key, c.line);
                  nav.pop();
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (c.line != null) LineChip(c.line!),
                                Text(
                                  c.line == null ? s.usualRoute : s.lineChoiceTitle(c.line!),
                                  style: t.titleMedium?.copyWith(color: c.line == current ? DL.ink : null),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.choiceSummary(c.minutes, c.changes, start(c)),
                              style: t.bodyMedium?.copyWith(color: c.line == current ? DL.ink : DL.muted(context)),
                            ),
                          ],
                        ),
                      ),
                      if (c.line == current) const Icon(Icons.check_circle, color: DL.ink),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bus to leave for, on top of a trip card: "Leave in 7 min to catch 36", in the "go" colour.
class _LeaveCard extends ConsumerWidget {
  const _LeaveCard({required this.lb});
  final LeaveBy lb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    // The plate scales down rather than wrap "970A" inside it.
    final plate = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 96),
      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: BusPlate(lb.service)),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.leaveInHead(lb.service, lb.leaveIn),
            style: t.titleLarge?.copyWith(color: DL.ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1, right: 4),
              child: Icon(Icons.directions_walk, size: 18, color: DL.ink),
            ),
            Expanded(
              child: Text(s.walkToStopThenBus(lb.walk, lb.leaveIn + lb.walk), style: t.bodyMedium?.copyWith(color: DL.ink)),
            ),
          ],
        ),
      ],
    );
    return Panel(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      color: DL.mint,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        // Large text or a narrow card: the plate goes on top, so "catch 190" and "bus in 11 min"
        // get the whole width and never break inside a word or number.
        child: LayoutBuilder(
          builder: (context, box) => MediaQuery.textScalerOf(context).scale(16) > 20 || box.maxWidth < 260
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [plate, const SizedBox(height: 8), text],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [plate, const SizedBox(width: 12), Expanded(child: text)],
                ),
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
    this.fromName,
  });

  /// Where the trip starts, for "leave in N min" (walk to the stop plus live arrivals).
  final Place? from;

  /// The start as shown ("Here", "Home", a searched address), for "… from Home".
  final String? fromName;

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
    final routes = ref.watch(busRoutesProvider).value ?? BusRoutes.empty;
    final all = ref.watch(busStopsProvider).value ?? const <BusStop>[];
    final names = {for (final x in all) x.code: x.name};
    final byCode = ref.watch(busStopsByCodeProvider);
    String? live(BusEta e) => s.busLive(e, busWhere(e, stop.code, routes, byCode));
    final rides = routes.routes.isEmpty ? null : tripRides(routes, stop, to, destinationStops(to, all));
    final startName = fromName ?? (fromKey == null ? s.hereNow : s.placeLabel(fromKey!));

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
                      Text(s.fromStop(stop.name), style: t.bodyMedium),
                      if (suggestedMetres != null)
                        Text(s.suggestedStop(s.metres(suggestedMetres!), startName), style: t.bodySmall),
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
                    return EmptyNote(transitResting(ref.watch(clockProvider).value ?? DateTime.now()) ? s.busesResting : s.noBusesNow);
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
                  // The bus to leave for comes first and stands out; buses that come before
                  // the walk to the stop is done are dimmed as "Too soon", at the end.
                  final walkM = from == null ? null : distanceMeters(from!.lat, from!.lng, stop.lat, stop.lng);
                  // At the stop already (within atStopMetres): no walk, so the bus there now can be caught.
                  final walk = walkM == null || walkM >= 1500 ? null : (walkM < atStopMetres ? 0 : walkMinutesTo(walkM));
                  final lb = walk == null ? null : leaveBy(direct, null, walk);
                  // Honest comparison with walking all the way: the bus to leave for, door to door.
                  // When it is no quicker, there is no "Leave now" card and the buses fold into one line.
                  final byStop = {for (final x in all) x.code: x};
                  final straight = from == null ? 0.0 : distanceMeters(from!.lat, from!.lng, to.lat, to.lng);
                  final ride = lb == null ? null : rides[lb.service];
                  final alight = ride == null ? null : byStop[ride.alightAt];
                  final slow = from != null &&
                      lb != null &&
                      ride != null &&
                      alight != null &&
                      busNotFaster(
                        stops: ride.stops,
                        doorToDoor: busDoorToDoor(
                          walkToStop: lb.walk,
                          busIn: lb.leaveIn + lb.walk,
                          stops: ride.stops,
                          alightMetres: distanceMeters(alight.lat, alight.lng, to.lat, to.lng),
                        ),
                        straightMetres: straight,
                      );
                  final board = direct.isEmpty
                      ? null
                      : BusBoard(
                        arrLabel: s.minutesAway(0),
                        minLabel: s.min,
                        thenLabel: s.thenIn,
                        hint: s.tapBusHint,
                        rows: [
                          for (final r in tripBoard(direct, lb, walk).take(6))
                            BoardRow(
                              service: r.eta.service,
                              minutes: r.eta.minutes,
                              next: r.next,
                              live: live(r.eta),
                              load: r.eta.load,
                              dim: r.tooSoon,
                              tag: r.tooSoon ? s.tooSoon : null,
                              info: [s.loadLabel(r.eta.load), s.busExtras(r.eta)].where((x) => x.isNotEmpty).join(' · '),
                              note: s.rideInfo(
                                rides[r.eta.service]!.stops,
                                rides[r.eta.service]!.km,
                                names[rides[r.eta.service]!.alightAt] ?? rides[r.eta.service]!.alightAt,
                              ),
                              onTap: () => showWhereBus(context,
                                  stop: stop,
                                  service: r.eta.service,
                                  toName: names[rides[r.eta.service]!.alightAt] ?? ''),
                            ),
                        ],
                      );
                  final wake = direct.isEmpty
                      ? null
                      : Builder(builder: (context) {
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
                              builder: (_) => WakeMePage(service: c.$1, alight: c.$2, before: c.$3, from: stop),
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
                      });
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
                      // Past walkInsteadMetres the trip has no walking card of its own: say what
                      // the bus was compared with.
                      if (board != null && slow && straight >= walkInsteadMetres)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _WalkCard(to: to, straight: straight),
                        ),
                      if (board != null && slow)
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(s.busNotFaster(lb.service, ride.stops), style: t.titleSmall),
                            subtitle: Text(s.busNotFasterHint, style: t.bodySmall),
                            children: [board, if (wake != null) wake],
                          ),
                        )
                      else if (board != null) ...[
                        if (lb != null) _LeaveCard(lb: lb),
                        board,
                        if (wake != null) wake,
                      ],
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
  const _DriveBlock({
    required this.from,
    required this.to,
    required this.toLabel,
    required this.lotType,
    required this.endsHere,
  });
  final Place from;
  final Place to;
  final String toLabel;
  final String lotType;
  final bool endsHere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final mode = lotType == 'Y' ? TravelMode.motorcycle : TravelMode.car;
    final incidents = incidentsOnTrip(ref.watch(incidentsProvider).value, from, to);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeCard(mode: mode, from: from, to: to, mapsLabel: s.driveInMaps, mapsMode: 'driving'),
        _LiveExtras(mode: mode, at: to, here: endsHere, title: s.parkingNearPlace(toLabel)),
        if (lotType == 'C' && ref.watch(favoritesProvider.select((f) => f.drivesEv)))
          EvChargers(lat: to.lat, lng: to.lng, title: s.evChargersNear(toLabel)),
        SectionTitle(s.trafficOnWay, padding: const EdgeInsets.fromLTRB(4, 0, 4, 10)),
        if (incidents.isEmpty)
          Panel(child: EmptyNote(s.noIncidents, icon: Icons.check_circle_outline))
        else
          for (final (type, msg) in incidents.take(4))
            AlertBanner(icon: Icons.warning_amber_rounded, text: '$type: $msg'),
        const SizedBox(height: 14),
      ],
    );
  }
}

// ---------------------------------------------------------------- bicycle

class _CycleBlock extends ConsumerWidget {
  const _CycleBlock({required this.from, required this.to, required this.toLabel, required this.endsHere});
  final Place from;
  final Place to;
  final String toLabel;
  final bool endsHere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeCard(mode: TravelMode.bicycle, from: from, to: to, mapsLabel: s.rideInMaps, mapsMode: 'bicycling'),
        AlertBanner(icon: Icons.wb_cloudy_outlined, text: s.cycleWeatherTip, tone: AlertTone.info),
        _LiveExtras(mode: TravelMode.bicycle, at: to, here: endsHere, title: '${s.bicycleParking} $toLabel'),
        const SizedBox(height: 14),
      ],
    );
  }
}

// ---------------------------------------------------------------- taxi

class _TaxiBlock extends ConsumerWidget {
  const _TaxiBlock({required this.from, required this.to, required this.startsHere});
  final Place from;
  final Place to;
  final bool startsHere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeCard(mode: TravelMode.taxi, from: from, to: to, mapsLabel: s.routeInMaps, mapsMode: 'driving'),
        _LiveExtras(
          mode: TravelMode.taxi,
          at: from,
          here: startsHere,
          title: s.taxisNear(placeTitle(s.placeLabel, from)),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

// ---------------------------------------------------------------- live LTA details

/// What LTA DataMall knows for this mode, under the mode's card: car parks with free car or
/// motorbike lots and bicycle parking near the destination, or the free taxis near the start,
/// each with the time it was read. Asked only while this mode is the one picked
/// (`tripExtrasProvider`). When it cannot be had, one quiet line; the card above stays.
class _LiveExtras extends ConsumerWidget {
  const _LiveExtras({required this.mode, required this.at, required this.here, required this.title});
  final TravelMode mode;

  /// The destination, or the start for taxis.
  final Place at;

  /// [at] is the phone's own position: the phone works the details out itself.
  final bool here;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final extras = ref.watch(tripExtrasProvider((mode: mode, lat: at.lat, lng: at.lng, here: here)));
    final heading = SectionTitle(title, padding: const EdgeInsets.fromLTRB(4, 0, 4, 10));
    Widget small(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(text, style: t.bodySmall),
        );
    return extras.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const Panel(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())),
        ],
      ),
      error: (_, __) => small(s.liveUnavailable),
      data: (x) {
        final time = x.asOf == null ? null : clockLabel(x.asOf!);
        if (mode == TravelMode.taxi) {
          final n = x.taxis ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              Panel(
                color: n == 0 ? DL.attention : null,
                child: ListTile(
                  leading: Icon(Icons.local_taxi_outlined, color: n == 0 ? DL.ink : null),
                  title: Text(s.taxisInRadius(n, x.radius),
                      style: t.titleMedium?.copyWith(color: n == 0 ? DL.ink : null)),
                  subtitle: Text([if (time != null) s.asOf(time), s.seeTaxis].join(' · '),
                      style: t.bodySmall?.copyWith(color: n == 0 ? DL.ink : null)),
                  trailing: Icon(Icons.chevron_right, color: n == 0 ? DL.ink : null),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => TaxiSheet(origin: at),
                  ),
                ),
              ),
            ],
          );
        }
        final bike = mode == TravelMode.bicycle;
        // Large text: the lots go under the name as a line of their own, so nothing is squeezed.
        final stacked = MediaQuery.textScalerOf(context).scale(16) > 20;
        if (x.spots.isEmpty) {
          // No car park with motorbike lots nearby: nothing to say, so no section.
          if (mode == TravelMode.motorcycle) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, Panel(child: EmptyNote(bike ? s.noBicycleParkingNear : s.noParkingNear))],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            Panel(
              margin: const EdgeInsets.only(bottom: 6),
              child: Column(
                children: [
                  for (final p in x.spots)
                    InkWell(
                      onTap: () => showPlaceSheet(context,
                          s: s, title: p.name.isEmpty ? title : p.name, lat: p.lat, lng: p.lng, distance: p.metres),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          // A row of its own, not a ListTile: the lots figure and its label keep
                          // their height at large text.
                          child: Row(
                            children: [
                              Icon(bike
                                  ? Icons.pedal_bike
                                  : mode == TravelMode.motorcycle
                                      ? Icons.two_wheeler
                                      : Icons.local_parking),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name.isEmpty ? title : p.name,
                                        style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    Text(
                                      [
                                        if (bike) s.rackLine(p.rackType, p.racks, p.sheltered),
                                        s.metres(p.metres),
                                        if (!bike) p.agency,
                                      ].where((e) => e.isNotEmpty).join(' · '),
                                      style: t.bodySmall,
                                    ),
                                    if (stacked && p.lots != null)
                                      Text(
                                        '${p.lots} ${s.lotsLabel(p.lots!, motorbike: mode == TravelMode.motorcycle)}',
                                        style: t.titleSmall?.copyWith(color: p.lots == 0 ? DL.stopText(context) : null),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (p.lots == null)
                                const Icon(Icons.map_outlined)
                              else if (!stacked)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${p.lots}',
                                        style: t.displaySmall
                                            ?.copyWith(fontSize: 24, color: p.lots == 0 ? DL.stopText(context) : null)),
                                    Text(s.lotsLabel(p.lots!, motorbike: mode == TravelMode.motorcycle),
                                        style: t.labelSmall),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (time != null) small(bike ? s.asOf(time) : s.lotsAsOf(time)) else const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- go somewhere

/// Plan a trip: one route card with From on top and To below (the same choices on both ends:
/// Here, Home, Work, School, saved places and an address search), a swap button between them,
/// then how to get there now.
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

  /// The address search for one end; the hit becomes that end's one-off place and is picked
  /// there, also when that end already had a searched place.
  Future<void> _search(BuildContext context, WidgetRef ref, {required bool isFrom, required String from}) async {
    final s = ref.read(stringsProvider);
    final hit = await Navigator.of(context).push<AddressHit>(
      MaterialPageRoute(builder: (_) => AddressPickerPage(title: s.searchPlace, places: true)),
    );
    if (hit == null) return;
    // "Use my current location" in the search is Here, not a searched place: Here is what
    // stays on the phone (the live details of a mode card are never asked for it).
    if (hit.here) {
      ref.read(goFromHereProvider.notifier).state =
          Place(kind: PlaceKind.other, name: s.hereNow, addrLat: hit.lat, addrLng: hit.lng);
      return _pick(ref, isFrom: isFrom, key: 'here', from: from);
    }
    (isFrom ? ref.read(goAdhocFromProvider.notifier) : ref.read(goAdhocDestProvider.notifier)).state = Place(
      kind: PlaceKind.other,
      name: hit.name ?? shortAddress(hit.label),
      address: hit.label,
      postal: hit.postal.isEmpty ? null : hit.postal,
      addrLat: hit.lat,
      addrLng: hit.lng,
    );
    _pick(ref, isFrom: isFrom, key: 'adhoc', from: from);
  }

  /// [from] is the start as shown, which may be a saved place standing in for "Here" while the
  /// location is unknown, so a pick works on what the user sees.
  void _pick(WidgetRef ref, {required bool isFrom, required String key, required String from, String fallback = 'here'}) {
    final to = ref.read(goKeyProvider);
    final next = pickTripEnd(
      isFrom: isFrom,
      key: key,
      from: from,
      to: to,
      fallback: fallback,
    );
    ref.read(goPicksProvider.notifier).state++;
    // A pick that swaps the ends carries the searched places along, like the swap button (two
    // searched ends both read "adhoc": a new search there is no swap).
    if (to != null && next.from != next.to && next.from == to && next.to == from) return _swap(ref, from, to);
    // The start is written only when the pick changes it: a start set meanwhile (Here, once the
    // location came in while the address picker was open) is kept.
    if (next.from != from) ref.read(goFromKeyProvider.notifier).state = next.from;
    ref.read(goKeyProvider.notifier).state = next.to;
  }

  void _swap(WidgetRef ref, String from, String to) {
    ref.read(goPicksProvider.notifier).state++;
    final adhocFrom = ref.read(goAdhocFromProvider);
    ref.read(goAdhocFromProvider.notifier).state = ref.read(goAdhocDestProvider);
    ref.read(goAdhocDestProvider.notifier).state = adhocFrom;
    ref.read(goFromKeyProvider.notifier).state = to;
    ref.read(goKeyProvider.notifier).state = from;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final fav = ref.watch(favoritesProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final key = ref.watch(goKeyProvider);
    final here = ref.watch(goFromHereProvider);
    final adhocTo = ref.watch(goAdhocDestProvider);
    final adhocFrom = ref.watch(goAdhocFromProvider);
    var fromKey = ref.watch(goFromKeyProvider);

    // The same choices on both ends: "Here" first (away from home, starting from where you
    // are is the usual case), then saved places. The address search is its own field.
    final options = <(String, IconData, String)>[
      ('here', Icons.my_location, s.hereNow),
      for (final k in [PlaceKind.home, PlaceKind.work, PlaceKind.school])
        if (fav.places[k] != null) (k.name, PlaceSelector.iconOf(k), s.placeLabel(k.name)),
      for (final i in extrasForToday(fav, now)) ('extra:$i', Icons.star_outline, placeTitle(s.placeLabel, fav.extraPlaces[i])),
    ];
    Place? placeFor(String? k, Place? adhoc) {
      if (k == null) return null;
      if (k == 'here') return here;
      if (k == 'adhoc') return adhoc;
      if (k.startsWith('extra:')) {
        final i = int.tryParse(k.substring(6)) ?? -1;
        return i >= 0 && i < fav.extraPlaces.length ? fav.extraPlaces[i] : null;
      }
      return fav.places[PlaceKind.values.asNameMap()[k]];
    }

    final dest = placeFor(key, adhocTo);
    // No location yet (or a saved place since removed): start from the first saved place
    // that is not the destination.
    // The same place on both ends (Here picked as To while the start waited for the location)
    // falls back the same way, so a trip never goes from a place to itself.
    if (placeFor(fromKey, adhocFrom) == null || (fromKey == key && key != 'adhoc')) {
      final saved = options.where((o) => o.$1 != 'here' && o.$1 != key).firstOrNull;
      if (saved != null) fromKey = saved.$1;
    }
    final from = placeFor(fromKey, adhocFrom);
    // Where the start goes when it is picked as the destination before one was set.
    String fallback(String not) => options.where((o) => o.$1 != not).firstOrNull?.$1 ?? 'here';

    Widget end({required bool isFrom}) {
      final selected = isFrom ? fromKey : key;
      final adhoc = isFrom ? adhocFrom : adhocTo;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Label(isFrom ? s.from : s.to),
          PillRow(
            items: options,
            selected: selected ?? '',
            onTap: (k) {
              _pick(ref, isFrom: isFrom, key: k, from: fromKey, fallback: fallback(k));
              if (k == 'here' && here == null) _useHere(context, ref);
            },
          ),
          const SizedBox(height: 6),
          _SearchField(
            label: selected == 'adhoc' ? adhoc?.name : null,
            hint: s.searchAddressHint,
            clearLabel: s.clearSearch,
            onTap: () => _search(context, ref, isFrom: isFrom, from: fromKey),
            onClear: () => isFrom
                ? _pick(ref, isFrom: true, key: fallback(key ?? ''), from: fromKey)
                : ref.read(goKeyProvider.notifier).state = null,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Text(s.goSomewhere, style: t.titleLarge),
          ),
        Panel(
          margin: const EdgeInsets.only(top: 4, bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                end(isFrom: true),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    IconButton.outlined(
                      tooltip: s.swapEnds,
                      icon: const Icon(Icons.swap_vert),
                      onPressed: key == null ? null : () => _swap(ref, fromKey, key),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                end(isFrom: false),
              ],
            ),
          ),
        ),
        if (dest == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(s.goSomewhereHint, style: t.bodyMedium),
          ),
        if (dest != null && from != null)
          TripSection(
            fromKey: fromKey == 'here' || fromKey == 'adhoc' ? null : fromKey,
            from: from,
            fromLabel: fromKey == 'here' ? s.hereNow : null,
            startsHere: fromKey == 'here',
            endsHere: key == 'here',
            to: dest,
            modeKey: plannedModeKey(from, dest),
            modePlace: dest,
          ),
        // A small tip at the end, only until a place of one's own (beyond Home and Work) is saved.
        if (fav.extraPlaces.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: DL.muted(context)),
                const SizedBox(width: 6),
                Expanded(child: Text(s.addPlacesHint, style: t.bodySmall)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The address search on one end of the route card. It looks like a search box and opens the
/// address picker; once a searched place is picked it shows it, selected, with Clear.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.label,
    required this.hint,
    required this.clearLabel,
    required this.onTap,
    required this.onClear,
  });

  /// The searched place on this end when it is the one picked, else null (shows [hint]).
  final String? label;
  final String hint;
  final String clearLabel;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final picked = label != null;
    return Material(
      color: picked ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: picked ? DL.edge(context) : scheme.outline, width: picked ? DL.stroke : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(picked ? Icons.place_outlined : Icons.search,
                    color: picked ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      label ?? hint,
                      style: picked
                          ? t.titleSmall?.copyWith(color: scheme.onPrimaryContainer)
                          : t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                if (picked)
                  IconButton(
                    tooltip: clearLabel,
                    icon: Icon(Icons.close, color: scheme.onPrimaryContainer),
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Trip planner on its own page, so it is not mixed up with the daily trip on Today.
/// Starts from "Here" when location is already allowed.
class TripPlannerPage extends ConsumerStatefulWidget {
  const TripPlannerPage({super.key, this.shared});

  /// A place shared from another app (Google Maps' Share): it becomes the destination.
  final SharedPlace? shared;

  @override
  ConsumerState<TripPlannerPage> createState() => _TripPlannerPageState();
}

class _TripPlannerPageState extends ConsumerState<TripPlannerPage> {
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    if (widget.shared case final shared?) {
      _resolving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _useShared(shared));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // A pick the user makes while the location is coming in wins over what follows here.
      final picksBefore = ref.read(goPicksProvider);
      final toBefore = ref.read(goKeyProvider);
      try {
        final perm = await Geolocator.checkPermission();
        if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (!mounted) return;
        ref.read(goFromHereProvider.notifier).state =
            Place(kind: PlaceKind.other, name: ref.read(stringsProvider).hereNow, addrLat: pos.latitude, addrLng: pos.longitude);
        if (ref.read(goPicksProvider) != picksBefore) return;
        // A Here destination from an earlier visit was where the phone was then, not now: drop it.
        // (Only while it still is: a shared place may have become the destination meanwhile.)
        if (toBefore == 'here' && ref.read(goKeyProvider) == 'here') ref.read(goKeyProvider.notifier).state = null;
        ref.read(goFromKeyProvider.notifier).state = 'here';
      } on Object {
        // No location: the planner starts from a saved place.
      }
    });
  }

  /// Turns the shared place into the trip's destination: a link alone (a shared route) is opened
  /// first to read where it leads; then its point or its postal code looked up on OneMap, else the
  /// address search with a note saying what was missing.
  Future<void> _useShared(SharedPlace shared) async {
    final s = ref.read(stringsProvider);
    var place = shared;
    if (place.needsLink) {
      try {
        final full = await ref.read(mapsLinksProvider).expand(place.link!);
        final fromLink = full == null ? null : mapsLinkPlace(full);
        if (fromLink != null) place = place.merge(fromLink);
      } on Object {
        // Offline or Google unreachable: ask for the postal code below.
      }
    }

    void setDest(String? address, String? postal, double lat, double lng) {
      ref.read(goAdhocDestProvider.notifier).state = Place(
        kind: PlaceKind.other,
        name: place.name ?? (address == null ? s.sharedPlace : shortAddress(address)),
        address: address,
        postal: postal,
        addrLat: lat,
        addrLng: lng,
      );
      ref.read(goKeyProvider.notifier).state = 'adhoc';
    }

    String? note;
    try {
      if (place.postal case final postal?) {
        final hits = parseOneMap(await ref.read(oneMapProvider).search(postal));
        final hit = hits.where((h) => h.postal == postal).firstOrNull ?? hits.firstOrNull;
        if (hit != null) {
          setDest(hit.label, hit.postal.isEmpty ? postal : hit.postal, hit.lat, hit.lng);
          return;
        }
        note = s.sharedNotFound(postal);
      }
      if (place.hasPoint) {
        setDest(null, null, place.lat!, place.lng!);
        return;
      }
    } on Object {
      // Search failed (offline, server asleep): fall back to the point or the search page.
      if (place.hasPoint) {
        setDest(null, null, place.lat!, place.lng!);
        return;
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
    if (!mounted) return;
    final hit = await Navigator.of(context).push<AddressHit>(
      MaterialPageRoute(
        builder: (_) => AddressPickerPage(title: s.searchPlace, note: note ?? s.sharedNoAddress(place.name)),
      ),
    );
    if (hit == null || !mounted) return;
    if (hit.here) {
      ref.read(goFromHereProvider.notifier).state =
          Place(kind: PlaceKind.other, name: s.hereNow, addrLat: hit.lat, addrLng: hit.lng);
      ref.read(goKeyProvider.notifier).state = 'here';
      return;
    }
    setDest(hit.label, hit.postal.isEmpty ? null : hit.postal, hit.lat, hit.lng);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.planTrip)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (_resolving)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Text(s.findingShared), const SizedBox(height: 8), const LinearProgressIndicator()],
              ),
            ),
          const GoSomewhere(showTitle: false),
        ],
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
    if (start == null || ends == null || ref.watch(rideProvider) != null) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
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
