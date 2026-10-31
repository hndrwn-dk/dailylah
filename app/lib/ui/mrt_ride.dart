import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic.dart';
import '../mrt_ride.dart';
import '../providers.dart';
import 'theme.dart';
import 'widgets.dart';

/// "On the train": the line status (checked every 2 min), every station to the rider's stop
/// with an estimated position, the one-stop-before alert, and I've arrived.
class MrtRidePage extends ConsumerWidget {
  const MrtRidePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final st = ref.watch(rideProvider);
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    if (st == null) {
      return Scaffold(appBar: AppBar(title: Text(s.rideTitle)), body: const SizedBox.shrink());
    }
    final r = st.ride;
    final here = st.indexAt(now);
    final eta = clockLabel(st.eta(now));
    final firstLine = rideLineAt(r, 0);
    return Scaffold(
      appBar: AppBar(title: Text(s.rideTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(s.rideTo(r.alight.name), style: t.titleLarge),
              for (final c in r.alight.codes) StationChip(c),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 12),
            child: Text(s.rideSub(firstLine == null ? '' : s.lineName(firstLine), r.stops - here, eta),
                style: t.bodyMedium?.copyWith(color: DL.mist)),
          ),
          RideStatusCard(state: st),
          const SizedBox(height: 14),
          Panel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, station) in r.stations.indexed)
                    _RideRow(
                      name: station.name,
                      codes: station.codes,
                      first: i == 0,
                      last: i == r.stops,
                      passed: i < here,
                      here: i == here && i != r.stops,
                      color: DL.lineColor(rideLineAt(r, i) ?? ''),
                      tag: i == r.stops
                          ? s.rideYourStop(eta)
                          : i == here
                              ? s.rideAboutHere
                              : i < here
                                  ? s.ridePassed
                                  : i == r.viaIndex
                                      ? s.rideChangeHere
                                      : st.alertOn && i == r.stops - 1
                                          ? s.rideAlertHere
                                          : '',
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 0, 0),
                    child: Text(s.rideEstimateNote, style: t.bodySmall),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (r.stops >= 2)
            Panel(
              child: SwitchListTile(
                title: Text(s.rideAlertTitle),
                subtitle: Text(s.rideAlertSub(r.stations[r.stops - 1].name)),
                value: st.alertOn,
                onChanged: ref.read(rideProvider.notifier).setAlert,
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () {
                    ref.read(rideProvider.notifier).stop();
                    Navigator.of(context).maybePop();
                  },
                  child: Text(s.rideStop),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => finishRide(context, ref),
                  child: Text(s.rideArrived),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ends the ride and, when a trip is being timed, logs it to History.
Future<void> finishRide(BuildContext context, WidgetRef ref) async {
  final s = ref.read(stringsProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final nav = Navigator.of(context);
  final onPage = ModalRoute.of(context)?.isFirst == false;
  ref.read(rideProvider.notifier).stop();
  final habits = ref.read(habitsProvider);
  if (habits.tripStart != null) {
    final m = await ref.read(habitsProvider.notifier).finishTrip(DateTime.now());
    messenger?.showSnackBar(SnackBar(content: Text(m == null ? s.tripTooShort : s.tripLogged(m))));
  }
  if (onPage && nav.canPop()) nav.maybePop();
}

/// Green "Running normally" or amber "Delay on the X Line" with LTA's detail.
class RideStatusCard extends ConsumerWidget {
  const RideStatusCard({super.key, required this.state});
  final RideState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final bad = state.disrupted;
    final ok = bad.isEmpty;
    return Panel(
      color: ok ? DL.mint : DL.amber,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded, color: ok ? DL.tealText : DL.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.alerts == null ? s.rideChecking : ok ? s.rideOk : s.rideDelayOn(s.lineName(bad.first.line)),
                    style: t.titleSmall?.copyWith(color: DL.ink),
                  ),
                  Text(
                    ok ? s.rideCheckNote : (bad.first.detail ?? s.rideCheckNote),
                    style: t.bodySmall?.copyWith(color: DL.ink),
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

class _RideRow extends StatelessWidget {
  const _RideRow({
    required this.name,
    required this.codes,
    required this.first,
    required this.last,
    required this.passed,
    required this.here,
    required this.color,
    required this.tag,
  });
  final String name;
  final List<String> codes;
  final bool first;
  final bool last;
  final bool passed;
  final bool here;
  final Color color;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final line = passed ? DL.shield : color;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: first ? null : 0,
                  bottom: last ? null : 0,
                  height: first || last ? 20 : null,
                  child: Container(width: 5, color: line),
                ),
                if (here)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: DL.amber,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DL.ink, width: 2),
                    ),
                    child: const Icon(Icons.subway, size: 16, color: DL.ink),
                  )
                else
                  Container(
                    width: last ? 20 : 14,
                    height: last ? 20 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: last ? DL.edge(context) : Theme.of(context).colorScheme.surface,
                      border: Border.all(color: last ? DL.edge(context) : line, width: 3),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    name,
                    style: last
                        ? t.titleSmall?.copyWith(fontWeight: FontWeight.w800)
                        : passed
                            ? t.bodyMedium?.copyWith(color: DL.mist)
                            : t.bodyMedium,
                  ),
                  if (first || last || codes.length > 1)
                    for (final c in codes) StationChip(c),
                ],
              ),
            ),
          ),
          if (tag.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 10),
              child: Text(
                tag,
                style: t.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: last ? DL.tealText : passed ? DL.mist : const Color(0xFFB45309),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The ride above the tabs on every screen (like [WakeBanner]); amber when the line is
/// disrupted. Tap to open the ride, Arrived to end it.
class RideBanner extends ConsumerWidget {
  const RideBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(rideProvider);
    if (st == null) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final bad = st.disrupted;
    final left = st.ride.stops - st.indexAt(now);
    return Panel(
      margin: const EdgeInsets.only(bottom: 10),
      color: bad.isEmpty ? DL.mint : DL.amber,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MrtRidePage())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Icon(bad.isEmpty ? Icons.subway_outlined : Icons.warning_amber_rounded, color: DL.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.rideTo(st.ride.alight.name), style: t.titleSmall?.copyWith(color: DL.ink)),
                    Text(
                      s.rideBannerSub(left, clockLabel(st.eta(now)), bad.isEmpty ? null : s.rideDelayOn(s.lineName(bad.first.line))),
                      style: t.bodySmall?.copyWith(color: DL.ink),
                    ),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => finishRide(context, ref),
                child: Text(s.arrived),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
