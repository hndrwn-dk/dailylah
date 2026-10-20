import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'homes.dart';
import 'more.dart';
import 'nearby.dart';
import 'theme.dart';
import 'today.dart';

final _tabProvider = StateProvider<int>((ref) => 0);

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
      busStopsProvider,
    ]) {
      ref.invalidate(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final index = ref.watch(_tabProvider);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [TodayPage(), NearbyPage(), HomesPage(), MorePage()],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(color: DL.ink.withValues(alpha: 0.22), blurRadius: 30, spreadRadius: -18, offset: const Offset(0, -14)),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => ref.read(_tabProvider.notifier).state = i,
          destinations: [
            NavigationDestination(icon: const Icon(Icons.wb_sunny_outlined), selectedIcon: const Icon(Icons.wb_sunny), label: s.tabToday),
            NavigationDestination(icon: const Icon(Icons.explore_outlined), selectedIcon: const Icon(Icons.explore), label: s.tabNearby),
            NavigationDestination(icon: const Icon(Icons.apartment_outlined), selectedIcon: const Icon(Icons.apartment), label: s.tabHomes),
            NavigationDestination(icon: const Icon(Icons.more_horiz), selectedIcon: const Icon(Icons.more_horiz), label: s.tabMore),
          ],
          ),
        ),
      ),
    );
  }
}
