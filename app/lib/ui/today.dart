import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../background.dart';
import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'place_sheet.dart';
import 'stop_picker.dart';
import 'theme.dart';
import 'trip.dart';
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
    final origin = fav.places[originFor(kind, fav, now)];
    final commute = isCommuteDay(fav, now);
    final destKind = destinationFor(kind, fav, now);
    final dest = destKind == null ? null : fav.places[destKind];
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
      ref.invalidate(rainfallProvider);
      ref.invalidate(uvProvider);
      ref.invalidate(psiProvider);
      ref.invalidate(pm25Provider);
      ref.invalidate(carparkLiveProvider);
      ref.invalidate(taxiProvider);
      ref.invalidate(parkingLiveProvider);
      ref.invalidate(incidentsProvider);
      await ref.read(forecastProvider.future).catchError((_) => <String, dynamic>{});
    }

    final dests = <Widget>[
      for (final a in alerts) AlertBanner(icon: _alertIcon(a.kind), text: a.text),
      if (origin != null) _WeatherTiles(origin: origin),
      if (commute && origin != null && dest != null)
        TripSection(
          fromKey: origin.kind.name,
          from: origin,
          to: dest,
          modeKey: (kind == CardKind.morning ? dest : origin).kind.name,
          modePlace: kind == CardKind.morning ? dest : origin,
        ),
      if ((!commute || ref.watch(modeOverrideProvider)[(kind == CardKind.morning ? dest : origin)?.kind.name] == TravelMode.transit || ((kind == CardKind.morning ? dest : origin)?.mode ?? TravelMode.transit) == TravelMode.transit))
        _MrtCard(showCrowd: kind == CardKind.evening),
      const GoSomewhere(),
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
          padding: const EdgeInsets.only(bottom: kNavClearance),
          children: [
            HeroHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${kind == CardKind.morning ? s.morningCard : s.eveningCard} · ${_dateLabel(now)}',
                          style: t.labelMedium?.copyWith(color: t.bodySmall?.color),
                        ),
                      ),
                      StickerIconButton(
                        tooltip: s.checkBuses,
                        icon: Icons.search,
                        onPressed: () => _searchStop(context, s),
                      ),
                    ],
                  ),
                  Text(s.greeting(now.hour), style: t.displayLarge),
                  const SizedBox(height: 18),
                  if (origin != null) _HeroWeather(origin: origin, kind: kind),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 18, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: dests),
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

String _dateLabel(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

IconData _alertIcon(AlertKind k) => switch (k) {
      AlertKind.rain => Icons.umbrella,
      AlertKind.mrt => Icons.train_outlined,
      AlertKind.hawker => Icons.storefront_outlined,
      AlertKind.dengue => Icons.bug_report_outlined,
      AlertKind.heat => Icons.thermostat,
      AlertKind.lightning => Icons.bolt,
      AlertKind.haze => Icons.masks_outlined,
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
    final dest = destinationFor(kind, fav, ref.watch(clockProvider).valueOrNull);
    final destPlace = dest == null ? null : fav.places[dest];
    final body = ref.watch(forecastProvider);
    final t = Theme.of(context).textTheme;
    final dim = t.bodyMedium;

    return body.when(
      loading: () => Text(s.loading, style: dim),
      error: (_, __) => Text(s.serverWaking, style: dim),
      data: (json) {
        final here = forecastNear(json, origin.lat, origin.lng);
        final there = destPlace == null ? null : forecastNear(json, destPlace.lat, destPlace.lng);
        if (here == null) return Text(s.notAvailable, style: dim);
        final rainy = here.isRainy || (there?.isRainy ?? false);
        // Sky panel when dry, amber when rain is expected.
        return Panel(
          margin: EdgeInsets.zero,
          color: rainy ? DL.amber : DL.sky,
          child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: DL.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: DL.ink, width: 2),
                ),
                child: Icon(rainy ? Icons.umbrella : Icons.wb_sunny_outlined, size: 28, color: DL.ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rainy ? s.bringUmbrella : s.noRain,
                        style: t.titleLarge?.copyWith(color: DL.ink)),
                    const SizedBox(height: 6),
                    _ForecastLine(label: s.placeLabel(origin.kind.name), f: here),
                    if (there != null && destPlace != null)
                      _ForecastLine(label: s.placeLabel(destPlace.kind.name), f: there),
                    if (here.validText != null) ...[
                      const SizedBox(height: 4),
                      Text('${s.weather2h} · ${s.validUntil(here.validText!)}',
                          style: t.bodySmall?.copyWith(color: DL.ink.withValues(alpha: 0.7))),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
        TextSpan(text: '$label · ${f.area}  ', style: t.bodySmall?.copyWith(color: DL.ink.withValues(alpha: 0.7))),
        TextSpan(text: f.forecast, style: t.labelLarge?.copyWith(color: DL.ink)),
      ])),
    );
  }
}

