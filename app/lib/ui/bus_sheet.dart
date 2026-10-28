import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens "Where's my bus?" for [service] arriving at [stop]. [toName] is where the rider is
/// heading (shown under the title), empty when unknown.
Future<void> showWhereBus(BuildContext context, {required BusStop stop, required String service, String toName = ''}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => WhereBusSheet(stop: stop, service: service, toName: toName),
    );

/// The stops the bus still has to pass, with the bus drawn where LTA's GPS puts it. Refreshes
/// with the stop's arrivals (every 30 s). No map: "Open in Maps" hands the position to Google Maps.
class WhereBusSheet extends ConsumerStatefulWidget {
  const WhereBusSheet({super.key, required this.stop, required this.service, this.toName = ''});
  final BusStop stop;
  final String service;
  final String toName;

  @override
  ConsumerState<WhereBusSheet> createState() => _WhereBusSheetState();
}

class _WhereBusSheetState extends ConsumerState<WhereBusSheet> {
  int _pick = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final routes = ref.watch(busRoutesProvider).valueOrNull ?? BusRoutes.empty;
    final byCode = ref.watch(busStopsByCodeProvider);
    final etas = ref.watch(busArrivalProvider(widget.stop.code));
    final buses = [for (final e in etas.valueOrNull ?? const <BusEta>[]) if (e.service == widget.service) e];
    final bus = buses.isEmpty ? null : buses[_pick.clamp(0, buses.length - 1)];
    final strip = bus == null ? null : busStrip(bus, widget.stop.code, routes, byCode);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                BusPlate(widget.service),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.whereBusTitle, style: t.titleMedium),
                      Text(s.whereBusTo(widget.toName, clockLabel(now)), style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (etas.isLoading && buses.isEmpty) const LinearProgressIndicator(),
            if (!etas.isLoading && bus == null) EmptyNote(s.busGone),
            if (bus != null) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (i, b) in buses.take(2).indexed)
                    ChoiceChip(
                      label: Text(i == 0 ? s.nextBusChip(b.minutes) : s.thenBusChip(b.minutes)),
                      selected: i == _pick.clamp(0, buses.length - 1),
                      onSelected: (_) => setState(() => _pick = i),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!bus.monitored || bus.lat == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(s.noBusPosition, style: t.bodySmall),
                ),
              if (strip != null)
                for (final (k, st) in strip.stops.indexed)
                  _StripRow(
                    name: st.name,
                    first: k == 0,
                    last: k == strip.stops.length - 1,
                    passed: strip.busAt != null && k < strip.busAt!,
                    busHere: k == strip.busAt ? widget.service : null,
                    tag: k == strip.stops.length - 1
                        ? s.youTag(bus.minutes)
                        : strip.busAt != null && k < strip.busAt!
                            ? s.passedTag
                            : k == strip.busAt
                                ? s.busHereTag
                                : s.stopsTag(strip.stops.length - 1 - k),
                  ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(children: [
                  if (LoadBars.level(bus.load) > 0)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(padding: const EdgeInsets.only(right: 6), child: LoadBars(bus.load)),
                    ),
                  TextSpan(text: [s.loadLabel(bus.load), s.busExtras(bus)].where((x) => x.isNotEmpty).join(' · ')),
                ]),
                style: t.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (bus.lat != null && bus.lng != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.map_outlined),
                  label: Text(s.openInMaps),
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.google.com/maps/search/?api=1&query=${bus.lat},${bus.lng}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One stop on the route strip: a teal line (grey once passed), a dot, the bus plate where the
/// bus is, and the rider's stop drawn bigger and bold.
class _StripRow extends StatelessWidget {
  const _StripRow({
    required this.name,
    required this.first,
    required this.last,
    required this.passed,
    required this.busHere,
    required this.tag,
  });
  final String name;
  final bool first;
  final bool last;
  final bool passed;
  final String? busHere;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final lineColor = passed ? DL.shield : scheme.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: first ? null : 0,
                  bottom: last ? null : 0,
                  height: first || last ? 24 : null,
                  child: Container(width: 5, color: lineColor),
                ),
                if (busHere != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: DL.amber,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DL.ink, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_bus, size: 14, color: DL.ink),
                        const SizedBox(width: 2),
                        Text(busHere!,
                            style: const TextStyle(fontFamily: DL.display, fontWeight: FontWeight.w700, fontSize: 15, color: DL.ink)),
                      ],
                    ),
                  )
                else
                  Container(
                    width: last ? 22 : 16,
                    height: last ? 22 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: last ? DL.edge(context) : scheme.surface,
                      border: Border.all(color: last ? DL.edge(context) : lineColor, width: 3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                name,
                style: last
                    ? t.titleSmall?.copyWith(fontWeight: FontWeight.w800)
                    : passed
                        ? t.bodyMedium?.copyWith(color: DL.mist)
                        : t.bodyLarge,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 12),
            child: Text(
              tag,
              style: t.labelMedium?.copyWith(
                color: last ? DL.tealText : busHere != null ? const Color(0xFFB45309) : DL.mist,
                fontWeight: last || busHere != null ? FontWeight.w800 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
