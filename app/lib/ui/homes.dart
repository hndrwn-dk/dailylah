import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'theme.dart';
import 'widgets.dart';

final _homesQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Homes: HDB block search, watched blocks, comparison and the CEA agent check.
class HomesPage extends ConsumerWidget {
  const HomesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final query = ref.watch(_homesQueryProvider);
    final blocks = ref.watch(hdbBlocksProvider);
    final t = Theme.of(context).textTheme;
    final byKey = {for (final b in blocks.valueOrNull ?? const <HdbBlock>[]) b.key: b};

    final all = blocks.valueOrNull ?? const <HdbBlock>[];
    final postal = isPostalCode(query);
    final byPostal = postal ? searchBlocks(all, query) : const <HdbBlock>[];
    // Postal codes not in the bundle are resolved on OneMap, then matched to a block.
    final postalHit = postal && byPostal.isEmpty && all.isNotEmpty ? ref.watch(addressSearchProvider(query.trim())) : null;
    final postalBlock = postalHit?.valueOrNull?.isNotEmpty == true ? blockForAddress(all, postalHit!.value!.first) : null;
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
                const SizedBox(height: 8),
                PageTitle(s.homesTitle, subtitle: s.homesIntro),
                const SizedBox(height: 18),
                TextField(
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
                  for (final b in results) _BlockTile(block: b),
                ] else ...[
                  if (fav.compareBlocks.length >= 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: FilledButton.icon(
                        icon: const Icon(Icons.compare_arrows),
                        label: Text(s.compareCount(fav.compareBlocks.length)),
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const ComparePage())),
                      ),
                    ),
                  SectionTitle(s.watched, padding: const EdgeInsets.fromLTRB(4, 4, 4, 10)),
                  if (fav.watchedBlocks.isEmpty)
                    Panel(child: EmptyNote(s.emptyWatch, icon: Icons.visibility_outlined))
                  else
                    for (final k in fav.watchedBlocks.keys)
                      if (byKey[k] != null) _BlockTile(block: byKey[k]!),
                  SectionTitle(s.checkAgent),
                  Panel(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: const _IconBadge(Icons.verified_user_outlined),
                      title: Text(s.checkAgent),
                      subtitle: Text(s.agentHint),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AgentCheckPage())),
                    ),
                  ),
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

class _BlockTile extends ConsumerWidget {
  const _BlockTile({required this.block});
  final HdbBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final resale = ref.watch(resaleProvider).valueOrNull;
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(sgd(top.median, compact: true), style: t.displaySmall?.copyWith(fontSize: 24)),
                    Text(top.flatType.toLowerCase(), style: t.bodySmall),
                  ],
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
        color: large ? DL.amber : DL.mint,
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
    final resale = ref.watch(resaleProvider).valueOrNull;
    final rent = ref.watch(rentProvider).valueOrNull;
    final year = (ref.watch(clockProvider).valueOrNull ?? DateTime.now()).year;
    final stats = resale?.blocks[block.key] ?? const <ResaleStat>[];
    final townMedians = resale?.towns[block.town] ?? const <String, int>{};
    final rents = rent?.towns[block.town] ?? const <String, int>{};
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
                          Text(block.street, style: t.headlineSmall),
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
                    _HeroChip(Icons.hourglass_bottom, s.leaseLeft(block.leaseLeft(year))),
                    if (block.floors > 0) _HeroChip(Icons.apartment, s.storeys(block.floors)),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: watching ? DL.amber : DL.ink,
                          foregroundColor: watching ? DL.ink : DL.card,
                        ),
                        icon: Icon(watching ? Icons.visibility : Icons.visibility_outlined),
                        label: Text(watching ? s.watching : s.watch),
                        onPressed: () => ref
                            .read(favoritesProvider.notifier)
                            .toggleWatch(block.key, resale?.countFor(block.key) ?? 0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                        icon: Icon(comparing ? Icons.check : Icons.add),
                        label: Text(comparing ? s.inCompare : s.compare),
                        onPressed: () => ref.read(favoritesProvider.notifier).toggleCompare(block.key),
                      ),
                    ),
                  ],
                ),
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
                  for (final st in stats) _ResaleCard(stat: st, townMedian: townMedians[st.flatType], town: block.town),
                if (rents.isNotEmpty) ...[
                  SectionTitle(s.rentTitle, trailing: Text(rent!.period, style: t.bodySmall)),
                  Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 24,
                            runSpacing: 16,
                            children: [
                              for (final e in rents.entries)
                                Stat(value: sgd(e.value), caption: '${e.key.toLowerCase()} ${s.perMonth}'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(s.rentNote, style: t.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
                SectionTitle(s.dailyLifeScore),
                _ScoreCard(block: block),
                const SizedBox(height: 8),
                Text(s.homesDisclaimer, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
          Text(text, style: Theme.of(context).textTheme.labelMedium),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stat.flatType.toLowerCase(), style: t.labelLarge?.copyWith(color: scheme.primary)),
                      const SizedBox(height: 4),
                      Text(sgd(stat.median), style: t.displayMedium?.copyWith(fontSize: 36)),
                    ],
                  ),
                ),
                Text(s.medianOf(stat.count), style: t.bodySmall),
              ],
            ),
            if (tm != null && maxV > 0) ...[
              const SizedBox(height: 14),
              _Bar(label: s.medianOf(stat.count), value: stat.median / maxV, color: scheme.primary),
              const SizedBox(height: 6),
              _Bar(label: '${s.townMedian(town)} ${sgd(tm, compact: true)}', value: tm / maxV, color: DL.mist),
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
    final pois = ref.watch(poisProvider).valueOrNull;
    final stops = ref.watch(busStopsProvider).valueOrNull;
    final hawkers = ref.watch(hawkersProvider).valueOrNull;
    final dengue = ref.watch(dengueProvider).valueOrNull ?? const <DengueCluster>[];
    if (pois == null || stops == null || hawkers == null) {
      return const Panel(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    }
    final sc = scoreBlock(block, pois: pois, stops: stops, hawkers: hawkers, dengue: dengue);
    final rows = <(IconData, String, String, bool)>[
      (
        Icons.train_outlined,
        s.nearestMrt,
        sc.nearestMrt == null ? '–' : '${_title(sc.nearestMrt!.$1.name)} · ${s.metres(sc.nearestMrt!.$2)}',
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
            ListTile(
              leading: _IconBadge(icon, color: warn ? DL.amber : null),
              title: Text(label, style: t.bodyMedium),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: value.length <= 3 ? t.displaySmall?.copyWith(fontSize: 24) : t.labelLarge),
              ),
            ),
        ],
      ),
    );
  }
}

