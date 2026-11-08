// Commute and all-in cost on "Prices, rent and score" (BlockPage): the trip from the block's
// town to the office area nearest the user's work or school (or one picked), the estimated month,
// and the HDB towns ranked by that trip on the LED board. Rules in logic.dart (wtl*), the same as
// dailylah.sg/where-to-live; the data is the where-to-live bundle. A block takes its town's
// numbers, from the town's MRT station. The saved work or school place only picks the area, here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data.dart';
import '../logic.dart';
import '../providers.dart';
import 'about.dart' show openExternal;
import 'theme.dart';
import 'widgets.dart';

/// Rows shown in "Fits your choices" before "Show all".
const _topRows = 8;

// Session only: a budget, a time limit and the order are quick filters, not settings.
final _budgetProvider = StateProvider.autoDispose<int?>((ref) => null);
final _maxMinutesProvider = StateProvider.autoDispose<int?>((ref) => null);
final _sortProvider = StateProvider.autoDispose<WtlSort>((ref) => WtlSort.time);

/// The town's page on the website (id checked against `[a-z0-9-]+` when the bundle is read).
Uri wtlTownUrl(String id) => Uri.https('dailylah.sg', '/where-to-live/${Uri.encodeComponent(id)}');

/// The choices for the block page and the block comparison: saved area, mode and flat type, with
/// this session's budget and time limit.
WtlChoice wtlSessionChoice(WidgetRef ref, WhereToLive data) {
  final c = wtlChoiceFor(data, ref.watch(favoritesProvider)).choice;
  final budget = ref.watch(_budgetProvider);
  return c.copyWith(
    budget: () => budget != null && budget > 0 && budget <= wtlBudgetLimit(c.mode) ? budget : null,
    maxMinutes: () => ref.watch(_maxMinutesProvider),
  );
}

void _setMode(WidgetRef ref, WhereToLive data, WtlChoice c, WtlMode mode) {
  // A rent budget is not a resale budget: switching drops it (wtlChangeMode).
  final next = wtlChangeMode(data, c, mode);
  ref.read(_budgetProvider.notifier).state = next.budget;
  ref
      .read(favoritesProvider.notifier)
      .update((f) => f.copyWith(wtlMode: mode == WtlMode.buy ? 'buy' : '', wtlFlat: next.flat));
}

