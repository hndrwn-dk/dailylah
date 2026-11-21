import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'address_picker.dart';
import 'bus_sheet.dart';
import 'ev.dart';
import 'home.dart' show NearGroup, NearItem;
import 'place_sheet.dart';
import 'today.dart' show TaxiSheet, foodApps, openApp;
import 'theme.dart';
import 'toilets.dart';
import 'widgets.dart';

/// Nearby: what you need right where you are (or at work, school, a saved place):
/// live buses, food (and delivery when it makes sense), parking, taxis and help.
/// Things about home (schools, dengue, weekend) live in the Home tab.
class NearbyPage extends ConsumerStatefulWidget {
  const NearbyPage({super.key, this.controller});

  /// Main list scroll, owned by the shell.
  final ScrollController? controller;

  /// The place the tab is about, from the selected key.
  static Place? resolve(String key, Favorites fav, Place? adhoc) {
    if (key == 'adhoc') return adhoc;
    if (key.startsWith('extra:')) {
      final i = int.tryParse(key.substring(6)) ?? -1;
      return i >= 0 && i < fav.extraPlaces.length ? fav.extraPlaces[i] : null;
    }
    final kind = PlaceKind.values.where((k) => k.name == key).firstOrNull;
    return kind == null ? null : fav.places[kind];
  }

  @override
  ConsumerState<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends ConsumerState<NearbyPage> {
  @override
  void initState() {
    super.initState();
    // Start on "Here" without asking: only when location is already allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || ref.read(nearbyKeyProvider) != 'here') return;
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
          if (mounted) await _useHere(quiet: true);
        }
      } on Object {
        // No location service (tests, emulator): stay on the prompt.
      }
    });
  }

  Future<void> _useHere({bool quiet = false}) async {
    final s = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && !quiet) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (!quiet) messenger.showSnackBar(SnackBar(content: Text(s.locationDenied)));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      ref.read(adhocPlaceProvider.notifier).state = Place(
        kind: PlaceKind.other,
        name: s.hereNow,
        address: s.myLocation,
        addrLat: pos.latitude,
        addrLng: pos.longitude,
      );
      ref.read(nearbyKeyProvider.notifier).state = 'adhoc';
    } on Object {
      if (!quiet) messenger.showSnackBar(SnackBar(content: Text(s.locationUnavailable)));
    }
  }

  Future<void> _search() async {
    final s = ref.read(stringsProvider);
    final hit = await Navigator.of(context).push<AddressHit>(
      MaterialPageRoute(builder: (_) => AddressPickerPage(title: s.searchPlace)),
    );
    if (hit == null) return;
    ref.read(adhocPlaceProvider.notifier).state = Place(
      kind: PlaceKind.other,
      name: hit.label,
      address: hit.label,
      postal: hit.postal.isEmpty ? null : hit.postal,
      addrLat: hit.lat,
      addrLng: hit.lng,
    );
    ref.read(nearbyKeyProvider.notifier).state = 'adhoc';
  }

  /// The list behind the place button: Current location, the saved places and Search.
  Future<void> _pickPlace() async {
    final s = ref.read(stringsProvider);
    final fav = ref.read(favoritesProvider);
    final key = ref.read(nearbyKeyProvider);
    final adhoc = ref.read(adhocPlaceProvider);
    final here = key == 'adhoc' && adhoc?.address == s.myLocation;
    String label(String k) => s.placeLabel(k);
    // Home has its own tab; it only shows here when another screen sent us there.
    final rows = <(String, IconData, String, String?)>[
      ('here', Icons.my_location, s.hereNow, null),
      for (final p in fav.places.values)
        if (p.kind != PlaceKind.home || key == 'home')
          (p.kind.name, PlaceSelector.iconOf(p.kind), label(p.kind.name), p.address),
      for (var i = 0; i < fav.extraPlaces.length; i++)
        ('extra:$i', Icons.star_outline, placeTitle(label, fav.extraPlaces[i]), fav.extraPlaces[i].address),
      if (adhoc != null && adhoc.address != s.myLocation) ('adhoc', Icons.place, adhoc.name ?? '', null),
      ('search', Icons.search, s.nearbySearchPlace, null),
    ];
    final selected = key == 'adhoc' ? (here ? 'here' : 'adhoc') : key;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(s.nearbyWhere, style: Theme.of(ctx).textTheme.titleLarge),
              ),
              for (final (k, icon, name, address) in rows)
                ListTile(
                  leading: Icon(icon),
                  title: Text(name),
                  subtitle: address == null || address == name ? null : Text(address),
                  trailing: k == selected ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(ctx).pop(k),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == 'here') {
      await _useHere();
    } else if (picked == 'search') {
      await _search();
    } else {
      ref.read(nearbyKeyProvider.notifier).state = picked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final key = ref.watch(nearbyKeyProvider);
    final adhoc = ref.watch(adhocPlaceProvider);
    final place = NearbyPage.resolve(key, fav, adhoc);
    String label(String k) => s.placeLabel(k);

    // One section at a time, like Home: chips under the place pills.
    final sections = ['bus', 'eat', 'green', 'park', 'taxi', 'toilet', if (fav.showPrayer) 'prayer', 'help'];
    final picked = ref.watch(nearbySectionProvider);
    final section = sections.contains(picked) ? picked : 'bus';
    final here = key == 'adhoc' && adhoc?.address == s.myLocation;
    // The place is said once, on the control that changes it: "Gym · TAMPINES HUB".
    final title = place == null ? s.nearbyChoosePlace : (here ? s.hereNow : placeTitle(label, place));
    final address = place == null || here || place.address == title ? null : place.address;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(carparkLiveProvider);
          ref.invalidate(parkingLiveProvider);
          ref.invalidate(taxiProvider);
          ref.invalidate(rainfallProvider);
          ref.invalidate(busArrivalProvider);
          if (key == 'adhoc' && adhoc?.address == s.myLocation) await _useHere(quiet: true);
        },
        child: ListView(
          controller: widget.controller,
          padding: EdgeInsets.zero,
          children: [
            HeroHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  PageTitle(s.tabNearby, subtitle: place == null ? s.nearbySubtitle : null),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Flexible(
                        child: _PlaceButton(
                          icon: place == null
                              ? Icons.place_outlined
                              : here
                                  ? Icons.my_location
                                  : _placeIcon(key, place),
                          label: address == null ? title : '$title · $address',
                          picked: place != null,
                          tooltip: s.nearbyChangePlace,
                          onTap: _pickPlace,
                        ),
                      ),
                      const SizedBox(width: 10),
                      StickerIconButton(icon: Icons.my_location, tooltip: s.useMyLocation, onPressed: _useHere),
                    ],
                  ),
                  if (place != null) ...[
                    const SizedBox(height: 14),
                    SectionTiles(
                      items: [for (final k in sections) (k, _sectionIcons[k]!, s.nearbySection(k))],
                      selected: section,
                      danger: const {'help'},
                      onTap: (k) => ref.read(nearbySectionProvider.notifier).state = k,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24 + kNavClearance),
              child: place == null
                  ? Panel(
                      child: EmptyNote(
                        s.nearbyPickPrompt,
                        icon: Icons.near_me_outlined,
                        action: FilledButton.icon(
                          icon: const Icon(Icons.my_location),
                          label: Text(s.useMyLocation),
                          onPressed: _useHere,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        switch (section) {
                          'eat' => _EatSection(place: place),
                          'green' => _GreenSection(place: place),
                          'park' => _ParkSection(place: place),
                          'taxi' => _TaxiSection(place: place),
                          'toilet' => ToiletsNearby(lat: place.lat, lng: place.lng),
                          'prayer' => const _PrayerSection(),
                          'help' => _HelpSection(place: place),
                          _ => _BusSection(place: place),
                        },
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _placeIcon(String key, Place place) => key == 'adhoc'
    ? Icons.place
    : key.startsWith('extra:')
        ? Icons.star_outline
        : PlaceSelector.iconOf(place.kind);

/// The place Nearby is about, on the control that changes it: amber and raised once a place
/// is picked, with a down arrow because it opens the list of places.
class _PlaceButton extends StatelessWidget {
  const _PlaceButton({
    required this.icon,
    required this.label,
    required this.picked,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool picked;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final edge = DL.edge(context);
    final fg = picked ? DL.ink : Theme.of(context).colorScheme.onSurface;
    final r = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3, right: 3),
      child: Tooltip(
        message: tooltip,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: picked ? DL.amber : Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: r,
            border: Border.all(color: edge, width: DL.stroke),
            boxShadow: [BoxShadow(color: edge, offset: const Offset(3, 3))],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: r,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: fg),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg)),
                      ),
                      Icon(Icons.expand_more, color: fg),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _sectionIcons = <String, IconData>{
  'bus': Icons.directions_bus_outlined,
  'eat': Icons.ramen_dining_outlined,
  'green': Icons.park_outlined,
  'park': Icons.local_parking,
  'taxi': Icons.local_taxi_outlined,
  'toilet': Icons.wc,
  'prayer': Icons.mosque_outlined,
  'help': Icons.emergency_outlined,
};

/// Opens one full list (all hawkers, all car parks...) on its own page.
void _openFull(BuildContext context, String title, Widget body) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body)),
    );