/// All MRT/LRT lines at a glance. Disruptions float to the top; up to three starred lines
/// get a full row (with crowd levels in the evening) and alerts.
class _MrtCard extends ConsumerWidget {
  const _MrtCard({required this.showCrowd});
  final bool showCrowd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final starred = ref.watch(favoritesProvider.select((f) => f.lines));
    final alerts = ref.watch(trainAlertsProvider);
    final t = Theme.of(context).textTheme;

    void toggle(String line) {
      if (!starred.contains(line) && starred.length >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.maxStarredLines)));
        return;
      }
      ref.read(favoritesProvider.notifier).toggleLine(line);
    }

    Widget row(LineStatus st) => Padding(
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
                      style: st.disrupted ? t.bodySmall?.copyWith(color: DL.stop) : t.bodySmall,
                    ),
                  ],
                ),
              ),
              if (showCrowd && starred.contains(st.line)) _CrowdBadge(line: st.line),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: s.starLine,
                icon: Icon(starred.contains(st.line) ? Icons.star : Icons.star_border,
                    color: starred.contains(st.line) ? DL.amber : null),
                onPressed: () => toggle(st.line),
              ),
            ],
          ),
        );

    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: alerts.when(
          loading: () => Text(s.loading),
          error: (_, __) => Text(s.notAvailable),
          data: (json) {
            final all = lineStatuses(json, trainLines.keys.toSet());
            final down = all.where((x) => x.disrupted).toList();
            final pinned = all.where((x) => !x.disrupted && starred.contains(x.line)).toList();
            final rest = all.where((x) => !x.disrupted && !starred.contains(x.line)).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.mrtLinesAll, style: t.titleMedium),
                Text(down.isEmpty ? s.allLinesNormal : s.mrtAlert(down.map((x) => x.line).join(', ')),
                    style: t.bodySmall?.copyWith(color: down.isEmpty ? null : DL.stop)),
                const SizedBox(height: 6),
                for (final st in down) row(st),
                for (final st in pinned) row(st),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final st in rest)
                      Tooltip(
                        message: '${trainLines[st.line]} · ${s.starLine}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => toggle(st.line),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LineChip(st.line, dense: true),
                              const SizedBox(width: 3),
                              const Icon(Icons.circle, size: 8, color: Color(0xFF2E9E5B)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(starred.isEmpty ? s.starHintNone : s.starHint, style: t.bodySmall),
                ),
              ],
            );
          },
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
    return Panel(
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
                  : Column(children: [
                      for (final (i, e) in list.take(8).indexed)
                        BusRow(eta: e, pulse: i == list.indexWhere((x) => x.minutes == 0)),
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}

class BusRow extends ConsumerWidget {
  const BusRow({super.key, required this.eta, this.pulse = true, this.note});
  final BusEta eta;

  /// Blink "Arr"; only the first arriving bus in a list blinks to keep it calm.
  final bool pulse;

  /// Optional line under the row, e.g. where to get off.
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final arriving = eta.minutes == 0;
    final arr = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: DL.amber,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DL.edge(context), width: 2),
      ),
      child: Text(s.minutesAway(0), style: t.displaySmall?.copyWith(color: DL.ink, fontSize: 26)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(
        children: [
          BusPlate(eta.service),
          const SizedBox(width: 14),
          SizedBox(
            width: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (arriving)
                  pulse ? Pulse(child: arr) : arr
                else
                  Text(s.minutesAway(eta.minutes), style: t.displaySmall),
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
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 74, top: 2),
              child: Text(note!, style: t.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Bento row with live readings near the origin: rain gauge, UV and heat stress.
class _WeatherTiles extends ConsumerWidget {
  const _WeatherTiles({required this.origin});
  final Place origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final rain = ref.watch(rainfallProvider).valueOrNull;
    final uv = ref.watch(uvProvider).valueOrNull;
    final wbgt = ref.watch(wbgtProvider).valueOrNull;
    final air = airNear(ref.watch(psiProvider).valueOrNull, ref.watch(pm25Provider).valueOrNull, origin.lat, origin.lng);
    final r = rain == null ? null : rainfallNear(rain, origin.lat, origin.lng);
    final u = uv == null ? null : uvIndex(uv);
    final w = wbgt == null ? null : wbgtNear(wbgt, origin.lat, origin.lng);
    if (r == null && u == null && w == null && air == null) return const SizedBox.shrink();
    final tiles = <Widget>[
      if (air != null)
        Expanded(
          child: BentoTile(
            icon: Icons.masks_outlined,
            value: air.psi24 != null ? '${air.psi24}' : '${air.pm25}',
            caption: '${s.airLabel} · ${air.level.index >= AirLevel.unhealthy.index ? s.maskNeeded : s.noMask}',
            tint: air.level.index >= AirLevel.unhealthy.index ? DL.amber : null,
            onTap: () => _showAir(context, s, air),
          ),
        ),
      if (r != null)
        Expanded(
          child: BentoTile(
            icon: Icons.water_drop_outlined,
            value: s.rainMm(r.$2),
            caption: s.rainNow,
            tint: r.$2 > 0 ? DL.amber : null,
          ),
        ),
      if (u != null)
        Expanded(
          child: BentoTile(
            icon: Icons.wb_sunny_outlined,
            value: '$u',
            caption: '${s.uvLabel} · ${s.uvLevel(u)}',
            tint: u >= 8 ? DL.amber : null,
          ),
        ),
      if (w != null)
        Expanded(
          child: BentoTile(
            icon: Icons.thermostat,
            value: '${w.$1.toStringAsFixed(1)}°',
            caption: '${s.heatLabel} · ${s.heatLevel(w.$2)}',
            tint: isHighHeat(w.$2) ? DL.amber : null,
          ),
        ),
    ];
    // Two tiles per row so numbers stay large.
    final rows = [for (var i = 0; i < tiles.length; i += 2) tiles.sublist(i, i + 2 > tiles.length ? tiles.length : i + 2)];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    row[i],
                  ],
                  if (row.length == 1) ...[const SizedBox(width: 12), const Expanded(child: SizedBox())],
                ],
              ),
            ),
          ),
      ],
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
            caption: '${s.taxisNear(placeTitle(s.placeLabel, origin))} · 500 m',
            tint: DL.amber,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => TaxiSheet(origin: origin),
            ),
          ),
        ),
      if (near != null)
        Expanded(
          child: BentoTile(
            icon: Icons.ramen_dining_outlined,
            value: s.metres(near.$2),
            caption: '${near.$1.name}${near.$1.closureOn(today) != null ? ' · ${s.closedNow}' : ''}',
            onTap: () {
              final h = near.$1;
              final closed = h.closureOn(today);
              final next = h.nextClosure(today);
              final alt = closed == null ? const <(Hawker, double)>[] : openAlternatives(hawkers, h, today, limit: 1);
              showPlaceSheet(
                context,
                s: s,
                title: h.name,
                subtitle: h.address,
                lat: h.lat,
                lng: h.lng,
                distance: near.$2,
                extra: [
                  const HalalButton(),
                  AlertBanner(
                    icon: closed != null ? Icons.event_busy : Icons.event_available,
                    tone: closed != null ? AlertTone.warning : AlertTone.info,
                    text: closed != null
                        ? [s.closedNow, if (alt.isNotEmpty) s.tryInstead(alt.first.$1.name, s.metres(alt.first.$2))].join('. ')
                        : next == null
                            ? s.noUpcomingClosure
                            : s.closedRange(shortDate(next.from), shortDate(next.to), s.closureReason(next.reason)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextButton.icon(
                      icon: const Icon(Icons.ramen_dining_outlined),
                      label: Text(s.seeHawkers),
                      onPressed: () {
                        Navigator.of(context).pop();
                        ref.read(nearbyKeyProvider.notifier).state = origin.kind.name;
                        ref.read(shellTabProvider.notifier).state = 1;
                      },
                    ),
                  ),
                ],
              );
            },
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
    return Panel(
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


Future<void> _showAir(BuildContext context, S s, AirQuality air) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.hazeTitle} · ${s.airLevel(air.level)}', style: t.titleLarge),
                const SizedBox(height: 6),
                Text(s.airDetail(air.region, air.psi24, air.pm25), style: t.bodySmall),
                const SizedBox(height: 14),
                AlertBanner(
                  icon: Icons.masks_outlined,
                  text: s.airAdviceShort(air.level),
                  tone: air.level.index >= AirLevel.unhealthy.index ? AlertTone.warning : AlertTone.info,
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(s.moreAtHaze),
                  onPressed: () => launchUrl(Uri.parse('https://www.haze.gov.sg'), mode: LaunchMode.externalApplication),
                ),
                Text(s.hazeSource, style: t.bodySmall),
              ],
            ),
          ),
        );
      },
    );