/// The block's town to the office area: choices, minutes, transfers, fare and the estimated month.
class BlockCommute extends ConsumerWidget {
  const BlockCommute({super.key, required this.block});
  final HdbBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final async = ref.watch(whereToLiveProvider);
    final data = async.value;
    if (data == null || data.isEmpty) {
      return Panel(
        child: async.isLoading
            ? const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
            : EmptyNote(
                s.wtlNoData,
                icon: Icons.cloud_off,
                action: TextButton(onPressed: () => ref.invalidate(whereToLiveProvider), child: Text(s.retry)),
              ),
      );
    }
    final fav = ref.watch(favoritesProvider);
    final picked = wtlChoiceFor(data, fav);
    final c = wtlSessionChoice(ref, data);
    final area = data.areas.firstWhere((a) => a.id == c.area, orElse: () => data.areas.first);
    final town = wtlTownFor(data, block.town);
    final note = picked.anchor != null
        ? s.wtlRankedFor(area.name, picked.anchor!.kind, picked.meters! / 1000)
        : (data.areas.any((a) => a.id == fav.wtlArea)
            ? s.wtlPickedArea
            : (wtlAnchorPlace(fav.places) == null ? s.wtlPickArea : s.wtlFarArea));
    final row = town == null
        ? null
        : WtlRow(
            town: town,
            commute: town.commute[c.area],
            price: (c.mode == WtlMode.buy ? town.resale : town.rent)[c.flat],
            group: WtlGroup.match);
    final month = row == null ? null : wtlMonthly(c, row);
    final cm = row?.commute;
    InputDecoration label(String text) => InputDecoration(labelText: text, border: const OutlineInputBorder());

    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(note, style: t.bodyMedium?.copyWith(color: DL.muted(context))),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('wtl-area'),
              initialValue: c.area,
              isExpanded: true,
              decoration: label(s.wtlOfficeArea),
              items: [for (final a in data.areas) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: (v) =>
                  v == null ? null : ref.read(favoritesProvider.notifier).update((f) => f.copyWith(wtlArea: v)),
            ),
            const SizedBox(height: 12),
            Text(s.wtlIWantTo, style: t.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<WtlMode>(
              key: const ValueKey('wtl-mode'),
              segments: [
                ButtonSegment(value: WtlMode.rent, label: Text(s.wtlRent)),
                ButtonSegment(value: WtlMode.buy, label: Text(s.wtlBuy)),
              ],
              selected: {c.mode},
              showSelectedIcon: false,
              onSelectionChanged: (v) => _setMode(ref, data, c, v.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('wtl-flat-${c.mode.name}'),
              initialValue: c.flat,
              isExpanded: true,
              decoration: label(s.wtlFlatType),
              items: [
                for (final f in wtlFlatTypes(data, c.mode)) DropdownMenuItem(value: f, child: Text(s.wtlFlatName(f)))
              ],
              onChanged: (v) =>
                  v == null ? null : ref.read(favoritesProvider.notifier).update((f) => f.copyWith(wtlFlat: v)),
            ),
            const Divider(height: 28),
            if (town == null)
              EmptyNote(s.wtlNotInData)
            else ...[
              Text('${town.name} · ${s.wtlFromStation(town.station)}',
                  key: const ValueKey('wtl-from'), style: t.titleSmall),
              const SizedBox(height: 12),
              if (cm == null || cm.sameArea)
                Text(s.wtlRoute(row!), style: t.titleMedium)
              else ...[
                // Two by two: minutes | transfers, fare a trip | hours a month.
                _Pair(
                  _Figure(cm.min == null ? '–' : '${cm.min} ${s.min}', s.wtlLine(WtlLineKey.time, area.name, c)),
                  _Figure(cm.transfers == null ? '–' : s.wtlTransfersValue(cm.transfers!), s.wtlTransfersCaption),
                ),
                const SizedBox(height: 14),
                _Pair(
                  _Figure(cm.fare == null ? '–' : 'S\$${(cm.fare! / 100).toStringAsFixed(2)}', s.wtlPerTrip),
                  _Figure(month == null ? '–' : s.wtlHours(month.hours), s.wtlHoursLabel),
                ),
                if (month != null) ...[
                  const Divider(height: 28),
                  if (c.mode == WtlMode.rent) ...[
                    _Figure(month.total == null ? '–' : '≈ ${sgd(month.total!)}', s.wtlAllInLabel, large: true),
                    if (month.total != null && row!.price != null && month.fares != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(s.wtlAllInParts(sgd(row.price!.median), sgd(month.fares!)),
                            key: const ValueKey('wtl-all-in-parts'),
                            style: t.bodySmall?.copyWith(color: DL.muted(context))),
                      ),
                  ] else
                    _Figure(month.fares == null ? '–' : '≈ ${sgd(month.fares!)}', s.wtlFaresLabel, large: true),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Two figures side by side, each half the width.
class _Pair extends StatelessWidget {
  const _Pair(this.left, this.right);
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: left), const SizedBox(width: 16), Expanded(child: right)],
      );
}

/// A figure on one line (scaled down rather than broken) over its caption.
class _Figure extends StatelessWidget {
  const _Figure(this.value, this.caption, {this.large = false});
  final String value;
  final String caption;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, style: large ? t.displayMedium?.copyWith(fontSize: 40) : t.displaySmall),
        ),
        const SizedBox(height: 2),
        Text(caption, style: t.bodySmall),
      ],
    );
  }
}