Widget _seeAll(S s, VoidCallback onTap) => Builder(
      builder: (context) => TextButton(
        style: TextButton.styleFrom(foregroundColor: DL.goText(context)),
        onPressed: onTap,
        child: Text(s.seeAll),
      ),
    );

// ---------------------------------------------------------------- buses

class _BusSection extends ConsumerWidget {
  const _BusSection({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final stops = ref.watch(busStopsProvider).value ?? const <BusStop>[];
    final near = within(stops, place.lat, place.lng, 500, latOf: (b) => b.lat, lngOf: (b) => b.lng, limit: 3);
    return CardColumns(
      children: [
        // The hint is said once for all the boards under it: beside the heading, or under it
        // when both do not fit on a line (large text).
        FullWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(s.busesNearHere, style: Theme.of(context).textTheme.titleMedium),
                if (near.isNotEmpty) Text(s.tapBusHint, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        if (near.isEmpty)
          Panel(child: EmptyNote(stops.isEmpty ? s.bundlesLoading : s.noStopsNear))
        else
          for (final (b, d) in near) _StopBoard(stop: b, distance: d),
      ],
    );
  }
}

class _StopBoard extends ConsumerStatefulWidget {
  const _StopBoard({required this.stop, required this.distance});
  final BusStop stop;
  final double distance;

  @override
  ConsumerState<_StopBoard> createState() => _StopBoardState();
}

class _StopBoardState extends ConsumerState<_StopBoard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final stop = widget.stop;
    final etas = ref.watch(busArrivalProvider(stop.code));
    final fav = ref.watch(favoritesProvider);
    final routes = ref.watch(busRoutesProvider).value ?? BusRoutes.empty;
    final stops = ref.watch(busStopsProvider).value ?? const <BusStop>[];
    final byCode = ref.watch(busStopsByCodeProvider);
    // Which services here go straight to Home, Work or School: "to Home" on the board.
    final goesTo = servicesToPlaces(routes, stop, {
      for (final k in const [PlaceKind.home, PlaceKind.work, PlaceKind.school])
        if (fav.places[k] case final p?) s.placeLabel(k.name): destinationStops(p, stops),
    });
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stop.name, style: t.titleMedium),
            Text('${stop.code} · ${stop.road} · ${s.metres(widget.distance)}', style: t.bodySmall),
            const SizedBox(height: 6),
            etas.when(
              loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
              error: (_, __) => EmptyNote(s.busesUnavailable),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyNote(transitResting(ref.watch(clockProvider).value ?? DateTime.now())
                      ? s.busesResting
                      : s.noBusesNow);
                }
                final grouped = groupEtas(list);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BusBoard(
                      arrLabel: s.minutesAway(0),
                      minLabel: s.min,
                      thenLabel: s.thenIn,
                      rows: [
                        for (final (e, next) in _all ? grouped : grouped.take(5))
                          BoardRow(
                            service: e.service,
                            minutes: e.minutes,
                            next: next,
                            live: s.busLive(e, busWhere(e, stop.code, routes, byCode)),
                            load: e.load,
                            info: [s.loadLabel(e.load), s.busExtras(e)].where((x) => x.isNotEmpty).join(' · '),
                            note: [if (goesTo[e.service] case final to?) s.toPlaces(to)].join(),
                            onTap: () => showWhereBus(context, stop: stop, service: e.service, minutes: e.minutes),
                          ),
                      ],
                    ),
                    if (grouped.length > 5)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() => _all = !_all),
                          child: Text(_all ? s.showFewer : s.showAllBuses(grouped.length)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- eat

class _EatSection extends ConsumerWidget {
  const _EatSection({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final fav = ref.watch(favoritesProvider);
    final today = dateOnly(ref.watch(clockProvider).value ?? DateTime.now());
    final all = ref.watch(hawkersProvider).value ?? const <Hawker>[];
    final list = within(all, place.lat, place.lng, 2000, latOf: (h) => h.lat, lngOf: (h) => h.lng, limit: 3);
    final rain = ref.watch(rainfallProvider).value;
    final air = airNear(ref.watch(psiProvider).value, ref.watch(pm25Provider).value, place.lat, place.lng);
    final why = orderInReason(
      rainMm: rain == null ? null : rainfallNear(rain, place.lat, place.lng)?.$2,
      air: air?.level,
      nearestHawkerClosed: list.isNotEmpty && list.first.$1.closureOn(today) != null,
    );
    final halal = fav.showHalal ? ref.watch(halalProvider).value ?? const <EPoint>[] : const <EPoint>[];
    final halalList = fav.showHalal ? halalNear(halal, place.lat, place.lng, limit: 3, favs: fav.halalPlaces) : const <(EPoint, double)>[];

    Widget orderButtons() => Row(
          children: [
            for (final (i, (name, id, color)) in foodApps.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: Panel(
                  color: color,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => openApp(id),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            const Icon(Icons.delivery_dining_outlined, size: 20, color: DL.ink),
                            Text(name, style: t.titleSmall?.copyWith(color: DL.ink)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );

    return CardColumns(
      children: [
        FullWidth(
          child: SectionTitle(s.eat,
              trailingAtEnd: true,
              trailing: _seeAll(s, () => _openFull(context, s.hawkers, _HawkerTab(place: place)))),
        ),
        if (fav.learnHabits)
          if (mealNudge(ref.watch(habitsProvider).meals, all, DateTime.now(), place.lat, place.lng) case final n?)
            FullWidth(
              child: AlertBanner(
              icon: Icons.explore_outlined,
              tone: AlertTone.info,
              text: s.mealNudge(n.usual.name, n.times, n.instead.name, s.metres(n.distance)),
            ),
            ),
        // Delivery only when it helps: rain, unhealthy air, or the nearest hawker closed.
        if (why != null) ...[
          FullWidth(child: AlertBanner(icon: Icons.delivery_dining_outlined, text: s.orderInWhy(why))),
          FullWidth(child: orderButtons()),
          FullWidth(
            child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(s.orderInNote, style: t.bodySmall),
          ),
          ),
        ],
        Panel(
          child: Column(
            children: [
              if (list.isEmpty) EmptyNote(all.isEmpty ? s.bundlesLoading : s.notAvailable),
              for (final (h, d) in list)
                PlaceRow(
                  icon: Icons.ramen_dining_outlined,
                  iconColor: h.closureOn(today) != null ? DL.nearText(context) : null,
                  title: h.name,
                  subtitle: h.closureOn(today) != null ? s.closedNow : h.address,
                  subtitleColor: h.closureOn(today) != null ? DL.nearText(context) : null,
                  figure: s.metresParts(d).$1,
                  figureLabel: s.metresParts(d).$2,
                  starred: fav.hawkers.contains(h.id),
                  onTap: () => showPlaceSheet(
                    context,
                    s: s,
                    title: h.name,
                    subtitle: h.address,
                    lat: h.lat,
                    lng: h.lng,
                    distance: d,
                    // "Ate here" lives on the sheet, not on the row: a button at the right
                    // edge of every row was easy to hit by accident while scrolling.
                    extra: [_AteHereButton(id: h.id, name: h.name)],
                  ),
                ),
            ],
          ),
        ),
        if (fav.showHalal) ...[
          SectionTitle(s.halalNearby,
              trailingAtEnd: true,
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              trailing: _seeAll(s, () => _openFull(context, s.halalTab, _HalalTab(place: place)))),
          Panel(
            child: Column(
              children: [
                if (halalList.isEmpty) EmptyNote(halal.isEmpty ? s.bundlesLoading : s.halalNone),
                for (final (p, d) in halalList)
                  PlaceRow(
                    icon: Icons.restaurant_outlined,
                    title: p.name,
                    subtitle: p.address,
                    figure: s.metresParts(d).$1,
                    figureLabel: s.metresParts(d).$2,
                    starred: fav.halalPlaces.contains(halalPlaceId(p)),
                    onTap: () => showPlaceSheet(context,
                        s: s,
                        title: p.name,
                        subtitle: s.halalSheetSubtitle(p.address),
                        lat: p.lat,
                        lng: p.lng,
                        distance: d,
                        extra: [_AteHereButton(id: mealPlaceId(p.lat, p.lng), name: p.name, place: true)]),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(s.halalDisclaimer, style: t.bodySmall),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "Ate here" on a food place's sheet (hawker centre, or with [place] another food place such
/// as a halal restaurant). Hidden when "Learn my habits" is off. Logs the meal with Undo.
/// An optional price sits above it, preselected (`mealPriceToOffer`) with the price of a meal
/// this tap corrects or the last price paid here; one tap on "Ate here" still logs the meal.
class _AteHereButton extends ConsumerStatefulWidget {
  const _AteHereButton({required this.id, required this.name, this.place = false});
  final String id;
  final String name;
  final bool place;

  @override
  ConsumerState<_AteHereButton> createState() => _AteHereButtonState();
}

class _AteHereButtonState extends ConsumerState<_AteHereButton> {
  late int? _price = mealPriceToOffer(ref.read(habitsProvider).meals, widget.id, DateTime.now(),
      name: widget.place ? widget.name : null);

  /// When it was eaten, for a meal logged later; null is now.
  DateTime? _at;

  Future<void> _pickDay(S s) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: dateOnly(_at ?? now),
      firstDate: mealFirstDay(now, now),
      lastDate: dateOnly(now),
      helpText: s.mealDateHelp,
    );
    if (day == null || !mounted) return;
    if (day == dateOnly(now)) return setState(() => _at = null);
    // Another day: the time of day matters too (lunch or dinner), so ask for it.
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at ?? now),
      helpText: s.mealTimeHelp,
    );
    // No time, no change: a guessed time would put the meal at the wrong point of that day.
    if (time == null || !mounted) return;
    final clock = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    setState(() => _at = mealOnDay(clock, day, DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(favoritesProvider.select((f) => f.learnHabits))) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.mealPrice, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          MealPricePicker(s: s, value: _price, onChanged: (v) => setState(() => _price = v)),
          // Forgot to log it? Pick the day it was eaten.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                switch (_at) {
                  null => s.mealWhenNow,
                  final at => s.mealWhenOn('${s.dayShort[at.weekday - 1]} ${shortDate(at)}', clockLabel(at)),
                },
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              TextButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text(s.mealAnotherDay),
                onPressed: () => _pickDay(s),
              ),
            ],
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.ramen_dining_outlined),
            label: Text(s.ateHere),
            onPressed: () async {
              final notifier = ref.read(habitsProvider.notifier);
              final before = ref.read(habitsProvider);
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop();
              await notifier.ateAt(widget.id, _at ?? DateTime.now(),
                  name: widget.place ? widget.name : null, priceCents: _price, backdated: _at != null);
              showActionSnackBar(messenger, s.ateLogged(widget.name),
                  actionLabel: s.undo, onAction: () => notifier.restore(before));
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- green (parks)

/// Parks within 2 km with facility icons and the "good time to go?" line.
class _GreenSection extends ConsumerWidget {
  const _GreenSection({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final pois = ref.watch(poisProvider).value;
    final items = pois == null ? const <NearItem>[] : NearItem.pois(pois.of(PoiKind.park), place, radius: 2000);
    if (items.isEmpty) return Panel(child: EmptyNote(pois == null ? s.bundlesLoading : s.notAvailable));
    return CardColumns(children: [
      Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NearGroup(
        title: s.parks,
        icon: Icons.park_outlined,
        show: 5,
        items: items,
        header: switch (ref.watch(parkTimeProvider((place.lat, place.lng)))) {
          final p? => ParkTimeBanner(time: p, text: s.parkTimeLine(p)),
          null => null,
        },
      ),
    ),
    ]);
  }
}

// ---------------------------------------------------------------- park

class _ParkSection extends ConsumerWidget {
  const _ParkSection({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final lots = ref.watch(carparkLiveProvider).value ?? const <String, (int, int)>{};
    final all = ref.watch(carparkInfoProvider).value ?? const [];
    final list = within(all, place.lat, place.lng, 800, latOf: (c) => c.lat, lngOf: (c) => c.lng, limit: 3);
    // In town there are few HDB car parks: use LTA's live list (malls, URA, HDB) as well.
    final live = parkingNear(ref.watch(parkingLiveProvider).value ?? const <ParkingLot>[],
        place.lat, place.lng, 'C', radius: 800, limit: 3);
    // Name and spot for "I parked here": the nearest car park, else the place itself.
    final (parkName, parkLat, parkLng) = list.isNotEmpty
        ? (list.first.$1.address, list.first.$1.lat, list.first.$1.lng)
        : live.isNotEmpty
            ? (live.first.$1.name, live.first.$1.lat, live.first.$1.lng)
            : (place.address ?? s.hereNow, place.lat, place.lng);
    return CardColumns(
      children: [
        _ParkedCard(
          name: parkName,
          lat: parkLat,
          lng: parkLng,
          hdb: list.isNotEmpty,
          central: list.isNotEmpty && hdbCentralCarparks.contains(list.first.$1.id),
        ),
        SectionTitle(s.parkNearby,
            trailingAtEnd: true,
            trailing: _seeAll(
                s, () => _openFull(context, s.parking, _ParkingTab(lat: place.lat, lng: place.lng)))),
        Panel(
          child: Column(
            children: [
              if (list.isEmpty && live.isEmpty) EmptyNote(all.isEmpty ? s.bundlesLoading : s.notAvailable),
              // A car park with a live count shows it large; without one the row has no figure.
              if (list.isEmpty)
                for (final (p, d) in live)
                  PlaceRow(
                    icon: Icons.local_parking,
                    title: p.name,
                    subtitle: s.metres(d),
                    figure: '${p.available}',
                    figureLabel: s.freeLots,
                    warn: p.available == 0,
                    onTap: () => showPlaceSheet(context,
                        s: s, title: p.name, subtitle: s.lotsFree(p.available), lat: p.lat, lng: p.lng, distance: d),
                  ),
              for (final (c, d) in list)
                PlaceRow(
                  icon: Icons.local_parking,
                  title: c.address,
                  subtitle: '${s.metres(d)} · ${c.type.toLowerCase()}',
                  figure: lots[c.id] == null ? null : '${lots[c.id]!.$2}',
                  figureLabel: s.freeLots,
                  warn: lots[c.id]?.$2 == 0,
                  onTap: () => _showCarpark(context, s, c, d, lots[c.id]?.$2),
                ),
            ],
          ),
        ),
        if (ref.watch(favoritesProvider.select((f) => f.drivesEv)))
          EvChargers(lat: place.lat, lng: place.lng, title: s.evChargers, chevron: true)
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.ev_station_outlined),
              label: Text(s.evAsk),
              onPressed: () => ref.read(favoritesProvider.notifier).update((f) => f.copyWith(evPlug: 'any')),
            ),
          ),
      ],
    );
  }
}

/// "I parked here": the saved spot with how long ago, or a button to save one.
class _ParkedCard extends ConsumerWidget {
  const _ParkedCard({required this.name, required this.lat, required this.lng, this.hdb = false, this.central = false});
  final String name;
  final bool hdb;
  final bool central;
  final double lat;
  final double lng;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final level = TextEditingController();
    final lot = TextEditingController();
    var remind = 0;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.parkedHere, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('${s.parkWhere}: $name', style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 12),
              TextField(controller: level, decoration: InputDecoration(labelText: s.parkLevel)),
              const SizedBox(height: 8),
              TextField(controller: lot, decoration: InputDecoration(labelText: s.parkLot)),
              const SizedBox(height: 14),
              Text(s.parkRemind, style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final h in const [0, 1, 2, 3])
                    ChoiceChip(
                      label: Text(h == 0 ? s.parkNoReminder : s.hoursShort(h)),
                      selected: remind == h,
                      onSelected: (_) => setSheet(() => remind = h),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(s.parkSave),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    await ref.read(habitsProvider.notifier).park(ParkedCar(
          name: name,
          lat: lat,
          lng: lng,
          at: DateTime.now(),
          level: level.text.trim(),
          lot: lot.text.trim(),
          remindMinutes: remind == 0 ? null : remind * 60,
          hdb: hdb,
          central: central,
        ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final p = ref.watch(habitsProvider).parked;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    if (p == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.push_pin_outlined),
          label: Text(s.parkedHere),
          onPressed: () => _save(context, ref),
        ),
      );
    }
    final spot = s.levelLot(p.level, p.lot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.yourCar, padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
        Panel(
          color: parkReminderDue(p, now) ? DL.amber : DL.mint,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    now.difference(p.at).inHours >= 12
                        ? s.parkedSince(p.name, sinceLabel(p.at, now))
                        : s.parkedAgo(p.name, s.durationShort(now.difference(p.at).inMinutes)),
                    style: t.titleMedium?.copyWith(color: DL.ink)),
                if (spot.isNotEmpty) Text(spot, style: t.headlineSmall?.copyWith(color: DL.ink, fontFamily: DL.display)),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: DL.ink),
                      icon: const Icon(Icons.directions_walk),
                      label: Text(s.walkingRoute),
                      onPressed: () => openDirections(p.lat, p.lng, mode: 'walking'),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: DL.ink),
                      icon: const Icon(Icons.check),
                      label: Text(s.parkClear),
                      onPressed: () => ref.read(habitsProvider.notifier).clearParked(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- taxi

class _TaxiSection extends ConsumerWidget {
  const _TaxiSection({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final body = ref.watch(taxiProvider).value;
    final pts = body == null ? const <(double, double)>[] : taxiPoints(body);
    final (_, n500, n1k) = taxiBands(pts, place.lat, place.lng);
    final stand = nearestPoints(ref.watch(taxiStandsProvider).value ?? const <EPoint>[], place.lat, place.lng,
            limit: 1, radius: 1500)
        .firstOrNull;
    final level = taxiEase(n500, n1k);
    return CardColumns(
      children: [
        SectionTitle(s.taxiNearby),
        // The answer first ("Easy to get one"), then what it is based on; the sheet has the rest.
        Panel(
          child: InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => TaxiSheet(origin: place),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: body != null && level < 3 ? DL.amber : DL.mint,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: DL.edge(context), width: 2),
                    ),
                    child: const Icon(Icons.local_taxi_outlined, size: 20, color: DL.ink),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(body == null ? s.taxisNearby : s.taxiEaseTitle(level), style: t.titleMedium),
                        Text(
                          body == null
                              ? '–'
                              : s.taxiNearLine(n500, stand == null ? null : s.metres(stand.$2)),
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  ExcludeSemantics(child: Icon(Icons.chevron_right, color: DL.muted(context))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- prayer (opt-in)

class _PrayerSection extends ConsumerWidget {
  const _PrayerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final prayer = ref.watch(prayerProvider).value;
    final times = prayer?.on(dayKey(now));
    final next = times == null ? null : nextPrayerIndex(times, now);
    // After Isyak, show tomorrow's Subuh instead of nothing.
    final tomorrow = times != null && next == null ? prayer?.on(dayKey(now.add(const Duration(days: 1)))) : null;
    final (String label, String? at) = switch ((times, next, tomorrow)) {
      (final ts?, final i?, _) when i < ts.length && i < s.prayerNames.length => ('${s.nextPrayer}: ${s.prayerNames[i]}', ts[i]),
      (_, _, final tm?) when tm.isNotEmpty => ('${s.prayerTomorrow}: ${s.prayerNames.first}', tm.first),
      (null, _, _) when prayer != null && prayer.days.isNotEmpty => (s.prayerYearPending(now.year), null),
      _ => (s.notAvailable, null),
    };
    return CardColumns(
      children: [
        SectionTitle(s.prayerTimes),
        Panel(
          child: PlaceRow(
            icon: Icons.mosque_outlined,
            title: label,
            figure: at,
            onTap: () => _openFull(context, s.prayerTab, const _PrayerTab()),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- help

class _HelpSection extends ConsumerWidget {
  const _HelpSection({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final em = ref.watch(emergencyProvider).value ?? EmergencySet.empty;
    final around = ref.watch(aroundProvider).value ?? AroundSet.empty;
    final rows = <(IconData, List<EPoint>, int, String)>[
      (Icons.monitor_heart_outlined, em.of(EmergencyKind.aed), 1, s.aedShort),
      (Icons.local_hospital_outlined, em.of(EmergencyKind.ae), 1, s.aeShort),
      (Icons.local_police_outlined, around.of('police'), 1, s.policeShort),
    ];
    // Civil Defence shelters: where to go from here if something happens.
    final shelters = nearestPoints(em.of(EmergencyKind.shelter), place.lat, place.lng, limit: 2, radius: 3000);
    return CardColumns(
      children: [
        SectionTitle(s.helpNearby,
            trailingAtEnd: true,
            trailing: _seeAll(s, () => _openFull(context, s.emergency, _EmergencyTab(place: place)))),
        Panel(
          color: DL.stopDeep,
          child: InkWell(
            onTap: () => launchUrl(Uri(scheme: 'tel', path: '995')),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.call, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.call995,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
        Panel(
          color: DL.amber,
          child: InkWell(
            onTap: () => launchUrl(Uri(scheme: 'tel', path: '999')),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.call, color: DL.ink),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.call999, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: DL.ink))),
                  const Icon(Icons.chevron_right, color: DL.ink),
                ],
              ),
            ),
          ),
        ),
        Panel(
          child: Column(
            children: [
              for (final (icon, points, n, label) in rows)
                for (final (p, d) in nearestPoints(points, place.lat, place.lng, limit: n))
                  PlaceRow(
                    icon: icon,
                    title: '$label: ${p.name}',
                    subtitle: p.detail,
                    figure: s.metresParts(d).$1,
                    figureLabel: s.metresParts(d).$2,
                    onTap: () => showPlaceSheet(
                      context,
                      s: s,
                      title: p.name,
                      subtitle: [p.detail, p.address, p.hours].where((x) => x.isNotEmpty).join(' · '),
                      lat: p.lat,
                      lng: p.lng,
                      distance: d,
                      phone: p.tel,
                    ),
                  ),
            ],
          ),
        ),
        SectionTitle(s.meetingPoints, padding: const EdgeInsets.fromLTRB(4, 4, 4, 10)),
        Panel(
          child: Column(
            children: [
              if (shelters.isEmpty) EmptyNote(em.of(EmergencyKind.shelter).isEmpty ? s.bundlesLoading : s.notAvailable),
              for (final (p, d) in shelters)
                PlaceRow(
                  icon: Icons.shield_outlined,
                  iconColor: DL.stopText(context),
                  title: p.name,
                  subtitle: p.address,
                  figure: s.metresParts(d).$1,
                  figureLabel: s.metresParts(d).$2,
                  onTap: () => showPlaceSheet(
                    context,
                    s: s,
                    title: p.name,
                    subtitle: [p.detail, p.address, s.shelterNote].where((x) => x.isNotEmpty).join('\n'),
                    lat: p.lat,
                    lng: p.lng,
                    distance: d,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _loadingOr<T>(AsyncValue<T> v, S s, Widget Function(T) data) => v.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (_, __) => EmptyNote(s.bundlesLoading, icon: Icons.cloud_download_outlined),
      data: data,
    );

// ---------------------------------------------------------------- halal

class _HalalTab extends ConsumerStatefulWidget {
  const _HalalTab({required this.place});
  final Place place;

  @override
  ConsumerState<_HalalTab> createState() => _HalalTabState();
}

class _HalalTabState extends ConsumerState<_HalalTab> {
  String _query = '';

  /// Favourites as they were when the list opened. Starring sorts only on the next visit,
  /// so a row does not jump away from under the finger.
  Set<String>? _pinned;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final place = widget.place;
    return _loadingOr(ref.watch(halalProvider), s, (all) {
      final favs = ref.watch(favoritesProvider.select((f) => f.halalPlaces));
      final list = halalNear(all, place.lat, place.lng, query: _query, favs: _pinned ??= favs);
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24 + kNavClearance),
        children: [
          AlertBanner(icon: Icons.verified_outlined, text: s.halalDisclaimer, tone: AlertTone.warning),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(hintText: s.halalSearchHint, prefixIcon: const Icon(Icons.search)),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Panel(child: EmptyNote(all.isEmpty ? s.bundlesLoading : s.halalNone))
          else
            Panel(
              child: Column(
                children: [
                  for (final (p, d) in list)
                    ListTile(
                      leading: const Icon(Icons.restaurant_outlined),
                      title: Text(p.name),
                      subtitle: Text('${s.metres(d)} · ${p.address}', maxLines: 3, overflow: TextOverflow.ellipsis),
                      trailing: _HalalStar(id: halalPlaceId(p), on: favs.contains(halalPlaceId(p))),
                      onTap: () => showPlaceSheet(context,
                          s: s,
                          title: p.name,
                          subtitle: s.halalSheetSubtitle(p.address),
                          lat: p.lat,
                          lng: p.lng,
                          distance: d,
                          extra: [_AteHereButton(id: mealPlaceId(p.lat, p.lng), name: p.name, place: true)]),
                    ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// Star to keep a halal place as a favourite (listed first, like favourite hawkers).
class _HalalStar extends ConsumerWidget {
  const _HalalStar({required this.id, required this.on});
  final String id;
  final bool on;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: ref.watch(stringsProvider).favourite,
        icon: Icon(on ? Icons.star : Icons.star_border, color: on ? DL.amber : null),
        onPressed: () => ref.read(favoritesProvider.notifier).toggleHalal(id),
      );
}

// ---------------------------------------------------------------- hawkers

class _HawkerTab extends ConsumerStatefulWidget {
  const _HawkerTab({required this.place});
  final Place place;

  @override
  ConsumerState<_HawkerTab> createState() => _HawkerTabState();
}

class _HawkerTabState extends ConsumerState<_HawkerTab> {
  /// Favourites as they were when the list opened (see [_HalalTabState._pinned]).
  Set<String>? _pinned;

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final pinned = _pinned ??= fav.hawkers;
    final today = dateOnly(ref.watch(clockProvider).value ?? DateTime.now());
    return _loadingOr(ref.watch(hawkersProvider), s, (all) {
      final list = within(all, place.lat, place.lng, 3000, latOf: (h) => h.lat, lngOf: (h) => h.lng, limit: 25);
      // Favourites first (as of opening), then by distance.
      list.sort((a, b) {
        final fa = pinned.contains(a.$1.id) ? 0 : 1;
        final fb = pinned.contains(b.$1.id) ? 0 : 1;
        return fa != fb ? fa - fb : a.$2.compareTo(b.$2);
      });
      if (list.isEmpty) return EmptyNote(all.isEmpty ? s.bundlesLoading : s.notAvailable);
      final t = Theme.of(context).textTheme;
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + kNavClearance),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final (h, d) = list[i];
          final closedToday = h.closureOn(today);
          final next = h.nextClosure(today);
          final isFav = fav.hawkers.contains(h.id);
          final alt = closedToday == null ? const <(Hawker, double)>[] : openAlternatives(all, h, today, limit: 1);
          return Panel(
            child: InkWell(
              onTap: () => showPlaceSheet(
                context,
                s: s,
                title: h.name,
                subtitle: h.address,
                lat: h.lat,
                lng: h.lng,
                distance: d,
                extra: [
                  AlertBanner(
                    icon: closedToday != null ? Icons.event_busy : Icons.event_available,
                    tone: closedToday != null ? AlertTone.warning : AlertTone.info,
                    text: closedToday != null
                        ? [s.closedNow, if (alt.isNotEmpty) s.tryInstead(alt.first.$1.name, s.metres(alt.first.$2))].join('. ')
                        : next == null
                            ? s.noUpcomingClosure
                            : s.closedRange(shortDate(next.from), shortDate(next.to), s.closureReason(next.reason)),
                  ),
                  const SizedBox(height: 12),
                  _AteHereButton(id: h.id, name: h.name),
                ],
              ),
              child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: (closedToday != null ? DL.amber : Theme.of(context).colorScheme.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.ramen_dining_outlined,
                        size: 20, color: closedToday != null ? const Color(0xFFB45309) : Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.name, style: t.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          closedToday != null
                              ? '${s.metres(d)} · ${s.closedNow}'
                              : next == null
                                  ? '${s.metres(d)} · ${s.noUpcomingClosure}'
                                  : '${s.metres(d)} · ${s.closedRange(shortDate(next.from), shortDate(next.to), s.closureReason(next.reason))}',
                          style: closedToday != null ? t.bodySmall?.copyWith(color: const Color(0xFFB45309)) : t.bodySmall,
                        ),
                        if (alt.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(s.tryInstead(alt.first.$1.name, s.metres(alt.first.$2)), style: t.labelMedium),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.favourite,
                    icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? DL.amber : null),
                    onPressed: () => ref.read(favoritesProvider.notifier).toggleHawker(h.id),
                  ),
                ],
              ),
            ),
            ),
          );
        },
      );
    });
  }
}

// ---------------------------------------------------------------- parking

/// The sheet of one HDB car park: type, free and night parking, free lots now, and Save.
void _showCarpark(BuildContext context, S s, Carpark c, double d, int? free) => showPlaceSheet(
      context,
      s: s,
      title: c.address,
      subtitle: [
        c.type.toLowerCase(),
        if (c.freeParking.isNotEmpty && c.freeParking != 'NO') '${s.freeParking}: ${c.freeParking.toLowerCase()}',
        if (c.nightParking.isNotEmpty) '${s.nightParking}: ${c.nightParking.toLowerCase()}',
      ].join(' · '),
      lat: c.lat,
      lng: c.lng,
      distance: d,
      extra: [
        if (free != null)
          AlertBanner(
            icon: Icons.local_parking,
            tone: free == 0 ? AlertTone.warning : AlertTone.info,
            text: s.lotsFree(free),
          ),
        Consumer(
          builder: (context, ref, _) {
            final saved = ref.watch(favoritesProvider).carparks.contains(c.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                label: Text(saved ? s.savedCarpark : s.saveCarpark),
                onPressed: () => ref.read(favoritesProvider.notifier).toggleCarpark(c.id),
              ),
            );
          },
        ),
      ],
    );

/// HDB car parks around a point with live free lots. Also used for any address.
class _ParkingTab extends ConsumerWidget {
  const _ParkingTab({required this.lat, required this.lng, this.showOtherAddress = true});
  final double lat;
  final double lng;
  final bool showOtherAddress;

  Future<void> _other(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final hit = await Navigator.of(context).push<AddressHit>(
      MaterialPageRoute(builder: (_) => AddressPickerPage(title: s.parkingElsewhere)),
    );
    if (hit == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(s.parkingNear(hit.label))),
        body: _ParkingTab(lat: hit.lat, lng: hit.lng, showOtherAddress: false),
      ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final lots = ref.watch(carparkLiveProvider).value ?? const <String, (int, int)>{};
    return _loadingOr(ref.watch(carparkInfoProvider), s, (all) {
      final list = within(all, lat, lng, 800, latOf: (c) => c.lat, lngOf: (c) => c.lng, limit: 20);
      final t = Theme.of(context).textTheme;
      final scheme = Theme.of(context).colorScheme;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + kNavClearance),
        children: [
          if (showOtherAddress)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.travel_explore),
                label: Text(s.parkingElsewhere),
                onPressed: () => _other(context, ref),
              ),
            ),
          Text(s.parkingHint, style: t.bodySmall),
          const SizedBox(height: 10),
          if (list.isEmpty) Panel(child: EmptyNote(all.isEmpty ? s.bundlesLoading : s.notAvailable)),
          for (final (c, d) in list)
            Panel(
              child: InkWell(
                onTap: () => _showCarpark(context, s, c, d, lots[c.id]?.$2),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: fav.carparks.contains(c.id) ? DL.ink : scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('P',
                            style: t.displaySmall?.copyWith(
                                fontSize: 24, color: fav.carparks.contains(c.id) ? Colors.white : null)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.address, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              [
                                s.metres(d),
                                c.type.toLowerCase(),
                                if (c.freeParking.isNotEmpty && c.freeParking != 'NO')
                                  '${s.freeParking}: ${c.freeParking.toLowerCase()}',
                              ].join(' · '),
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            lots[c.id] == null ? '–' : '${lots[c.id]!.$2}',
                            style: t.displaySmall?.copyWith(color: (lots[c.id]?.$2 ?? 1) == 0 ? DL.amber : null),
                          ),
                          if (lots[c.id] != null) Text(s.freeLots, style: t.labelSmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- prayer times

class _PrayerTab extends ConsumerWidget {
  const _PrayerTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    return _loadingOr(ref.watch(prayerProvider), s, (prayer) {
      final times = prayer.on(dayKey(now));
      final next = times == null ? null : nextPrayerIndex(times, now);
      final t = Theme.of(context).textTheme;
      final scheme = Theme.of(context).colorScheme;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + kNavClearance),
        children: [
          SectionTitle(s.prayerTimes, padding: const EdgeInsets.fromLTRB(4, 4, 4, 10)),
          if (times == null)
            Panel(child: EmptyNote(prayer.days.isEmpty ? s.notAvailable : s.prayerYearPending(now.year)))
          else
            Panel(
              child: Column(
                children: [
                  for (var i = 0; i < times.length && i < s.prayerNames.length; i++)
                    Container(
                      color: i == next ? scheme.primary.withValues(alpha: 0.08) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(s.prayerNames[i], style: i == next ? t.titleMedium : t.bodyLarge),
                          ),
                          if (i == next)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(s.nextPrayer, style: t.labelMedium?.copyWith(color: scheme.primary)),
                            ),
                          Text(times[i], style: t.displaySmall?.copyWith(fontSize: 26)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (now.weekday == DateTime.friday) ...[
            const SizedBox(height: 8),
            AlertBanner(icon: Icons.mosque_outlined, text: s.fridayNote, tone: AlertTone.info),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(s.findMosque),
            onPressed: () => launchUrl(Uri.parse('https://www.muis.gov.sg/Mosque/Mosque-Directory'),
                mode: LaunchMode.externalApplication),
          ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- emergency

class _EmergencyTab extends ConsumerWidget {
  const _EmergencyTab({required this.place});
  final Place place;

  static Future<void> _call(String number) => launchUrl(Uri(scheme: 'tel', path: number));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final em = ref.watch(emergencyProvider).value ?? EmergencySet.empty;

    Widget callButton(String number, String label, Color color) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            margin: EdgeInsets.zero,
            color: color,
            child: InkWell(
              onTap: () => _call(number),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.call, color: color == DL.stopDeep ? Colors.white : DL.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(label,
                          style: t.titleMedium?.copyWith(color: color == DL.stopDeep ? Colors.white : DL.ink)),
                    ),
                    Icon(Icons.chevron_right, color: color == DL.stopDeep ? Colors.white : DL.ink),
                  ],
                ),
              ),
            ),
          ),
        );

    Widget group(String title, IconData icon, EmergencyKind kind, {int limit = 3}) {
      final list = nearestPoints(em.of(kind), place.lat, place.lng, limit: limit);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title),
          Panel(
            child: Column(
              children: [
                if (list.isEmpty) EmptyNote(s.bundlesLoading, icon: Icons.cloud_download_outlined),
                for (final (p, d) in list)
                  ListTile(
                    leading: Icon(icon),
                    title: Text(p.name),
                    subtitle: Text(
                      [s.metres(d), if (p.detail.isNotEmpty) p.detail, if (p.address.isNotEmpty) p.address, if (p.hours.isNotEmpty) p.hours]
                          .join(' · '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: p.tel.isEmpty
                        ? const Icon(Icons.chevron_right)
                        : IconButton(tooltip: s.callLabel, icon: const Icon(Icons.call_outlined), onPressed: () => _call(p.tel)),
                    onTap: () => showPlaceSheet(
                      context,
                      s: s,
                      title: p.name,
                      subtitle: [p.detail, p.address, p.hours].where((x) => x.isNotEmpty).join(' · '),
                      lat: p.lat,
                      lng: p.lng,
                      distance: d,
                      phone: p.tel,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 24 + kNavClearance),
      children: [
        callButton('995', s.call995, DL.stopDeep),
        callButton('999', s.call999, DL.amber),
        callButton('1777', s.call1777, DL.card),
        group(s.aeHospitals, Icons.local_hospital_outlined, EmergencyKind.ae),
        group(s.aeds, Icons.monitor_heart_outlined, EmergencyKind.aed),
        group(s.chasClinics, Icons.medical_services_outlined, EmergencyKind.clinic),
        group(s.fireStations, Icons.fire_truck_outlined, EmergencyKind.fire, limit: 2),
        group(s.shelters, Icons.shield_outlined, EmergencyKind.shelter, limit: 2),
        const SizedBox(height: 4),
        Text(s.emergencyNote, style: t.bodySmall),
      ],
    );
  }
}
