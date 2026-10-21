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
import 'place_sheet.dart';
import 'today.dart' show TaxiSheet, foodApps, openApp;
import 'theme.dart';
import 'widgets.dart';

/// Nearby: what you need right where you are (or at work, school, a saved place):
/// live buses, food (and delivery when it makes sense), parking, taxis and help.
/// Things about home (schools, dengue, weekend) live in the Home tab.
class NearbyPage extends ConsumerStatefulWidget {
  const NearbyPage({super.key});

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

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final fav = ref.watch(favoritesProvider);
    final key = ref.watch(nearbyKeyProvider);
    final adhoc = ref.watch(adhocPlaceProvider);
    final place = NearbyPage.resolve(key, fav, adhoc);
    String label(String k) => s.placeLabel(k);

    // Home has its own tab; it only shows here when another screen sent us there.
    final pills = <(String, IconData, String)>[
      ('here', Icons.my_location, s.hereNow),
      for (final p in fav.places.values)
        if (p.kind != PlaceKind.home || key == 'home') (p.kind.name, PlaceSelector.iconOf(p.kind), label(p.kind.name)),
      for (var i = 0; i < fav.extraPlaces.length; i++)
        ('extra:$i', Icons.star_outline, placeTitle(label, fav.extraPlaces[i])),
      if (adhoc != null && adhoc.address != s.myLocation) ('adhoc', Icons.place, adhoc.name ?? ''),
      ('search', Icons.search, s.searchPlace),
    ];
    final selected = key == 'adhoc'
        ? (adhoc?.address == s.myLocation ? 'here' : 'adhoc')
        : key;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(carparkLiveProvider);
          ref.invalidate(taxiProvider);
          ref.invalidate(rainfallProvider);
          ref.invalidate(busArrivalProvider);
          if (key == 'adhoc' && adhoc?.address == s.myLocation) await _useHere(quiet: true);
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            HeroHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  PageTitle(s.tabNearby,
                      subtitle: place == null ? s.nearbySubtitle : (place.address ?? placeTitle(label, place))),
                  const SizedBox(height: 14),
                  PillRow(
                    items: pills,
                    selected: selected,
                    onTap: (k) {
                      if (k == 'here') {
                        _useHere();
                      } else if (k == 'search') {
                        _search();
                      } else {
                        ref.read(nearbyKeyProvider.notifier).state = k;
                      }
                    },
                  ),
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
                        _BusSection(place: place),
                        _EatSection(place: place),
                        _ParkSection(place: place),
                        _TaxiSection(place: place),
                        if (fav.showPrayer) const _PrayerSection(),
                        _HelpSection(place: place),
                        Text(s.dataSource, style: t.bodySmall, textAlign: TextAlign.center),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens one full list (all hawkers, all car parks...) on its own page.
void _openFull(BuildContext context, String title, Widget body) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body)),
    );

Widget _seeAll(S s, VoidCallback onTap) => TextButton(
      style: TextButton.styleFrom(foregroundColor: DL.tealText),
      onPressed: onTap,
      child: Text(s.seeAll),
    );

// ---------------------------------------------------------------- buses

class _BusSection extends ConsumerWidget {
  const _BusSection({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final stops = ref.watch(busStopsProvider).valueOrNull ?? const <BusStop>[];
    final near = within(stops, place.lat, place.lng, 500, latOf: (b) => b.lat, lngOf: (b) => b.lng, limit: 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.busesNearHere, padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
        if (near.isEmpty)
          Panel(child: EmptyNote(stops.isEmpty ? s.bundlesLoading : s.noStopsNear))
        else
          for (final (b, d) in near) _StopBoard(stop: b, distance: d),
      ],
    );
  }
}