/// HDB towns ranked by the trip to the office area on the dark LED board, with a budget, a time
/// limit, the order, and the fastest and best-value towns; the block's own town is marked.
class TownsBoard extends ConsumerStatefulWidget {
  const TownsBoard({super.key, required this.block});
  final HdbBlock block;

  @override
  ConsumerState<TownsBoard> createState() => _TownsBoardState();
}

class _TownsBoardState extends ConsumerState<TownsBoard> {
  String? _open;
  bool _showAll = false;
  final _budgetText = TextEditingController();

  @override
  void dispose() {
    _budgetText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final data = ref.watch(whereToLiveProvider).value;
    if (data == null || data.isEmpty) return const SizedBox.shrink();
    // A mode switch on the commute card drops the budget: clear the field with it.
    ref.listen(_budgetProvider, (_, next) {
      if (next == null && _budgetText.text.isNotEmpty) _budgetText.clear();
    });
    final c = wtlSessionChoice(ref, data);
    final sort = ref.watch(_sortProvider);
    final groups = wtlRank(data, c);
    final picks = wtlHighlights(groups);
    final mine = wtlTownFor(data, widget.block.town)?.id;
    final match = wtlSorted(groups[WtlGroup.match]!, sort);
    final noPrice = wtlSorted(groups[WtlGroup.noPrice]!, sort);
    final other = wtlSorted(groups[WtlGroup.other]!, sort);
    // The block's own town always shows, after the top rows when it ranks lower.
    final shown = _showAll || match.length <= _topRows
        ? match
        : [...match.take(_topRows), ...match.skip(_topRows).where((r) => r.town.id == mine)];
    final dim = t.bodySmall?.copyWith(color: DL.ledDim);
    InputDecoration label(String text) => InputDecoration(labelText: text, border: const OutlineInputBorder());
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text(text, style: t.labelLarge?.copyWith(color: DL.ledDim)),
        );
    Widget rows(List<WtlRow> list) => Column(
          children: [
            for (final r in list)
              _TownLine(
                row: r,
                choice: c,
                mine: r.town.id == mine,
                open: _open == r.town.id,
                onOpen: (id) => setState(() => _open = _open == id ? null : id),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('wtl-budget'),
                  controller: _budgetText,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                  decoration: label(s.wtlBudgetLabel(c.mode)).copyWith(hintText: s.wtlAny),
                  onChanged: (v) => ref.read(_budgetProvider.notifier).state = int.tryParse(v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  key: const ValueKey('wtl-max'),
                  initialValue: c.maxMinutes,
                  isExpanded: true,
                  decoration: label(s.wtlTravelTime),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text(s.wtlAnyTime)),
                    for (final m in wtlMaxMinutes) DropdownMenuItem<int?>(value: m, child: Text(s.wtlUpTo(m))),
                  ],
                  onChanged: (v) => ref.read(_maxMinutesProvider.notifier).state = v,
                ),
                const SizedBox(height: 12),
                Text(s.wtlSortBy, style: t.labelLarge),
                const SizedBox(height: 6),
                SegmentedButton<WtlSort>(
                  key: const ValueKey('wtl-sort'),
                  segments: [
                    ButtonSegment(value: WtlSort.time, label: Text(s.wtlSortTime)),
                    ButtonSegment(value: WtlSort.price, label: Text(s.wtlSortPrice)),
                  ],
                  selected: {sort},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => ref.read(_sortProvider.notifier).state = v.first,
                ),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          decoration: BoxDecoration(
            color: DL.board,
            borderRadius: BorderRadius.circular(DL.radius),
            border: Border.all(color: DL.edge(context), width: DL.stroke),
            boxShadow: DL.hard(context),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.wtlTownsSub(c.flat, c.mode), style: dim),
                if (picks != null) ...[
                  const SizedBox(height: 10),
                  _Pick(label: s.wtlFastest, row: picks.fastest, choice: c),
                  _Pick(label: s.wtlBestValue, row: picks.value, choice: c),
                ],
                heading(s.wtlFits(match.length)),
                if (match.isEmpty)
                  Padding(padding: const EdgeInsets.all(4), child: Text(s.wtlNothingFits, style: dim))
                else
                  rows(shown),
                if (shown.length < match.length)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      key: const ValueKey('wtl-show-all'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DL.led,
                        backgroundColor: Colors.transparent,
                        side: const BorderSide(color: DL.led, width: 2),
                      ),
                      onPressed: () => setState(() => _showAll = true),
                      child: Text(s.wtlShowAll(match.length)),
                    ),
                  ),
                if (noPrice.isNotEmpty) ...[heading(s.wtlNoPriceGroup(c.flat, noPrice.length)), rows(noPrice)],
                if (other.isNotEmpty)
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const ValueKey('wtl-outside'),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                      childrenPadding: EdgeInsets.zero,
                      initiallyExpanded: match.isEmpty,
                      iconColor: DL.ledDim,
                      collapsedIconColor: DL.ledDim,
                      title: Text(s.wtlOutside(other.length), style: t.labelLarge?.copyWith(color: DL.ledDim)),
                      children: [rows(other)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Pick extends ConsumerWidget {
  const _Pick({required this.label, required this.row, required this.choice});
  final String label;
  final WtlRow row;
  final WtlChoice choice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final time = row.commute!.sameArea ? s.wtlHere : '${row.commute!.min} ${s.min}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label: ', style: t.labelMedium?.copyWith(color: DL.ledDim)),
          TextSpan(
            text: '${row.town.name} · $time · ${s.wtlShortPrice(choice.mode, row.price)}',
            style: t.titleMedium?.copyWith(fontFamily: DL.display, color: DL.led),
          ),
          TextSpan(text: '\n${s.wtlAllIn(wtlMonthly(choice, row))}', style: t.bodySmall?.copyWith(color: DL.ledDim)),
        ]),
      ),
    );
  }
}

