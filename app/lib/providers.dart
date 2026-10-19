import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'logic.dart';
import 'models.dart';
import 'store.dart';

final apiProvider = Provider((ref) => DailyLahApi());
final busStopRepoProvider = Provider((ref) => BusStopRepository());
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
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, Favorites>(FavoritesNotifier.new);

final busStopsProvider = FutureProvider<List<BusStop>>(
  (ref) => ref.watch(busStopRepoProvider).load(),
);

/// Ticks every 30 s so ETAs and the morning/evening switch stay current.
final clockProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now()),
);

DateTime _now(Ref ref) => ref.watch(clockProvider).valueOrNull ?? DateTime.now();

final cardKindProvider = Provider<CardKind>((ref) => cardFor(_now(ref)));

final forecastProvider = FutureProvider.autoDispose((ref) => ref.watch(apiProvider).forecast());

final trainAlertsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(apiProvider).trainAlerts());

final busArrivalProvider = FutureProvider.autoDispose.family<List<BusEta>, String>((ref, code) async {
  final body = await ref.watch(apiProvider).busArrival(code);
  return parseBusArrival(body, DateTime.now());
});

final crowdShareProvider = FutureProvider.autoDispose.family<double?, String>((ref, line) async {
  return highCrowdShare(await ref.watch(apiProvider).crowd(line));
});