/// Ride-hailing apps in Singapore (Play Store package ids). market://launch opens
/// the app when installed, otherwise its store page.
const _rideApps = [
  ('Grab', 'com.grabtaxi.passenger', DL.mint),
  ('Gojek', 'com.gojek.app', DL.sky),
  ('CDG Zig', 'com.codigo.comfort', DL.sky),
  ('TADA', 'com.mvlchain.tada', DL.mint),
];

/// Opens a ride app (through the Play Store, which launches it when installed),
/// or its store page in the browser.
Future<void> _openRideApp(String id) async {
  try {
    if (await launchUrl(Uri.parse('market://launch?id=$id'), mode: LaunchMode.externalApplication)) return;
  } on Object {
    // No Play Store: fall through to the web page.
  }
  await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=$id'), mode: LaunchMode.externalApplication);
}

/// Taxi detail: live counts, a small radar of free taxis and stands, nearest stands,
/// and shortcuts to booking apps.
class TaxiSheet extends ConsumerWidget {
  const TaxiSheet({super.key, required this.origin});
  final Place origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final body = ref.watch(taxiProvider).valueOrNull;
    final pts = body == null ? const <(double, double)>[] : taxiPoints(body);
    final (n200, n500, n1k) = taxiBands(pts, origin.lat, origin.lng);
    final stands = ref.watch(taxiStandsProvider).valueOrNull ?? const <EPoint>[];
    final nearStands = nearestPoints(stands, origin.lat, origin.lng, limit: 3, radius: 1500);
    final where = origin.address ?? placeTitle(s.placeLabel, origin);

