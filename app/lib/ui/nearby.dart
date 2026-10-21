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
import 'theme.dart';
import 'widgets.dart';

/// Nearby: hawkers, parking, dengue, weekend ideas and prayer times around a saved place.
class NearbyPage extends ConsumerWidget {
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
      ref.read(adhocPlaceProvider.notifier).state = Place(
        kind: PlaceKind.other,
        name: s.hereNow,
        address: s.myLocation,
        addrLat: pos.latitude,
        addrLng: pos.longitude,
      );
      ref.read(nearbyKeyProvider.notifier).state = 'adhoc';
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
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final key = ref.watch(nearbyKeyProvider);
    final adhoc = ref.watch(adhocPlaceProvider);
    final place = resolve(key, fav, adhoc) ?? fav.places[PlaceKind.home];
    String label(String k) => s.placeLabel(k);

    final pills = <(String, IconData, String)>[
      for (final p in fav.places.values) (p.kind.name, PlaceSelector.iconOf(p.kind), label(p.kind.name)),
      for (var i = 0; i < fav.extraPlaces.length; i++)
        ('extra:$i', Icons.star_outline, placeTitle(label, fav.extraPlaces[i])),
      if (adhoc != null) ('adhoc', adhoc.address == s.myLocation ? Icons.near_me : Icons.place, adhoc.name ?? ''),
      ('here', Icons.my_location, s.hereNow),
      ('search', Icons.search, s.searchPlace),
    ];

    final prayer = fav.showPrayer;
    final halal = fav.showHalal;
    return DefaultTabController(
      key: ValueKey((prayer, halal)),
      length: 6 + (prayer ? 1 : 0) + (halal ? 1 : 0),
      child: Scaffold(
        body: Column(
          children: [
            HeroHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  PageTitle(s.tabNearby, subtitle: place == null ? null : (place.address ?? placeTitle(label, place))),
                  const SizedBox(height: 14),
                  PillRow(
                    items: pills,
                    selected: place == null ? '' : (key == 'adhoc' || key.startsWith('extra:') ? key : place.kind.name),
                    onTap: (k) {
                      if (k == 'here') {
                        _useHere(context, ref);
                      } else if (k == 'search') {
                        _search(context, ref);
                      } else {
                        ref.read(nearbyKeyProvider.notifier).state = k;
                      }
                    },
                  ),
                ],
              ),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              tabs: [
                Tab(text: s.hawkers),
                if (halal) Tab(text: s.halalTab),
                Tab(text: s.parking),
                Tab(text: s.schools),
                Tab(text: s.dengue),
                Tab(text: s.weekend),
                if (prayer) Tab(text: s.prayerTab),
                Tab(text: s.emergency),
              ],
            ),
            Expanded(
              child: place == null
                  ? Center(child: EmptyNote(s.pickHomeFirst))
                  : TabBarView(
                      children: [
                        _HawkerTab(place: place),
                        if (halal) _HalalTab(place: place),
                        _ParkingTab(lat: place.lat, lng: place.lng),
                        _SchoolsTab(place: place),
                        _DengueTab(place: place),
                        _WeekendTab(place: place),
                        if (prayer) const _PrayerTab(),
                        _EmergencyTab(place: place),
                      ],
                    ),
            ),
          ],
        ),
      ),
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

// ---------------------------------------------------------------- schools

