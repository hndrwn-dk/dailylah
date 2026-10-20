import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'homes.dart';
import 'more.dart';
import 'nearby.dart';
import 'widgets.dart';
import 'today.dart';


/// Four tabs: Today, Nearby, Homes, More. Pages are kept alive between switches.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back in the foreground after a while: look for new data bundles.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (DateTime.now().difference(_lastRefresh) < const Duration(minutes: 10)) return;
    _lastRefresh = DateTime.now();
    ref.read(bundleRepoProvider).refresh();
    for (final p in <ProviderOrFamily>[
      hawkersProvider,
      dengueProvider,
      poisProvider,
      carparkInfoProvider,
      hdbBlocksProvider,
      resaleProvider,
      rentProvider,
      prayerProvider,
      emergencyProvider,
      taxiStandsProvider,
      busStopsProvider,
    ]) {
      ref.invalidate(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final index = ref.watch(shellTabProvider);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [TodayPage(), NearbyPage(), HomesPage(), MorePage()],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 22, 12),
          child: PillNav(
            index: index,
            onTap: (i) => ref.read(shellTabProvider.notifier).state = i,
            items: [
              (Icons.wb_sunny_outlined, Icons.wb_sunny, s.tabToday),
              (Icons.explore_outlined, Icons.explore, s.tabNearby),
              (Icons.apartment_outlined, Icons.apartment, s.tabHomes),
              (Icons.more_horiz, Icons.more_horiz, s.tabMore),
            ],
          ),
        ),
      ),
    );
  }
}
