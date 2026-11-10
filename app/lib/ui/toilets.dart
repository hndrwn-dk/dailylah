import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data.dart';
import '../logic.dart';
import '../mrt_ride.dart';
import '../providers.dart';
import '../wake_session.dart';
import 'place_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Where "Need a toilet?" was asked: on the bus ("Wake me at my stop") or on the train.
enum ToiletRide { bus, train }

/// Opens [ToiletSheet] for the ride that runs.
Future<void> showToiletSheet(BuildContext context, ToiletRide ride) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ToiletSheet(ride: ride),
    );

/// "Need a toilet?" during a ride: up to three stops or stations ahead where a toilet is close,
/// soonest first ([toiletsAheadBus], [toiletsAheadMrt]). Worked out on the phone from the
/// `toilets` bundle; the position is never sent anywhere.
class ToiletSheet extends ConsumerWidget {
  const ToiletSheet({super.key, required this.ride});
  final ToiletRide ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final list = ride == ToiletRide.bus ? ref.watch(busToiletsProvider) : ref.watch(trainToiletsProvider);
    final loading = ref.watch(toiletsProvider).isLoading;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(s.toiletNeed, style: t.titleLarge),
            const SizedBox(height: 12),
            if (list == null && loading)
              const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
            else if (list == null || list.isEmpty)
              Panel(child: EmptyNote(s.toiletNoneAhead, icon: Icons.wc))
            else
              ToiletRows(stops: list),
            const ToiletFooter(),
          ],
        ),
      ),
    );
  }
}

/// Nearby > Toilets: the three best toilets near [lat], [lng] ([toiletsNear]).
class ToiletsNearby extends ConsumerWidget {
  const ToiletsNearby({super.key, required this.lat, required this.lng});
  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final near = ref.watch(toiletsNearProvider((lat, lng)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(s.toiletsNearby),
        if (near == null && ref.watch(toiletsProvider).isLoading)
          const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
        else if (near == null || near.isEmpty)
          Panel(child: EmptyNote(s.toiletNoneNear, icon: Icons.wc))
        else
          ToiletRows(stops: [
            for (final (toilet, m) in near) ToiletStop(at: '', rideMinutes: 0, toilet: toilet, metres: m),
          ]),
        const ToiletFooter(),
      ],
    );
  }
}

/// The rows in one panel: "Get off at X (in about 6 min)" with the toilet and walk under it on a
/// ride, or the toilet with its distance near a place. Walking directions open Google Maps with the
/// toilet as the destination only (Maps uses the phone's own location).
class ToiletRows extends ConsumerWidget {
  const ToiletRows({super.key, required this.stops});
  final List<ToiletStop> stops;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Panel(
      child: Column(
        children: [
          for (final (i, st) in stops.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: Icon(_kindIcon(st.kind), color: DL.goText(context)),
              title: Text(st.at.isEmpty ? st.toilet!.name : s.toiletGetOff(st.at, st.rideMinutes)),
              subtitle: Text(switch (st) {
                ToiletStop(at: '', toilet: final toilet?) =>
                  s.toiletNearLine(s.toiletKind(toilet.kind), s.metres(st.metres), st.walkMinutes),
                ToiletStop(toilet: final toilet?) => s.toiletWalk(toilet.name, st.walkMinutes),
                _ => s.toiletAssumed,
              }),
              trailing: st.toilet == null
                  ? null
                  : IconButton(
                      tooltip: s.toiletDirections,
                      icon: const Icon(Icons.directions_walk),
                      onPressed: () => openDirections(st.toilet!.lat, st.toilet!.lng, mode: 'walking'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The estimate note and the OpenStreetMap attribution, under every toilet list.
class ToiletFooter extends ConsumerWidget {
  const ToiletFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.toiletNote, style: t.bodySmall?.copyWith(color: DL.muted(context))),
          const SizedBox(height: 4),
          Text(s.placesAttribution, style: t.bodySmall?.copyWith(color: DL.muted(context))),
        ],
      ),
    );
  }
}

IconData _kindIcon(ToiletKind k) => switch (k) {
      ToiletKind.mall => Icons.local_mall_outlined,
      ToiletKind.station => Icons.train_outlined,
      ToiletKind.hawker => Icons.ramen_dining_outlined,
      ToiletKind.park => Icons.park_outlined,
      ToiletKind.other => Icons.wc,
    };
