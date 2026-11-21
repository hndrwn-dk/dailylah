import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'theme.dart';
import 'widgets.dart';

/// Which period History shows. Kept while the app runs.
final historyPeriodProvider = StateProvider<HistoryPeriod>((ref) => HistoryPeriod.week);

/// Which kinds History shows (empty = all). Kept while the app runs.
final historyKindProvider = StateProvider<HistoryKind?>((ref) => null);

/// History tab: trips, parking and meals the user logged, by day, with totals for the period.
/// Everything here lives on the phone only (Habits).
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key, this.controller});

  /// Main list scroll, owned by the shell.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final on = ref.watch(favoritesProvider.select((f) => f.learnHabits));
    final habits = ref.watch(habitsProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final period = ref.watch(historyPeriodProvider);
    final kind = ref.watch(historyKindProvider);
    // The totals are the filter: they count the whole period, whatever kind is shown.
    final all = historyEntries(habits, since: historySince(period, now));
    final total = historySummary(all);
    final entries = historyOfKinds(all, {if (kind != null) kind});
    final bars = historySpendBars(entries, period, now);
    final hawkers = {for (final h in ref.watch(hawkersProvider).value ?? const <Hawker>[]) h.id: h.name};

    return Scaffold(
      body: ListView(
        controller: controller,
        padding: const EdgeInsets.only(bottom: kNavClearance),
        children: [
          HeroHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                PageTitle(s.historyTitle, subtitle: s.historySubtitle),
                const SizedBox(height: 14),
                _PeriodRail(
                  period: period,
                  onPick: (p) => ref.read(historyPeriodProvider.notifier).state = p,
                ),
                // Nothing logged in the period: no row of zeros, the note below says what to do.
                if (all.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _KindTiles(
                    total: total,
                    entries: all.length,
                    kind: kind,
                    onPick: (k) => ref.read(historyKindProvider.notifier).state = k,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            // Totals, notes and the empty state span both columns on a wide window; the days share them.
            child: CardColumns(
              children: [
                if (!on)
                  FullWidth(
                    child: Panel(
                    child: EmptyNote(
                      s.historyOff,
                      icon: Icons.history,
                      action: FilledButton(
                        onPressed: () =>
                            ref.read(favoritesProvider.notifier).update((f) => f.copyWith(learnHabits: true)),
                        child: Text(s.historyTurnOn),
                      ),
                    ),
                  ),
                  ),
                // Where the money went: a bar per day (per month for "all"), split by kind.
                // "All" draws the last 12 months: older costs alone make no chart.
                if (bars.any((b) => b.cents > 0))
                  FullWidth(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SpendChart(
                        // A new period or filter starts without a picked bar.
                        key: ValueKey((period, kind)),
                        bars: bars,
                        period: period,
                        now: now,
                        insight: historySpendInsight(bars, period, now,
                            previousCents: historyPreviousCents(habits, period, now, {if (kind != null) kind})),
                      ),
                    ),
                  ),
                if (on && entries.isEmpty) ...[
                  FullWidth(child: Panel(child: EmptyNote(s.historyEmpty, icon: Icons.history))),
                ],
                for (final (day, list) in historyByDay(entries)) ...[
                  SectionTitle(_dayLabel(s, day, now)),
                  Panel(
                    child: Column(
                      children: [
                        for (final e in list) _EntryTile(entry: e, hawkers: hawkers),
                      ],
                    ),
                  ),
                ],
                // Removing comes after the list: one row by a swipe (said once here), or all that
                // is shown, e.g. meals logged by mistake.
                if (entries.isNotEmpty)
                  FullWidth(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                      child: Text(s.historySwipeHint, style: t.bodySmall),
                    ),
                  ),
                if (entries.isNotEmpty)
                  FullWidth(
                    child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: DL.stopText(context)),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(s.historyRemoveShown(entries.length)),
                      onPressed: () async {
                        final notifier = ref.read(habitsProvider.notifier);
                        final before = ref.read(habitsProvider);
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            content: Text(s.historyRemoveAsk(entries.length)),
                            actions: [
                              DialogButtons(
                                cancelLabel: s.cancel,
                                confirmLabel: s.remove,
                                onCancel: () => Navigator.of(d).pop(false),
                                onConfirm: () => Navigator.of(d).pop(true),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await notifier.forgetAll(entries);
                        showActionSnackBar(messenger, s.historyDeleted,
                            actionLabel: s.undo, onAction: () => notifier.restore(before));
                      },
                    ),
                  ),
                  ),
                // How the costs are made, after the list like the notes on Nearby: above the
                // chart it pushed the numbers down the page.
                if (entries.isNotEmpty)
                  FullWidth(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: Text(s.historyCostNote, style: t.bodySmall),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

/// The period as one rail: this week, this month, all time. The pick is amber.
class _PeriodRail extends ConsumerWidget {
  const _PeriodRail({required this.period, required this.onPick});
  final HistoryPeriod period;
  final ValueChanged<HistoryPeriod> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final edge = DL.edge(context);
    final base = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, box) {
      // One size for the three names: when the longest does not fit its third of the rail
      // (large text), all three are drawn smaller together.
      var widest = 0.0;
      for (final p in HistoryPeriod.values) {
        final tp = TextPainter(
            text: TextSpan(text: s.historyPeriod(p.name), style: base), textDirection: TextDirection.ltr, textScaler: scaler)
          ..layout();
        if (tp.width > widest) widest = tp.width;
        tp.dispose();
      }
      final room = (box.maxWidth - 11) / HistoryPeriod.values.length - 10;
      final fit = widest > room && widest > 0 ? room / widest : 1.0;
      final style = base?.copyWith(fontSize: (base.fontSize ?? 14) * fit);
      return _rail(context, s, edge, style);
    });
  }

  Widget _rail(BuildContext context, S s, Color edge, TextStyle? style) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: edge, width: DL.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final p in HistoryPeriod.values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: p == period,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onPick(p),
                      child: Ink(
                        decoration: p == period
                            ? BoxDecoration(
                                color: DL.amber,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: edge, width: 2),
                              )
                            : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(s.historyPeriod(p.name),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: style?.copyWith(
                                      color: p == period ? DL.ink : Theme.of(context).colorScheme.onSurface)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The totals of the period as the filter: All (what was spent), Trips, Parking and Meals, each
/// a tile with its figure. Four in a row, two when that is too narrow for the figures.
class _KindTiles extends ConsumerWidget {
  const _KindTiles({required this.total, required this.entries, required this.kind, required this.onPick});
  final HistorySummary total;
  final int entries;
  final HistoryKind? kind;
  final ValueChanged<HistoryKind?> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final tiles = <(HistoryKind?, String, String, String)>[
      (null, s.money(total.costCents), s.historyAll, s.historyEntriesCount(entries)),
      (HistoryKind.trip, '${total.trips}', s.historyTrips, total.trips == 0 ? '' : s.durationShort(total.tripMinutes)),
      (HistoryKind.parking, '${total.parkings}', s.historyParking, total.parkings == 0 ? '' : s.durationShort(total.parkMinutes)),
      (HistoryKind.meal, '${total.meals}', s.historyMeals, total.mealsPriced == 0 ? '' : s.money(total.mealCents)),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 300 ? 2 : 4;
      return Column(
        children: [
          for (var i = 0; i < tiles.length; i += cols)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = i; j < i + cols; j++) ...[
                      if (j > i) const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 3, right: 3),
                          child: _KindTile(
                            figure: tiles[j].$2,
                            name: tiles[j].$3,
                            caption: tiles[j].$4,
                            selected: tiles[j].$1 == kind,
                            onTap: () => onPick(tiles[j].$1),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.figure,
    required this.name,
    required this.caption,
    required this.selected,
    required this.onTap,
  });
  final String figure;
  final String name;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final edge = DL.edge(context);
    final fg = selected ? DL.ink : Theme.of(context).colorScheme.onSurface;
    final r = BorderRadius.circular(12);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? DL.amber : Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: r,
        border: Border.all(color: edge, width: DL.stroke),
        boxShadow: selected ? [BoxShadow(color: edge, offset: const Offset(3, 3))] : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A long sum is drawn smaller, never cut.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(figure,
                          maxLines: 1, style: t.displaySmall?.copyWith(fontSize: 22, height: 1.1, color: fg)),
                    ),
                    Text(name, style: t.labelLarge?.copyWith(color: fg)),
                    if (caption.isNotEmpty)
                      Text(caption, style: t.bodySmall?.copyWith(color: selected ? DL.ink : null)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Today", "Yesterday" or "Wed 18/11".
String _dayLabel(S s, DateTime day, DateTime now) {
  final today = dateOnly(now);
  final d = dateOnly(day);
  if (d == today) return s.today;
  if (d == DateTime(today.year, today.month, today.day - 1)) return s.yesterday;
  return '${s.dayShort[d.weekday - 1]} ${shortDate(d)}';
}

/// Spending as stacked bars (meals, transport, parking) with the totals per kind and a few
/// lines of what stands out. Tap a bar to read its day or month.
class _SpendChart extends StatefulWidget {
  const _SpendChart({super.key, required this.bars, required this.period, required this.now, required this.insight});
  final List<SpendBar> bars;
  final HistoryPeriod period;
  final DateTime now;
  final SpendInsight insight;

  @override
  State<_SpendChart> createState() => _SpendChartState();
}

class _SpendChartState extends State<_SpendChart> {
  static const _height = 120.0;
  static const _maxBar = 56.0;
  int? _picked;

  bool get _byMonth => widget.period == HistoryPeriod.all;

  String _when(S s, SpendBar b) => _byMonth
      ? '${s.monthShort[b.start.month - 1]} ${b.start.year}'
      : '${s.dayShort[b.start.weekday - 1]} ${shortDate(b.start)}';

  /// Which bars get a label under them: every day of a week, every 7th day of a month, and
  /// for months all of them up to 6, else every 3rd.
  bool _labelled(int i) => switch (widget.period) {
        HistoryPeriod.week => true,
        HistoryPeriod.month => i % 7 == 0,
        HistoryPeriod.all => widget.bars.length <= 6 || i % 3 == 0,
      };

  String _label(S s, SpendBar b) => switch (widget.period) {
        HistoryPeriod.week => s.dayShort[b.start.weekday - 1].substring(0, 1),
        HistoryPeriod.month => '${b.start.day}',
        HistoryPeriod.all => s.monthShort[b.start.month - 1],
      };

  @override
  Widget build(BuildContext context) {
    final s = const S();
    final t = Theme.of(context).textTheme;
    final bars = widget.bars;
    final ins = widget.insight;
    final week = widget.period == HistoryPeriod.week;
    final meal = DL.amber, trip = DL.goText(context), parking = DL.muted(context);
    var max = 1, trips = 0, parkings = 0, meals = 0;
    for (final b in bars) {
      if (b.cents > max) max = b.cents;
      trips += b.tripCents;
      parkings += b.parkingCents;
      meals += b.mealCents;
    }
    final picked = _picked != null && _picked! < bars.length ? bars[_picked!] : null;
    // The total leads the card, with the average beside what it covers.
    final average = ins.averageCents <= 0
        ? null
        : _byMonth
            ? (bars.length > 1 ? s.spendAverageMonth(s.money(ins.averageCents)) : null)
            : s.spendAverageDay(s.money(ins.averageCents));
    final lines = [
      if (ins.top case final b?)
        _byMonth ? s.spendTopMonth(_when(s, b), s.money(b.cents)) : s.spendTop(_when(s, b), s.money(b.cents)),
      if (ins.previousCents case final p? when p > 0)
        p == ins.cents
            ? s.spendSameAsLast(week: week)
            : s.spendVsLast(s.money((ins.cents - p).abs()), more: ins.cents > p, week: week),
    ].whereType<String>().toList();

    // Flat: the card opens nothing (only its bars can be tapped, to read them).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(DL.radius),
        border: Border.all(color: DL.edge(context), width: DL.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.money(trips + parkings + meals), style: t.displaySmall?.copyWith(fontSize: 28, height: 1.1)),
            Text([s.spentIn(widget.period.name), if (average != null) average].join(' · '), style: t.bodySmall),
            const SizedBox(height: 8),
            Text(
              picked == null
                  ? (_byMonth ? s.spendTapHintMonth : s.spendTapHint)
                  : s.spendBar(_when(s, picked), s.money(picked.cents)),
              style: picked == null ? t.bodySmall : t.labelMedium,
            ),
            const SizedBox(height: 10),
            // One description for screen readers instead of up to 31 bars.
            Semantics(
              label: [
                for (final b in bars)
                  if (b.cents > 0) s.spendBar(_when(s, b), s.money(b.cents)),
              ].join(', '),
              child: ExcludeSemantics(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // A lone month (or two) keeps the width of a bar, not of the card.
                    final w = (box.maxWidth / bars.length).clamp(0.0, _maxBar);
                    final gap = w > 16 ? 3.0 : 1.0;
                    Widget part(Color c, int cents, {bool top = false}) => Container(
                          height: _height * cents / max,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: top ? const BorderRadius.vertical(top: Radius.circular(3)) : null,
                          ),
                        );
                    return Column(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => setState(() {
                            final i = (d.localPosition.dx / w).floor();
                            // Beside the last bar there is nothing to pick.
                            _picked = i < 0 || i >= bars.length || _picked == i ? null : i;
                          }),
                          child: SizedBox(
                            height: _height,
                            width: box.maxWidth,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final (i, b) in bars.indexed)
                                  SizedBox(
                                    width: w,
                                    child: Opacity(
                                      opacity: picked == null || _picked == i ? 1 : 0.4,
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: gap),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            // Top to bottom: parking, transport, meals.
                                            if (b.parkingCents > 0) part(parking, b.parkingCents, top: true),
                                            if (b.tripCents > 0) part(trip, b.tripCents, top: b.parkingCents == 0),
                                            if (b.mealCents > 0)
                                              part(meal, b.mealCents, top: b.parkingCents + b.tripCents == 0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Container(height: 1.5, color: DL.edge(context)),
                        const SizedBox(height: 4),
                        // Labels sit under their bar; a wide one may run past the next bars.
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Full width, so a label's left edge is its bar's.
                            SizedBox(width: box.maxWidth, child: Text(' ', style: t.bodySmall)),
                            for (final (i, b) in bars.indexed)
                              if (_labelled(i))
                                Positioned(
                                  left: i * w,
                                  width: week ? w : null,
                                  child: Text(_label(s, b),
                                      style: t.bodySmall,
                                      maxLines: 1,
                                      softWrap: false,
                                      textAlign: week ? TextAlign.center : TextAlign.start),
                                ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final (c, name, cents) in [
                  (meal, s.historyMeals, meals),
                  (trip, s.spendTransport, trips),
                  (parking, s.historyParking, parkings),
                ])
                  if (cents > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 6),
                        Flexible(child: Text('$name ${s.money(cents)}', style: t.labelMedium)),
                      ],
                    ),
              ],
            ),
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final l in lines) Text(l, style: t.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// One History row; swipe to remove it (with Undo).
class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.hawkers});
  final HistoryEntry entry;
  final Map<String, String> hawkers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final e = entry;
    final (IconData icon, String title, String detail) = switch (e.source) {
      final TripLog t => (
          _modeIcon(t.mode),
          _route(s, t.route),
          [s.durationShort(t.minutes), if (t.rainy) s.rainyTag].join(' · '),
        ),
      final ParkLog p => (Icons.local_parking, p.name.isEmpty ? s.historyParking : p.name, s.durationShort(p.minutes)),
      final MealLog m => (Icons.ramen_dining_outlined, hawkers[m.hawkerId] ?? m.name ?? s.historyMeals, ''),
      _ => (Icons.history, '', ''),
    };
    return Dismissible(
      key: ObjectKey(e.source),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) async {
        final notifier = ref.read(habitsProvider.notifier);
        final before = ref.read(habitsProvider);
        final messenger = ScaffoldMessenger.of(context);
        await notifier.forget(e);
        showActionSnackBar(messenger, s.historyDeleted, actionLabel: s.undo, onAction: () => notifier.restore(before));
      },
      child: PlaceRow(
        icon: icon,
        title: title,
        // When it was, then how long it took.
        subtitle: [clockLabel(e.at), if (detail.isNotEmpty) detail].join(' · '),
        // What it cost, large; an estimate says so in words. With no cost yet the row offers
        // to add one.
        figure: e.costCents == null ? null : s.money(e.costCents!),
        figureLabel: e.estimated ? s.historyEstimate : '',
        action: e.source is MealLog ? s.historyAddPrice : s.historyAddCost,
        onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => switch (e.source) {
                final MealLog m => _MealSheet(meal: m, title: title),
                _ => _CostSheet(entry: e, title: title),
              },
            ),
      ),
    );
  }

  static IconData _modeIcon(String? mode) => switch (mode) {
        'car' => Icons.directions_car_outlined,
        'motorcycle' => Icons.two_wheeler,
        'bicycle' => Icons.pedal_bike,
        'taxi' => Icons.local_taxi_outlined,
        'walk' => Icons.directions_walk,
        _ => Icons.directions_bus_outlined,
      };

  /// "home>work" → "Home → Work"; a planned trip keeps its names ("Here → ION Orchard").
  static String _route(S s, String route) {
    final ends = tripRouteEnds(route);
    return ends == null ? route : s.routeLabel(s.routeEnd(ends.$1), s.routeEnd(ends.$2));
  }
}

/// Edit a logged meal: its optional price (chips or "Other") and the day and time it was eaten.
class _MealSheet extends ConsumerStatefulWidget {
  const _MealSheet({required this.meal, required this.title});
  final MealLog meal;
  final String title;

  @override
  ConsumerState<_MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends ConsumerState<_MealSheet> {
  late int? _price = widget.meal.priceCents;
  late DateTime _at = widget.meal.at;

  Future<void> _pickDate(S s) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: dateOnly(_at),
      firstDate: mealFirstDay(_at, now),
      lastDate: dateOnly(now),
      helpText: s.mealDateHelp,
    );
    if (picked == null || !mounted) return;
    setState(() => _at = mealOnDay(_at, picked, DateTime.now()));
  }

  Future<void> _pickTime(S s) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      helpText: s.mealTimeHelp,
    );
    if (picked == null || !mounted) return;
    final at = mealTimeOn(_at, picked.hour, picked.minute, DateTime.now());
    if (at == null) {
      showActionSnackBar(messenger, s.mealTimeFuture);
      return;
    }
    setState(() => _at = at);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final notifier = ref.read(habitsProvider.notifier);
    // Scrolls when it is taller than the sheet may be (large text on a small phone).
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: t.titleMedium),
          const SizedBox(height: 12),
          Text(s.mealPrice, style: t.labelMedium),
          const SizedBox(height: 4),
          MealPricePicker(s: s, value: _price, onChanged: (v) => setState(() => _price = v)),
          const SizedBox(height: 8),
          // The day first: a meal logged a day late moves to the day it was eaten.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(_dayLabel(s, _at, DateTime.now()), style: t.bodyMedium),
              TextButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text(s.mealChangeDate),
                onPressed: () => _pickDate(s),
              ),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(s.mealTimeAt(clockLabel(_at)), style: t.bodyMedium),
              TextButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(s.mealChangeTime),
                onPressed: () => _pickTime(s),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              final nav = Navigator.of(context);
              await notifier.editMeal(widget.meal, widget.meal.withTime(_at).withPrice(_price));
              nav.pop();
            },
            child: Text(s.save),
          ),
          if (_price != null)
            TextButton(
              onPressed: () => setState(() => _price = null),
              child: Text(s.mealPriceClear),
            ),
        ],
      ),
    );
  }
}

