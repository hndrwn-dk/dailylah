import 'dart:async';

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

  /// Saves a suggested stop as the first stop of a place (keeps up to 3).
  Future<void> useStop(String key, BusStop stop) => update((f) {
        List<BusStop> put(List<BusStop> stops) => [stop, ...stops.where((x) => x.code != stop.code)].take(3).toList();
        if (key.startsWith('extra:')) {
          final i = int.parse(key.substring(6));
          final list = [...f.extraPlaces];
          list[i] = list[i].copyWith(stops: put(list[i].stops));
          return f.copyWith(extraPlaces: list);
        }
        final kind = PlaceKind.values.byName(key);
        final p = f.places[kind];
        if (p == null) return f;
        return f.copyWith(places: {...f.places, kind: p.copyWith(stops: put(p.stops))});
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

/// Parked car, logged trips and meals. On this phone only (SharedPreferences).
class HabitsNotifier extends Notifier<Habits> {
  final _store = HabitsStore();

  @override
  Habits build() {
    Future(() async {
      final h = await _store.load();
      state = h;
    });
    return Habits.empty;
  }

  Future<void> _set(Habits h) async {
    state = h;
    await _store.save(h);
  }

  Future<void> park(ParkedCar p) => _set(state.copyWith(parked: p));

  /// Car picked up: the parking goes to History (when it lasted a few minutes or more).
  Future<void> clearParked([DateTime? now]) {
    final p = state.parked;
    final end = now ?? DateTime.now();
    final m = p == null ? null : parkMinutes(p.at, end);
    final parkings = [
      ...state.parkings,
      if (p != null && m != null) ParkLog(name: p.name, start: p.at, minutes: m, hdb: p.hdb, central: p.central),
    ];
    return _set(state.copyWith(
      clearParked: true,
      parkings: parkings.length > Habits.maxParkings ? parkings.sublist(parkings.length - Habits.maxParkings) : parkings,
    ));
  }

  Future<void> startTrip(String route, DateTime now, {bool rainy = false, String? mode, double? km}) =>
      _set(state.copyWith(tripRoute: route, tripStart: now, tripRainy: rainy, tripMode: mode, tripKm: km));

  /// Puts History back as it was (Undo after a delete).
  Future<void> restore(Habits h) => _set(h);

  /// Sets (or clears, with null) the cost of a trip or parking on History.
  Future<void> setCost(HistoryEntry e, int? cents) => _set(switch (e.source) {
        final TripLog t => state.copyWith(trips: [for (final x in state.trips) identical(x, t) ? t.withCost(cents) : x]),
        final ParkLog p =>
          state.copyWith(parkings: [for (final x in state.parkings) identical(x, p) ? p.withCost(cents) : x]),
        _ => state,
      });

  /// Sets when a logged meal was eaten (History, for a meal logged late).
  Future<void> setMealTime(MealLog m, DateTime at) =>
      _set(state.copyWith(meals: [for (final x in state.meals) identical(x, m) ? m.withTime(at) : x]));

  /// Removes several History entries at once (e.g. all meals shown).
  Future<void> forgetAll(Iterable<HistoryEntry> entries) {
    final drop = {for (final e in entries) e.source};
    return _set(state.copyWith(
      trips: [for (final t in state.trips) if (!drop.contains(t)) t],
      parkings: [for (final p in state.parkings) if (!drop.contains(p)) p],
      meals: [for (final m in state.meals) if (!drop.contains(m)) m],
    ));
  }

  /// Removes one History entry the user deleted.
  Future<void> forget(HistoryEntry e) => _set(switch (e.kind) {
        HistoryKind.trip => state.copyWith(trips: [...state.trips]..remove(e.source)),
        HistoryKind.parking => state.copyWith(parkings: [...state.parkings]..remove(e.source)),
        HistoryKind.meal => state.copyWith(meals: [...state.meals]..remove(e.source)),
      });

  /// Finishes the running trip; returns its minutes, or null when it was not kept.
  Future<int?> finishTrip(DateTime now) async {
    final start = state.tripStart;
    final route = state.tripRoute;
    if (start == null || route == null) return null;
    final m = tripMinutes(start, now);
    final trips = [
      ...state.trips,
      if (m != null)
        TripLog(route: route, start: start, minutes: m, rainy: state.tripRainy, mode: state.tripMode, km: state.tripKm),
    ];
    await _set(state.copyWith(
      trips: trips.length > Habits.maxTrips ? trips.sublist(trips.length - Habits.maxTrips) : trips,
      clearTrip: true,
    ));
    return m;
  }

  /// Logs a meal at a hawker centre ([hawkerId]) or, with [name], at another food place.
  Future<void> ateAt(String hawkerId, DateTime now, {String? name}) {
    final meals = addMeal(state.meals, MealLog(hawkerId: hawkerId, at: now, name: name));
    return _set(state.copyWith(meals: meals.length > Habits.maxMeals ? meals.sublist(meals.length - Habits.maxMeals) : meals));
  }

  /// Deletes logged trips and meals and the parked car.
  Future<void> clearAll() async {
    state = Habits.empty;
    await _store.clear();
  }
}

final habitsProvider = NotifierProvider<HabitsNotifier, Habits>(HabitsNotifier.new);

final eventsProvider = FutureProvider<List<PublicEvent>>((ref) async {
  final raw = await ref.watch(bundleRepoProvider).load('events');
  return [
    if (raw is List)
      for (final r in raw)
        if (r is Map<String, dynamic>)
          if (PublicEvent.fromBundle(r) case final e?) e,
  ];
});

final schoolHolidaysProvider = FutureProvider<List<SchoolHoliday>>((ref) async =>
    SchoolHoliday.fromBundle(await ref.watch(bundleRepoProvider).load('school_holidays')));


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

/// Bus stops by code (for placing a live bus on its route), empty until loaded.
final busStopsByCodeProvider = Provider<Map<String, BusStop>>((ref) => {
      for (final s in ref.watch(busStopsProvider).valueOrNull ?? const <BusStop>[]) s.code: s,
    });

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

/// Private homes (URA transactions and rentals).
final privateHomesProvider =
    FutureProvider<List<PrivateProject>>((ref) => _list(ref, 'private_homes', PrivateProject.fromBundle));

/// Section shown on the Home tab ("home", "works", "schools" ...).
final homeSectionProvider = StateProvider<String>((ref) => 'home');

/// Which Nearby section is shown: bus, eat, park, taxi, prayer or help.
final nearbySectionProvider = StateProvider<String>((ref) => 'bus');

/// Halal places listed on Muslim.sg (opt-in feature).
final halalProvider = FutureProvider<List<EPoint>>((ref) => _list(ref, 'halal', EPoint.fromBundle));

final aroundProvider = FutureProvider<AroundSet>((ref) async {
  final raw = await _map(ref, 'around');
  return raw == null ? AroundSet.empty : AroundSet.fromBundle(raw);
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

final liveCacheProvider = Provider((ref) => LiveCache());

/// One live endpoint, cache first: the last good answer (if younger than [maxAge]) shows at
/// once, then the server's answer replaces it. A failed call is tried once more (the first
/// call wakes a sleeping Render instance), and while it keeps failing it retries every
/// [liveRetryEvery]; with nothing cached the error shows ("server may be waking up").
Stream<Map<String, dynamic>> _live(
  Ref ref,
  String name,
  Duration maxAge,
  Future<Map<String, dynamic>> Function(DailyLahApi api) fetch,
) {
  final api = ref.watch(apiProvider);
  final cache = ref.watch(liveCacheProvider);
  Timer? retry;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    retry?.cancel();
  });
  Future<Map<String, dynamic>> attempt() async {
    try {
      return await fetch(api);
    } on Object {
      return fetch(api);
    }
  }

  // Cache and server are read side by side, so a slow (or missing) cache never holds back
  // the live answer, and the cache only shows while the server has not answered yet.
  final out = StreamController<Map<String, dynamic>>();
  ref.onDispose(out.close);
  var live = false;
  var showedCache = false;
  final cacheRead = cache.read(name, reload: true).then((c) {
    if (live || out.isClosed || c == null || DateTime.now().difference(c.$2) > maxAge) return;
    showedCache = true;
    out.add(c.$1);
  }, onError: (Object _) {});
  attempt().then((body) {
    live = true;
    if (!out.isClosed) {
      out.add(body);
      out.close();
    }
    cache.write(name, body);
  }, onError: (Object e, StackTrace st) async {
    if (!disposed) retry = Timer(liveRetryEvery, ref.invalidateSelf);
    await cacheRead;
    if (out.isClosed) return;
    if (!showedCache) out.addError(e, st);
    await out.close();
  });
  return out.stream;
}

final forecastProvider = StreamProvider.autoDispose(
    (ref) => _live(ref, 'forecast', const Duration(hours: 2), (api) => api.forecast()));

final trainAlertsProvider = StreamProvider.autoDispose(
    (ref) => _live(ref, 'train-alerts', const Duration(minutes: 30), (api) => api.trainAlerts()));

AutoDisposeStreamProvider<Map<String, dynamic>> _weather(String kind) => StreamProvider.autoDispose(
    (ref) => _live(ref, 'weather-$kind', const Duration(hours: 1), (api) => api.weather(kind)));

final wbgtProvider = _weather('wbgt');

final rainfallProvider = _weather('rainfall');

final psiProvider = _weather('psi');

final pm25Provider = _weather('pm25');

final uvProvider = _weather('uv');

final lightningProvider = _weather('lightning');

/// Every live (server) provider, refreshed when the app comes back after a while.
final liveProviders = <ProviderOrFamily>[
  forecastProvider,
  trainAlertsProvider,
  wbgtProvider,
  rainfallProvider,
  psiProvider,
  pm25Provider,
  uvProvider,
  lightningProvider,
  busArrivalProvider,
  crowdShareProvider,
  carparkLiveProvider,
  taxiProvider,
  parkingLiveProvider,
  incidentsProvider,
];

/// Good time for a park near a point? Null until at least one weather reading has loaded.
final parkTimeProvider = Provider.autoDispose.family<ParkTime?, (double, double)>((ref, at) {
  final (lat, lng) = at;
  final lightning = ref.watch(lightningProvider).valueOrNull;
  final rain = ref.watch(rainfallProvider).valueOrNull;
  final wbgt = ref.watch(wbgtProvider).valueOrNull;
  final uv = ref.watch(uvProvider).valueOrNull;
  final forecast = ref.watch(forecastProvider).valueOrNull;
  final air = airNear(ref.watch(psiProvider).valueOrNull, ref.watch(pm25Provider).valueOrNull, lat, lng);
  if (lightning == null && rain == null && wbgt == null && uv == null && air == null) return null;
  return parkTime(
    now: nowOf(ref),
    lightning: lightning != null && lightningNear(lightning, lat, lng),
    rainMm: rain == null ? null : rainfallNear(rain, lat, lng)?.$2,
    air: air?.level,
    heat: wbgt == null ? null : heatStressNear(wbgt, lat, lng),
    uv: uv == null ? null : uvIndex(uv),
    showersForecast: forecast != null && preferIndoor(forecastNear(forecast, lat, lng)),
  );
});

final carparkLiveProvider = FutureProvider.autoDispose((ref) async => carparkLots(await ref.watch(apiProvider).carparks()));

final taxiProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).taxis());

/// Live arrivals for one stop. Refetched every 30 s while a screen shows it, so the board
/// keeps up when the user is waiting (the last list stays on screen during a refetch).
final busArrivalProvider = FutureProvider.autoDispose.family<List<BusEta>, String>((ref, code) async {
  final timer = Timer(busRefreshEvery, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
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

/// Which place the Nearby tab is about: "here" (until located), "work", "school",
/// "extra:<i>", "adhoc" (current location or a searched address) or "home".
final nearbyKeyProvider = StateProvider<String>((ref) => 'here');

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
    schoolHolidays: ref.watch(schoolHolidaysProvider).valueOrNull ?? const [],
  );
});

/// OneMap address search, cached per query while in use.
final addressSearchProvider = FutureProvider.autoDispose.family<List<AddressHit>, String>((ref, q) async {
  if (q.trim().length < 3) return const [];
  return parseOneMap(await ref.watch(oneMapProvider).search(q.trim()));
});

/// Selected bottom tab: 0 Today, 1 Nearby, 2 Home, 3 History, 4 More.
final shellTabProvider = StateProvider<int>((ref) => 0);
