import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
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
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final period = ref.watch(historyPeriodProvider);
    final kind = ref.watch(historyKindProvider);
    final entries =
        historyOfKinds(historyEntries(habits, since: historySince(period, now)), {if (kind != null) kind});
    final sum = historySummary(entries);
    final hawkers = {for (final h in ref.watch(hawkersProvider).valueOrNull ?? const <Hawker>[]) h.id: h.name};

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
                PillRow(
                  items: [
                    for (final p in HistoryPeriod.values) (p.name, Icons.calendar_today_outlined, s.historyPeriod(p.name)),
                  ],
                  selected: period.name,
                  onTap: (k) => ref.read(historyPeriodProvider.notifier).state = HistoryPeriod.values.byName(k),
                ),
                const SizedBox(height: 10),
                PillRow(
                  items: [
                    ('all', Icons.list, s.historyAll),
                    ('trip', Icons.route_outlined, s.historyTrips),
                    ('parking', Icons.local_parking, s.historyParking),
                    ('meal', Icons.ramen_dining_outlined, s.historyMeals),
                  ],
                  selected: kind?.name ?? 'all',
                  onTap: (k) =>
                      ref.read(historyKindProvider.notifier).state = k == 'all' ? null : HistoryKind.values.byName(k),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!on)
                  Panel(
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
                // Totals for the period; wraps at large text.
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (icon, value, caption) in [
                      (Icons.route_outlined, s.tripsCount(sum.trips), s.durationShort(sum.tripMinutes)),
                      (Icons.local_parking, s.parkingsCount(sum.parkings), s.durationShort(sum.parkMinutes)),
                      (Icons.ramen_dining_outlined, s.mealsCount(sum.meals), s.historyMeals),
                      if (sum.costCents > 0) (Icons.payments_outlined, s.money(sum.costCents), s.historySpent),
                    ])
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
                        child: IntrinsicWidth(child: BentoTile(icon: icon, value: value, caption: caption)),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                  child: Text(s.historyCostNote, style: t.bodySmall),
                ),
                // Clean up many at once, e.g. meals logged by mistake.
                if (entries.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
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
                if (on && entries.isEmpty) ...[
                  const SizedBox(height: 16),
                  Panel(child: EmptyNote(s.historyEmpty, icon: Icons.history)),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dayLabel(S s, DateTime day, DateTime now) {
    final today = dateOnly(now);
    if (day == today) return s.today;
    if (day == today.subtract(const Duration(days: 1))) return s.yesterday;
    return '${s.dayShort[day.weekday - 1]} ${shortDate(day)}';
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
      final MealLog m => (Icons.ramen_dining_outlined, hawkers[m.hawkerId] ?? s.historyMeals, s.historyMeals),
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
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(detail),
        trailing: Text(
          [
            clockLabel(e.at),
            if (e.costCents case final c?) e.estimated ? '≈ ${s.money(c)}' : s.money(c),
          ].join('\n'),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        // Trips and parkings: tap to set what it cost.
        onTap: e.kind == HistoryKind.meal
            ? null
            : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => _CostSheet(entry: e, title: title),
                ),
      ),
    );
  }

  static IconData _modeIcon(String? mode) => switch (mode) {
        'car' => Icons.directions_car_outlined,
        'motorcycle' => Icons.two_wheeler,
        'bicycle' => Icons.pedal_bike,
        'taxi' => Icons.local_taxi_outlined,
        _ => Icons.directions_bus_outlined,
      };

  /// "home>work" → "Home → Work".
  static String _route(S s, String route) {
    final parts = route.split('>');
    if (parts.length != 2) return route;
    return s.routeLabel(s.placeLabel(parts[0]), s.placeLabel(parts[1]));
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
