import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data.dart';
import '../logic.dart';
import '../providers.dart';
import 'place_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// EV chargers near a point for people who drive electric (Favorites.evPlug): the nearest
/// locations with the user's plug from the ev.json bundle, each with its free chargers asked
/// live from /v1/ev/{postal}. Used in Nearby > Park, Home > Parking and car trips.
class EvChargers extends ConsumerWidget {
  const EvChargers({super.key, required this.lat, required this.lng, required this.title});
  final double lat;
  final double lng;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final plug = ref.watch(favoritesProvider.select((f) => f.evPlug));
    final sites = ref.watch(evSitesProvider);
    final all = sites.valueOrNull ?? const <EvSite>[];
    final near = evNear(all, lat, lng, plug);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title, padding: const EdgeInsets.fromLTRB(4, 4, 4, 10)),
        Panel(
          child: Column(
            children: [
              if (sites.isLoading && all.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
              else if (all.isEmpty)
                EmptyNote(s.evNoData, icon: Icons.ev_station_outlined)
              else if (near.isEmpty)
                EmptyNote(s.evNone, icon: Icons.ev_station_outlined),
              for (final (site, d) in near) _EvRow(site: site, distance: d, plug: plug),
            ],
          ),
        ),
      ],
    );
  }
}

class _EvRow extends ConsumerWidget {
  const _EvRow({required this.site, required this.distance, required this.plug});
  final EvSite site;
  final double distance;
  final String plug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final live = ref.watch(evLiveProvider(site.postal));
    final counts = live.valueOrNull == null ? null : evFree(site, live.valueOrNull!, plug);
    final plugs = [for (final p in site.plugs) if (evPlugMatches(p.type, plug)) p];
    return ListTile(
      leading: const Icon(Icons.ev_station_outlined),
      title: Text(site.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([s.metres(distance), if (plugs.isNotEmpty) s.evPlugLine(plugs.first)].join(' · ')),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            counts == null ? '–' : s.evFreeOf(counts.$1, counts.$2),
            style: t.titleLarge?.copyWith(fontFamily: DL.display, color: counts != null && counts.$1 == 0 ? DL.attention : null),
          ),
          if (counts != null) Text(s.evFreeLabel, style: t.labelSmall),
        ],
      ),
      onTap: () => showPlaceSheet(
        context,
        s: s,
        title: site.name,
        subtitle: site.address,
        lat: site.lat,
        lng: site.lng,
        distance: distance,
        extra: [_EvDetail(site: site)],
      ),
    );
  }
}

/// Every charger group at the location with its live free count, price and operator.
class _EvDetail extends ConsumerWidget {
  const _EvDetail({required this.site});
  final EvSite site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final live = ref.watch(evLiveProvider(site.postal)).valueOrNull;
    final here = live == null ? const <EvLive>[] : evLiveFor(site, live);
    final plugs = here.isNotEmpty ? here.expand((l) => l.plugs).toList() : site.plugs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in plugs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.power_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.evPlugLine(p), style: t.bodyMedium)),
                  const SizedBox(width: 8),
                  Text(s.evPlugFree(p),
                      style: t.labelLarge?.copyWith(color: p.free == 0 ? DL.attention : DL.tealText)),
                ],
              ),
            ),
          if (site.operators.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.evOperator(site.operators), style: t.bodySmall)),
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.evLiveNote, style: t.bodySmall)),
        ],
      ),
    );
  }
}
