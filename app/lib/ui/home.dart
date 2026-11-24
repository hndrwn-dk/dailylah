import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'ev.dart';
import 'homes.dart';
import 'place_sheet.dart';
import 'setup.dart';
import 'theme.dart';
import 'widgets.dart';

/// Home tab: everything about and around the user's own home, one section at a time
/// (tiles under the hero). Other blocks are one tap away (search).
class HomePage extends ConsumerWidget {
  const HomePage({super.key, this.controller});

  /// Main list scroll, owned by the shell.
  final ScrollController? controller;

  /// The sections under the hero, one at a time: eight tiles in two rows, like Nearby.
  static const sections = ['home', 'safety', 'schools', 'health', 'community', 'weekend', 'food', 'parking'];

  /// What My home links to on a page of its own ([HomeTopicPage]).
  static const topics = ['works', 'recycling', 'blocks'];
  static const _icons = {
    'home': Icons.home_outlined,
    'safety': Icons.emergency_outlined,
    'schools': Icons.school_outlined,
    'health': Icons.health_and_safety_outlined,
    'community': Icons.groups_outlined,
    'weekend': Icons.park_outlined,
    'food': Icons.restaurant_outlined,
    'parking': Icons.local_parking,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final fav = ref.watch(favoritesProvider);
    final home = fav.places[PlaceKind.home];
    final blocks = ref.watch(hdbBlocksProvider).value;
    final block = home == null || blocks == null ? null : homeBlock(blocks, home);
    final private = home == null || block != null
        ? null
        : privateProjectFor(ref.watch(privateHomesProvider).value ?? const [], home);
    final picked = ref.watch(homeSectionProvider);
    final section = sections.contains(picked) ? picked : 'home';

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
            'safety' => [FullWidth(child: _Safety(home: home))],
            'schools' => [FullWidth(child: _Schools(home: home))],
            'health' => [FullWidth(child: _Dengue(home: home)), FullWidth(child: _Health(home: home))],
            'community' => [FullWidth(child: _Community(home: home))],
            'weekend' => [FullWidth(child: _Weekend(home: home))],
            'food' => [FullWidth(child: _Food(home: home))],
            'parking' => [FullWidth(child: _Parking(home: home))],
            _ => [
                if (block != null) _MyBlock(block: block) else if (private != null) _PrivateCard(project: private)
                else Panel(child: EmptyNote(s.notHdb, icon: Icons.home_work_outlined)),
                _Glance(home: home),
              ],
          };