class _SchoolsTab extends ConsumerWidget {
  const _SchoolsTab({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return _loadingOr(ref.watch(poisProvider), s, (pois) {
      final t = Theme.of(context).textTheme;
      Widget group(String title, IconData icon, List<Poi> items) {
        final (near, far) = schoolsByBand(items, place.lat, place.lng);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(title),
            Panel(
              child: Column(
                children: [
                  if (items.isEmpty) EmptyNote(s.bundlesLoading, icon: Icons.cloud_download_outlined),
                  for (final (band, list) in [(s.within1km, near), (s.between1and2km, far)])
                    if (list.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                        child: Row(children: [
                          Text(band, style: t.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                          const Spacer(),
                          Text('${list.length}', style: t.labelMedium),
                        ]),
                      ),
                      for (final (p, d) in list.take(12))
                        ListTile(
                          dense: true,
                          leading: Icon(icon, size: 20),
                          title: Text(p.name),
                          trailing: Text(s.metres(d), style: t.labelLarge),
                          onTap: () => showPlaceSheet(context, s: s, title: p.name, lat: p.lat, lng: p.lng, distance: d),
                        ),
                    ],
                  if (items.isNotEmpty && near.isEmpty && far.isEmpty) EmptyNote(s.notAvailable),
                ],
              ),
            ),
          ],
        );
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24 + kNavClearance),
        children: [
          if (!place.hasAddress) ...[
            const SizedBox(height: 12),
            AlertBanner(icon: Icons.place_outlined, text: s.setAddressForSchools, tone: AlertTone.info),
          ],
          group(s.primarySchools, Icons.school_outlined, pois.of(PoiKind.primarySchool)),
          group(s.secondarySchools, Icons.school_outlined, pois.of(PoiKind.school)),
          group(s.preschools, Icons.child_care_outlined, pois.of(PoiKind.preschool)),
          const SizedBox(height: 10),
          Text(s.p1Note, style: t.bodySmall),
          TextButton.icon(
            style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(s.openSchoolFinder),
            onPressed: () => launchUrl(Uri.parse('https://www.moe.gov.sg/schoolfinder'),
                mode: LaunchMode.externalApplication),
          ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- dengue

class _DengueTab extends ConsumerWidget {
  const _DengueTab({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return _loadingOr(ref.watch(dengueProvider), s, (all) {
      final near = dengueNear(all, place.lat, place.lng, km: 2);
      final t = Theme.of(context).textTheme;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + kNavClearance),
        children: [
          if (near.isEmpty)
            Panel(child: EmptyNote(s.dengueNone, icon: Icons.check_circle_outline))
          else
            for (final (c, d) in near)
              Panel(
                child: ListTile(
                  leading: Icon(Icons.bug_report_outlined, color: d <= 1000 ? DL.amber : null),
                  title: Text(c.locality),
                  subtitle: Text('${s.dengueCases(c.cases)} · ${d == 0 ? s.around : s.metres(d)}'),
                ),
              ),
          const SizedBox(height: 8),
          Text(s.dengueTips, style: t.bodySmall),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- weekend

class _WeekendTab extends ConsumerWidget {
  const _WeekendTab({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final forecast = ref.watch(forecastProvider).valueOrNull;
    final here = forecast == null ? null : forecastNear(forecast, place.lat, place.lng);
    final air = airNear(ref.watch(psiProvider).valueOrNull, ref.watch(pm25Provider).valueOrNull, place.lat, place.lng);
    final hazy = air != null && air.level.index >= AirLevel.unhealthy.index;
    final indoor = preferIndoor(here) || hazy;
    return _loadingOr(ref.watch(poisProvider), s, (pois) {
      final groups = indoor
          ? [(s.libraries, PoiKind.library, Icons.local_library_outlined), (s.communityClubs, PoiKind.cc, Icons.groups_outlined), (s.sports, PoiKind.sport, Icons.pool_outlined)]
          : [(s.parks, PoiKind.park, Icons.park_outlined), (s.sports, PoiKind.sport, Icons.pool_outlined), (s.libraries, PoiKind.library, Icons.local_library_outlined)];
      final t = Theme.of(context).textTheme;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + kNavClearance),
        children: [
          AlertBanner(
            icon: indoor ? Icons.umbrella : Icons.wb_sunny_outlined,
            text: hazy ? s.airAdviceShort(air.level) : indoor ? s.weekendRainy : s.weekendSunny,
            tone: indoor ? AlertTone.warning : AlertTone.info,
          ),
          for (final (title, kind, icon) in groups) ...[
            SectionTitle(title),
            Panel(
              child: Column(
                children: [
                  for (final (p, d) in within(pois.of(kind), place.lat, place.lng, 5000,
                      latOf: (p) => p.lat, lngOf: (p) => p.lng, limit: 3))
                    ListTile(
                      leading: Icon(icon),
                      title: Text(p.name),
                      subtitle: Text([s.metres(d), if (p.detail.isNotEmpty) p.detail].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => showPlaceSheet(context,
                          s: s, title: p.name, subtitle: p.detail, lat: p.lat, lng: p.lng, distance: d),
                    ),
                  if (pois.of(kind).isEmpty) EmptyNote(s.notAvailable),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(s.dataSource, style: t.bodySmall),
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
