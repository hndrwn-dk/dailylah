import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../background.dart';
import '../data.dart';
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'bus_sheet.dart';
import 'place_sheet.dart';
import 'stop_picker.dart';
import 'theme.dart';
import 'trip.dart';
import 'widgets.dart';

/// Today: morning card before 14:00, evening card after.
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key, this.controller});

  /// Main list scroll, owned by the shell (tap the tab again to go to the top).
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final kind = ref.watch(cardKindProvider);
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final origin = fav.places[originFor(kind, fav, now)];
    // MOE school holidays: no school trip (work trips are not affected).
    final holiday = schoolHolidayOn(ref.watch(schoolHolidaysProvider).valueOrNull ?? const [], now);
    final schoolOff = holiday != null && commutePlace(fav, now)?.kind == PlaceKind.school;
    final commute = isCommuteDay(fav, now) && !schoolOff;
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

    final modeEnd = kind == CardKind.morning ? dest : origin;
    final tripMode = modeEnd == null ? null : ref.watch(modeOverrideProvider)[modeEnd.kind.name] ?? modeEnd.mode;

    final dests = <Widget>[
      for (final a in alerts) AlertBanner(icon: _alertIcon(a.kind), text: a.text),
      if (schoolOff) AlertBanner(icon: Icons.beach_access_outlined, tone: AlertTone.info, text: s.schoolHolidayToday(holiday.name)),
      if (origin != null) _WeatherTiles(origin: origin),
      if (commute && origin != null && dest != null)
        TripSection(
          commute: true,
          fromKey: origin.kind.name,
          from: origin,
          to: dest,
          modeKey: (kind == CardKind.morning ? dest : origin).kind.name,
          modePlace: kind == CardKind.morning ? dest : origin,
        ),
      if (!commute || (tripMode ?? TravelMode.transit) == TravelMode.transit)
        _MrtCard(showCrowd: kind == CardKind.evening),
      if (!commute && fav.places[PlaceKind.home] != null) _WeekendCard(home: fav.places[PlaceKind.home]!),
      const PlanTripCard(),
      if (fav.carparks.isNotEmpty) const _SavedParking(),
      const SizedBox(height: 8),
      Text('${s.dataSource} ${s.pullToRefresh}', style: t.bodySmall, textAlign: TextAlign.center),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        edgeOffset: 80,
        child: ListView(
          controller: controller,
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
                          '${!commute || dest == null ? s.todayLabel : kind == CardKind.morning ? s.headingTo(placeTitle(s.placeLabel, dest)) : s.headingHome} · ${_dateLabel(now)}',
                          style: t.labelMedium?.copyWith(color: t.bodySmall?.color),
                        ),
                      ),
                      const SizedBox(width: 8),
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
      error: (_, __) => Row(
        children: [
          Expanded(child: Text(s.serverWaking, style: dim)),
          TextButton(onPressed: () => ref.invalidate(forecastProvider), child: Text(s.retry)),
        ],
      ),
      data: (json) {
        final stale = liveStaleSince(json, ref.watch(clockProvider).valueOrNull ?? DateTime.now());
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
                    if (stale != null) ...[
                      const SizedBox(height: 2),
                      Text(s.updatedAt(clockLabel(stale)),
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
        TextSpan(text: '$label  ', style: t.bodySmall?.copyWith(color: DL.ink.withValues(alpha: 0.7))),
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
    final resting = transitResting(ref.watch(clockProvider).valueOrNull ?? DateTime.now());

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
                      st.disrupted
                          ? (st.detail?.isNotEmpty == true ? st.detail! : s.mrtDisrupted)
                          : resting
                              ? s.mrtResting
                              : s.mrtNormal,
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
          error: (_, __) => Row(
            children: [
              Expanded(child: Text(s.serverWaking)),
              TextButton(onPressed: () => ref.invalidate(trainAlertsProvider), child: Text(s.retry)),
            ],
          ),
          data: (json) {
            final all = lineStatuses(json, trainLines.keys.toSet());
            final down = all.where((x) => x.disrupted).toList();
            final pinned = all.where((x) => !x.disrupted && starred.contains(x.line)).toList();
            final rest = all.where((x) => !x.disrupted && !starred.contains(x.line)).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.mrtLinesAll, style: t.titleMedium),
                Text(
                    down.isNotEmpty
                        ? s.mrtAlert(down.map((x) => x.line).join(', '))
                        : resting
                            ? s.trainsResting
                            : s.allLinesNormal,
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
    final routes = ref.watch(busRoutesProvider).valueOrNull ?? BusRoutes.empty;
    final byCode = ref.watch(busStopsByCodeProvider);
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
                  ? EmptyNote(transitResting(ref.watch(clockProvider).valueOrNull ?? DateTime.now()) ? s.busesResting : s.noBusesNow)
                  : Column(children: [
                      for (final (i, (e, next)) in groupEtas(list).take(8).indexed)
                        BusRow(
                          eta: e,
                          next: next,
                          pulse: i == 0 && e.minutes == 0,
                          live: s.busLive(e, busWhere(e, stop.code, routes, byCode)),
                          onTap: () => showWhereBus(context, stop: stop, service: e.service),
                        ),
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}

class BusRow extends ConsumerWidget {
  const BusRow({super.key, required this.eta, this.pulse = true, this.note, this.next, this.live, this.onTap});
  final BusEta eta;

  /// Opens "Where's my bus?"; the row shows a chevron when set.
  final VoidCallback? onTap;

  /// Where the bus is now, or that its time is only the timetable.
  final String? live;

  /// Minutes until the following bus of the same service, if known.
  final int? next;

  /// Blink "Arr"; only the first arriving bus in a list blinks to keep it calm.
  final bool pulse;

  /// Optional line under the row, e.g. where to get off.
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final arriving = eta.minutes == 0;
    // No blinking when the phone asks for less motion.
    final blink = pulse && !MediaQuery.of(context).disableAnimations;
    final arr = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: DL.amber,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DL.edge(context), width: 2),
      ),
      child: Text(s.minutesAway(0), style: t.displaySmall?.copyWith(color: DL.ink, fontSize: 26)),
    );
    final eta0 = arriving
        ? (blink ? Pulse(child: arr) : arr)
        : Text.rich(
            TextSpan(children: [
              TextSpan(text: s.minutesAway(eta.minutes), style: t.displaySmall),
              TextSpan(text: ' ${s.min}', style: t.bodyMedium),
            ]),
          );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BusPlate(eta.service),
          const SizedBox(width: 12),
          // Wraps under large text instead of overflowing.
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                eta0,
                if (next != null) Text(s.thenIn(next!), style: t.bodyMedium),
                LoadMeter(eta.load, label: s.loadLabel(eta.load)),
                if (eta.wheelchair) Text(s.wheelchairBus, style: t.bodySmall),
                if (live != null)
                  SizedBox(
                    width: double.infinity,
                    child: Text.rich(
                      TextSpan(children: [
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.my_location, size: 14)),
                        ),
                        TextSpan(text: live),
                      ]),
                      style: t.bodySmall,
                    ),
                  ),
                if (note != null) SizedBox(width: double.infinity, child: Text(note!, style: t.bodySmall)),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right),
        ],
      ),
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

