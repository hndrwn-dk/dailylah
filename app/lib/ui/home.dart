import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'homes.dart';
import 'place_sheet.dart';
import 'setup.dart';
import 'theme.dart';
import 'widgets.dart';

/// Home tab: everything about and around the user's own home, one section at a time
/// (chips under the hero). Other blocks are one tap away (search).
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const sections = [
    'home', 'emergency', 'shelter', 'works', 'schools', 'health', 'community', 'weekend', 'recycling', 'food', 'parking', 'blocks',
  ];
  static const _icons = {
    'home': Icons.home_outlined,
    'emergency': Icons.emergency_outlined,
    'shelter': Icons.shield_outlined,
    'works': Icons.construction_outlined,
    'schools': Icons.school_outlined,
    'health': Icons.health_and_safety_outlined,
    'community': Icons.groups_outlined,
    'weekend': Icons.park_outlined,
    'recycling': Icons.recycling,
    'food': Icons.restaurant_outlined,
    'parking': Icons.local_parking,
    'blocks': Icons.apartment_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final fav = ref.watch(favoritesProvider);
    final home = fav.places[PlaceKind.home];
    final blocks = ref.watch(hdbBlocksProvider).valueOrNull;
    final block = home == null || blocks == null ? null : homeBlock(blocks, home);
    final private = home == null || block != null
        ? null
        : privateProjectFor(ref.watch(privateHomesProvider).valueOrNull ?? const [], home);
    final section = home == null ? 'blocks' : ref.watch(homeSectionProvider);

    Widget hero() {
      if (block != null) {
        // The block number, big, like it is painted on the block itself.
        return Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            PaintedBlockNumber(block.block),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titleCase(block.street), style: t.titleLarge),
                  Text(titleCase(block.town), style: t.bodyMedium),
                ],
              ),
            ),
          ],
        );
      }
      if (private != null) {
        return PageTitle(private.name, subtitle: private.street);
      }
      return PageTitle(s.homeTitle, subtitle: home == null ? s.setHomeFirst : home.label);
    }

    final body = home == null
        ? <Widget>[
            Panel(
              child: EmptyNote(
                s.setHomeFirst,
                icon: Icons.home_outlined,
                action: FilledButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SetupPage())),
                  child: Text(s.setHome),
                ),
              ),
            ),
            const _WatchedAndAgent(),
          ]
        : switch (section) {
            'works' => [_Works(home: home)],
            'schools' => [_Schools(home: home)],
            'emergency' => [_Emergency(home: home)],
            'shelter' => [_Shelters(home: home)],
            'health' => [_Dengue(home: home), _Health(home: home)],
            'community' => [_Community(home: home)],
            'weekend' => [_Weekend(home: home)],
            'recycling' => [_Recycling(home: home)],
            'food' => [_Food(home: home)],
            'parking' => [_Parking(home: home)],
            'blocks' => [const _WatchedAndAgent()],
            _ => [
                if (block != null) _MyBlock(block: block) else if (private != null) _PrivateCard(project: private)
                else Panel(child: EmptyNote(s.notHdb, icon: Icons.home_work_outlined)),
                _Glance(home: home),
              ],
          };

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: kNavClearance),
        children: [
          HeroHeader(
            accent: const Color(0xFF2E9E7E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Padding(padding: const EdgeInsets.only(top: 8), child: hero())),
                    const SizedBox(width: 8),
                    StickerIconButton(
                      tooltip: s.findBlock,
                      icon: Icons.search,
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockSearchPage())),
                    ),
                  ],
                ),
                if (home != null) ...[
                  const SizedBox(height: 16),
                  // One section at a time instead of one very long page.
                  PillRow(
                    items: [for (final k in sections) (k, _icons[k]!, s.homeSection(k))],
                    selected: section,
                    danger: const {'emergency', 'shelter'},
                    onTap: (k) => ref.read(homeSectionProvider.notifier).state = k,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...body,
                const SizedBox(height: 12),
                Text(s.homeDataNote, style: t.bodySmall),
                if (private != null && section == 'home') Text(s.uraSource, style: t.bodySmall),
                if (section == 'home' || section == 'blocks') ...[
                  const SizedBox(height: 4),
                  Text(s.homesDisclaimer, style: t.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A few facts at a glance on the "My home" section; each opens its section.
class _Glance extends ConsumerWidget {
  const _Glance({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final around = ref.watch(aroundProvider).valueOrNull ?? AroundSet.empty;
    final works = projectsNear(around.projects, home.lat, home.lng, now: now);
    final mine = upgradingAtHome(works);
    final dengue = ref.watch(dengueProvider).valueOrNull;
    final near = dengue == null ? const <(DengueCluster, double)>[] : dengueNear(dengue, home.lat, home.lng, km: 1);
    final pois = ref.watch(poisProvider).valueOrNull;
    final school = pois == null
        ? null
        : nearest(pois.of(PoiKind.primarySchool), home.lat, home.lng, latOf: (p) => p.lat, lngOf: (p) => p.lng);
    final em = ref.watch(emergencyProvider).valueOrNull ?? EmergencySet.empty;
    final aed = nearestPoints(em.of(EmergencyKind.aed), home.lat, home.lng, limit: 1);
    final hawkers = ref.watch(hawkersProvider).valueOrNull ?? const <Hawker>[];
    final hawker = nearest(hawkers, home.lat, home.lng, latOf: (h) => h.lat, lngOf: (h) => h.lng);
    void go(String k) => ref.read(homeSectionProvider.notifier).state = k;

    Widget tile(String key, IconData icon, String value, String caption, {bool warn = false}) => Expanded(
          child: BentoTile(icon: icon, value: value, caption: caption, tint: warn ? DL.attention : null, onTap: () => go(key)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        for (final p in mine)
          AlertBanner(
            icon: Icons.elevator_outlined,
            text: s.atYourBlock([s.projectKind(p.kind), if (p.status.isNotEmpty) p.status].join(' · ')),
          ),
        for (final (c, d) in near.take(1))
          AlertBanner(icon: Icons.bug_report_outlined, text: '${s.dengueHeading}: ${c.locality} · ${s.metres(d)}'),
        // Same height side by side, like the weather tiles on Today.
        IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tile('works', Icons.construction_outlined, '${works.length}', s.worksNearby(works.length)),
            const SizedBox(width: 12),
            tile('schools', Icons.school_outlined, school == null ? '–' : s.metres(school.$2),
                school == null ? s.nearestPrimary : '${s.nearestPrimary} · ${school.$1.name}'),
          ],
          ),
        ),
        const SizedBox(height: 12),
        // Same height side by side, like the weather tiles on Today.
        IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tile('emergency', Icons.monitor_heart_outlined, aed.isEmpty ? '–' : s.metres(aed.first.$2), s.nearestAed),
            const SizedBox(width: 12),
            tile('food', Icons.storefront_outlined, hawker == null ? '–' : s.metres(hawker.$2),
                hawker == null ? s.nearestHawkerShort : '${s.nearestHawkerShort} · ${shortPlaceName(hawker.$1.name)}'),
          ],
          ),
        ),
      ],
    );
  }
}