class _TownLine extends ConsumerWidget {
  const _TownLine(
      {required this.row, required this.choice, required this.mine, required this.open, required this.onOpen});
  final WtlRow row;
  final WtlChoice choice;
  final bool mine;
  final bool open;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final color =
        row.group == WtlGroup.other ? const Color(0xFF8C9DA2) : (row.group == WtlGroup.noPrice ? DL.ledDim : DL.led);
    final led = TextStyle(fontFamily: DL.display, fontWeight: FontWeight.w700, color: color, height: 1.05);
    final c = row.commute;
    final eta = c == null ? '--' : (c.sameArea ? s.wtlHere : '${c.min}');
    final detail = t.bodySmall?.copyWith(color: DL.ledDim);
    return Container(
      decoration: mine ? BoxDecoration(color: const Color(0x1FFFB627), borderRadius: BorderRadius.circular(8)) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: const Color(0x33FFB627)),
          InkWell(
            key: ValueKey('wtl-row-${row.town.id}'),
            onTap: () => onOpen(row.town.id),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mine)
                    Text(s.wtlYourTown, style: t.labelSmall?.copyWith(color: DL.led, fontWeight: FontWeight.w700)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: Text(row.town.name, style: led.copyWith(fontSize: 24))),
                      const SizedBox(width: 8),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: eta, style: led.copyWith(fontSize: 24)),
                          if (c != null && !c.sameArea) TextSpan(text: ' ${s.min}', style: led.copyWith(fontSize: 14)),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.wtlShortPrice(choice.mode, row.price),
                    style: row.price == null ? detail : led.copyWith(fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (row.reason != null)
                    Text(s.wtlReason(row.reason, choice.maxMinutes),
                        style: detail?.copyWith(color: DL.led, fontWeight: FontWeight.w700)),
                  Text(s.wtlRoute(row), style: detail),
                  Text(s.wtlPriceDetail(choice, row.price), style: detail),
                  if (row.commute != null)
                    Text(s.wtlAllIn(wtlMonthly(choice, row)), style: detail?.copyWith(color: DL.led)),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: DL.led, padding: EdgeInsets.zero),
                    onPressed: () => openExternal(
                        context, wtlTownUrl(row.town.id), s.cannotOpen(wtlTownUrl(row.town.id).toString())),
                    child: Text(s.wtlMoreAbout(row.town.name)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The comparison's commute lines for these blocks, with the choices as saved.
({WtlChoice choice, WtlArea? area, List<WtlLine> lines})? wtlCompareLinesFor(WidgetRef ref, List<HdbBlock> blocks) {
  final data = ref.watch(whereToLiveProvider).value;
  if (data == null || data.isEmpty) return null;
  final c = wtlChoiceFor(data, ref.watch(favoritesProvider)).choice;
  final area = data.areas.where((a) => a.id == c.area).firstOrNull;
  return (choice: c, area: area, lines: wtlBlockLines(data, c, [for (final b in blocks) b.town]));
}

/// A comparison cell: the words, bold with a "Best" tag on the best of its line.
class WtlCellText extends ConsumerWidget {
  const WtlCellText({super.key, required this.line, required this.cell, required this.mode});
  final WtlLineKey line;
  final WtlCell cell;
  final WtlMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final bestBg = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF17322F) : DL.mint;
    final style = t.titleSmall?.copyWith(fontWeight: cell.best ? FontWeight.w800 : null);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: cell.best ? BoxDecoration(color: bestBg, borderRadius: BorderRadius.circular(8)) : null,
      child: Column(
        children: [
          // One line, scaled down when the column is narrow, so nothing breaks mid-word.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(s.wtlCell(line, cell, mode), maxLines: 1, textAlign: TextAlign.center, style: style),
          ),
          if (cell.kind == WtlCellKind.inAreaRent)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(s.wtlRentOnly, maxLines: 1, style: t.labelSmall?.copyWith(color: DL.muted(context))),
            ),
          if (cell.best)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: DL.goText(context), borderRadius: BorderRadius.circular(6)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                s.wtlBest,
                style:
                    t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.w700),
              ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "8 Nov 2026" for a bundle's ISO time, in Singapore time; '' when unreadable.