/// On days without a trip to work or school: a few weekend ideas near home, indoor ones
/// first when it rains or the air is unhealthy.
class _WeekendCard extends ConsumerWidget {
  const _WeekendCard({required this.home});
  final Place home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final around = ref.watch(aroundProvider).valueOrNull ?? AroundSet.empty;
    final pois = ref.watch(poisProvider).valueOrNull ?? PoiSet.empty;
    final forecast = ref.watch(forecastProvider).valueOrNull;
    final air = airNear(ref.watch(psiProvider).valueOrNull, ref.watch(pm25Provider).valueOrNull, home.lat, home.lng);
    final indoor = preferIndoor(forecast == null ? null : forecastNear(forecast, home.lat, home.lng)) ||
        (air != null && air.level.index >= AirLevel.unhealthy.index);
    EPoint fromPoi(Poi p) => EPoint(name: p.name, lat: p.lat, lng: p.lng, detail: p.detail);
    // Park facilities by name, for icons on the park picks.
    final facilities = {for (final p in pois.of(PoiKind.park)) if (p.facilities.isNotEmpty) p.name: p.facilities};
    final picks = weekendPicks({
      for (final k in const ['museum', 'activesg', 'attraction', 'bbq', 'pcn']) k: around.of(k),
      'park': [for (final p in pois.of(PoiKind.park)) fromPoi(p)],
      'library': [for (final p in pois.of(PoiKind.library)) fromPoi(p)],
    }, home.lat, home.lng, indoor: indoor);
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final events = eventsNear(ref.watch(eventsProvider).valueOrNull ?? const <PublicEvent>[], home.lat, home.lng, now,
        days: daysToWeekendEnd(now));
    if (picks.isEmpty && events.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          s.weekendCard,
          trailing: TextButton(
            onPressed: () {
              ref.read(homeSectionProvider.notifier).state = 'weekend';
              ref.read(shellTabProvider.notifier).state = 2;
            },
            child: Text(s.seeAll),
          ),
        ),
        if (events.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(s.eventsNearby, style: t.titleSmall)),
          Panel(
            child: Column(
              children: [
                for (final (e, d) in events)
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: Text(e.name),
                    subtitle: Text(
                      [
                        if (e.when.isNotEmpty) e.when,
                        if (e.place.isNotEmpty) e.place,
                        s.metres(d),
                        if (e.free) s.freeEvent,
                      ].join(' · '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => launchUrl(Uri.parse(e.url), mode: LaunchMode.externalApplication),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(s.eventsFrom({for (final (e, _) in events) e.source}.join(' and ')), style: t.bodySmall),
                ),
              ],
            ),
          ),
        ],
        if (indoor && picks.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(s.weekendIndoor, style: t.bodySmall)),
        if (!indoor && picks.any((x) => x.$1 == 'park' || x.$1 == 'pcn' || x.$1 == 'bbq'))
          if (ref.watch(parkTimeProvider((home.lat, home.lng))) case final p?)
            ParkTimeBanner(time: p, text: s.parkTimeLine(p)),
        if (picks.isNotEmpty)
        Panel(
          child: Column(
            children: [
              for (final (k, p, d) in picks)
                ListTile(
                  leading: Icon(switch (k) {
                    'museum' => Icons.museum_outlined,
                    'library' => Icons.local_library_outlined,
                    'activesg' => Icons.sports_tennis,
                    'park' => Icons.park_outlined,
                    'bbq' => Icons.outdoor_grill_outlined,
                    'pcn' => Icons.directions_bike,
                    _ => Icons.attractions_outlined,
                  }),
                  title: Text(p.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${s.weekendKind(k)} · ${s.metres(d)}'),
                      if (k == 'park')
                        if (facilities[p.name] case final f?) FacilityIcons(f),
                    ],
                  ),
                  onTap: () => showPlaceSheet(
                    context,
                    s: s,
                    title: p.name,
                    subtitle: p.detail,
                    lat: p.lat,
                    lng: p.lng,
                    distance: d,
                    extra: [
                      if (k == 'park')
                        if (facilities[p.name] case final f?) ...[
                          Text(s.facilities, style: t.titleSmall),
                          const SizedBox(height: 8),
                          InfoChips(f, icons: true),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
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

const _apps = MethodChannel('dailylah/apps');

/// Food delivery apps in Singapore (GrabFood lives inside the Grab app).
const foodApps = [
  ('GrabFood', 'com.grabtaxi.passenger', DL.mint),
  ('foodpanda', 'com.global.foodpanda.android', DL.sky),
];

/// Opens an app directly when installed; otherwise its Play Store page.
Future<void> openApp(String id) async {
  try {
    if (await _apps.invokeMethod<bool>('launch', {'package': id}) ?? false) return;
  } on Object {
    // No channel (tests, iOS): fall through to the store.
  }
  try {
    if (await launchUrl(Uri.parse('market://details?id=$id'), mode: LaunchMode.externalApplication)) return;
  } on Object {
    // No Play Store: open the web page below.
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
    final (_, n500, n1k) = taxiBands(pts, origin.lat, origin.lng);
    final stands = ref.watch(taxiStandsProvider).valueOrNull ?? const <EPoint>[];
    final nearStands = nearestPoints(stands, origin.lat, origin.lng, limit: 3, radius: 1500);
    final where = origin.address ?? placeTitle(s.placeLabel, origin);
    final best = nearStands.isEmpty ? null : nearStands.first;

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
          // 1. The answer: is it easy to get a taxi here now?
          if (body == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LinearProgressIndicator())
          else
            TaxiEaseCard(level: taxiEase(n500, n1k), count: n1k),
          // 2. The fastest way: the nearest stand and the taxis around it.
          if (best != null) ...[
            _Tag(s.fastestWay),
            Panel(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const _StandBadge(size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.taxiStandAt(best.$1.name), style: t.titleMedium),
                              Text(s.standLine(best.$2, taxisAround(pts, best.$1.lat, best.$1.lng)),
                                  style: t.bodyMedium?.copyWith(color: DL.mist)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.directions_walk),
                      label: Text(s.walkThere),
                      onPressed: () => openDirections(best.$1.lat, best.$1.lng, distance: best.$2, mode: 'walking'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // 3. Where the taxis are: a live radar, stands and taxis tappable.
          _Tag(s.taxisWhereNow),
          TaxiRadar(
            origin: origin,
            taxis: pts,
            stands: [for (final (p, _) in nearestPoints(stands, origin.lat, origin.lng, limit: 30, radius: 1000)) p],
          ),
          // 4. Or book one.
          _Tag(s.bookTaxi),
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
                    onTap: () => openApp(id),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
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
                ),
            ],
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.call),
            label: Text(s.callCdg),
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: '65521111')),
          ),
          if (nearStands.length > 1) ...[
            _Tag(s.taxiStands),
            Panel(
              child: Column(
                children: [
                  for (final (p, d) in nearStands)
                    ListTile(
                      leading: const _StandBadge(size: 32),
                      title: Text(p.name),
                      subtitle: Text('${s.metres(d)} · ${s.walkMinutes(d)}'),
                      trailing: IconButton(
                        tooltip: s.directions,
                        icon: const Icon(Icons.directions_walk),
                        onPressed: () => openDirections(p.lat, p.lng, distance: d, mode: 'walking'),
                      ),
                      onTap: () => _openStand(context, s, p, d, pts),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text('${s.taxiLive} ${s.bookTaxiNote}', style: t.bodySmall),
        ],
      ),
    );
  }
}

void _openStand(BuildContext context, S s, EPoint p, double d, List<(double, double)> taxis) => showPlaceSheet(
      context,
      s: s,
      title: p.name,
      subtitle: [p.detail, s.standLine(d, taxisAround(taxis, p.lat, p.lng))].where((x) => x.isNotEmpty).join('\n'),
      lat: p.lat,
      lng: p.lng,
      distance: d,
    );

/// Small caps section label inside the taxi sheet.
class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: DL.mist, letterSpacing: 0.8, fontWeight: FontWeight.w800)),
      );
}

/// Teal "T" square for a taxi stand.
class _StandBadge extends StatelessWidget {
  const _StandBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DL.teal,
          borderRadius: BorderRadius.circular(size / 4),
          border: Border.all(color: DL.ink, width: 2),
        ),
        child: Text('T', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.45)),
      );
}

