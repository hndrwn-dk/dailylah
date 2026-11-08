import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'block_commute.dart';
import 'theme.dart';
import 'widgets.dart';

final _homesQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Homes: HDB block search, watched blocks, comparison and the CEA agent check.
/// Search any HDB block by street, block or postal code.
class BlockSearchPage extends ConsumerWidget {
  const BlockSearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final query = ref.watch(_homesQueryProvider);
    final blocks = ref.watch(hdbBlocksProvider);
    final t = Theme.of(context).textTheme;

    final all = blocks.value ?? const <HdbBlock>[];
    final postal = isPostalCode(query);
    final byPostal = postal ? searchBlocks(all, query) : const <HdbBlock>[];
    // Postal codes not in the bundle are resolved on OneMap, then matched to a block.
    final postalHit = postal && byPostal.isEmpty && all.isNotEmpty ? ref.watch(addressSearchProvider(query.trim())) : null;
    final postalBlock = postalHit?.value?.isNotEmpty == true ? blockForAddress(all, postalHit!.value!.first) : null;
    final results = postal
        ? (byPostal.isNotEmpty ? byPostal : [if (postalBlock != null) postalBlock])
        : query.trim().length < 2
            ? const <HdbBlock>[]
            : searchBlocks(all, query);
    final empty = blocks.hasError || (blocks.hasValue && all.isEmpty);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: kNavClearance),
        children: [
          HeroHeader(
            accent: const Color(0xFF2E9E7E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BackButton(),
                PageTitle(s.homesTitle, subtitle: s.homesIntro),
                const SizedBox(height: 18),
                TextField(
                  autofocus: true,
                  onChanged: (v) => ref.read(_homesQueryProvider.notifier).state = v,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: s.blockSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (blocks.isLoading) const LinearProgressIndicator(),
                if (empty) Panel(child: EmptyNote(s.bundlesLoading, icon: Icons.cloud_download_outlined)),
                if (query.trim().length >= 2) ...[
                  if (postalHit?.isLoading == true) const LinearProgressIndicator(),
                  if (!empty && results.isEmpty && !(postalHit?.isLoading ?? false))
                    Panel(child: EmptyNote(postal ? s.blockNotInData : s.notAvailable)),
                  for (final b in results) BlockTile(block: b),
                ],
                const SizedBox(height: 12),
                Text(s.homesDisclaimer, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge(this.icon, {this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 20, color: c),
    );
  }
}

class BlockTile extends ConsumerWidget {
  const BlockTile({super.key, required this.block});
  final HdbBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final resale = ref.watch(resaleProvider).value;
    final stats = resale?.blocks[block.key] ?? const <ResaleStat>[];
    final t = Theme.of(context).textTheme;
    final top = stats.isEmpty ? null : (stats.toList()..sort((a, b) => b.count.compareTo(a.count))).first;
    return Panel(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlockPage(block: block))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _BlockNumber(block.block),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(block.street, style: t.titleSmall),
                    const SizedBox(height: 2),
                    Text('${block.town} · ${s.builtIn(block.yearCompleted)}', style: t.bodySmall),
                  ],
                ),
              ),
              if (top != null)
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(sgd(top.median, compact: true), style: t.displaySmall?.copyWith(fontSize: 24)),
                      ),
                      Text(top.flatType.toLowerCase(), style: t.bodySmall, textAlign: TextAlign.end),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Block number set like the painted numbers on HDB block facades.
