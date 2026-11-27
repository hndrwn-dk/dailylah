import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:geolocator/geolocator.dart';

import '../background.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import '../trip_nav.dart';
import '../share_intake.dart';
import 'history.dart';
import 'home.dart';
import 'more.dart';
import 'nearby.dart';
import 'widgets.dart';
import 'today.dart';
import 'trip.dart';
import 'mrt_ride.dart';
import 'wake.dart';


/// Five tabs: Today, Nearby, Home, History, More. Pages are kept alive between switches and keep
/// their scroll position; tapping the selected tab again scrolls it to the top.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  DateTime _lastRefresh = DateTime.now();

  /// One scroll controller per tab's main list.
  final _scroll = List.generate(5, (_) => ScrollController());

  /// Whether the open tab is scrolled down from the top: the status bar then blurs what is under it.
  final _scrolled = ValueNotifier(false);

  void _syncScrolled() {
    final c = _scroll[ref.read(shellTabProvider)];
    _scrolled.value = c.hasClients && c.positions.length == 1 && c.offset > 1;
  }

  /// When the app last went to the background, and which card Today showed then.
  DateTime? _awaySince;
  CardKind? _cardWhenAway;

  /// Taps on the home screen widget's Today / Nearby / Home buttons.
  StreamSubscription<(int, String?)>? _widgetTaps;

  /// Places shared to DailyLah from Google Maps (Share > DailyLah).
  StreamSubscription<SharedPlace>? _shares;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    _widgetTaps = widgetTabTaps().listen(_openFromWidget);
    _shares = sharedPlaces().listen(_openShared);
    for (final c in _scroll) {
      c.addListener(_syncScrolled);
    }
  }

  /// Opens the trip planner with a shared place as the destination, above Today.
  void _openShared(SharedPlace place) {
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    ref.read(shellTabProvider.notifier).state = 0;
    nav.push(MaterialPageRoute<void>(builder: (_) => TripPlannerPage(shared: place)));
  }

  /// A tap on the home screen widget or on an alert: the tab, and for Nearby the section asked for.
  void _openFromWidget((int, String?) target) {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (target.$2 case final section?) ref.read(nearbySectionProvider.notifier).state = section;
    ref.read(shellTabProvider.notifier).state = target.$1;
  }

  @override
  void dispose() {
    _widgetTaps?.cancel();
    _shares?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _scroll) {
      c.dispose();
    }
    _scrolled.dispose();
    super.dispose();
  }

  /// Is the phone at the saved Home, Work or School? Today then greets instead of showing the
  /// trip, and a trip being timed to that place ends. Only when location is already allowed
  /// (never asks); the position is compared on the phone and not kept.
  Future<void> _locate() async {
    PlaceKind? at;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
        );
        if (!mounted) return;
        at = savedPlaceAt(ref.read(favoritesProvider), pos.latitude, pos.longitude);
        // A trip still being timed to a place picked in the planner ends there too.
        await ref.read(habitsProvider.notifier).arrivedNear(pos.latitude, pos.longitude, DateTime.now());
        if (!mounted) return;
      }
    } on Object {
      // No location (denied, switched off, no fix in time): Today shows the trip as usual.
    }
    if (!mounted) return;
    ref.read(phoneAtProvider.notifier).state = at;
    if (at != null) await ref.read(habitsProvider.notifier).arrivedAt(at, DateTime.now());
  }

  /// Back in the foreground after a while: refresh live readings, and look for new data bundles.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _awaySince ??= DateTime.now();
      _cardWhenAway ??= ref.read(cardKindProvider);
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    // Where the phone was before it went away says nothing about now.
    if (_awaySince case final since? when DateTime.now().difference(since) >= liveRefreshAfter) {
      ref.read(phoneAtProvider.notifier).state = null;
    }
    ref.read(showTripAnywayProvider.notifier).state = false;
    _locate();
    if (_awaySince case final since?) {
      final card = cardFor(DateTime.now(), ref.read(favoritesProvider));
      if (todayBackToTop(awaySince: since, now: DateTime.now(), cardBefore: _cardWhenAway ?? card, cardNow: card)) {
        _toTop(0, animate: false);
      }
      // Live readings kept from before (or an error from a server that was asleep) are
      // refetched; the phone's cache shows meanwhile. The clock restarts so the morning or
      // evening card is right at once.
      if (DateTime.now().difference(since) >= liveRefreshAfter) {
        ref.invalidate(clockProvider);
        for (final p in liveProviders) {
          ref.invalidate(p);
        }
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
    // Trip navigation runs while the app is open, for a trip with changes.
    ref.listen(tripNavProvider, (_, __) {});
    ref.listen(cardKindProvider, (before, now) {
      if (before != null && before != now && ref.read(shellTabProvider) != 0) _toTop(0, animate: false);
    });
    // Another tab has its own place: the status bar follows it.
    ref.listen(shellTabProvider, (before, now) => WidgetsBinding.instance.addPostFrameCallback((frame) {
          if (mounted) _syncScrolled();
        }));
    final s = ref.watch(stringsProvider);
    final index = ref.watch(shellTabProvider);
    final paper = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      // Content scrolls behind the floating pill instead of stopping at a hard edge.
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          IndexedStack(
            index: index,
            children: [
              TodayPage(controller: _scroll[0]),
              NearbyPage(controller: _scroll[1]),
              HomePage(controller: _scroll[2]),
              HistoryPage(controller: _scroll[3]),
              MorePage(controller: _scroll[4]),
            ],
          ),
          StatusBarFade(scrolled: _scrolled),
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
          // On the narrowest phones the bar goes closer to the edges, so each tab stays 48 dp wide.
          padding: MediaQuery.sizeOf(context).width < 345
              ? const EdgeInsets.fromLTRB(6, 14, 8, 12)
              : const EdgeInsets.fromLTRB(18, 14, 22, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const WakeBanner(),
                const RideBanner(),
                const TripBanner(),
                PillNav(
            index: index,
            onTap: _onTab,
            items: [
              (Icons.wb_sunny_outlined, Icons.wb_sunny, s.tabToday),
              (Icons.explore_outlined, Icons.explore, s.tabNearby),
              (Icons.home_outlined, Icons.home, s.tabHomes),
              (Icons.history, Icons.history, s.tabHistory),
              (Icons.more_horiz, Icons.more_horiz, s.tabMore),
            ],
          ),
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
