import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'setup.dart';
import 'stop_picker.dart';

/// The daily card: morning (home → work/school) before 14:00, evening after.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favoritesProvider);
    final kind = ref.watch(cardKindProvider);
    final origin = fav.places[originFor(kind, fav)];

    // Keep the home screen widget in sync with what the card shows.
    ref.listen(forecastProvider, (_, next) {
      final json = next.valueOrNull;
      if (json == null || origin == null) return;
      final here = forecastNear(json, origin.lat, origin.lng);
      if (here == null) return;
      updateWidget(
        title: kind == CardKind.morning ? 'Pagi' : 'Sore',
        body: '${here.area}: ${here.forecast}',
      );
    });

    Future<void> refresh() async {
      ref.invalidate(forecastProvider);
      ref.invalidate(trainAlertsProvider);
      ref.invalidate(busArrivalProvider);
      ref.invalidate(crowdShareProvider);
      await ref.read(forecastProvider.future).catchError((_) => <String, dynamic>{});
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(kind == CardKind.morning ? 'Kartu pagi' : 'Kartu sore'),
        actions: [
          IconButton(
            tooltip: 'Cek bus di halte lain',
            icon: const Icon(Icons.search),
            onPressed: () async {
              final stop = await Navigator.of(context).push<BusStop>(
                MaterialPageRoute(builder: (_) => const StopPickerPage(title: 'Cek bus')),
              );
              if (stop != null && context.mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => StopArrivalsPage(stop: stop)),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SetupPage()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (origin != null) _WeatherCard(origin: origin, kind: kind),
            if (fav.lines.isNotEmpty) _MrtCard(lines: fav.lines, showCrowd: kind == CardKind.evening),
            if (origin != null)
              for (final stop in origin.stops) _BusCard(stop: stop, title: 'Bus dari ${origin.kind.label}'),
            const SizedBox(height: 16),
            Text(
              'Data: NEA via data.gov.sg dan LTA DataMall. Tarik ke bawah untuk memperbarui.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherCard extends ConsumerWidget {
  const _WeatherCard({required this.origin, required this.kind});
  final Place origin;
  final CardKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favoritesProvider);
    final dest = destinationFor(kind, fav);
    final destPlace = dest == null ? null : fav.places[dest];
    final body = ref.watch(forecastProvider);
    return Card(
      child: body.when(
        loading: () => const ListTile(leading: Icon(Icons.cloud_outlined), title: Text('Memuat cuaca…')),
        error: (_, __) => const ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Cuaca belum tersedia'),
          subtitle: Text('Server mungkin sedang bangun. Tarik untuk coba lagi.'),
        ),
        data: (json) {
          final here = forecastNear(json, origin.lat, origin.lng);
          final there = destPlace == null ? null : forecastNear(json, destPlace.lat, destPlace.lng);
          if (here == null) {
            return const ListTile(leading: Icon(Icons.cloud_outlined), title: Text('Cuaca belum tersedia'));
          }
          final rainy = here.isRainy || (there?.isRainy ?? false);
          return ListTile(
            leading: Icon(rainy ? Icons.umbrella : Icons.wb_sunny_outlined),
            title: Text(rainy ? 'Bawa payung' : 'Cuaca 2 jam ke depan'),
            subtitle: Text([
              '${origin.kind.label} (${here.area}): ${here.forecast}',
              if (there != null && destPlace != null)
                '${destPlace.kind.label} (${there.area}): ${there.forecast}',
              if (here.validText != null) 'Berlaku ${here.validText}',
            ].join('\n')),
          );
        },
      ),
    );
  }
}

class _MrtCard extends ConsumerWidget {
  const _MrtCard({required this.lines, required this.showCrowd});
  final Set<String> lines;
  final bool showCrowd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(trainAlertsProvider);
    return Card(
      child: alerts.when(
        loading: () => const ListTile(leading: Icon(Icons.train_outlined), title: Text('Memuat status MRT…')),
        error: (_, __) => const ListTile(
          leading: Icon(Icons.train_outlined),
          title: Text('Status MRT belum tersedia'),
        ),
        data: (json) {
          final statuses = lineStatuses(json, lines);
          final anyBad = statuses.any((s) => s.disrupted);
          return Column(
            children: [
              ListTile(
                leading: Icon(anyBad ? Icons.warning_amber : Icons.train_outlined,
                    color: anyBad ? Theme.of(context).colorScheme.error : null),
                title: Text(anyBad ? 'Ada gangguan MRT' : 'MRT normal'),
              ),
              for (final s in statuses)
                ListTile(
                  dense: true,
                  title: Text('${s.line} · ${trainLines[s.line] ?? ''}'),
                  subtitle: s.disrupted && (s.detail ?? '').isNotEmpty ? Text(s.detail!) : null,
                  trailing: showCrowd
                      ? _CrowdBadge(line: s.line)
                      : Text(s.disrupted ? 'Gangguan' : 'Normal'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CrowdBadge extends ConsumerWidget {
  const _CrowdBadge({required this.line});
  final String line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final share = ref.watch(crowdShareProvider(line));
    return share.maybeWhen(
      data: (v) => Text(v == null
          ? '-'
          : v >= 0.3
              ? 'Padat'
              : v >= 0.1
                  ? 'Agak padat'
                  : 'Lengang'),
      orElse: () => const Text('…'),
    );
  }
}

class _BusCard extends ConsumerWidget {
  const _BusCard({required this.stop, required this.title});
  final BusStop stop;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etas = ref.watch(busArrivalProvider(stop.code));
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.directions_bus_outlined),
            title: Text(title),
            subtitle: Text('${stop.name} (${stop.code})'),
          ),
          etas.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (_, __) => const ListTile(dense: true, title: Text('Jadwal bus belum tersedia')),
            data: (list) => _EtaList(etas: list),
          ),
        ],
      ),
    );
  }
}

class _EtaList extends StatelessWidget {
  const _EtaList({required this.etas});
  final List<BusEta> etas;

  @override
  Widget build(BuildContext context) {
    if (etas.isEmpty) {
      return const ListTile(dense: true, title: Text('Tidak ada bus saat ini'));
    }
    return Column(
      children: [
        for (final e in etas.take(6))
          ListTile(
            dense: true,
            leading: Text(e.service, style: Theme.of(context).textTheme.titleMedium),
            title: Text(e.minutes == 0 ? 'Tiba' : '${e.minutes} menit'),
            trailing: Text(loadLabel(e.load)),
          ),
      ],
    );
  }
}

/// On-demand arrivals for any stop the user searched.
class StopArrivalsPage extends ConsumerWidget {
  const StopArrivalsPage({super.key, required this.stop});
  final BusStop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(stop.name)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(busArrivalProvider(stop.code)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [_BusCard(stop: stop, title: 'Kode ${stop.code} · ${stop.road}')],
        ),
      ),
    );
  }
}