class _BlockNumber extends StatelessWidget {
  const _BlockNumber(this.number, {this.large = false});
  final String number;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: large ? 76 : 56, minHeight: large ? 76 : 56),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DL.mint,
        borderRadius: BorderRadius.circular(large ? 18 : 14),
        border: Border.all(color: DL.edge(context), width: DL.stroke),
      ),
      child: Text(
        number,
        style: TextStyle(
          fontFamily: DL.display,
          fontWeight: FontWeight.w700,
          fontSize: large ? 34 : 24,
          color: DL.ink,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- block detail

class BlockPage extends ConsumerWidget {
  const BlockPage({super.key, required this.block});
  final HdbBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final resale = ref.watch(resaleProvider).value;
    final rent = ref.watch(rentProvider).value;
    final wtl = ref.watch(whereToLiveProvider).value;
    final year = (ref.watch(clockProvider).value ?? DateTime.now()).year;
    final stats = resale?.blocks[block.key] ?? const <ResaleStat>[];
    final townMedians = resale?.towns[block.town] ?? const <String, int>{};
    // One rent per town on this page: the quarterly where-to-live medians (each with its quarter),
    // the same figures the commute and town board below use; hdb_rent only for a town not in it.
    final rents = townRents(wtl, rent, block.town);
    final quarterly = rents.values.any((r) => r.quarterly);
    final areaName = wtl == null || wtl.isEmpty
        ? ''
        : wtl.areas.where((a) => a.id == wtlChoiceFor(wtl, fav).choice.area).firstOrNull?.name ?? '';
    final watching = fav.watchedBlocks.containsKey(block.key);
    final comparing = fav.compareBlocks.contains(block.key);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroHeader(
            accent: const Color(0xFF2E9E7E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BackButton(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _BlockNumber(block.block, large: true),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WordWrapTitle(block.street, style: t.headlineSmall),
                          const SizedBox(height: 4),
                          Text(block.town, style: t.bodyMedium?.copyWith(color: t.bodySmall?.color)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroChip(Icons.calendar_today_outlined, s.builtIn(block.yearCompleted)),
                    if (block.floors > 0) _HeroChip(Icons.apartment, s.storeys(block.floors)),
                  ],
                ),
                const SizedBox(height: 14),
                LeaseBar(block: block, year: year),
                const SizedBox(height: 18),
                _ActionButtons(
                  watch: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: watching ? DL.amber : DL.ink,
                          foregroundColor: watching ? DL.ink : DL.card,
                        ),
                        icon: Icon(watching ? Icons.visibility : Icons.visibility_outlined),
                        label: _OneLine(watching ? s.watching : s.watch),
                        onPressed: () => ref
                            .read(favoritesProvider.notifier)
                            .toggleWatch(block.key, resale?.countFor(block.key) ?? 0),
                      ),
                  compare: OutlinedButton.icon(
                        key: const ValueKey('block-compare'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                        icon: Icon(comparing ? Icons.compare_arrows : Icons.add),
                        label: _OneLine(comparing ? s.openCompare(fav.compareBlocks.length) : s.compare),
                        onPressed: () async {
                          if (comparing) {
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComparePage()));
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(context);
                          await ref.read(favoritesProvider.notifier).toggleCompare(block.key);
                          if (comparing) return;
                          final n = ref.read(favoritesProvider).compareBlocks.length;
                          showActionSnackBar(
                            messenger,
                            s.compareAdded(n),
                            actionLabel: n < 2 ? null : s.open,
                            onAction: () => nav.push(MaterialPageRoute(builder: (_) => const ComparePage())),
                          );
                        },
                      ),
                ),
                const SizedBox(height: 8),
                Text(s.watchNote, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(s.resalePrices),
                if (stats.isEmpty)
                  Panel(child: EmptyNote(s.noResale))
                else
                  for (final st in stats)
                    Semantics(
                      container: true,
                      child: _ResaleCard(stat: st, townMedian: townMedians[st.flatType], town: block.town),
                    ),
                if (rents.isNotEmpty) ...[
                  SectionTitle(s.rentTitle, trailing: quarterly ? null : Text(rents.values.first.period, style: t.bodySmall)),
                  Semantics(container: true, child: Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in rents.entries)
                            _RentRow(flat: s.wtlFlatName(e.key), median: e.value.median, quarter: e.value.quarterly ? s.wtlQuarter(e.value.period) : ''),
                        ],
                      ),
                    ),
                  )),
                ],
                SectionTitle(s.wtlCommuteTitle),
                BlockCommute(block: block),
                SectionTitle(s.dailyLifeScore),
                _ScoreCard(block: block),
                if (areaName.isNotEmpty) ...[
                  SectionTitle(s.wtlTownsTitle(areaName)),
                  TownsBoard(block: block),
                ],
                const DataFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Watch and Compare side by side, the same width and height with one-line labels; stacked full