/// Private home: URA prices and rents for the project at the saved address.
class _PrivateCard extends ConsumerWidget {
  const _PrivateCard({required this.project});
  final PrivateProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final p = project;
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (p.type.isNotEmpty) _Chip(Icons.apartment, p.type),
                if (p.tenure.isNotEmpty) _Chip(Icons.hourglass_bottom, p.tenure),
              ],
            ),
            if (p.psf != null) ...[
              const SizedBox(height: 14),
              Text(sgd(p.psf!), style: t.displaySmall?.copyWith(fontSize: 28)),
              Text('${s.psfLabel} · ${s.salesCount(p.sales, p.salesMonths)}', style: t.bodySmall),
            ],
            if (p.recent.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(s.latestSales, style: t.titleSmall),
              for (final (month, price, sqm, floor) in p.recent)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(s.saleLine(month, sgd(price), sqm, floor), style: t.bodyMedium),
                ),
            ],
            if (p.rent.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(s.rentByBedrooms, style: t.titleSmall),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  for (final e in p.rent.entries)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sgd(e.value), style: t.displaySmall?.copyWith(fontSize: 24)),
                        Text(s.bedrooms(e.key), style: t.bodySmall),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- building blocks

/// ActiveSG (Sport Singapore): bookings, gym and pool entry. No per-centre deep link exists.
const activeSgUrl = 'https://activesg.gov.sg';

