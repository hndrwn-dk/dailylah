import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'theme.dart';
import 'widgets.dart';

/// Nearby: hawkers, parking, dengue, weekend ideas and prayer times around a saved place.
class NearbyPage extends ConsumerWidget {
  const NearbyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final selected = ref.watch(nearbyPlaceProvider);
    final place = fav.places[selected] ?? fav.places[PlaceKind.home];

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        body: Column(
          children: [
            HeroHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  PageTitle(s.tabNearby, subtitle: place == null ? null : s.placeLabel(place.kind.name)),
                  const SizedBox(height: 14),
                  PlaceSelector(
                    places: fav.places.keys,
                    selected: selected,
                    labelOf: (k) => s.placeLabel(k.name),
                    onChanged: (k) => ref.read(nearbyPlaceProvider.notifier).state = k,
                    onDark: true,
                  ),
                ],
              ),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: [
                Tab(text: s.hawkers),
                Tab(text: s.parking),
                Tab(text: s.dengue),
                Tab(text: s.weekend),
                Tab(text: s.prayerTab),
              ],
            ),
            Expanded(
              child: place == null
                  ? Center(child: EmptyNote(s.pickHomeFirst))
                  : TabBarView(
                      children: [
                        _HawkerTab(place: place),
                        _ParkingTab(place: place),
                        _DengueTab(place: place),
                        _WeekendTab(place: place),
                        const _PrayerTab(),
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
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
        itemBuilder: (context, i) {
          final (h, d) = list[i];
          final closedToday = h.closureOn(today);
          final next = h.nextClosure(today);
          final isFav = fav.hawkers.contains(h.id);
          return ListTile(
            title: Text(h.name),
            subtitle: Text(
              closedToday != null
                  ? s.closedNow
                  : next == null
                      ? '${s.metres(d)} · ${s.noUpcomingClosure}'
                      : '${s.metres(d)} · ${s.closedRange(shortDate(next.from), shortDate(next.to), s.closureReason(next.reason))}',
              style: closedToday != null ? t.bodySmall?.copyWith(color: const Color(0xFFB45309)) : t.bodySmall,
            ),
            trailing: IconButton(
              tooltip: s.favourite,
              icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? DL.amber : null),
              onPressed: () => ref.read(favoritesProvider.notifier).toggleHawker(h.id),
            ),
          );
        },
      );
    });
  }
}

// ---------------------------------------------------------------- parking

class _ParkingTab extends ConsumerWidget {
  const _ParkingTab({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final lots = ref.watch(carparkLiveProvider).valueOrNull ?? const <String, (int, int)>{};
    return _loadingOr(ref.watch(carparkInfoProvider), s, (all) {
      final list = within(all, place.lat, place.lng, 800, latOf: (c) => c.lat, lngOf: (c) => c.lng, limit: 20);
      final t = Theme.of(context).textTheme;
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Text(s.parkingHint, style: t.bodySmall)),
          if (list.isEmpty) EmptyNote(all.isEmpty ? s.bundlesLoading : s.notAvailable),
          for (final (c, d) in list)
            ListTile(
              leading: Icon(fav.carparks.contains(c.id) ? Icons.bookmark : Icons.bookmark_border),
              title: Text(c.address, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                s.metres(d),
                c.type.toLowerCase(),
                if (c.freeParking.isNotEmpty && c.freeParking != 'NO') '${s.freeParking}: ${c.freeParking.toLowerCase()}',
              ].join(' · ')),
              trailing: Text(
                lots[c.id] == null ? '–' : '${lots[c.id]!.$2}',
                style: t.displaySmall?.copyWith(color: (lots[c.id]?.$2 ?? 1) == 0 ? DL.amber : null),
              ),
              onTap: () => ref.read(favoritesProvider.notifier).toggleCarpark(c.id),
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
        padding: const EdgeInsets.all(16),
        children: [
          if (near.isEmpty)
            Card(child: EmptyNote(s.dengueNone, icon: Icons.check_circle_outline))
          else
            for (final (c, d) in near)
              Card(
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
    final indoor = preferIndoor(here);
    return _loadingOr(ref.watch(poisProvider), s, (pois) {
      final groups = indoor
          ? [(s.libraries, PoiKind.library, Icons.local_library_outlined), (s.communityClubs, PoiKind.cc, Icons.groups_outlined), (s.sports, PoiKind.sport, Icons.pool_outlined)]
          : [(s.parks, PoiKind.park, Icons.park_outlined), (s.sports, PoiKind.sport, Icons.pool_outlined), (s.libraries, PoiKind.library, Icons.local_library_outlined)];
      final t = Theme.of(context).textTheme;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AlertBanner(
            icon: indoor ? Icons.umbrella : Icons.wb_sunny_outlined,
            text: indoor ? s.weekendRainy : s.weekendSunny,
            tone: indoor ? AlertTone.warning : AlertTone.info,
          ),
          for (final (title, kind, icon) in groups) ...[
            SectionTitle(title),
            Card(
              child: Column(
                children: [
                  for (final (p, d) in within(pois.of(kind), place.lat, place.lng, 5000,
                      latOf: (p) => p.lat, lngOf: (p) => p.lng, limit: 3))
                    ListTile(
                      leading: Icon(icon),
                      title: Text(p.name),
                      subtitle: Text([s.metres(d), if (p.detail.isNotEmpty) p.detail].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
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
        padding: const EdgeInsets.all(16),
        children: [
          SectionTitle(s.prayerTimes, padding: const EdgeInsets.fromLTRB(4, 4, 4, 10)),
          if (times == null)
            Card(child: EmptyNote(s.notAvailable))
          else
            Card(
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
