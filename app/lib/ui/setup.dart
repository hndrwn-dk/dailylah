import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background.dart';
import '../models.dart';
import '../providers.dart';
import 'stop_picker.dart';

/// Onboarding and settings in one page: places (by bus stop), MRT lines, departure
/// times and alert toggles. Everything is saved on the device as it changes.
class SetupPage extends ConsumerWidget {
  const SetupPage({super.key, this.firstRun = false});
  final bool firstRun;

  Future<void> _pickStop(BuildContext context, WidgetRef ref, PlaceKind kind) async {
    final stop = await Navigator.of(context).push<BusStop>(
      MaterialPageRoute(builder: (_) => StopPickerPage(title: 'Halte dekat ${kind.label}')),
    );
    if (stop == null) return;
    final fav = ref.read(favoritesProvider);
    final existing = fav.places[kind]?.stops ?? const <BusStop>[];
    if (existing.any((s) => s.code == stop.code)) return;
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
    final fav = ref.watch(favoritesProvider);
    final notifier = ref.read(favoritesProvider.notifier);
    final text = Theme.of(context).textTheme;

    Widget placeTile(PlaceKind kind, {required bool required}) {
      final place = fav.places[kind];
      return Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(kind.label + (required ? '' : ' (opsional)')),
              subtitle: Text(place == null
                  ? 'Pilih halte bus terdekat dari ${kind.label.toLowerCase()}'
                  : place.stops.map((s) => '${s.name} (${s.code})').join('\n')),
              trailing: place == null
                  ? null
                  : IconButton(
                      tooltip: 'Hapus',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => notifier.removePlace(kind),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(place == null ? 'Pilih halte' : 'Tambah halte lain'),
                onPressed: (place?.stops.length ?? 0) >= 2 ? null : () => _pickStop(context, ref, kind),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(firstRun ? 'Selamat datang di DailyLah' : 'Pengaturan'),
        automaticallyImplyLeading: !firstRun,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (firstRun)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Atur sekali, lalu DailyLah kasih tahu yang penting: bus, MRT, dan hujan. '
                'Semua pilihanmu tersimpan di HP ini saja.',
                style: text.bodyLarge,
              ),
            ),
          Text('Tempat', style: text.titleMedium),
          const SizedBox(height: 8),
          placeTile(PlaceKind.home, required: true),
          placeTile(PlaceKind.work, required: false),
          placeTile(PlaceKind.school, required: false),
          const SizedBox(height: 24),
          Text('Jalur MRT/LRT yang biasa dipakai', style: text.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in trainLines.entries)
                FilterChip(
                  label: Text('${e.key} · ${e.value}'),
                  selected: fav.lines.contains(e.key),
                  onSelected: (_) => notifier.toggleLine(e.key),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Jam berangkat biasa', style: text.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dari rumah'),
            trailing: Text(fav.leaveHome.format()),
            onTap: () => _pickTime(context, ref, true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pulang dari kantor'),
            trailing: Text(fav.leaveWork.format()),
            onTap: () => _pickTime(context, ref, false),
          ),
          const SizedBox(height: 16),
          Text('Notifikasi', style: text.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gangguan MRT di jalur saya'),
            value: fav.mrtAlerts,
            onChanged: (v) => notifier.update((f) => f.copyWith(mrtAlerts: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hujan sebelum berangkat'),
            subtitle: const Text('Maksimal 3 per hari, tidak ada notifikasi 22.00–06.00'),
            value: fav.rainAlerts,
            onChanged: (v) => notifier.update((f) => f.copyWith(rainAlerts: v)),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: fav.isSetUp ? () => _finish(context, ref) : null,
            child: Text(firstRun ? 'Selesai' : 'Simpan'),
          ),
          if (!fav.isSetUp)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Pilih halte dekat rumah dulu.', style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}
