import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic.dart';
import '../providers.dart';
import 'home.dart';
import 'more.dart';
import 'nearby.dart';
import 'widgets.dart';
import 'today.dart';


/// Four tabs: Today, Nearby, Home, More. Pages are kept alive between switches and keep
/// their scroll position; tapping the selected tab again scrolls it to the top.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  DateTime _lastRefresh = DateTime.now();

  /// One scroll controller per tab's main list.
  final _scroll = List.generate(4, (_) => ScrollController());

  /// When the app last went to the background, and which card Today showed then.
  DateTime? _awaySince;
  CardKind? _cardWhenAway;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _scroll) {
      c.dispose();
    }
    super.dispose();
  }

  /// Back in the foreground after a while: look for new data bundles.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _awaySince ??= DateTime.now();
      _cardWhenAway ??= ref.read(cardKindProvider);
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    if (_awaySince case final since?) {
      final card = cardFor(DateTime.now(), ref.read(favoritesProvider));
      if (todayBackToTop(awaySince: since, now: DateTime.now(), cardBefore: _cardWhenAway ?? card, cardNow: card)) {
        _toTop(0, animate: false);
      }
      _awaySince = null;
      _cardWhenAway = null;
    }
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
      busRoutesProvider,
      mrtStationsProvider,
      bicycleRacksProvider,
      aroundProvider,
      halalProvider,
      privateHomesProvider,
    ]) {
      ref.invalidate(p);
    }
  }

  void _toTop(int tab, {bool animate = true}) {
    final c = _scroll[tab];
    if (!c.hasClients) return;
    if (animate) {
      c.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      c.jumpTo(0);
    }
  }

  void _onTab(int i) {
    if (i == ref.read(shellTabProvider)) {
      _toTop(i);
    } else {
      ref.read(shellTabProvider.notifier).state = i;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Today's card switched (morning to evening) while another tab was open: start Today at
    // the top. If Today is on screen, leave the reader where they are.
    ref.listen(cardKindProvider, (before, now) {
      if (before != null && before != now && ref.read(shellTabProvider) != 0) _toTop(0, animate: false);
    });
    final s = ref.watch(stringsProvider);
    final index = ref.watch(shellTabProvider);
    final paper = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      // Content scrolls behind the floating pill instead of stopping at a hard edge.
      extendBody: true,
      body: IndexedStack(
        index: index,
        children: [
          TodayPage(controller: _scroll[0]),
          NearbyPage(controller: _scroll[1]),
          HomePage(controller: _scroll[2]),
          MorePage(controller: _scroll[3]),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [paper.withValues(alpha: 0), paper.withValues(alpha: 0.92)],
            stops: const [0, 0.55],
          ),
        ),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 22, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: PillNav(
            index: index,
            onTap: _onTab,
            items: [
              (Icons.wb_sunny_outlined, Icons.wb_sunny, s.tabToday),
              (Icons.explore_outlined, Icons.explore, s.tabNearby),
              (Icons.home_outlined, Icons.home, s.tabHomes),
              (Icons.more_horiz, Icons.more_horiz, s.tabMore),
            ],
          ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
