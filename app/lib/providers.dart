import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'data.dart';
import 'l10n.dart';
import 'logic.dart';
import 'models.dart';
import 'store.dart';

final apiProvider = Provider((ref) => DailyLahApi());
final oneMapProvider = Provider((ref) => OneMapApi());
final bundleRepoProvider = Provider((ref) => BundleRepository());
final busStopRepoProvider = Provider((ref) => BusStopRepository.fromBundles(ref.watch(bundleRepoProvider)));
final favoritesStoreProvider = Provider((ref) => FavoritesStore());

/// Loaded once in main() and injected with overrideWithValue.
final initialFavoritesProvider = Provider<Favorites>((ref) => const Favorites());

class FavoritesNotifier extends Notifier<Favorites> {
  @override
  Favorites build() => ref.watch(initialFavoritesProvider);

  Future<void> update(Favorites Function(Favorites) change) async {
    state = change(state);
    await ref.read(favoritesStoreProvider).save(state);
  }

  Future<void> setPlace(Place place) =>
      update((f) => f.copyWith(places: {...f.places, place.kind: place}));

  Future<void> removePlace(PlaceKind kind) =>
      update((f) => f.copyWith(places: {...f.places}..remove(kind)));

  Future<void> toggleLine(String line) => update((f) {
        final lines = {...f.lines};
        if (!lines.remove(line)) lines.add(line);
        return f.copyWith(lines: lines);
      });

  Future<void> toggleHawker(String id) => update((f) {
        final s = {...f.hawkers};
        if (!s.remove(id)) s.add(id);
        return f.copyWith(hawkers: s);
      });

  Future<void> toggleCarpark(String id) => update((f) {
        final s = {...f.carparks};
        if (!s.remove(id)) s.add(id);
        return f.copyWith(carparks: s);
      });

  /// Starts watching with the current transaction count so only new sales notify.
  Future<void> toggleWatch(String key, int currentCount) => update((f) {
        final m = {...f.watchedBlocks};
        if (m.remove(key) == null) m[key] = currentCount;
        return f.copyWith(watchedBlocks: m);
      });

  Future<void> toggleCompare(String key) => update((f) {
        final l = [...f.compareBlocks];
        if (!l.remove(key)) {
          l.add(key);
          if (l.length > 3) l.removeAt(0);
        }
        return f.copyWith(compareBlocks: l);
      });
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, Favorites>(FavoritesNotifier.new);

/// The app language: the saved choice, else the phone's language (Indonesian or English).
final langProvider = Provider<AppLang>((ref) {
  final saved = ref.watch(favoritesProvider.select((f) => f.lang));
  if (saved != null) return langFromCode(saved);
  return langFromCode(PlatformDispatcher.instance.locale.languageCode);
});

final stringsProvider = Provider<S>((ref) => S(ref.watch(langProvider)));

// ---------------------------------------------------------------- static bundles

Future<List<T>> _list<T>(Ref ref, String name, T Function(Map<String, dynamic>) parse) async {
  final raw = await ref.watch(bundleRepoProvider).load(name);
  if (raw is! List) return const [];
  return [for (final r in raw) parse(r as Map<String, dynamic>)];
}

Future<Map<String, dynamic>?> _map(Ref ref, String name) async {
  final raw = await ref.watch(bundleRepoProvider).load(name);
  return raw is Map<String, dynamic> ? raw : null;
}

final busStopsProvider = FutureProvider<List<BusStop>>(
  (ref) => ref.watch(busStopRepoProvider).load(),
);

final hawkersProvider = FutureProvider<List<Hawker>>((ref) => _list(ref, 'hawkers', Hawker.fromBundle));

final dengueProvider = FutureProvider<List<DengueCluster>>((ref) async {
  final m = await _map(ref, 'dengue');
  final rows = m?['clusters'];
  if (rows is! List) return const [];
  return [for (final r in rows) DengueCluster.fromBundle(r as Map<String, dynamic>)];
});

final poisProvider = FutureProvider<PoiSet>((ref) async {
  final m = await _map(ref, 'poi');
  return m == null ? PoiSet.empty : PoiSet.fromBundle(m);
});

final carparkInfoProvider = FutureProvider<List<Carpark>>((ref) => _list(ref, 'carparks', Carpark.fromBundle));

final hdbBlocksProvider = FutureProvider<List<HdbBlock>>((ref) => _list(ref, 'hdb_blocks', HdbBlock.fromBundle));

final resaleProvider = FutureProvider<ResaleData>((ref) async {
  final m = await _map(ref, 'hdb_resale');
  return m == null ? ResaleData.empty : ResaleData.fromBundle(m);
});

final rentProvider = FutureProvider<RentData>((ref) async {
  final m = await _map(ref, 'hdb_rent');
  return m == null ? RentData.empty : RentData.fromBundle(m);
});

final prayerProvider = FutureProvider<PrayerTimes>((ref) async {
  final m = await _map(ref, 'prayer');
  return m == null ? PrayerTimes.empty : PrayerTimes.fromBundle(m);
});

// ---------------------------------------------------------------- live data

/// Ticks every 30 s so ETAs and the morning/evening switch stay current.
final clockProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now()),
);

DateTime nowOf(Ref ref) => ref.watch(clockProvider).valueOrNull ?? DateTime.now();

final cardKindProvider = Provider<CardKind>((ref) => cardFor(nowOf(ref)));

final forecastProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).forecast());

final trainAlertsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(apiProvider).trainAlerts());

final wbgtProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).weather('wbgt'));

final rainfallProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).weather('rainfall'));

final uvProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).weather('uv'));

final lightningProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).weather('lightning'));

final carparkLiveProvider = FutureProvider.autoDispose((ref) async => carparkLots(await ref.watch(apiProvider).carparks()));

final taxiProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).taxis());

final busArrivalProvider = FutureProvider.autoDispose.family<List<BusEta>, String>((ref, code) async {
  final body = await ref.watch(apiProvider).busArrival(code);
  return parseBusArrival(body, DateTime.now());
});

final crowdShareProvider = FutureProvider.autoDispose.family<double?, String>((ref, line) async {
  return highCrowdShare(await ref.watch(apiProvider).crowd(line));
});

final agentProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, reg) => ref.watch(apiProvider).agent(reg),
);

// ---------------------------------------------------------------- derived

/// The place a "Nearby" view is centred on (Home unless the user picked another).
final nearbyPlaceProvider = StateProvider<PlaceKind>((ref) => PlaceKind.home);

/// Alerts for the top of Today. Fills in as each source loads; failures are skipped.
final todayAlertsProvider = Provider.autoDispose<List<TodayAlert>>((ref) {
  return todayAlerts(
    fav: ref.watch(favoritesProvider),
    now: nowOf(ref),
    s: ref.watch(stringsProvider),
    forecast: ref.watch(forecastProvider).valueOrNull,
    trainAlerts: ref.watch(trainAlertsProvider).valueOrNull,
    hawkers: ref.watch(hawkersProvider).valueOrNull ?? const [],
    dengue: ref.watch(dengueProvider).valueOrNull ?? const [],
    wbgt: ref.watch(wbgtProvider).valueOrNull,
    lightning: ref.watch(lightningProvider).valueOrNull,
  );
});

/// OneMap address search, cached per query while in use.
final addressSearchProvider = FutureProvider.autoDispose.family<List<AddressHit>, String>((ref, q) async {
  if (q.trim().length < 3) return const [];
  return parseOneMap(await ref.watch(oneMapProvider).search(q.trim()));
});