/// One place in a list: name, a line of detail and the distance from home.
class NearItem {
  const NearItem({
    required this.name,
    required this.lat,
    required this.lng,
    required this.distance,
    this.detail = '',
    this.tel = '',
    this.big,
    this.bigLabel = '',
    this.bigWarn = false,
    this.linkUrl,
    this.linkLabel = '',
  });

  /// Optional button on the place sheet, e.g. booking on ActiveSG.
  final String? linkUrl;
  final String linkLabel;

  /// A number to show large on the right (e.g. free car park lots), with a small label.
  final String? big;
  final String bigLabel;
  final bool bigWarn;
  final String name;
  final String detail;
  final double lat;
  final double lng;
  final double distance;
  final String tel;

  static List<NearItem> points(List<EPoint> all, Place home, {double radius = 3000, int limit = 15}) => [
        for (final (p, d) in nearestPoints(all, home.lat, home.lng, limit: limit, radius: radius))
          NearItem(
            name: p.name,
            detail: [p.detail, p.address, p.hours].where((x) => x.isNotEmpty).join(' · '),
            lat: p.lat,
            lng: p.lng,
            distance: d,
            tel: p.tel,
          ),
      ];

  static List<NearItem> pois(List<Poi> all, Place home, {double radius = 3000, int limit = 15}) => [
        for (final (p, d) in dedupePlaces(
            within(all, home.lat, home.lng, radius, latOf: (p) => p.lat, lngOf: (p) => p.lng, limit: limit * 2),
            nameOf: (p) => p.name, latOf: (p) => p.lat, lngOf: (p) => p.lng).take(limit))
          NearItem(name: p.name, detail: p.detail, lat: p.lat, lng: p.lng, distance: d),
      ];
}

/// A titled list that shows the nearest few and expands to the rest.
class NearGroup extends ConsumerStatefulWidget {
  const NearGroup({super.key, required this.title, required this.icon, required this.items, this.show = 3});
  final String title;
  final IconData icon;
  final List<NearItem> items;
  final int show;

  @override
  ConsumerState<NearGroup> createState() => _NearGroupState();
}

class _NearGroupState extends ConsumerState<NearGroup> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final shown = _all ? items : items.take(widget.show).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(widget.title, style: t.titleSmall),
        ),
        Panel(
          child: Column(
            children: [
              for (final it in shown)
                ListTile(
                  leading: Icon(widget.icon),
                  title: Text(it.name),
                  subtitle: Text(
                    [s.metres(it.distance), if (it.detail.isNotEmpty) it.detail].join(' · '),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: it.big != null
                      ? _BigNumber(value: it.big!, label: it.bigLabel, warn: it.bigWarn)
                      : it.tel.isEmpty
                      ? null
                      : IconButton(
                          tooltip: s.callLabel,
                          icon: const Icon(Icons.call_outlined),
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: it.tel)),
                        ),
                  onTap: () => showPlaceSheet(
                    context,
                    s: s,
                    title: it.name,
                    subtitle: it.detail,
                    lat: it.lat,
                    lng: it.lng,
                    distance: it.distance,
                    phone: it.tel,
                    extra: [
                      if (it.linkUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            icon: const Icon(Icons.open_in_new),
                            label: Text(it.linkLabel),
                            onPressed: () => launchUrl(Uri.parse(it.linkUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                    ],
                  ),
                ),
              if (items.length > widget.show)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _all = !_all),
                    child: Text(_all ? s.showLess : s.showAll(items.length)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Large figure at the end of a row, amber when it needs a look (e.g. 0 lots free).
class _BigNumber extends StatelessWidget {
  const _BigNumber({required this.value, required this.label, this.warn = false});
  final String value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: warn
          ? BoxDecoration(
              color: DL.attention,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DL.edge(context), width: 2),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value, style: t.displaySmall?.copyWith(fontSize: 26, height: 1, color: warn ? DL.ink : null)),
          Text(label, style: t.labelSmall?.copyWith(color: warn ? DL.ink : null)),
        ],
      ),
    );
  }
}

/// Section heading for the Home page.
class _Heading extends StatelessWidget {
  const _Heading(this.text, this.icon);
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
          ],
        ),
      );
}

// ---------------------------------------------------------------- my block

