import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'address_picker.dart';
import 'place_sheet.dart';
import 'stop_picker.dart';
import 'theme.dart';
import 'today.dart';
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
  });

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
        body,
      ],
    );
  }
}

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
        ),
    ];
    final mrt = _MrtOption(from: from, to: to);

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
        if (straight < walkInsteadMetres)
          ...buses
        else if (anyDirect)
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
  });

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
                    return EmptyNote(transitResting(DateTime.now()) ? s.busesResting : s.noBusesNow);
                  }
                  if (rides == null) {
                    // Route data not downloaded yet: show every bus, as before.
                    return list.isEmpty
                        ? EmptyNote(s.noBusesNow)
                        : Column(children: [
                            for (final (i, (e, next)) in groupEtas(list).take(8).indexed)
                              BusRow(eta: e, next: next, pulse: i == 0 && e.minutes == 0),
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
                      if (direct.isNotEmpty)
                        BusBoard(
                          arrLabel: s.minutesAway(0),
                          minLabel: s.min,
                          thenLabel: s.thenIn,
                          rows: [
                            for (final (e, next) in direct.take(6))
                              BoardRow(
                                service: e.service,
                                minutes: e.minutes,
                                next: next,
                                note: [
                                  s.rideInfo(
                                    rides[e.service]!.stops,
                                    rides[e.service]!.km,
                                    names[rides[e.service]!.alightAt] ?? rides[e.service]!.alightAt,
                                  ),
                                  s.loadLabel(e.load),
                                ].join(' · '),
                              ),
                          ],
                        ),
                      if (others.isNotEmpty)
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text('${s.otherBuses} (${others.length})', style: t.labelLarge),
                            children: [for (final (e, next) in others.take(10)) BusRow(eta: e, next: next, pulse: false)],
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
  const GoSomewhere({super.key});

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
      name: hit.label,
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
    final starts = <(String, IconData, String)>[
      for (final k in [PlaceKind.home, PlaceKind.work, PlaceKind.school])
        if (fav.places[k] != null && k.name != key) (k.name, PlaceSelector.iconOf(k), s.placeLabel(k.name)),
      ('here', Icons.my_location, s.hereNow),
    ];
    if (!starts.any((o) => o.$1 == fromKey) || (fromKey == 'here' && here == null)) {
      fromKey = starts.first.$1;
    }
    final from = fromKey == 'here' ? here : fav.places[PlaceKind.values.byName(fromKey)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}