/// "Easy to get one now": teal when easy (go), amber when hard or none (look now), with a
/// four-step Hard–Easy gauge and the count within 1 km.
class TaxiEaseCard extends ConsumerWidget {
  const TaxiEaseCard({super.key, required this.level, required this.count});
  final int level;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final easy = level >= 3;
    final fg = easy ? Colors.white : DL.ink;
    return Panel(
      color: easy ? DL.teal : DL.amber,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: DL.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: DL.ink, width: 2.5),
                  ),
                  child: const Icon(Icons.local_taxi, color: DL.ink, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.taxiEaseTitle(level),
                          style: t.headlineSmall
                              ?.copyWith(fontFamily: DL.display, fontWeight: FontWeight.w700, color: fg, height: 1.05)),
                      Text(s.taxiEaseSub(count), style: t.bodyMedium?.copyWith(color: fg)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 1; i <= 4; i++) ...[
                  if (i > 1) const SizedBox(width: 5),
                  Expanded(
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: i <= level ? fg : fg.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(s.easeHard, style: t.labelSmall?.copyWith(color: fg)),
                const Spacer(),
                Text(s.easeEasy, style: t.labelSmall?.copyWith(color: fg)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 1 km radar on the dark board: rings labelled in walking minutes, free taxis as small cabs
/// with a glow, stands as tappable "T" pins (open the stand), and a tap near a taxi says how
/// far and which way it is. Counts per ring under it.
class TaxiRadar extends ConsumerStatefulWidget {
  const TaxiRadar({super.key, required this.origin, required this.taxis, required this.stands});
  final Place origin;
  final List<(double, double)> taxis;
  final List<EPoint> stands;

  static const range = 1000.0;
  static const rings = [200.0, 500.0, 1000.0];

  @override
  ConsumerState<TaxiRadar> createState() => _TaxiRadarState();
}

class _TaxiRadarState extends ConsumerState<TaxiRadar> {
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final o = widget.origin;
    final (n200, n500, n1k) = taxiBands(widget.taxis, o.lat, o.lng);
    final picked = _picked != null && _picked! < widget.taxis.length ? widget.taxis[_picked!] : null;
    String pickedText() {
      if (picked == null) return s.taxiTapHint;
      final (e, n) = offsetMetres(o.lat, o.lng, picked.$1, picked.$2);
      return s.freeTaxiAt(distanceMeters(o.lat, o.lng, picked.$1, picked.$2), compass8(e, n));
    }

    final light = t.bodySmall?.copyWith(color: DL.ledDim);

    Widget count(int n, double m) => Expanded(
          child: Column(
            children: [
              Text('$n', style: t.headlineSmall?.copyWith(fontFamily: DL.display, color: DL.led, fontWeight: FontWeight.w700)),
              Text(s.underWalk(m), style: light, textAlign: TextAlign.center),
            ],
          ),
        );

    return Panel(
      color: DL.board,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(builder: (context, box) {
                final c = box.biggest.center(Offset.zero);
                final r = box.biggest.shortestSide / 2 - 20;
                Offset at(double lat, double lng) {
                  final (e, n) = offsetMetres(o.lat, o.lng, lat, lng);
                  return c + Offset(e / TaxiRadar.range * r, -n / TaxiRadar.range * r);
                }

                final cabs = <(int, Offset)>[
                  for (final (i, (la, lo)) in widget.taxis.indexed)
                    if ((at(la, lo) - c).distance <= r) (i, at(la, lo)),
                ];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    (int, double)? hit;
                    for (final (i, p) in cabs) {
                      final dist = (p - d.localPosition).distance;
                      if (dist <= 28 && (hit == null || dist < hit.$2)) hit = (i, dist);
                    }
                    setState(() => _picked = hit?.$1);
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TaxiRadarPainter(
                            center: c,
                            radius: r,
                            cabs: [for (final (_, p) in cabs) p],
                            picked: picked == null ? null : at(picked.$1, picked.$2),
                            labels: [for (final m in TaxiRadar.rings) s.ringMin(m)],
                          ),
                        ),
                      ),
                      for (final p in widget.stands)
                        if ((at(p.lat, p.lng) - c).distance <= r)
                          Positioned(
                            left: at(p.lat, p.lng).dx - 16,
                            top: at(p.lat, p.lng).dy - 16,
                            child: TaxiStandPin(
                              stand: p,
                              onTap: () => _openStand(context, s, p, distanceMeters(o.lat, o.lng, p.lat, p.lng), widget.taxis),
                            ),
                          ),
                    ],
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(pickedText(),
                  style: picked == null ? light : t.bodyMedium?.copyWith(color: DL.led, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [count(n200, 200), count(n500, 500), count(n1k, 1000)]),
            const Divider(color: DL.nightEdge, height: 22),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final (color, label) in [(DL.led, s.legendTaxi), (DL.tealLight, s.legendStand), (DL.tealLight, s.legendYou)])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 12, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      Text(label, style: t.bodySmall?.copyWith(color: DL.card)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A taxi stand on the radar: a 32 px tap target around the "T" square.
class TaxiStandPin extends StatelessWidget {
  const TaxiStandPin({super.key, required this.stand, required this.onTap});
  final EPoint stand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: stand.name,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DL.teal,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: DL.card, width: 2),
              ),
              child: const Text('T',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1)),
            ),
          ),
        ),
      );
}