/// Set what a trip or parking cost: start from the estimate (or the saved amount), type the
/// real one, or go back to the estimate.
class _CostSheet extends ConsumerStatefulWidget {
  const _CostSheet({required this.entry, required this.title});
  final HistoryEntry entry;
  final String title;

  @override
  ConsumerState<_CostSheet> createState() => _CostSheetState();
}

class _CostSheetState extends ConsumerState<_CostSheet> {
  late final _ctrl = TextEditingController(
    text: widget.entry.costCents == null ? '' : (widget.entry.costCents! / 100).toStringAsFixed(2),
  );
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final e = widget.entry;
    final estimate = switch (e.source) {
      final TripLog x => tripFareEstimate(x),
      final ParkLog x => parkingEstimate(x),
      _ => null,
    };
    final note = switch (e.source) {
      TripLog() => estimate == null ? s.costNoFareEstimate : s.costFareNote,
      ParkLog() => estimate == null ? s.costNoParkingEstimate : s.costParkingNote,
      _ => '',
    };
    final notifier = ref.read(habitsProvider.notifier);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: t.titleMedium),
          const SizedBox(height: 4),
          if (estimate != null) Text(s.costEstimate(s.money(estimate)), style: t.bodyMedium),
          Text(note, style: t.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(prefixText: r'$ ', labelText: s.costLabel, errorText: _error),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              final cents = parseCents(_ctrl.text);
              if (cents == null) {
                setState(() => _error = s.costInvalid);
                return;
              }
              final nav = Navigator.of(context);
              await notifier.setCost(e, cents);
              nav.pop();
            },
            child: Text(s.save),
          ),
          if (!e.estimated || estimate == null)
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                await notifier.setCost(e, null);
                nav.pop();
              },
              child: Text(estimate == null ? s.costClear : s.costUseEstimate),
            ),
        ],
      ),
    );
  }
}