class _StopBoard extends ConsumerWidget {
  const _StopBoard({required this.stop, required this.distance});
  final BusStop stop;
  final double distance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final etas = ref.watch(busArrivalProvider(stop.code));
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stop.name, style: t.titleMedium),
            Text('${stop.code} · ${stop.road} · ${s.metres(distance)}', style: t.bodySmall),
            const SizedBox(height: 6),
            etas.when(
              loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
              error: (_, __) => EmptyNote(s.busesUnavailable),
              data: (list) => list.isEmpty
                  ? EmptyNote(s.noBusesNow)
                  : BusBoard(
                      arrLabel: s.minutesAway(0),
                      minLabel: s.min,
                      thenLabel: s.thenIn,
                      rows: [
                        for (final (e, next) in groupEtas(list).take(5))
                          BoardRow(service: e.service, minutes: e.minutes, next: next, note: s.loadLabel(e.load)),
                      ],
                    ),
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
    final today = dateOnly(ref.watch(clockProvider).valueOrNull ?? DateTime.now());
    final all = ref.watch(hawkersProvider).valueOrNull ?? const <Hawker>[];
    final list = within(all, place.lat, place.lng, 2000, latOf: (h) => h.lat, lngOf: (h) => h.lng, limit: 3);
    final rain = ref.watch(rainfallProvider).valueOrNull;
    final air = airNear(ref.watch(psiProvider).valueOrNull, ref.watch(pm25Provider).valueOrNull, place.lat, place.lng);
    final why = orderInReason(
      rainMm: rain == null ? null : rainfallNear(rain, place.lat, place.lng)?.$2,
      air: air?.level,
      nearestHawkerClosed: list.isNotEmpty && list.first.$1.closureOn(today) != null,
    );
    final halal = fav.showHalal ? ref.watch(halalProvider).valueOrNull ?? const <EPoint>[] : const <EPoint>[];
    final halalList = fav.showHalal ? halalNear(halal, place.lat, place.lng, limit: 3) : const <(EPoint, double)>[];

    Widget orderButtons() => Row(
          children: [
            for (final (i, (name, id, color)) in foodApps.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: Panel(
                  color: why != null ? color : null,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => openApp(id),
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
            ],
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.eat,
            trailing: _seeAll(s, () => _openFull(context, s.hawkers, _HawkerTab(place: place)))),
        if (why != null) AlertBanner(icon: Icons.delivery_dining_outlined, text: s.orderInWhy(why)),
        if (why != null) orderButtons(),
        Panel(
          child: Column(
            children: [
              if (list.isEmpty) EmptyNote(all.isEmpty ? s.bundlesLoading : s.notAvailable),
              for (final (h, d) in list)
                ListTile(
                  leading: Icon(Icons.ramen_dining_outlined,
                      color: h.closureOn(today) != null ? const Color(0xFFB45309) : null),
                  title: Text(h.name),
                  subtitle: Text(
                    h.closureOn(today) != null ? '${s.metres(d)} · ${s.closedNow}' : s.metres(d),
                    style: h.closureOn(today) != null ? t.bodySmall?.copyWith(color: const Color(0xFFB45309)) : null,
                  ),
                  trailing: fav.hawkers.contains(h.id) ? const Icon(Icons.star, color: DL.amber) : null,
                  onTap: () => _openFull(context, s.hawkers, _HawkerTab(place: place)),
                ),
            ],
          ),
        ),
        if (fav.showHalal) ...[
          SectionTitle(s.halalNearby,
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              trailing: _seeAll(s, () => _openFull(context, s.halalTab, _HalalTab(place: place)))),
          Panel(
            child: Column(
              children: [
                if (halalList.isEmpty) EmptyNote(halal.isEmpty ? s.bundlesLoading : s.halalNone),
                for (final (p, d) in halalList)
                  ListTile(
                    leading: const Icon(Icons.restaurant_outlined),
                    title: Text(p.name),
                    subtitle: Text('${s.metres(d)} · ${p.address}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => showPlaceSheet(context,
                        s: s, title: p.name, subtitle: '${p.address}\n${s.halalDisclaimer}', lat: p.lat, lng: p.lng, distance: d),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(s.halalDisclaimer, style: t.bodySmall),
                ),
              ],
            ),
          ),
        ],
        if (why == null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(s.orderIn, style: t.labelLarge),
          ),
          orderButtons(),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(s.orderInNote, style: t.bodySmall),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- park

class _ParkSection extends ConsumerWidget {
  const _ParkSection({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final lots = ref.watch(carparkLiveProvider).valueOrNull ?? const <String, (int, int)>{};
    final all = ref.watch(carparkInfoProvider).valueOrNull ?? const [];
    final list = within(all, place.lat, place.lng, 800, latOf: (c) => c.lat, lngOf: (c) => c.lng, limit: 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.parkNearby,
            trailing: _seeAll(
                s, () => _openFull(context, s.parking, _ParkingTab(lat: place.lat, lng: place.lng)))),
        Panel(
          child: Column(
            children: [
              if (list.isEmpty) EmptyNote(all.isEmpty ? s.bundlesLoading : s.notAvailable),
              for (final (c, d) in list)
                ListTile(
                  leading: const Icon(Icons.local_parking),
                  title: Text(c.address, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${s.metres(d)} · ${c.type.toLowerCase()}'),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(lots[c.id] == null ? '–' : '${lots[c.id]!.$2}',
                          style: t.titleLarge?.copyWith(
                              fontFamily: DL.display, color: (lots[c.id]?.$2 ?? 1) == 0 ? DL.attention : null)),
                      if (lots[c.id] != null) Text(s.freeLots, style: t.labelSmall),
                    ],
                  ),
                  onTap: () => _openFull(context, s.parking, _ParkingTab(lat: place.lat, lng: place.lng)),
                ),
            ],
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
    final taxis = ref.watch(taxiProvider).valueOrNull;
    final n = taxis == null ? null : taxisWithin(taxis, place.lat, place.lng);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.taxiNearby),
        BentoTile(
          icon: Icons.local_taxi_outlined,
          value: n == null ? '–' : '$n',
          caption: '${s.taxisNearby} · 500 m',
          tint: n == 0 ? DL.attention : null,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => TaxiSheet(origin: place),
          ),
        ),
        const SizedBox(height: 16),
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
    final t = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final times = ref.watch(prayerProvider).valueOrNull?.on(dayKey(now));
    final next = times == null ? null : nextPrayerIndex(times, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.prayerTimes,
            trailing: _seeAll(s, () => _openFull(context, s.prayerTab, const _PrayerTab()))),
        Panel(
          child: ListTile(
            leading: const Icon(Icons.mosque_outlined),
            title: Text(times == null || next == null || next >= s.prayerNames.length
                ? s.notAvailable
                : '${s.nextPrayer}: ${s.prayerNames[next]}'),
            trailing: times == null || next == null || next >= times.length
                ? null
                : Text(times[next], style: t.titleLarge?.copyWith(fontFamily: DL.display)),
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
    final em = ref.watch(emergencyProvider).valueOrNull ?? EmergencySet.empty;
    final around = ref.watch(aroundProvider).valueOrNull ?? AroundSet.empty;
    final rows = <(IconData, List<EPoint>)>[
      (Icons.monitor_heart_outlined, em.of(EmergencyKind.aed)),
      (Icons.local_hospital_outlined, em.of(EmergencyKind.ae)),
      (Icons.local_police_outlined, around.of('police')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.helpNearby,
            trailing: _seeAll(s, () => _openFull(context, s.emergency, _EmergencyTab(place: place)))),
        Panel(
          color: DL.stop,
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
                ],
              ),
            ),
          ),
        ),
        Panel(
          child: Column(
            children: [
              for (final (icon, points) in rows)
                for (final (p, d) in nearestPoints(points, place.lat, place.lng, limit: 1))
                  ListTile(
                    leading: Icon(icon),
                    title: Text(p.name),
                    subtitle: Text([s.metres(d), if (p.detail.isNotEmpty) p.detail].join(' · '),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
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

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final place = widget.place;
    return _loadingOr(ref.watch(halalProvider), s, (all) {
      final list = halalNear(all, place.lat, place.lng, query: _query);
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
                      onTap: () => showPlaceSheet(context,
                          s: s, title: p.name, subtitle: '${p.address}\n${s.halalDisclaimer}', lat: p.lat, lng: p.lng, distance: d),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(s.halalSource, style: t.bodySmall),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- hawkers

class _HawkerTab extends ConsumerWidget {
  const _HawkerTab({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final today = dateOnly(ref.watch(clockProvider).valueOrNull ?? DateTime.now());
    return _loadingOr(ref.watch(hawkersProvider), s, (all) {
      final list = within(all, place.lat, place.lng, 3000, latOf: (h) => h.lat, lngOf: (h) => h.lng, limit: 25);
      // Favourites first, then by distance.
      list.sort((a, b) {
        final fa = fav.hawkers.contains(a.$1.id) ? 0 : 1;
        final fb = fav.hawkers.contains(b.$1.id) ? 0 : 1;
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
    final lots = ref.watch(carparkLiveProvider).valueOrNull ?? const <String, (int, int)>{};
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
                onTap: () => showPlaceSheet(
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
                    if (lots[c.id] != null)
                      AlertBanner(
                        icon: Icons.local_parking,
                        tone: lots[c.id]!.$2 == 0 ? AlertTone.warning : AlertTone.info,
                        text: s.lotsFree(lots[c.id]!.$2),
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
                ),
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
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
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
            Panel(child: EmptyNote(s.notAvailable))
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
          Text(s.prayerSource, style: t.bodySmall),
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
    final em = ref.watch(emergencyProvider).valueOrNull ?? EmergencySet.empty;

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
                    Icon(Icons.call, color: color == DL.stop ? Colors.white : DL.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(label,
                          style: t.titleMedium?.copyWith(color: color == DL.stop ? Colors.white : DL.ink)),
                    ),
                    Icon(Icons.chevron_right, color: color == DL.stop ? Colors.white : DL.ink),
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
        callButton('995', s.call995, DL.stop),
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
