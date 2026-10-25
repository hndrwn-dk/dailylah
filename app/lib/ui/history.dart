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
    final entries = historyEntries(habits, since: historySince(period, now));
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
                  child: Text(s.historyCostSoon, style: t.bodySmall),
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
          [clockLabel(e.at), if (e.costCents != null) s.money(e.costCents!)].join('\n'),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelMedium,
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