/// width when the labels would not fit (large text, narrow screens).
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.watch, required this.compare});
  final Widget watch;
  final Widget compare;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(builder: (context, box) {
      // Each half needs about 170 dp for "Notifying you" with its icon at 100% text.
      if (box.maxWidth / 2 - 5 < 170 * scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [watch, const SizedBox(height: 10), compare],
        );
      }
      return Row(
        children: [Expanded(child: watch), const SizedBox(width: 10), Expanded(child: compare)],
      );
    });
  }
}

/// A button label kept on one line, scaled down rather than wrapped.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1));
}

/// Lease left as a bar of the 99-year lease, with the year it ends.
class LeaseBar extends ConsumerWidget {
  const LeaseBar({super.key, required this.block, required this.year, this.compact = false});
  final HdbBlock block;
  final int year;

  /// In the comparison: the years and a thin bar only.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final left = block.leaseLeft(year);
    final ends = block.yearCompleted + 99;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: left / 99,
        minHeight: compact ? 6 : 10,
        color: left < 40 ? DL.amber : DL.teal,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        semanticsLabel: '${s.leaseLeft(left)}, ${s.leaseEnds(ends)}',
      ),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text('$left', maxLines: 1, style: t.titleSmall)),
            const SizedBox(height: 4),
            bar,
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text('$ends', maxLines: 1, style: t.labelSmall?.copyWith(color: DL.muted(context)))),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hourglass_bottom, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(s.leaseLeft(left), style: t.labelLarge)),
            Text(s.leaseEnds(ends), style: t.labelMedium?.copyWith(color: DL.muted(context))),
          ],
        ),
        const SizedBox(height: 6),
        bar,
      ],
    );
  }
}

/// One line of the town rent list: flat type chip, the monthly median, its quarter in small type.
class _RentRow extends ConsumerWidget {
  const _RentRow({required this.flat, required this.median, required this.quarter});
  final String flat;
  final int median;
  final String quarter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final s = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      // Chip, price and quarter on one line; they wrap under each other at large text sizes.
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(constraints: const BoxConstraints(minWidth: 104), child: FlatChip(flat)),
          Text.rich(TextSpan(children: [
            TextSpan(text: sgd(median), style: t.displaySmall?.copyWith(fontSize: 24)),
            TextSpan(text: ' ${s.perMonthShort}', style: t.bodySmall),
          ])),
          if (quarter.isNotEmpty) Text(quarter, style: t.labelSmall?.copyWith(color: DL.muted(context))),
        ],
      ),
    );
  }
}

/// A flat type ("4-room") as a small mint chip.
class FlatChip extends StatelessWidget {
  const FlatChip(this.flat, {super.key});
  final String flat;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: DL.mint,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DL.edge(context), width: 1.5),
        ),
        child: Text(flat, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: DL.ink)),
      );
}

class _HeroChip extends StatelessWidget {
  const _HeroChip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DL.edge(context), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: Theme.of(context).textTheme.labelMedium)),
        ],
      ),
    );
  }
}

