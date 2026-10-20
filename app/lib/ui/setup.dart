import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background.dart';
import '../l10n.dart';
import '../models.dart';
import '../providers.dart';
import 'stop_picker.dart';
import 'theme.dart';
import 'widgets.dart';

/// Onboarding and setup in one page: places (by bus stop), MRT lines and departure
/// times. Everything is saved on the device as it changes.
class SetupPage extends ConsumerWidget {
  const SetupPage({super.key, this.firstRun = false});
  final bool firstRun;

  Future<void> _pickStop(BuildContext context, WidgetRef ref, PlaceKind kind) async {
    final s = ref.read(stringsProvider);
    final stop = await Navigator.of(context).push<BusStop>(
      MaterialPageRoute(builder: (_) => StopPickerPage(title: s.pickStopNear(s.placeLabel(kind.name)))),
    );
    if (stop == null) return;
    final fav = ref.read(favoritesProvider);
    final existing = fav.places[kind]?.stops ?? const <BusStop>[];
    if (existing.any((x) => x.code == stop.code)) return;
    final stops = [...existing, stop].take(2).toList(); // max 2 stops per place
    await ref.read(favoritesProvider.notifier).setPlace(Place(kind: kind, stops: stops));
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref, bool home) async {
    final fav = ref.read(favoritesProvider);
    final current = home ? fav.leaveHome : fav.leaveWork;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    final t = TimeOfDayHM(picked.hour, picked.minute);
    await ref
        .read(favoritesProvider.notifier)
        .update((f) => home ? f.copyWith(leaveHome: t) : f.copyWith(leaveWork: t));
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    await requestNotificationPermission();
    await registerBackgroundWork();
    await ref.read(favoritesProvider.notifier).update((f) => f.copyWith(onboarded: true));
    if (context.mounted && !firstRun) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final notifier = ref.read(favoritesProvider.notifier);
    final t = Theme.of(context).textTheme;

    Widget placeCard(PlaceKind kind, {required bool required}) {
      final place = fav.places[kind];
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: place == null ? Theme.of(context).colorScheme.surfaceContainer : DL.ink,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(PlaceSelector.iconOf(kind),
                        size: 20, color: place == null ? null : Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.placeLabel(kind.name) + (required ? '' : ' · ${s.optional}'),
                      style: t.titleMedium,
                    ),
                  ),
                  if (place != null)
                    IconButton(
                      tooltip: s.remove,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => notifier.removePlace(kind),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (place == null)
                Text(s.pickStopNear(s.placeLabel(kind.name).toLowerCase()), style: t.bodySmall)
              else
                for (final st in place.stops)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${st.name} · ${st.code}', style: t.bodyMedium),
                  ),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                icon: const Icon(Icons.add),
                label: Text(place == null ? s.pickStop : s.addAnotherStop),
                onPressed: (place?.stops.length ?? 0) >= 2 ? null : () => _pickStop(context, ref, kind),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!firstRun) const BackButton(color: Colors.white) else const SizedBox(height: 24),
                const SizedBox(height: 8),
                PageTitle(firstRun ? s.welcome : s.yourSetup, subtitle: firstRun ? s.welcomeIntro : s.editSetup),
                if (firstRun) ...[
                  const SizedBox(height: 16),
                  _LanguagePills(),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(s.places),
                placeCard(PlaceKind.home, required: true),
                placeCard(PlaceKind.work, required: false),
                placeCard(PlaceKind.school, required: false),
                SectionTitle(s.yourLines),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in trainLines.entries)
                      FilterChip(
                        avatar: CircleAvatar(backgroundColor: DL.lineColor(e.key), radius: 6),
                        label: Text('${e.key} · ${e.value}'),
                        selected: fav.lines.contains(e.key),
                        onSelected: (_) => notifier.toggleLine(e.key),
                      ),
                  ],
                ),
                SectionTitle(s.departureTimes),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.wb_twilight),
                        title: Text(s.leaveHome),
                        trailing: Text(fav.leaveHome.format(), style: t.displaySmall?.copyWith(fontSize: 24)),
                        onTap: () => _pickTime(context, ref, true),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.nights_stay_outlined),
                        title: Text(s.leaveWork),
                        trailing: Text(fav.leaveWork.format(), style: t.displaySmall?.copyWith(fontSize: 24)),
                        onTap: () => _pickTime(context, ref, false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: fav.isSetUp ? () => _finish(context, ref) : null,
                  child: Text(firstRun ? s.done : s.save),
                ),
                if (!fav.isSetUp)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(s.pickHomeFirst, style: t.bodySmall, textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguagePills extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    return Wrap(
      spacing: 8,
      children: [
        for (final (l, label) in const [(AppLang.en, 'English'), (AppLang.id, 'Bahasa Indonesia')])
          ChoiceChip(
            label: Text(label),
            selected: lang == l,
            onSelected: (_) => ref.read(favoritesProvider.notifier).update((f) => f.copyWith(lang: l.name)),
          ),
      ],
    );
  }
}