String _title(String upper) => upper
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

// ---------------------------------------------------------------- compare

class ComparePage extends ConsumerWidget {
  const ComparePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final blocks = ref.watch(hdbBlocksProvider).valueOrNull ?? const <HdbBlock>[];
    final resale = ref.watch(resaleProvider).valueOrNull;
    final pois = ref.watch(poisProvider).valueOrNull;
    final stops = ref.watch(busStopsProvider).valueOrNull ?? const <BusStop>[];
    final hawkers = ref.watch(hawkersProvider).valueOrNull ?? const <Hawker>[];
    final dengue = ref.watch(dengueProvider).valueOrNull ?? const <DengueCluster>[];
    final year = DateTime.now().year;
    final byKey = {for (final b in blocks) b.key: b};
    final chosen = [for (final k in fav.compareBlocks) if (byKey[k] != null) byKey[k]!];
    final t = Theme.of(context).textTheme;

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

    final rows = <(String, String Function(HdbBlock))>[
      (s.builtLabel, (b) => '${b.yearCompleted}'),
      (s.leaseLabel, (b) => '${b.leaseLeft(year)}'),
      for (final ft in flatTypes) (ft.toLowerCase(), (b) => priceFor(b, ft)),
      (s.nearestMrt, (b) => scores[b.key]?.nearestMrt == null ? '–' : s.metres(scores[b.key]!.nearestMrt!.$2)),
      (s.busStops400, (b) => '${scores[b.key]?.busStops400 ?? '–'}'),
      (s.hawkers1km, (b) => '${scores[b.key]?.hawkers1km ?? '–'}'),
      (s.primary1km, (b) => '${scores[b.key]?.primary1km ?? '–'}'),
      (s.parks1km, (b) => '${scores[b.key]?.parks1km ?? '–'}'),
      (s.dengue1km, (b) => '${scores[b.key]?.dengue1km ?? '–'}'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s.compare)),
      body: chosen.isEmpty
          ? Center(child: EmptyNote(s.notAvailable))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Panel(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Table(
                      columnWidths: const {0: FlexColumnWidth(1.4)},
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(children: [
                          const SizedBox(),
                          for (final b in chosen)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  _BlockNumber(b.block),
                                  const SizedBox(height: 6),
                                  Text(b.street, style: t.labelSmall, textAlign: TextAlign.center, maxLines: 2),
                                  TextButton(
                                    onPressed: () => ref.read(favoritesProvider.notifier).toggleCompare(b.key),
                                    child: Text(s.remove),
                                  ),
                                ],
                              ),
                            ),
                        ]),
                        for (var i = 0; i < rows.length; i++)
                          TableRow(
                            decoration: BoxDecoration(
                              color: i.isEven ? Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.5) : null,
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Text(rows[i].$1, style: t.bodySmall),
                              ),
                              for (final b in chosen)
                                Text(rows[i].$2(b), textAlign: TextAlign.center, style: t.titleSmall),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                Text(s.homesDisclaimer, style: t.bodySmall),
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