class _ResaleCard extends ConsumerWidget {
  const _ResaleCard({required this.stat, required this.townMedian, required this.town});
  final ResaleStat stat;
  final int? townMedian;
  final String town;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tm = townMedian;
    final maxV = [stat.median, tm ?? 0].reduce((a, b) => a > b ? a : b).toDouble();
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FlatChip(s.wtlFlatName(stat.flatType)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(sgd(stat.median, compact: true), maxLines: 1, style: t.displayMedium?.copyWith(fontSize: 36)),
            ),
            Text('${sgd(stat.median)} · ${s.medianOf(stat.count)}', style: t.bodySmall?.copyWith(color: DL.muted(context))),
            if (tm != null && maxV > 0) ...[
              const SizedBox(height: 14),
              _Bar(label: '${s.thisBlock} ${sgd(stat.median, compact: true)}', value: stat.median / maxV, color: scheme.primary),
              const SizedBox(height: 6),
              _Bar(label: '${s.townMedian(titleCase(town))} ${sgd(tm, compact: true)}', value: tm / maxV, color: DL.mist),
            ],
            const SizedBox(height: 10),
            Text(s.latestSale(monthLabel(stat.lastMonth), sgd(stat.lastPrice)), style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 8,
            color: color,
            backgroundColor: scheme.surfaceContainer,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _ScoreCard extends ConsumerWidget {
  const _ScoreCard({required this.block});
  final HdbBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final pois = ref.watch(poisProvider).value;
    final stops = ref.watch(busStopsProvider).value;
    final hawkers = ref.watch(hawkersProvider).value;
    final dengue = ref.watch(dengueProvider).value ?? const <DengueCluster>[];
    if (pois == null || stops == null || hawkers == null) {
      return const Panel(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    }
    final sc = scoreBlock(block, pois: pois, stops: stops, hawkers: hawkers, dengue: dengue);
    final rows = <(IconData, String, String, bool)>[
      (
        Icons.train_outlined,
        s.nearestMrt,
        sc.nearestMrt == null ? '–' : '${titleCase(sc.nearestMrt!.$1.name)} · ${s.metres(sc.nearestMrt!.$2)}',
        false
      ),
      (Icons.directions_bus_outlined, s.busStops400, '${sc.busStops400}', false),
      (Icons.ramen_dining_outlined, s.hawkers1km, '${sc.hawkers1km}', false),
      (Icons.school_outlined, s.primary1km, '${sc.primary1km}', false),
      (Icons.school_outlined, s.primary2km, '${sc.primary2km}', false),
      (Icons.park_outlined, s.parks1km, '${sc.parks1km}', false),
      (Icons.bug_report_outlined, s.dengue1km, '${sc.dengue1km}', sc.dengue1km > 0),
    ];
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        children: [
          for (final (icon, label, value, warn) in rows)
            value.length <= 3
                ? ListTile(
                    leading: _IconBadge(icon, color: warn ? DL.amber : null),
                    title: Text(label, style: t.bodyMedium),
                    trailing: Text(value, style: t.displaySmall?.copyWith(fontSize: 24)),
                  )
                : ListTile(
                    leading: _IconBadge(icon, color: warn ? DL.amber : null),
                    title: Text(label, style: t.bodyMedium),
                    subtitle: Text(value, style: t.labelLarge),
                  ),
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------- compare

class ComparePage extends ConsumerWidget {
  const ComparePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final blocks = ref.watch(hdbBlocksProvider).value ?? const <HdbBlock>[];
    final resale = ref.watch(resaleProvider).value;
    final pois = ref.watch(poisProvider).value;
    final stops = ref.watch(busStopsProvider).value ?? const <BusStop>[];
    final hawkers = ref.watch(hawkersProvider).value ?? const <Hawker>[];
    final dengue = ref.watch(dengueProvider).value ?? const <DengueCluster>[];
    final year = DateTime.now().year;
    final byKey = {for (final b in blocks) b.key: b};
    final chosen = [for (final k in fav.compareBlocks) if (byKey[k] != null) byKey[k]!];
    final t = Theme.of(context).textTheme;
    final commute = wtlCompareLinesFor(ref, chosen);

    String priceFor(HdbBlock b, String ft) {
      final st = (resale?.blocks[b.key] ?? const <ResaleStat>[]).where((r) => r.flatType == ft);
      return st.isEmpty ? '–' : sgd(st.first.median, compact: true);
    }

    final flatTypes = <String>{
      for (final b in chosen) ...(resale?.blocks[b.key] ?? const <ResaleStat>[]).map((r) => r.flatType),
    }.toList()
      ..sort();
    final scores = {
      for (final b in chosen)
        if (pois != null) b.key: scoreBlock(b, pois: pois, stops: stops, hawkers: hawkers, dengue: dengue),
    };

    // Numbers stay on one line, scaled down when a column is narrow.
    Widget number(String v) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(v, maxLines: 1, style: t.titleSmall)),
        );
    Widget label(String v) => Text(v, style: t.bodySmall);
    // A small section title over a group of lines ("Resale median", "Rent in town").
    Widget section(String v) => Text(v, style: t.labelLarge?.copyWith(color: DL.goText(context)));
    final wtl = ref.watch(whereToLiveProvider).value;
    final rentData = ref.watch(rentProvider).value;
    final rentFlat = commute?.choice.flat ?? '4-ROOM';
    Widget rentCell(HdbBlock b) {
      final r = townRents(wtl, rentData, b.town)[rentFlat];
      if (r == null) return number('–');
      return Column(children: [
        number(sgd(r.median)),
        if (r.quarterly)
          Padding(
            // Apart from the next column's quarter at large text and on narrow screens.
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(s.wtlQuarter(r.period), maxLines: 1, style: t.labelSmall?.copyWith(color: DL.muted(context))),
            ),
          ),
      ]);
    }

    final rows = <(Widget, Widget Function(HdbBlock))>[
      (label(s.builtLabel), (b) => number('${b.yearCompleted}')),
      (label(s.leaseLabel), (b) => LeaseBar(block: b, year: year, compact: true)),
      if (flatTypes.isNotEmpty) (section(s.resaleMedian), (_) => const SizedBox.shrink()),
      for (final ft in flatTypes)
        (Align(alignment: Alignment.centerLeft, child: FlatChip(s.wtlFlatName(ft.replaceAll(' ', '-')))), (b) => number(priceFor(b, ft))),
      (section(s.rentInTown), (_) => const SizedBox.shrink()),
      (Align(alignment: Alignment.centerLeft, child: FlatChip(s.wtlFlatName(rentFlat))), rentCell),
      (label(s.nearestMrt), (b) => number(scores[b.key]?.nearestMrt == null ? '–' : s.metres(scores[b.key]!.nearestMrt!.$2))),
      (label(s.cmpBusStops), (b) => number('${scores[b.key]?.busStops400 ?? '–'}')),
      (label(s.cmpHawkers), (b) => number('${scores[b.key]?.hawkers1km ?? '–'}')),
      (label(s.cmpPrimary), (b) => number('${scores[b.key]?.primary1km ?? '–'}')),
      (label(s.cmpParks), (b) => number('${scores[b.key]?.parks1km ?? '–'}')),
      (label(s.cmpDengue), (b) => number('${scores[b.key]?.dengue1km ?? '–'}')),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s.compare)),
      body: chosen.isEmpty
          ? Center(child: EmptyNote(s.notAvailable))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // What the commute lines are for: office area, flat type, rent or buy.
                if (commute != null && commute.area != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      key: const ValueKey('compare-context'),
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeroChip(Icons.work_outline, s.wtlToArea(commute.area!.name)),
                        _HeroChip(Icons.apartment, s.wtlFlatName(commute.choice.flat)),
                        _HeroChip(commute.choice.mode == WtlMode.buy ? Icons.sell_outlined : Icons.key_outlined,
                            s.wtlModeName(commute.choice.mode)),
                      ],
                    ),
                  ),
                Panel(
                  // Clip so the striped rows stay inside the rounded outline.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(DL.radius - 2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: LayoutBuilder(builder: (context, box) {
                        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                        // A label column beside the cells needs room; at large text or on a narrow
                        // screen each line's label goes above its cells, full width.
                        final stacked = box.maxWidth / (chosen.length + 1.4) * 1.4 < 110 * scale;
                        final lines = <(Widget, List<Widget>)>[
                          for (final r in rows) (r.$1, [for (final b in chosen) r.$2(b)]),
                          // Commute from each block's town ("In this area" and "Best" as on the website).
                          if (commute != null)
                            for (final line in commute.lines)
                              (
                                Text(s.wtlLine(line.key, commute.area?.name ?? '', commute.choice), style: t.bodySmall),
                                [for (final cell in line.cells) WtlCellText(line: line.key, cell: cell, mode: commute.choice.mode)],
                              ),
                        ];
                        Color? stripe(int i) =>
                            i.isEven ? Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.5) : null;
                        final heads = [
                          for (final b in chosen)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  FittedBox(fit: BoxFit.scaleDown, child: _BlockNumber(b.block)),
                                  const SizedBox(height: 6),
                                  if (stacked)
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(titleCase(b.street), style: t.labelSmall, maxLines: 1),
                                    )
                                  else
                                    Text(b.street, style: t.labelSmall, textAlign: TextAlign.center, maxLines: 3),
                                  IconButton(
                                    tooltip: s.remove,
                                    icon: const Icon(Icons.close),
                                    onPressed: () => ref.read(favoritesProvider.notifier).toggleCompare(b.key),
                                  ),
                                ],
                              ),
                            ),
                        ];
                        if (stacked) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final h in heads) Expanded(child: h)]),
                              for (var i = 0; i < lines.length; i++)
                                Container(
                                  color: stripe(i),
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      lines[i].$1,
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [for (final c in lines[i].$2) Expanded(child: Center(child: c))],
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        }
                        return Table(
                          columnWidths: const {0: FlexColumnWidth(1.4)},
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          children: [
                            TableRow(children: [
                              const SizedBox(),
                              // Top-aligned so the block numbers line up whatever the street length.
                              for (final h in heads) TableCell(verticalAlignment: TableCellVerticalAlignment.top, child: h),
                            ]),
                            for (var i = 0; i < lines.length; i++)
                              TableRow(
                                decoration: BoxDecoration(color: stripe(i)),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    child: lines[i].$1,
                                  ),
                                  ...lines[i].$2,
                                ],
                              ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                const DataFooter(),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------- CEA agent check

class AgentCheckPage extends ConsumerStatefulWidget {
  const AgentCheckPage({super.key});

  @override
  ConsumerState<AgentCheckPage> createState() => _AgentCheckPageState();
}

class _AgentCheckPageState extends ConsumerState<AgentCheckPage> {
  final _ctrl = TextEditingController();
  String? _reg;

  static final _re = RegExp(r'^[A-Z]\d{6}[A-Z]$');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _check() {
    final v = _ctrl.text.trim().toUpperCase();
    setState(() => _reg = _re.hasMatch(v) ? v : '');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final reg = _reg;
    return Scaffold(
      appBar: AppBar(title: Text(s.checkAgent)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _ctrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: s.agentHint, prefixIcon: const Icon(Icons.badge_outlined)),
            onSubmitted: (_) => _check(),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _check, child: Text(s.search)),
          const SizedBox(height: 16),
          if (reg == '') Panel(child: EmptyNote(s.agentHint)),
          if (reg != null && reg.isNotEmpty) _AgentResult(reg: reg, s: s),
          const SizedBox(height: 8),
          Text(s.ceaSource, style: t.bodySmall),
        ],
      ),
    );
  }
}

