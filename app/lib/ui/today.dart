import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background.dart';
import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'stop_picker.dart';
import 'theme.dart';
import 'widgets.dart';

/// Today: morning card before 14:00, evening card after.
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final kind = ref.watch(cardKindProvider);
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final origin = fav.places[originFor(kind, fav)];
    final alerts = ref.watch(todayAlertsProvider);
    final t = Theme.of(context).textTheme;

    // Keep the home screen widget in sync with what the card shows.
    ref.listen(forecastProvider, (_, next) {
      final json = next.valueOrNull;
      if (json == null || origin == null) return;
      final here = forecastNear(json, origin.lat, origin.lng);
      if (here == null) return;
      updateWidget(
        title: kind == CardKind.morning ? s.morningCard : s.eveningCard,
        body: '${here.area}: ${here.forecast}',
      );
    });

    Future<void> refresh() async {
      ref.invalidate(forecastProvider);
      ref.invalidate(trainAlertsProvider);
      ref.invalidate(busArrivalProvider);
      ref.invalidate(crowdShareProvider);
      ref.invalidate(wbgtProvider);
      ref.invalidate(lightningProvider);
      ref.invalidate(carparkLiveProvider);
      ref.invalidate(taxiProvider);
      await ref.read(forecastProvider.future).catchError((_) => <String, dynamic>{});
    }

    final dests = <Widget>[
      for (final a in alerts) AlertBanner(icon: _alertIcon(a.kind), text: a.text),
      if (fav.lines.isNotEmpty) _MrtCard(lines: fav.lines, showCrowd: kind == CardKind.evening),
      if (origin != null)
        for (final stop in origin.stops)
          BusStopCard(stop: stop, title: s.busFrom(s.placeLabel(origin.kind.name))),
      if (origin != null) _QuickTiles(origin: origin),
      if (fav.carparks.isNotEmpty) const _SavedParking(),
      const SizedBox(height: 8),
      Text('${s.dataSource} ${s.pullToRefresh}', style: t.bodySmall, textAlign: TextAlign.center),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        edgeOffset: 80,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            HeroHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${kind == CardKind.morning ? s.morningCard : s.eveningCard} · ${_dateLabel(now, s.lang)}',
                          style: t.labelMedium?.copyWith(color: Colors.white70),
                        ),
                      ),
                      IconButton(
                        tooltip: s.checkBuses,
                        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.12)),
                        icon: const Icon(Icons.search, color: Colors.white),
                        onPressed: () => _searchStop(context, s),
                      ),
                    ],
                  ),
                  Text(s.greeting(now.hour), style: t.displayMedium?.copyWith(color: Colors.white)),
                  const SizedBox(height: 18),
                  if (origin != null) _HeroWeather(origin: origin, kind: kind),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: dests),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchStop(BuildContext context, S s) async {
    final stop = await Navigator.of(context).push<BusStop>(
      MaterialPageRoute(builder: (_) => StopPickerPage(title: s.checkBuses)),
    );
    if (stop != null && context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StopArrivalsPage(stop: stop)));
    }
  }
}

String _dateLabel(DateTime d, AppLang lang) {
  const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const id = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  const mEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const mId = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  final idLang = lang == AppLang.id;
  return '${(idLang ? id : en)[d.weekday - 1]}, ${d.day} ${(idLang ? mId : mEn)[d.month - 1]}';
}

IconData _alertIcon(AlertKind k) => switch (k) {
      AlertKind.rain => Icons.umbrella,
      AlertKind.mrt => Icons.train_outlined,
      AlertKind.hawker => Icons.storefront_outlined,
      AlertKind.dengue => Icons.bug_report_outlined,
      AlertKind.heat => Icons.thermostat,
      AlertKind.lightning => Icons.bolt,
    };

/// Weather for the trip, set in large type inside the hero.
class _HeroWeather extends ConsumerWidget {
  const _HeroWeather({required this.origin, required this.kind});
  final Place origin;
  final CardKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final dest = destinationFor(kind, fav);
    final destPlace = dest == null ? null : fav.places[dest];
    final body = ref.watch(forecastProvider);
    final t = Theme.of(context).textTheme;
    final dim = t.bodyMedium?.copyWith(color: Colors.white70);

    return body.when(
      loading: () => Text(s.loading, style: dim),
      error: (_, __) => Text(s.serverWaking, style: dim),
      data: (json) {
        final here = forecastNear(json, origin.lat, origin.lng);
        final there = destPlace == null ? null : forecastNear(json, destPlace.lat, destPlace.lng);
        if (here == null) return Text(s.notAvailable, style: dim);
        final rainy = here.isRainy || (there?.isRainy ?? false);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: rainy ? DL.amber : DL.tealLight.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(rainy ? Icons.umbrella : Icons.wb_sunny_outlined,
                    size: 28, color: rainy ? DL.ink : Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rainy ? s.bringUmbrella : s.noRain,
                        style: t.titleLarge?.copyWith(color: Colors.white)),
                    const SizedBox(height: 6),
                    _ForecastLine(label: s.placeLabel(origin.kind.name), f: here),
                    if (there != null && destPlace != null)
                      _ForecastLine(label: s.placeLabel(destPlace.kind.name), f: there),
                    if (here.validText != null) ...[
                      const SizedBox(height: 4),
                      Text('${s.weather2h} · ${s.validUntil(here.validText!)}',
                          style: t.bodySmall?.copyWith(color: Colors.white60)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ForecastLine extends StatelessWidget {
  const _ForecastLine({required this.label, required this.f});
  final String label;
  final AreaForecast f;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label · ${f.area}  ', style: t.bodySmall?.copyWith(color: Colors.white60)),
        TextSpan(text: f.forecast, style: t.labelLarge?.copyWith(color: Colors.white)),
      ])),
    );
  }
}