class _MyBlock extends ConsumerWidget {
  const _MyBlock({required this.block});
  final HdbBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final resale = ref.watch(resaleProvider).valueOrNull;
    final rent = ref.watch(rentProvider).valueOrNull;
    final stats = [...?resale?.blocks[block.key]]..sort((a, b) => b.count.compareTo(a.count));
    final rents = rent?.towns[block.town] ?? const <String, int>{};
    final topRent = rentFor(rents, stats.isEmpty ? null : stats.first.flatType);
    final watching = ref.watch(favoritesProvider).watchedBlocks.containsKey(block.key);
    final year = DateTime.now().year;

    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(Icons.calendar_today_outlined, s.builtIn(block.yearCompleted)),
                _Chip(Icons.hourglass_bottom, s.leaseLeft(block.leaseLeft(year))),
                if (block.floors > 0) _Chip(Icons.apartment, s.storeys(block.floors)),
              ],
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  for (final st in stats.take(2))
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sgd(st.median, compact: true), style: t.displaySmall?.copyWith(fontSize: 28)),
                        Text(s.medianFor(st.flatType), style: t.bodySmall),
                      ],
                    ),
                ],
              ),
            ],
            if (topRent != null) ...[
              const SizedBox(height: 8),
              Text(s.rentMedian(topRent.$1, sgd(topRent.$2)), style: t.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.bar_chart),
                  label: Text(s.blockDetails),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlockPage(block: block))),
                ),
                OutlinedButton.icon(
                  icon: Icon(watching ? Icons.visibility : Icons.visibility_outlined),
                  label: Text(watching ? s.watchingBlock : s.watchBlock),
                  onPressed: () => ref
                      .read(favoritesProvider.notifier)
                      .toggleWatch(block.key, resale?.countFor(block.key) ?? 0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: DL.mint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DL.edge(context), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: DL.ink),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: DL.ink))),
          ],
        ),
      );
}

// ---------------------------------------------------------------- upgrading and works

