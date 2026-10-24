import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import '../wake_session.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Wake me at my stop": shows the ride kept in [wakeProvider]. Leaving this page does not
/// stop it; the banner above the tabs does, as does Stop here. Location is used only while a
/// ride runs (kept alive with the screen off by a foreground notification) and never stored.
class WakeMePage extends ConsumerStatefulWidget {
  const WakeMePage({super.key, required this.service, required this.alight, this.before});
  final String service;
  final BusStop alight;
  final BusStop? before;

  @override
  ConsumerState<WakeMePage> createState() => _WakeMePageState();
}

class _WakeMePageState extends ConsumerState<WakeMePage> {
  @override
  void initState() {
    super.initState();
    final now = ref.read(wakeProvider);
    // Opening the page for the ride already running just shows it.
    if (now == null || now.service != widget.service || now.alight.code != widget.alight.code) {
      Future.microtask(() => ref.read(wakeProvider.notifier).start(widget.service, widget.alight, widget.before));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final w = ref.watch(wakeProvider);
    final done = w?.done ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(s.wakeTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Panel(
            color: done ? DL.amber : null,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.wakeRiding(widget.service, widget.alight.name),
                      style: t.titleMedium?.copyWith(color: done ? DL.ink : null)),
                  const SizedBox(height: 10),
                  if (w?.error case final e?)
                    Text(e, style: t.bodyMedium)
                  else if (w?.event == WakeEvent.passed)
                    Text(s.wakePassed(widget.alight.name), style: t.headlineSmall?.copyWith(color: DL.ink))
                  else if (done)
                    Text(s.wakeNowAt(widget.alight.name), style: t.headlineSmall?.copyWith(color: DL.ink))
                  else if (w?.left == null)
                    const LinearProgressIndicator()
                  else
                    Text(s.wakeLeft(s.metres(w!.left!)), style: t.displaySmall),
                ],
              ),
            ),
          ),
          Text(s.wakeHow, style: t.bodySmall),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () {
              ref.read(wakeProvider.notifier).stop();
              Navigator.of(context).pop();
            },
            child: Text(done ? s.wakeDone : s.wakeStop),
          ),
        ],
      ),
    );
  }
}

/// Above the tabs while a "Wake me" ride runs: where to, how far, and Stop.
class WakeBanner extends ConsumerWidget {
  const WakeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(wakeProvider);
    if (w == null) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final text = switch (w) {
      WakeState(error: final e?) => e,
      WakeState(event: WakeEvent.passed) => s.wakePassed(w.alight.name),
      WakeState(event: WakeEvent.wake) => s.wakeNowAt(w.alight.name),
      WakeState(left: final l?) => '${s.wakeRiding(w.service, w.alight.name)} · ${s.wakeLeft(s.metres(l))}',
      _ => s.wakeRiding(w.service, w.alight.name),
    };
    return Panel(
      margin: const EdgeInsets.only(bottom: 10),
      color: w.done ? DL.amber : DL.mint,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => WakeMePage(service: w.service, alight: w.alight),
        )),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined, color: DL.ink),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: t.bodyMedium?.copyWith(color: DL.ink))),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: DL.ink),
                onPressed: () => ref.read(wakeProvider.notifier).stop(),
                child: Text(w.done ? s.wakeDone : s.wakeStop),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