class _MrtCard extends ConsumerWidget {
  const _MrtCard({required this.lines, required this.showCrowd});
  final Set<String> lines;
  final bool showCrowd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final alerts = ref.watch(trainAlertsProvider);
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.mrtLines, style: t.titleMedium),
            const SizedBox(height: 8),
            alerts.when(
              loading: () => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s.loading)),
              error: (_, __) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s.notAvailable)),
              data: (json) => Column(
                children: [
                  for (final st in lineStatuses(json, lines))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 52, child: Align(alignment: Alignment.centerLeft, child: LineChip(st.line))),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(trainLines[st.line] ?? st.line, style: t.labelLarge),
                                Text(
                                  st.disrupted ? (st.detail?.isNotEmpty == true ? st.detail! : s.mrtDisrupted) : s.mrtNormal,
                                  style: st.disrupted ? t.bodySmall?.copyWith(color: const Color(0xFFB45309)) : t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (showCrowd) _CrowdBadge(line: st.line),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrowdBadge extends ConsumerWidget {
  const _CrowdBadge({required this.line});
  final String line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final share = ref.watch(crowdShareProvider(line));
    final text = share.maybeWhen(
      data: (v) => v == null
          ? '–'
          : v >= 0.3
              ? s.crowdHigh
              : v >= 0.1
                  ? s.crowdMid
                  : s.crowdLow,
      orElse: () => '…',
    );
    return Text(text, style: Theme.of(context).textTheme.labelMedium);
  }
}

/// Next buses at one stop, as signage plates with minutes and load.
class BusStopCard extends ConsumerWidget {
  const BusStopCard({super.key, required this.stop, required this.title});
  final BusStop stop;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final etas = ref.watch(busArrivalProvider(stop.code));
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.titleMedium),
            Text('${stop.name} · ${stop.code}', style: t.bodySmall),
            const SizedBox(height: 8),
            etas.when(
              loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
              error: (_, __) => EmptyNote(s.busesUnavailable),
              data: (list) => list.isEmpty
                  ? EmptyNote(s.noBusesNow)
                  : Column(children: [for (final e in list.take(8)) _BusRow(eta: e)]),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusRow extends ConsumerWidget {
  const _BusRow({required this.eta});
  final BusEta eta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final arriving = eta.minutes == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          BusPlate(eta.service),
          const SizedBox(width: 14),
          SizedBox(
            width: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(s.minutesAway(eta.minutes), style: arriving ? t.displaySmall?.copyWith(color: DL.teal) : t.displaySmall),
                if (!arriving) ...[
                  const SizedBox(width: 3),
                  Text(s.min, style: t.bodySmall),
                ],
              ],
            ),
          ),
          const Spacer(),
          LoadMeter(eta.load, label: s.loadLabel(eta.load)),
        ],
      ),
    );
  }
}

/// Bento row: taxis nearby (useful when it rains) and the nearest hawker.
class _QuickTiles extends ConsumerWidget {
  const _QuickTiles({required this.origin});
  final Place origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final taxis = ref.watch(taxiProvider).valueOrNull;
    final hawkers = ref.watch(hawkersProvider).valueOrNull ?? const <Hawker>[];
    final today = dateOnly(ref.watch(clockProvider).valueOrNull ?? DateTime.now());
    final near = nearest(hawkers, origin.lat, origin.lng, latOf: (h) => h.lat, lngOf: (h) => h.lng);
    final tiles = <Widget>[
      if (taxis != null)
        Expanded(
          child: BentoTile(
            icon: Icons.local_taxi_outlined,
            value: '${taxisWithin(taxis, origin.lat, origin.lng)}',
            caption: s.taxisNearby,
            tint: DL.amber,
          ),
        ),
      if (near != null)
        Expanded(
          child: BentoTile(
            icon: Icons.ramen_dining_outlined,
            value: s.metres(near.$2),
            caption: '${near.$1.name}${near.$1.closureOn(today) != null ? ' · ${s.closedNow}' : ''}',
          ),
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              tiles[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SavedParking extends ConsumerWidget {
  const _SavedParking();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final info = ref.watch(carparkInfoProvider).valueOrNull ?? const <Carpark>[];
    final lots = ref.watch(carparkLiveProvider).valueOrNull ?? const <String, (int, int)>{};
    final saved = info.where((c) => fav.carparks.contains(c.id)).toList();
    if (saved.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.parkingAt, style: t.titleMedium),
            for (final c in saved)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.local_parking),
                title: Text(c.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(lots[c.id] == null ? '–' : s.lotsFree(lots[c.id]!.$2), style: t.labelLarge),
              ),
          ],
        ),
      ),
    );
  }
}

/// On-demand arrivals for any stop the user searched.
class StopArrivalsPage extends ConsumerWidget {
  const StopArrivalsPage({super.key, required this.stop});
  final BusStop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(stop.name)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(busArrivalProvider(stop.code)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [BusStopCard(stop: stop, title: '${s.stopCode(stop.code)} · ${stop.road}')],
        ),
      ),
    );
  }
}