class _AgentResult extends ConsumerWidget {
  const _AgentResult({required this.reg, required this.s});
  final String reg;
  final S s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return ref.watch(agentProvider(reg)).when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          error: (_, __) => Panel(child: EmptyNote(s.serverWaking)),
          data: (body) {
            final rows = body['data'];
            if (rows is! List || rows.isEmpty) {
              return Panel(child: EmptyNote(s.agentNotFound, icon: Icons.warning_amber_outlined));
            }
            final a = rows.first as Map;
            return Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _IconBadge(Icons.verified, color: Color(0xFF2E9E7E)),
                        const SizedBox(width: 10),
                        Text(s.agentRegistered, style: t.labelLarge?.copyWith(color: const Color(0xFF2E9E7E))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('${a['name'] ?? ''}', style: t.titleLarge),
                    const SizedBox(height: 4),
                    Text('${a['registration_no'] ?? reg}', style: t.bodyMedium),
                    const SizedBox(height: 10),
                    Text('${a['agency'] ?? ''} (${a['agency_licence'] ?? ''})', style: t.bodyMedium),
                    Text('${a['start'] ?? ''} – ${a['end'] ?? ''}', style: t.bodySmall),
                  ],
                ),
              ),
            );
          },
        );
  }
}

/// A title that wraps between words and never inside one: when its longest word is wider than the
/// line (long street names at 200% text), the whole title is set smaller until that word fits.
class WordWrapTitle extends StatelessWidget {
  const WordWrapTitle(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, box) {
      var widest = 0.0;
      for (final w in text.split(' ')) {
        final tp = TextPainter(text: TextSpan(text: w, style: base), textDirection: TextDirection.ltr, textScaler: scaler)
          ..layout();
        if (tp.width > widest) widest = tp.width;
        tp.dispose();
      }
      final fit = widest > box.maxWidth && widest > 0 ? box.maxWidth / widest * 0.98 : 1.0;
      final size = (base.fontSize ?? 14) * fit;
      return Text(text, style: base.copyWith(fontSize: size));
    });
  }
}