class _Works extends ConsumerWidget {
  const _Works({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final around = ref.watch(aroundProvider).valueOrNull ?? AroundSet.empty;
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final near = projectsNear(around.projects, home.lat, home.lng, now: now);
    final mine = upgradingAtHome(near);

    String line(Project p) => [
          s.projectKind(p.kind),
          if (p.status.isNotEmpty) p.status,
          if (s.projectWhen(p.from, p.to).isNotEmpty) s.projectWhen(p.from, p.to),
        ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.worksTitle, Icons.construction_outlined),
        for (final p in mine)
          AlertBanner(icon: Icons.elevator_outlined, text: s.atYourBlock(line(p))),
        if (near.isEmpty)
          Panel(child: EmptyNote(around.projects.isEmpty ? s.bundlesLoading : s.worksNone, icon: Icons.check_circle_outline))
        else
          NearGroup(
            title: s.within1km,
            icon: Icons.construction_outlined,
            items: [
              for (final (p, d) in near)
                NearItem(
                  name: p.name,
                  detail: [line(p), if (p.by.isNotEmpty) p.by].join(' · '),
                  lat: p.lat,
                  lng: p.lng,
                  distance: d,
                  tel: RegExp(r'^[0-9 +-]{8,}$').hasMatch(p.contact) ? p.contact.replaceAll(' ', '') : '',
                ),
            ],
          ),
        Text(s.hipNote, style: t.bodySmall),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(s.checkHip),
            onPressed: () => launchUrl(Uri.parse('https://www.hdb.gov.sg/residential/living-in-an-hdb-flat/sers-and-upgrading-programmes/upgrading-programmes/types/home-improvement-programme-hip'),
                mode: LaunchMode.externalApplication),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- dengue

class _Dengue extends ConsumerWidget {
  const _Dengue({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final all = ref.watch(dengueProvider).valueOrNull;
    final near = all == null ? const <(DengueCluster, double)>[] : dengueNear(all, home.lat, home.lng, km: 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.dengueHeading, Icons.bug_report_outlined),
        if (near.isEmpty)
          Panel(child: EmptyNote(all == null ? s.loading : s.dengueNone, icon: Icons.check_circle_outline))
        else
          for (final (c, d) in near)
            Panel(
              color: d <= 1000 ? DL.amber : null,
              child: ListTile(
                leading: const Icon(Icons.bug_report_outlined, color: DL.ink),
                title: Text(c.locality, style: d <= 1000 ? const TextStyle(color: DL.ink) : null),
                subtitle: Text('${s.dengueCases(c.cases)} · ${d == 0 ? s.around : s.metres(d)}',
                    style: d <= 1000 ? const TextStyle(color: DL.ink) : null),
              ),
            ),
        if (near.isNotEmpty) Text(s.dengueTips, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- schools

class _Schools extends ConsumerWidget {
  const _Schools({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final pois = ref.watch(poisProvider).valueOrNull;
    if (pois == null) return const SizedBox.shrink();
    final (near, far) = schoolsByBand(pois.of(PoiKind.primarySchool), home.lat, home.lng);
    NearItem item((Poi, double) x) => NearItem(name: x.$1.name, lat: x.$1.lat, lng: x.$1.lng, distance: x.$2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.schoolsTitle, Icons.school_outlined),
        NearGroup(title: '${s.primarySchools} · ${s.within1km}', icon: Icons.school_outlined, items: [for (final x in near) item(x)]),
        NearGroup(title: '${s.primarySchools} · ${s.between1and2km}', icon: Icons.school_outlined, items: [for (final x in far) item(x)]),
        NearGroup(title: s.secondarySchools, icon: Icons.school_outlined, items: NearItem.pois(pois.of(PoiKind.school), home)),
        NearGroup(title: s.preschools, icon: Icons.child_care_outlined, items: NearItem.pois(pois.of(PoiKind.preschool), home, radius: 1000)),
        Text(s.p1Note, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- health and safety

class _Health extends ConsumerWidget {
  const _Health({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final em = ref.watch(emergencyProvider).valueOrNull ?? EmergencySet.empty;
    final around = ref.watch(aroundProvider).valueOrNull ?? AroundSet.empty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.healthTitle, Icons.health_and_safety_outlined),
        NearGroup(title: s.chasClinics, icon: Icons.medical_services_outlined, items: NearItem.points(em.of(EmergencyKind.clinic), home, radius: 2000)),
        NearGroup(title: s.pharmacies, icon: Icons.local_pharmacy_outlined, items: NearItem.points(around.of('pharmacy'), home)),
      ],
    );
  }
}

/// Emergency meeting points: Civil Defence public shelters, nearest first, on their own so
/// they are one tap away when something happens.
class _Shelters extends ConsumerWidget {
  const _Shelters({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final em = ref.watch(emergencyProvider).valueOrNull ?? EmergencySet.empty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.meetingPoints, Icons.shield_outlined),
        NearGroup(
          title: s.within2km,
          icon: Icons.shield_outlined,
          show: 5,
          items: NearItem.points(em.of(EmergencyKind.shelter), home, radius: 2000),
        ),
        Text(s.shelterNote, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Emergency: call buttons first, then A&E, AEDs, police and SCDF fire stations.
class _Emergency extends ConsumerWidget {
  const _Emergency({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final em = ref.watch(emergencyProvider).valueOrNull ?? EmergencySet.empty;
    final around = ref.watch(aroundProvider).valueOrNull ?? AroundSet.empty;

    Widget call(String number, String label, Color bg, Color fg) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            margin: EdgeInsets.zero,
            color: bg,
            child: InkWell(
              onTap: () => launchUrl(Uri(scheme: 'tel', path: number)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.call, color: fg),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: t.titleMedium?.copyWith(color: fg))),
                    Icon(Icons.chevron_right, color: fg),
                  ],
                ),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.emergency, Icons.emergency_outlined),
        call('995', s.call995, DL.stop, Colors.white),
        call('999', s.call999, DL.stop, Colors.white),
        call('1777', s.call1777, DL.card, DL.ink),
        NearGroup(title: s.aeHospitals, icon: Icons.local_hospital_outlined, items: NearItem.points(em.of(EmergencyKind.ae), home, radius: 20000, limit: 3)),
        NearGroup(title: s.aeds, icon: Icons.monitor_heart_outlined, items: NearItem.points(em.of(EmergencyKind.aed), home, radius: 1000)),
        NearGroup(title: s.police, icon: Icons.local_police_outlined, items: NearItem.points(around.of('police'), home, radius: 5000, limit: 5)),
        NearGroup(title: s.scdfFireStations, icon: Icons.fire_truck_outlined, items: NearItem.points(em.of(EmergencyKind.fire), home, radius: 8000, limit: 2)),
        Text(s.emergencyNote, style: t.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- community

class _Community extends ConsumerWidget {
  const _Community({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final around = ref.watch(aroundProvider).valueOrNull ?? AroundSet.empty;
    final pois = ref.watch(poisProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.communityTitle, Icons.groups_outlined),
        if (pois != null) ...[
          NearGroup(title: s.communityClubs, icon: Icons.groups_outlined, items: NearItem.pois(pois.of(PoiKind.cc), home)),
          NearGroup(title: s.libraries, icon: Icons.local_library_outlined, items: NearItem.pois(pois.of(PoiKind.library), home, radius: 5000)),
        ],
        NearGroup(title: s.residentsCommittees, icon: Icons.diversity_3_outlined, items: NearItem.points(around.of('rc'), home, radius: 1000)),
        NearGroup(title: s.mpOffices, icon: Icons.how_to_vote_outlined, items: NearItem.points(around.of('mp'), home, limit: 3)),
        NearGroup(title: s.hdbBranch, icon: Icons.apartment_outlined, items: NearItem.points(around.of('hdbbranch'), home, radius: 10000, limit: 1)),
        NearGroup(title: s.eldercare, icon: Icons.elderly_outlined, items: NearItem.points(around.of('eldercare'), home)),
        NearGroup(title: s.studentCare, icon: Icons.backpack_outlined, items: NearItem.points(around.of('studentcare'), home, radius: 2000)),
        NearGroup(title: s.familyServices, icon: Icons.family_restroom_outlined, items: NearItem.points(around.of('family'), home, radius: 5000)),
      ],
    );
  }
}

// ---------------------------------------------------------------- recycling

class _Recycling extends ConsumerWidget {
  const _Recycling({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final around = ref.watch(aroundProvider).valueOrNull ?? AroundSet.empty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.recyclingTitle, Icons.recycling),
        NearGroup(title: s.ewastePoints, icon: Icons.battery_charging_full_outlined, items: NearItem.points(around.of('ewaste'), home, radius: 2000)),
        NearGroup(title: s.reuseChannels, icon: Icons.volunteer_activism_outlined, items: NearItem.points(around.of('reuse'), home, radius: 5000)),
        Text(s.recyclingNote, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- weekend

class _Weekend extends ConsumerWidget {
  const _Weekend({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final around = ref.watch(aroundProvider).valueOrNull ?? AroundSet.empty;
    final pois = ref.watch(poisProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.weekendTitle, Icons.park_outlined),
        if (pois != null) NearGroup(title: s.parks, icon: Icons.park_outlined, items: NearItem.pois(pois.of(PoiKind.park), home, radius: 2000)),
        NearGroup(title: s.attractions, icon: Icons.attractions_outlined, items: NearItem.points(around.of('attraction'), home, radius: 6000)),
        NearGroup(title: s.museums, icon: Icons.museum_outlined, items: NearItem.points(around.of('museum'), home, radius: 10000, limit: 3)),
        NearGroup(
          title: s.activeSgCentres,
          icon: Icons.sports_tennis_outlined,
          items: [
            for (final it in NearItem.points(around.of('activesg'), home, radius: 8000, limit: 5))
              NearItem(
                name: it.name,
                detail: it.detail,
                lat: it.lat,
                lng: it.lng,
                distance: it.distance,
                linkUrl: activeSgUrl,
                linkLabel: s.bookOnActiveSg,
              ),
          ],
        ),
        if (pois != null) NearGroup(title: s.sports, icon: Icons.pool_outlined, items: NearItem.pois(pois.of(PoiKind.sport), home, radius: 3000)),
        NearGroup(title: s.bbqPits, icon: Icons.outdoor_grill_outlined, items: NearItem.points(around.of('bbq'), home, radius: 3000)),
        NearGroup(title: s.pcnAccess, icon: Icons.directions_bike_outlined, items: NearItem.points(around.of('pcn'), home, radius: 2000)),
      ],
    );
  }
}

// ---------------------------------------------------------------- parking and food

class _Parking extends ConsumerWidget {
  const _Parking({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final carparks = ref.watch(carparkInfoProvider).valueOrNull ?? const <Carpark>[];
    final lots = ref.watch(carparkLiveProvider).valueOrNull ?? const <String, (int, int)>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.parkingTitle, Icons.local_parking),
        NearGroup(
          title: s.hdbCarparks,
          icon: Icons.local_parking,
          show: 5,
          items: [
            for (final (c, d) in within(carparks, home.lat, home.lng, 500, latOf: (c) => c.lat, lngOf: (c) => c.lng, limit: 10))
              NearItem(
                name: c.address,
                detail: c.type.toLowerCase(),
                lat: c.lat,
                lng: c.lng,
                distance: d,
                big: lots[c.id] == null ? null : '${lots[c.id]!.$2}',
                bigLabel: s.lotsFreeShort,
                bigWarn: lots[c.id] != null && lots[c.id]!.$2 == 0,
              ),
          ],
        ),
      ],
    );
  }
}

class _Food extends ConsumerWidget {
  const _Food({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final hawkers = ref.watch(hawkersProvider).valueOrNull ?? const <Hawker>[];
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final closures = upcomingClosures(hawkers, home.lat, home.lng, now);
    final halal = ref.watch(favoritesProvider.select((f) => f.showHalal));
    String day(DateTime d) => '${d.day}/${d.month}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _Heading(s.foodTitle, Icons.restaurant_outlined)),
            // Same setting as More > Extras > Halal food nearby, one tap away here.
            FilterChip(
              avatar: const Icon(Icons.verified_outlined, size: 18),
              label: Text(s.halalTab),
              selected: halal,
              onSelected: (v) => ref.read(favoritesProvider.notifier).update((f) => f.copyWith(showHalal: v)),
            ),
          ],
        ),
        if (halal) ...[
          NearGroup(
            title: s.halalFood,
            icon: Icons.restaurant_outlined,
            items: [
              for (final (p, d) in halalNear(ref.watch(halalProvider).valueOrNull ?? const <EPoint>[], home.lat, home.lng, limit: 15))
                NearItem(name: p.name, detail: p.address, lat: p.lat, lng: p.lng, distance: d),
            ],
          ),
          Text(s.halalDisclaimer, style: t.bodySmall),
          const SizedBox(height: 12),
        ],
        NearGroup(
          title: s.hawkers,
          icon: Icons.storefront_outlined,
          items: [
            for (final (h, d) in within(hawkers, home.lat, home.lng, 1500, latOf: (h) => h.lat, lngOf: (h) => h.lng, limit: 10))
              NearItem(name: shortPlaceName(h.name), detail: h.address, lat: h.lat, lng: h.lng, distance: d),
          ],
        ),
        if (closures.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 8), child: Text(s.hawkerClosures, style: t.titleSmall)),
          Panel(
            child: Column(
              children: [
                for (final (h, c, _) in closures)
                  ListTile(
                    leading: const Icon(Icons.event_busy_outlined),
                    title: Text(shortPlaceName(h.name)),
                    subtitle: Text('${day(c.from)} – ${day(c.to)} · ${s.closureReason(c.reason)}'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- watched blocks and agents

class _WatchedAndAgent extends ConsumerWidget {
  const _WatchedAndAgent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final blocks = ref.watch(hdbBlocksProvider).valueOrNull ?? const <HdbBlock>[];
    final byKey = {for (final b in blocks) b.key: b};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(s.watched, Icons.visibility_outlined),
        if (fav.compareBlocks.length >= 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: FilledButton.icon(
              icon: const Icon(Icons.compare_arrows),
              label: Text(s.compareCount(fav.compareBlocks.length)),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComparePage())),
            ),
          ),
        if (fav.watchedBlocks.isEmpty)
          Panel(child: EmptyNote(s.emptyWatch, icon: Icons.visibility_outlined))
        else
          for (final k in fav.watchedBlocks.keys)
            if (byKey[k] != null) BlockTile(block: byKey[k]!),
        OutlinedButton.icon(
          icon: const Icon(Icons.search),
          label: Text(s.findBlock),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockSearchPage())),
        ),
        _Heading(s.propertyAgents, Icons.verified_user_outlined),
        Panel(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(s.checkAgent),
            subtitle: Text(s.agentHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AgentCheckPage())),
          ),
        ),
      ],
    );
  }
}