class _TaxiRadarPainter extends CustomPainter {
  _TaxiRadarPainter({required this.center, required this.radius, required this.cabs, required this.picked, required this.labels});
  final Offset center;
  final double radius;
  final List<Offset> cabs;
  final Offset? picked;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    final c = center, r = radius;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF2B3B40);
    for (final m in TaxiRadar.rings) {
      canvas.drawCircle(c, r * m / TaxiRadar.range, ring);
    }
    // Soft glow under each taxi so busy areas read at a glance.
    final glow = Paint()
      ..color = DL.led.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    for (final p in cabs) {
      canvas.drawCircle(p, 13, glow);
    }
    // Ring labels in walking minutes, at the bottom right of each ring.
    for (final (i, m) in TaxiRadar.rings.indexed) {
      final k = r * m / TaxiRadar.range * 0.707;
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: const TextStyle(color: DL.ledDim, fontSize: 10, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = Rect.fromCenter(center: c + Offset(k, k), width: tp.width + 12, height: tp.height + 4);
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(8));
      canvas.drawRRect(rr, Paint()..color = DL.board);
      canvas.drawRRect(rr, ring);
      tp.paint(canvas, box.topLeft + const Offset(6, 2));
    }
    final body = Paint()..color = DL.led;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = DL.ink;
    final roof = Paint()..color = DL.ink;
    for (final p in cabs) {
      final car = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 14, height: 9), const Radius.circular(3));
      canvas.drawRRect(car, body);
      canvas.drawRRect(car, edge);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: p + const Offset(0, -5.5), width: 6, height: 3), const Radius.circular(1)),
          roof);
    }
    if (picked != null) {
      canvas.drawCircle(
          picked!,
          13,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = DL.card);
    }
    // You are here.
    canvas.drawCircle(c, 15, Paint()..color = DL.teal.withValues(alpha: 0.3));
    canvas.drawCircle(c, 8, Paint()..color = DL.card);
    canvas.drawCircle(
        c,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = DL.teal);
    for (final (label, off) in [('N', Offset(0, -r - 11)), ('E', Offset(r + 11, 0)), ('S', Offset(0, r + 11)), ('W', Offset(-r - 11, 0))]) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(color: DL.card, fontSize: 12, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + off - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_TaxiRadarPainter old) =>
      old.cabs != cabs || old.picked != picked || old.center != center || old.radius != radius;
}
