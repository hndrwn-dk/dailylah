import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'address_picker.dart';
import 'stop_picker.dart';
import 'theme.dart';
import 'trip.dart';
import 'widgets.dart';

/// Onboarding and setup in one page: places (by bus stop), MRT lines and departure
/// times. Everything is saved on the device as it changes.
class SetupPage extends ConsumerWidget {
  const SetupPage({super.key, this.firstRun = false});
  final bool firstRun;

  Future<void> _pickAddress(BuildContext context, WidgetRef ref, PlaceKind kind) async {
    final s = ref.read(stringsProvider);
    final hit = await Navigator.of(context).push<AddressHit>(
      MaterialPageRoute(builder: (_) => AddressPickerPage(title: s.addressFor(s.placeLabel(kind.name)))),
    );
    if (hit == null) return;
    final old = ref.read(favoritesProvider).places[kind];
    // Keep saved stops near the new address; after a move, pick the nearest ones instead.
    final all = await ref.read(busStopsProvider.future).catchError((_) => const <BusStop>[]);
    final (stops, autoPicked) = stopsForNewAddress(old?.stops ?? const <BusStop>[], all, hit.lat, hit.lng);
    final postal = hit.postal.isEmpty ? null : hit.postal;
    await ref.read(favoritesProvider.notifier).setPlace(old == null
        ? Place(kind: kind, stops: stops, address: hit.label, postal: postal, addrLat: hit.lat, addrLng: hit.lng)
        : old.withAddress(address: hit.label, postal: postal, lat: hit.lat, lng: hit.lng, stops: stops));
    if (autoPicked && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.stopsAutoPicked)));
    }
  }

  Future<void> _pickStop(BuildContext context, WidgetRef ref, PlaceKind kind) async {
    final s = ref.read(stringsProvider);
    final stop = await Navigator.of(context).push<BusStop>(
      MaterialPageRoute(builder: (_) => StopPickerPage(title: s.pickStopNear(s.placeLabel(kind.name)))),
    );
    if (stop == null) return;
    final place = ref.read(favoritesProvider).places[kind];
    final existing = place?.stops ?? const <BusStop>[];
    if (existing.any((x) => x.code == stop.code)) return;
    final stops = [...existing, stop].take(2).toList(); // max 2 stops per place
    await ref
        .read(favoritesProvider.notifier)
        .setPlace(place == null ? Place(kind: kind, stops: stops) : place.copyWith(stops: stops));
  }

  Future<void> _removeStop(WidgetRef ref, Place place, BusStop stop) async {
    final stops = place.stops.where((x) => x.code != stop.code).toList();
    final n = ref.read(favoritesProvider.notifier);
    if (stops.isEmpty && !place.hasAddress) {
      await n.removePlace(place.kind);
    } else {
      await n.setPlace(place.copyWith(stops: stops));
    }
  }

  /// Pick the usual go (leave home) or back (leave this place) time for a work/school place.
  Future<void> _pickTime(BuildContext context, WidgetRef ref, Place place, {required bool go}) async {
    final fav = ref.read(favoritesProvider);
    final current = go ? (place.go ?? fav.leaveHome) : (place.back ?? fav.leaveWork);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    final t = TimeOfDayHM(picked.hour, picked.minute);
    await ref.read(favoritesProvider.notifier).setPlace(go ? place.copyWith(go: t) : place.copyWith(back: t));
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
      return Panel(
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
              const SizedBox(height: 10),
              // Address
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _pickAddress(context, ref, kind),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: place?.hasAddress == true
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(place!.address ?? s.myLocation, style: t.titleSmall),
                                  if (place.postal != null) Text('Singapore ${place.postal}', style: t.bodySmall),
                                ],
                              )
                            : Text(s.setAddress, style: t.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
                      ),
                      Icon(place?.hasAddress == true ? Icons.edit_outlined : Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
              const Divider(height: 16),
              // Bus stops
              Text(s.busStopsHere, style: t.labelMedium),
              const SizedBox(height: 4),
              if (place == null || place.stops.isEmpty)
                Text(s.pickStopNear(s.placeLabel(kind.name).toLowerCase()), style: t.bodySmall)
              else
                for (final st in place.stops)
                  Row(
                    children: [
                      const Icon(Icons.directions_bus_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${st.name} · ${st.code}', style: t.bodyMedium)),
                      IconButton(
                        tooltip: s.remove,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _removeStop(ref, place, st),
                      ),
                    ],
                  ),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                icon: const Icon(Icons.add),
                label: Text(place == null || place.stops.isEmpty ? s.pickStop : s.addAnotherStop),
                onPressed: (place?.stops.length ?? 0) >= 2 ? null : () => _pickStop(context, ref, kind),
              ),
              if (kind != PlaceKind.home && place != null) ...[
                const Divider(height: 16),
                Text(s.days, style: t.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(s.dayShort[d - 1]),
                        selected: place.days.contains(d),
                        onSelected: (on) => notifier.setPlace(place.copyWith(
                          days: on ? {...place.days, d} : ({...place.days}..remove(d)),
                        )),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final (go, label, icon) in [
                      (true, s.goAt, Icons.wb_twilight),
                      (false, s.backAt(place.kind.name), Icons.nights_stay_outlined),
                    ]) ...[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            alignment: Alignment.centerLeft,
                          ),
                          onPressed: () => _pickTime(context, ref, place, go: go),
                          child: Row(
                            children: [
                              Icon(icon, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(label, style: t.labelMedium, overflow: TextOverflow.ellipsis)),
                              // Large text or a narrow phone: shrink the time rather than overflow.
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    (go ? (place.go ?? fav.leaveHome) : (place.back ?? fav.leaveWork)).format(),
                                    style: t.displaySmall?.copyWith(fontSize: 20),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (go) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(s.usuallyBy, style: t.labelMedium),
                const SizedBox(height: 6),
                ModeChips(
                  selected: place.modes,
                  onChanged: (m) => notifier.setPlace(place.copyWith(modes: m)),
                ),
                const SizedBox(height: 8),
              ],
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
                if (!firstRun) const BackButton() else const SizedBox(height: 16),
                const SizedBox(height: 8),
                if (firstRun) ...[
                  // "Welcome to" followed by the DailyLah mark (daily plate + lah sun).
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(s.welcomeTo, style: Theme.of(context).textTheme.displayLarge),
                      Semantics(
                        label: 'DailyLah',
                        image: true,
                        child: Image.asset('assets/brand/wordmark.png', height: 64, excludeFromSemantics: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(s.welcomeIntro,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color)),
                ] else
                  PageTitle(s.yourSetup, subtitle: s.editSetup),
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
                SectionTitle(s.otherPlaces),
                const _ExtraPlaces(),
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



/// Custom favourite places with their own names (max [Favorites.maxExtraPlaces]).
class _ExtraPlaces extends ConsumerWidget {
  const _ExtraPlaces();

  Future<String?> _askName(BuildContext context, WidgetRef ref, {String? initial}) {
    final s = ref.read(stringsProvider);
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.placeName),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 24,
          decoration: InputDecoration(hintText: s.placeNameHint),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: Text(s.save)),
        ],
      ),
    );
  }

  Future<Place?> _withAddress(BuildContext context, WidgetRef ref, String name) async {
    final s = ref.read(stringsProvider);
    final hit = await Navigator.of(context).push<AddressHit>(
      MaterialPageRoute(builder: (_) => AddressPickerPage(title: s.addressFor(name))),
    );
    if (hit == null) return null;
    final all = await ref.read(busStopsProvider.future).catchError((_) => const <BusStop>[]);
    final stops = nearestStops(all, hit.lat, hit.lng, limit: 2)
        .where((st) => distanceMeters(hit.lat, hit.lng, st.lat, st.lng) <= 600)
        .toList();
    return Place(
      kind: PlaceKind.other,
      name: name,
      stops: stops,
      address: hit.label,
      postal: hit.postal.isEmpty ? null : hit.postal,
      addrLat: hit.lat,
      addrLng: hit.lng,
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await _askName(context, ref);
    if (name == null || name.isEmpty || !context.mounted) return;
    final place = await _withAddress(context, ref, name);
    if (place != null) await ref.read(favoritesProvider.notifier).addExtra(place);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final n = ref.read(favoritesProvider.notifier);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(s.otherPlacesHint, style: t.bodySmall)),
        for (var i = 0; i < fav.extraPlaces.length; i++)
          Panel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const Icon(Icons.star_outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fav.extraPlaces[i].name ?? '', style: t.titleSmall),
                        Text(fav.extraPlaces[i].address ?? '', style: t.bodySmall),
                        if (fav.extraPlaces[i].stops.isNotEmpty)
                          Text(fav.extraPlaces[i].stops.map((x) => x.name).join(' · '), style: t.bodySmall),
                        const SizedBox(height: 8),
                        Text(s.whenLabel, style: t.labelMedium),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final w in PlaceWhen.values)
                              ChoiceChip(
                                label: Text(s.whenName(w.name)),
                                selected: fav.extraPlaces[i].when == w,
                                onSelected: (_) => n.setExtra(i, fav.extraPlaces[i].copyWith(when: w)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(s.usuallyBy, style: t.labelMedium),
                        const SizedBox(height: 4),
                        ModeChips(
                          selected: fav.extraPlaces[i].modes,
                          onChanged: (m) => n.setExtra(i, fav.extraPlaces[i].copyWith(modes: m)),
                        ),
                        const SizedBox(height: 8),
                        // Optional usual time (e.g. school pick-up): drives "leave in" and a reminder.
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.schedule, size: 18),
                              label: Text(fav.extraPlaces[i].go == null
                                  ? s.setLeaveTime
                                  : s.leaveHomeAt(fav.extraPlaces[i].go!.format())),
                              onPressed: () async {
                                final p = fav.extraPlaces[i];
                                final cur = p.go ?? const TimeOfDayHM(9, 0);
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute),
                                );
                                if (picked != null) await n.setExtra(i, p.copyWith(go: TimeOfDayHM(picked.hour, picked.minute)));
                              },
                            ),
                            if (fav.extraPlaces[i].go != null)
                              TextButton(
                                onPressed: () => n.setExtra(i, fav.extraPlaces[i].copyWith(clearGo: true)),
                                child: Text(s.clearTime),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      final p = fav.extraPlaces[i];
                      if (v == 'rename') {
                        final name = await _askName(context, ref, initial: p.name);
                        if (name != null && name.isNotEmpty) await n.setExtra(i, p.copyWith(name: name));
                      } else if (v == 'address') {
                        final np = await _withAddress(context, ref, p.name ?? '');
                        if (np != null) await n.setExtra(i, np);
                      } else {
                        await n.removeExtra(i);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'rename', child: Text(s.rename)),
                      PopupMenuItem(value: 'address', child: Text(s.changeAddress)),
                      PopupMenuItem(value: 'remove', child: Text(s.remove)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (fav.extraPlaces.length < Favorites.maxExtraPlaces)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: Text(s.addPlace),
            onPressed: () => _add(context, ref),
          )
        else
          Text(s.maxPlaces(Favorites.maxExtraPlaces), style: t.bodySmall),
      ],
    );
  }
}


/// Multi-select travel modes; order of picking decides the default (first).
class ModeChips extends ConsumerWidget {
  const ModeChips({super.key, required this.selected, required this.onChanged});
  final List<TravelMode> selected;
  final ValueChanged<List<TravelMode>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in TravelMode.values)
              FilterChip(
                avatar: Icon(modeIcon(m), size: 16),
                label: Text(selected.isNotEmpty && selected.first == m ? '${s.modeLabel(m.name)} ★' : s.modeLabel(m.name)),
                selected: selected.contains(m),
                showCheckmark: false,
                onSelected: (on) {
                  final next = on ? [...selected, m] : selected.where((x) => x != m).toList();
                  if (next.isNotEmpty) onChanged(next);
                },
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(s.usuallyByHint, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