String dataDay(String iso) {
  final d = DateTime.tryParse(iso)?.toUtc().add(const Duration(hours: 8));
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

final _hdbUrl = Uri.https('www.hdb.gov.sg', '/');

/// The one disclaimer line at the foot of the block page and the comparison, with "About this data".
class DataFooter extends ConsumerWidget {
  const DataFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final wtl = ref.watch(whereToLiveProvider).value;
    final day = wtl == null ? '' : dataDay(wtl.generatedAt);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(s.dataFooter(day), style: t.bodySmall?.copyWith(color: DL.muted(context))),
          TextButton.icon(
            key: const ValueKey('about-data'),
            style: TextButton.styleFrom(foregroundColor: DL.goText(context), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => showAboutData(context),
            icon: const Icon(Icons.info_outline, size: 18),
            label: Text(s.aboutData),
          ),
        ],
      ),
    );
  }
}

/// Sources, licence, how the numbers are made, and that they are past transactions, not listings.
Future<void> showAboutData(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final s = ref.watch(stringsProvider);
          final t = Theme.of(context).textTheme;
          Widget part(String title, String text) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleSmall),
                    const SizedBox(height: 4),
                    Text(text, style: t.bodyMedium),
                  ],
                ),
              );
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(s.aboutData, style: t.headlineSmall),
                const SizedBox(height: 14),
                part(s.aboutDataSources, s.aboutDataSourcesText),
                part(s.aboutDataMethod, s.aboutDataMethodText),
                part(s.aboutDataListings, s.aboutDataListingsText),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('check-eligibility'),
                    style: TextButton.styleFrom(foregroundColor: DL.goText(context), padding: EdgeInsets.zero),
                    onPressed: () => openExternal(context, _hdbUrl, s.cannotOpen(_hdbUrl.toString())),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(s.checkEligibility),
                  ),
                ),
                ],
              ),
            ),
          );
        },
      ),
    );