    return Scaffold(
      body: ListView(
        controller: controller,
        padding: EdgeInsets.only(bottom: navClearance(context)),
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
                  SectionTiles(
                    items: [for (final k in sections) (k, _icons[k]!, s.homeSection(k))],
                    selected: section,
                    danger: const {'safety'},
                    onTap: (k) => ref.read(homeSectionProvider.notifier).state = k,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 18, 24),
            // A section with its own heading lays its cards out itself (FullWidth here); the
            // home section's cards share the two columns of a wide window.
            child: CardColumns(
              children: [
                ...body,
                if (home == null || section == 'home') ...[
                  const FullWidth(child: SizedBox(height: 12)),
                  if (private != null && home != null) FullWidth(child: Text(s.privateHomesNote, style: t.bodySmall)),
                  FullWidth(child: Text(s.homesDisclaimer, style: t.bodySmall)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Around your home" on My home: the nearest school, hawker and AED, each opening its
/// section, then upgrading, recycling and watched blocks, each on a page of its own.
class _Glance extends ConsumerWidget {
  const _Glance({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final around = ref.watch(aroundProvider).value ?? AroundSet.empty;
    final works = projectsNear(around.projects, home.lat, home.lng, now: now);
    final mine = upgradingAtHome(works);
    final dengue = ref.watch(dengueProvider).value;
    final near = dengue == null ? const <(DengueCluster, double)>[] : dengueNear(dengue, home.lat, home.lng, km: 1);
    final pois = ref.watch(poisProvider).value;
    final school = pois == null
        ? null
        : nearest(pois.of(PoiKind.primarySchool), home.lat, home.lng, latOf: (p) => p.lat, lngOf: (p) => p.lng);
    final em = ref.watch(emergencyProvider).value ?? EmergencySet.empty;
    final aed = nearestPoints(em.of(EmergencyKind.aed), home.lat, home.lng, limit: 1).firstOrNull;
    final hawkers = ref.watch(hawkersProvider).value ?? const <Hawker>[];
    final hawker = nearest(hawkers, home.lat, home.lng, latOf: (h) => h.lat, lngOf: (h) => h.lng);
    final fav = ref.watch(favoritesProvider);
    void go(String k) => ref.read(homeSectionProvider.notifier).state = k;
    void open(String topic) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => HomeTopicPage(topic: topic)));

    Widget row(IconData icon, String title, String? sub, double? metres, VoidCallback onTap) => PlaceRow(
          icon: icon,
          title: title,
          subtitle: sub,
          figure: metres == null ? null : s.metresParts(metres).$1,
          figureLabel: metres == null ? '' : s.metresParts(metres).$2,
          onTap: onTap,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in mine)
          AlertBanner(
            icon: Icons.elevator_outlined,
            text: s.atYourBlock([s.projectKind(p.kind), if (p.status.isNotEmpty) p.status].join(' · ')),
          ),
        for (final (c, d) in near.take(1))
          AlertBanner(icon: Icons.bug_report_outlined, text: '${s.dengueHeading}: ${c.locality} · ${s.metres(d)}'),
        SectionTitle(s.aroundBlock, padding: const EdgeInsets.fromLTRB(4, 4, 4, 10)),
        Panel(
          child: Column(
            children: [
              row(Icons.school_outlined, s.nearestPrimary, school?.$1.name, school?.$2, () => go('schools')),
              row(Icons.storefront_outlined, s.nearestHawkerShort,
                  hawker == null ? null : shortPlaceName(hawker.$1.name), hawker?.$2, () => go('food')),
              row(Icons.monitor_heart_outlined, s.nearestAed, aed?.$1.detail, aed?.$2, () => go('safety')),
              row(Icons.construction_outlined, s.homeTopic('works'),
                  works.isEmpty ? s.worksNoneShort : s.worksNearby(works.length), null, () => open('works')),
              row(Icons.recycling, s.homeTopic('recycling'), s.recyclingHint, null, () => open('recycling')),
              row(Icons.apartment_outlined, s.homeTopic('blocks'),
                  s.blocksHint(fav.watchedBlocks.length, fav.compareBlocks.length), null, () => open('blocks')),
            ],
          ),
        ),
      ],
    );
  }
}

/// Upgrading and works, Recycling, or Watched blocks and agents, for the saved home, on a page
/// of its own: opened from "Around your home" on My home.
class HomeTopicPage extends ConsumerWidget {
  const HomeTopicPage({super.key, required this.topic});

  /// One of [HomePage.topics].
  final String topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final home = ref.watch(favoritesProvider).places[PlaceKind.home];
    return Scaffold(
      appBar: AppBar(title: Text(s.homeTopic(topic))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 18, 24),
        children: [
          switch (topic) {
            'works' when home != null => _Works(home: home),
            'recycling' when home != null => _Recycling(home: home),
            _ => const _WatchedAndAgent(),
          },
          if (topic == 'blocks') ...[
            const SizedBox(height: 12),
            Text(s.homesDisclaimer, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
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
    this.chips = const [],
    this.sheetNote = '',
  });

  /// A line under the address on the place sheet only, e.g. the halal disclaimer.
  final String sheetNote;

  /// Labels shown as chips on the place sheet, e.g. park facilities.
  final List<String> chips;

  /// Optional button on the place sheet, e.g. booking on ActiveSG.
  final String? linkUrl;
  final String linkLabel;

  /// A number to show large on the right (e.g. free car park lots), with a small label; the
  /// distance then moves under the name. Empty: no figure at all. Null: the distance is the figure.
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
          NearItem(
            name: p.name,
            detail: p.detail,
            lat: p.lat,
            lng: p.lng,
            distance: d,
            chips: p.facilities,
          ),
      ];
}

/// A titled list that shows the nearest few and expands to the rest. Each row is a [PlaceRow]:
/// the distance (or the row's own number, with the distance under the name) large at the end,
/// then a chevron; the sheet it opens has the phone number and links.
class NearGroup extends ConsumerStatefulWidget {
  const NearGroup({super.key, required this.title, required this.icon, required this.items, this.show = 3, this.header});
  final String title;

  /// Shown between the title and the list, e.g. the parks "good time to go?" line.
  final Widget? header;
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
    void open(NearItem it) => showPlaceSheet(
                    context,
                    s: s,
                    title: it.name,
                    subtitle: it.sheetNote.isEmpty ? it.detail : '${it.detail}\n${it.sheetNote}',
                    lat: it.lat,
                    lng: it.lng,
                    distance: it.distance,
                    phone: it.tel,
                    extra: [
                      if (it.chips.isNotEmpty) ...[
                        Text(s.facilities, style: t.titleSmall),
                        const SizedBox(height: 8),
                        InfoChips(it.chips, icons: true),
                        const SizedBox(height: 12),
                      ],
                      if (widget.header case final h?) h,
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
                  );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(widget.title, style: t.titleSmall),
        ),
        if (widget.header case final h?) h,
        Panel(
          child: Column(
            children: [
              for (final it in shown)
                PlaceRow(
                  icon: widget.icon,
                  title: it.name,
                  // A row with its own number keeps the distance in the line under the name.
                  // A row never prints a web address (some bundles put one in the details).
                  subtitle: [
                    if (it.big != null) s.metres(it.distance),
                    if (withoutWebAddress(it.detail) case final d when d.isNotEmpty) d,
                  ].join(' · '),
                  below: it.chips.isEmpty ? null : FacilityIcons(it.chips),
                  figure: it.big == null ? s.metresParts(it.distance).$1 : (it.big!.isEmpty ? null : it.big),
                  figureLabel: it.big != null ? it.bigLabel : s.metresParts(it.distance).$2,
                  warn: it.bigWarn,
                  onTap: () => open(it),
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
    final resale = ref.watch(resaleProvider).value;
    final stats = [...?resale?.blocks[block.key]]..sort((a, b) => b.count.compareTo(a.count));
    // The same rent as "Prices, rent and commute": the town's quarterly median when known.
    final rents = townRents(ref.watch(whereToLiveProvider).value, ref.watch(rentProvider).value, block.town);
    final topRent = townRentFor(rents, stats.isEmpty ? null : stats.first.flatType);
    final watching = ref.watch(favoritesProvider).watchedBlocks.containsKey(block.key);
    final year = DateTime.now().year;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // What only tells lies flat; the card that opens the block's page is raised.
        _FactStrip([
          ('${block.yearCompleted}', s.factBuilt),
          (s.yearsShort(block.leaseLeft(year)), s.factLease),
          if (block.floors > 0) ('${block.floors}', s.factStoreys),
        ]),
        const SizedBox(height: 12),
        Panel(
          margin: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlockPage(block: block))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (stats.isNotEmpty)
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
                        if (topRent != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            s.rentMedian(topRent.$1, sgd(topRent.$2.median),
                                topRent.$2.quarterly ? s.wtlQuarter(topRent.$2.period) : topRent.$2.period),
                            style: t.bodySmall,
                          ),
                        ],
                        if (stats.isNotEmpty || topRent != null) const SizedBox(height: 10),
                        Text(s.blockDetails, style: t.titleMedium),
                      ],
                    ),
                  ),
                  ExcludeSemantics(child: Icon(Icons.chevron_right, color: DL.muted(context))),
                ],
              ),
            ),
          ),
        ),
        // Watching is one quiet line: what it does, and the one word that changes it.
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(watching ? Icons.visibility : Icons.visibility_outlined, size: 20, color: DL.muted(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(watching ? s.watchingBlock : s.watchBlockHint,
                    style: t.bodyMedium?.copyWith(color: DL.muted(context))),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: DL.goText(context),
                    minimumSize: const Size(kMinInteractiveDimension, kMinInteractiveDimension)),
                onPressed: () =>
                    ref.read(favoritesProvider.notifier).toggleWatch(block.key, resale?.countFor(block.key) ?? 0),
                // The word alone says too little to a screen reader.
                child: Text(watching ? s.watchStop : s.watchStart,
                    semanticsLabel: watching ? s.watchStopLabel : s.watchBlock),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A few facts side by side in one flat, outlined card with no shadow: each a figure over its
/// label ("1983" over "built"). Nothing here opens anything.
class _FactStrip extends StatelessWidget {
  const _FactStrip(this.facts);
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final edge = DL.edge(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(DL.radius),
        border: Border.all(color: edge, width: DL.stroke),
      ),
      child: LayoutBuilder(builder: (context, box) {
        // Large text on a small phone: one fact a line, the figure before its label.
        if (box.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 200) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (value, label) in facts)
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$value ', style: t.displaySmall?.copyWith(fontSize: 22, height: 1.3)),
                      TextSpan(text: label, style: t.bodySmall),
                    ]),
                  ),
              ],
            ),
          );
        }
        return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, (value, label)) in facts.indexed) ...[
              if (i > 0) VerticalDivider(width: 1.5, thickness: 1.5, color: Theme.of(context).dividerTheme.color),
              Expanded(
                // One stop for TalkBack: "1983 built".
                child: MergeSemantics(
                  child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // A figure never wraps: it shrinks to its cell at large text.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(value, maxLines: 1, style: t.displaySmall?.copyWith(fontSize: 24, height: 1.1)),
                      ),
                      Text(label, style: t.bodySmall),
                    ],
                  ),
                ),
                ),
              ),
            ],
          ],
        ),
        );
      }),
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
    final around = ref.watch(aroundProvider).value ?? AroundSet.empty;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final near = projectsNear(around.projects, home.lat, home.lng, now: now);
    final mine = upgradingAtHome(near);

    String line(Project p) => [
          s.projectKind(p.kind),
          if (p.status.isNotEmpty) p.status,
          if (s.projectWhen(p.from, p.to).isNotEmpty) s.projectWhen(p.from, p.to),
        ].join(' · ');

    return CardColumns(
      children: [
        // The page's title says what this is.
        const SizedBox(height: 12),
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
    final all = ref.watch(dengueProvider).value;
    final near = all == null ? const <(DengueCluster, double)>[] : dengueNear(all, home.lat, home.lng, km: 2);
    return CardColumns(
      children: [
        FullWidth(child: _Heading(s.dengueHeading, Icons.bug_report_outlined)),
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
    final pois = ref.watch(poisProvider).value;
    if (pois == null) return const SizedBox.shrink();
    final (near, far) = schoolsByBand(pois.of(PoiKind.primarySchool), home.lat, home.lng);
    NearItem item((Poi, double) x) => NearItem(name: x.$1.name, lat: x.$1.lat, lng: x.$1.lng, distance: x.$2);
    return CardColumns(
      children: [
        FullWidth(child: _Heading(s.schoolsTitle, Icons.school_outlined)),
        NearGroup(title: '${s.primarySchools} · ${s.within1km}', icon: Icons.school_outlined, items: [for (final x in near) item(x)]),
        NearGroup(title: '${s.primarySchools} · ${s.between1and2km}', icon: Icons.school_outlined, items: [for (final x in far) item(x)]),
        NearGroup(title: s.secondarySchools, icon: Icons.school_outlined, items: NearItem.pois(pois.of(PoiKind.school), home)),
        NearGroup(title: s.preschools, icon: Icons.child_care_outlined, items: NearItem.pois(pois.of(PoiKind.preschool), home, radius: 1000)),
        FullWidth(child: Text(s.p1Note, style: Theme.of(context).textTheme.bodySmall)),
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
    final em = ref.watch(emergencyProvider).value ?? EmergencySet.empty;
    final around = ref.watch(aroundProvider).value ?? AroundSet.empty;
    return CardColumns(
      children: [
        FullWidth(child: _Heading(s.healthTitle, Icons.health_and_safety_outlined)),
        NearGroup(title: s.chasClinics, icon: Icons.medical_services_outlined, items: NearItem.points(em.of(EmergencyKind.clinic), home, radius: 2000)),
        NearGroup(title: s.pharmacies, icon: Icons.local_pharmacy_outlined, items: NearItem.points(around.of('pharmacy'), home)),
      ],
    );
  }
}

/// Safety: call buttons first, then AEDs, A&E, police and SCDF fire stations, then the
/// emergency meeting points (Civil Defence public shelters, nearest first).
class _Safety extends ConsumerWidget {
  const _Safety({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final em = ref.watch(emergencyProvider).value ?? EmergencySet.empty;
    final around = ref.watch(aroundProvider).value ?? AroundSet.empty;

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

    return CardColumns(
      children: [
        FullWidth(child: _Heading(s.emergency, Icons.emergency_outlined)),
        // The same colours as Nearby > Help: red for 995, amber for 999.
        call('995', s.call995, DL.stopDeep, Colors.white),
        call('999', s.call999, DL.amber, DL.ink),
        call('1777', s.call1777, DL.card, DL.ink),
        NearGroup(title: s.aeds, icon: Icons.monitor_heart_outlined, items: NearItem.points(em.of(EmergencyKind.aed), home, radius: 1000)),
        NearGroup(title: s.aeHospitals, icon: Icons.local_hospital_outlined, items: NearItem.points(em.of(EmergencyKind.ae), home, radius: 20000, limit: 3)),
        NearGroup(title: s.police, icon: Icons.local_police_outlined, items: NearItem.points(around.of('police'), home, radius: 5000, limit: 5)),
        NearGroup(title: s.scdfFireStations, icon: Icons.fire_truck_outlined, items: NearItem.points(em.of(EmergencyKind.fire), home, radius: 8000, limit: 2)),
        FullWidth(child: Text(s.emergencyNote, style: t.bodySmall)),
        FullWidth(child: _Heading(s.meetingPoints, Icons.shield_outlined)),
        NearGroup(
          title: s.within2km,
          icon: Icons.shield_outlined,
          items: NearItem.points(em.of(EmergencyKind.shelter), home, radius: 2000),
        ),
        FullWidth(child: Text(s.shelterNote, style: t.bodySmall)),
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
    final around = ref.watch(aroundProvider).value ?? AroundSet.empty;
    final pois = ref.watch(poisProvider).value;
    return CardColumns(
      children: [
        FullWidth(child: _Heading(s.communityTitle, Icons.groups_outlined)),
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
    final around = ref.watch(aroundProvider).value ?? AroundSet.empty;
    return CardColumns(
      children: [
        const SizedBox(height: 12),
        NearGroup(title: s.ewastePoints, icon: Icons.battery_charging_full_outlined, items: NearItem.points(around.of('ewaste'), home, radius: 2000)),
        NearGroup(title: s.reuseChannels, icon: Icons.volunteer_activism_outlined, items: NearItem.points(around.of('reuse'), home, radius: 5000)),
        FullWidth(child: Text(s.recyclingNote, style: Theme.of(context).textTheme.bodySmall)),
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
    final around = ref.watch(aroundProvider).value ?? AroundSet.empty;
    final pois = ref.watch(poisProvider).value;
    return CardColumns(
      children: [
        FullWidth(child: _Heading(s.weekendTitle, Icons.park_outlined)),
        if (eventsNear(ref.watch(eventsProvider).value ?? const <PublicEvent>[], home.lat, home.lng,
                ref.watch(clockProvider).value ?? DateTime.now(),
                days: 7, limit: 10) case final evs when evs.isNotEmpty)
          NearGroup(
            title: s.eventsNearby,
            icon: Icons.event_outlined,
            items: [
              for (final (e, d) in evs)
                NearItem(
                  name: e.name,
                  detail: [if (e.when.isNotEmpty) e.when, if (e.place.isNotEmpty) e.place, if (e.free) s.freeEvent, e.source]
                      .join(' · '),
                  lat: e.lat,
                  lng: e.lng,
                  distance: d,
                  linkUrl: e.url,
                  linkLabel: s.eventDetails,
                ),
            ],
          ),
        if (pois != null)
          NearGroup(
            title: s.parks,
            icon: Icons.park_outlined,
            items: NearItem.pois(pois.of(PoiKind.park), home, radius: 2000),
            header: switch (ref.watch(parkTimeProvider((home.lat, home.lng)))) {
              final p? => ParkTimeBanner(time: p, text: s.parkTimeLine(p)),
              null => null,
            },
          ),
        NearGroup(title: s.attractions, icon: Icons.attractions_outlined, items: NearItem.points(around.of('attraction'), home, radius: 6000)),
        NearGroup(title: s.museums, icon: Icons.museum_outlined, items: NearItem.points(around.of('museum'), home, radius: 10000, limit: 3)),
        NearGroup(
          title: s.activeSgCentres,
          icon: Icons.sports_tennis_outlined,
          items: [
            for (final it in NearItem.points(around.of('activesg'), home, radius: 8000, limit: 5))
              NearItem(
                name: it.name,
                // The bundle's detail starts with the booking site's address: not on the row and
                // not on the sheet, where it is the Book on ActiveSG button.
                detail: withoutWebAddress(it.detail),
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
    final carparks = ref.watch(carparkInfoProvider).value ?? const <Carpark>[];
    final lots = ref.watch(carparkLiveProvider).value ?? const <String, (int, int)>{};
    return CardColumns(
      children: [
        FullWidth(child: _Heading(s.parkingTitle, Icons.local_parking)),
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
                // As on Nearby: free lots when known; a car park without a live count has no figure.
                big: lots[c.id] == null ? '' : '${lots[c.id]!.$2}',
                bigLabel: s.lotsFreeShort,
                bigWarn: lots[c.id] != null && lots[c.id]!.$2 == 0,
              ),
          ],
        ),
        if (ref.watch(favoritesProvider.select((f) => f.drivesEv)))
          EvChargers(lat: home.lat, lng: home.lng, title: s.evChargersTitle, chevron: true),
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
    final hawkers = ref.watch(hawkersProvider).value ?? const <Hawker>[];
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final closures = upcomingClosures(hawkers, home.lat, home.lng, now);
    final halal = ref.watch(favoritesProvider.select((f) => f.showHalal));
    String day(DateTime d) => '${d.day}/${d.month}';
    return CardColumns(
      children: [
        FullWidth(
          child: Row(
          children: [
            Expanded(child: _Heading(s.foodTitle, Icons.restaurant_outlined)),
            // Same setting as More > Extras > Halal food nearby, one tap away here.
            FilterChip(
              avatar: Icon(Icons.verified_outlined, size: 18, color: halal ? DL.ink : null),
              label: Text(s.halalTab),
              selected: halal,
              onSelected: (v) => ref.read(favoritesProvider.notifier).update((f) => f.copyWith(showHalal: v)),
            ),
          ],
        ),
        ),
        // One child, so the halal note stays under its list when the cards go into two columns.
        if (halal)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NearGroup(
            title: s.halalFood,
            icon: Icons.restaurant_outlined,
            items: [
              for (final (p, d) in halalNear(ref.watch(halalProvider).value ?? const <EPoint>[], home.lat, home.lng,
                  limit: 15, favs: ref.watch(favoritesProvider.select((f) => f.halalPlaces))))
                NearItem(name: p.name, detail: p.address, lat: p.lat, lng: p.lng, distance: d, sheetNote: s.halalDisclaimer),
            ],
          ),
          Text(s.halalDisclaimer, style: t.bodySmall),
          const SizedBox(height: 12),
        ]),
        NearGroup(
          title: s.hawkers,
          icon: Icons.storefront_outlined,
          items: [
            for (final (h, d) in within(hawkers, home.lat, home.lng, 1500, latOf: (h) => h.lat, lngOf: (h) => h.lng, limit: 10))
              NearItem(name: shortPlaceName(h.name), detail: h.address, lat: h.lat, lng: h.lng, distance: d),
          ],
        ),
        if ((ref.watch(poisProvider).value ?? PoiSet.empty).of(PoiKind.supermarket) case final shops when shops.isNotEmpty)
          NearGroup(
            title: s.supermarkets,
            icon: Icons.shopping_cart_outlined,
            items: NearItem.pois(shops, home, radius: 2000),
          ),
        if (closures.isNotEmpty) ...[
          KeepWithNext(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8), child: Text(s.hawkerClosures, style: t.titleSmall)),
          ),
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
    final blocks = ref.watch(hdbBlocksProvider).value ?? const <HdbBlock>[];
    final byKey = {for (final b in blocks) b.key: b};
    return CardColumns(
      children: [
        FullWidth(child: _Heading(s.watched, Icons.visibility_outlined)),
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
        KeepWithNext(child: _Heading(s.propertyAgents, Icons.verified_user_outlined)),
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
