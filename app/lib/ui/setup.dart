import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'address_picker.dart';
import 'stop_picker.dart';
import 'theme.dart';
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
    final existing = ref.read(favoritesProvider).places[kind]?.stops ?? const <BusStop>[];
    var stops = existing;
    var autoPicked = false;
    if (stops.isEmpty) {
      // Suggest the two nearest stops; the user can change them below.
      final all = await ref.read(busStopsProvider.future).catchError((_) => const <BusStop>[]);
      stops = nearestStops(all, hit.lat, hit.lng, limit: 2)
          .where((st) => distanceMeters(hit.lat, hit.lng, st.lat, st.lng) <= 600)
          .toList();
      autoPicked = stops.isNotEmpty;
    }
    await ref.read(favoritesProvider.notifier).setPlace(Place(
          kind: kind,
          stops: stops,
          address: hit.label,
          postal: hit.postal.isEmpty ? null : hit.postal,
          addrLat: hit.lat,
          addrLng: hit.lng,
        ));
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
                SectionTitle(s.otherPlaces),
                const _ExtraPlaces(),
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
                Panel(
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