    Widget count(int n, String label) => Expanded(
          child: Column(
            children: [
              Text('$n', style: t.displaySmall),
              Text(label, style: t.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 0, 22, 24),
        children: [
          Text(s.taxisNear(placeTitle(s.placeLabel, origin)), style: t.titleLarge),
          Text(where, style: t.bodySmall),
          const SizedBox(height: 14),
          Panel(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [count(n200, s.within200), count(n500, s.within500), count(n1k, s.taxiWithin1km)]),
            ),
          ),
          SectionTitle(s.bookTaxi, padding: const EdgeInsets.fromLTRB(4, 0, 4, 10)),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 0,
            children: [
              for (final (name, id, color) in _rideApps)
                Panel(
                  color: color,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => _openRideApp(id),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_new, size: 18, color: DL.ink),
                          const SizedBox(width: 8),
                          Text(name, style: t.titleMedium?.copyWith(color: DL.ink)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.call),
            label: Text(s.callCdg),
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: '65521111')),
          ),
          const SizedBox(height: 18),
          Panel(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: _TaxiRadar(
                        origin: origin,
                        taxis: pts,
                        stands: [for (final (p, _) in nearestPoints(stands, origin.lat, origin.lng, limit: 30, radius: 1000)) p],
                        edge: DL.edge(context),
                        ring: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(s.taxiMapLegend, style: t.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          SectionTitle(s.taxiStands, padding: const EdgeInsets.fromLTRB(4, 4, 4, 10)),
          Panel(
            child: Column(
              children: [
                if (nearStands.isEmpty) EmptyNote(stands.isEmpty ? s.bundlesLoading : s.notAvailable),
                for (final (p, d) in nearStands)
                  ListTile(
                    leading: const Icon(Icons.local_taxi_outlined),
                    title: Text(p.name),
                    subtitle: Text('${s.metres(d)} · ${p.detail}'),
                    trailing: IconButton(
                      tooltip: s.directions,
                      icon: const Icon(Icons.directions_walk),
                      onPressed: () => openDirections(p.lat, p.lng, distance: d),
                    ),
                    onTap: () => showPlaceSheet(context, s: s, title: p.name, subtitle: p.detail, lat: p.lat, lng: p.lng, distance: d),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('${s.taxiLive} ${s.bookTaxiNote}', style: t.bodySmall),
        ],
      ),
    );
  }
}

/// 1 km radar around a place: rings, free taxis as dots, taxi stands as squares.
class _TaxiRadar extends CustomPainter {
  _TaxiRadar({required this.origin, required this.taxis, required this.stands, required this.edge, required this.ring});
  final Place origin;
  final List<(double, double)> taxis;
  final List<EPoint> stands;
  final Color edge;
  final Color ring;

  static const _range = 1000.0;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ring;
    for (final m in const [250.0, 500.0, 1000.0]) {
      canvas.drawCircle(c, r * m / _range, ringPaint);
    }
    Offset at(double lat, double lng) {
      final (e, n) = offsetMetres(origin.lat, origin.lng, lat, lng);
      return c + Offset(e / _range * r, -n / _range * r);
    }

    final stand = Paint()..color = DL.teal;
    final standEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = edge;
    for (final p in stands) {
      final o = at(p.lat, p.lng);
      if ((o - c).distance > r) continue;
      final rect = Rect.fromCenter(center: o, width: 12, height: 12);
      canvas.drawRect(rect, stand);
      canvas.drawRect(rect, standEdge);
    }
    final dot = Paint()..color = DL.amber;
    final dotEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = edge;
    for (final (la, lo) in taxis) {
      final o = at(la, lo);
      if ((o - c).distance > r) continue;
      canvas.drawCircle(o, 5, dot);
      canvas.drawCircle(o, 5, dotEdge);
    }
    // You are here.
    canvas.drawCircle(c, 9, Paint()..color = edge);
    canvas.drawCircle(c, 5, Paint()..color = DL.card);
    final tp = TextPainter(
      text: TextSpan(text: 'N', style: TextStyle(color: edge, fontSize: 12, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(_TaxiRadar old) => old.taxis != taxis || old.stands != stands || old.edge != edge;
}
