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

  Future<void> addExtra(Place p) => update((f) => f.extraPlaces.length >= Favorites.maxExtraPlaces
      ? f
      : f.copyWith(extraPlaces: [...f.extraPlaces, p]));

  Future<void> setExtra(int i, Place p) => update((f) => f.copyWith(
        extraPlaces: [for (var j = 0; j < f.extraPlaces.length; j++) j == i ? p : f.extraPlaces[j]],
      ));

  Future<void> removeExtra(int i) =>
      update((f) => f.copyWith(extraPlaces: [...f.extraPlaces]..removeAt(i)));

  /// Replace one stop of a place (by trip key: "home", "work", "school" or "extra:<i>").
  Future<void> replaceStop(String key, String oldCode, BusStop stop) => update((f) {
        List<BusStop> swap(List<BusStop> stops) => [
              for (final x in stops)
                if (x.code == oldCode) stop else x,
            ];
        if (key.startsWith('extra:')) {
          final i = int.parse(key.substring(6));
          final list = [...f.extraPlaces];
          list[i] = list[i].copyWith(stops: swap(list[i].stops));
          return f.copyWith(extraPlaces: list);
        }
        final kind = PlaceKind.values.byName(key);
        final p = f.places[kind];
        if (p == null) return f;
        return f.copyWith(places: {...f.places, kind: p.copyWith(stops: swap(p.stops))});
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


final stringsProvider = Provider<S>((ref) => const S());

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

final busRoutesProvider = FutureProvider<BusRoutes>((ref) async {
  final m = await _map(ref, 'bus_routes');
  return m == null ? BusRoutes.empty : BusRoutes.fromBundle(m);
});

final mrtStationsProvider =
    FutureProvider<List<MrtStation>>((ref) => _list(ref, 'mrt_stations', MrtStation.fromBundle));

/// One-off destination for "Go somewhere" (a searched address), memory only.
final goAdhocDestProvider = StateProvider<Place?>((ref) => null);

/// Start of a "Go somewhere" trip: "home", "work", "school" or "here".
final goFromKeyProvider = StateProvider<String>((ref) => 'home');

final bicycleRacksProvider =
    FutureProvider<List<EPoint>>((ref) => _list(ref, 'bicycle_racks', EPoint.fromBundle));

final parkingLiveProvider =
    FutureProvider.autoDispose<List<ParkingLot>>((ref) async => parseParking(await ref.watch(apiProvider).parking()));

final incidentsProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).trafficIncidents());

/// Today's mode override per trip key (e.g. "work", "extra:0"); in memory only.
final modeOverrideProvider = StateProvider<Map<String, TravelMode>>((ref) => const {});

/// Destination picked in the "Go somewhere" card: "home", "work", "school", "extra:<i>" or null.
final goKeyProvider = StateProvider<String?>((ref) => null);

/// Start of a "Go somewhere" trip: null = Home, otherwise the phone's location (memory only).
final goFromHereProvider = StateProvider<Place?>((ref) => null);

final taxiStandsProvider =
    FutureProvider<List<EPoint>>((ref) => _list(ref, 'taxi_stands', EPoint.fromBundle));

final emergencyProvider = FutureProvider<EmergencySet>((ref) async {
  final m = await _map(ref, 'emergency');
  return m == null ? EmergencySet.empty : EmergencySet.fromBundle(m);
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

final cardKindProvider = Provider<CardKind>((ref) => cardFor(nowOf(ref), ref.watch(favoritesProvider)));

final forecastProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).forecast());

final trainAlertsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(apiProvider).trainAlerts());

final wbgtProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).weather('wbgt'));

final rainfallProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).weather('rainfall'));

final psiProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).weather('psi'));

final pm25Provider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).weather('pm25'));

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
/// Which place the Nearby tab is about: "home", "work", "school", "extra:<i>" or "adhoc".
final nearbyKeyProvider = StateProvider<String>((ref) => 'home');

/// A one-off place for Nearby: the phone's current location or a searched address.
/// Kept in memory only, never saved.
final adhocPlaceProvider = StateProvider<Place?>((ref) => null);

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
    psi: ref.watch(psiProvider).valueOrNull,
    pm25: ref.watch(pm25Provider).valueOrNull,
  );
});

/// OneMap address search, cached per query while in use.
final addressSearchProvider = FutureProvider.autoDispose.family<List<AddressHit>, String>((ref, q) async {
  if (q.trim().length < 3) return const [];
  return parseOneMap(await ref.watch(oneMapProvider).search(q.trim()));
});

/// Selected bottom tab: 0 Today, 1 Nearby, 2 Homes, 3 More.
final shellTabProvider = StateProvider<int>((ref) => 0);
