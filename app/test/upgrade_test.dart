// Upgrade safety (docs/QA.md section 5): data saved by an older version must load in this
// one, with nothing lost and no crash. The on-device emulator test (integration_test/)
// covers the real APK-over-APK install; these tests cover the stored formats.
import 'dart:convert';

import 'package:dailylah/models.dart';
import 'package:dailylah/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// What an early build (before custom places, modes, days and habits) wrote under favorites.v1.
const _oldestFavoritesJson = '''
{
  "places": [
    {"kind": "home", "stops": [{"c": "75009", "n": "Tampines Int", "r": "Tampines Ctrl 1", "la": 1.354076, "lo": 103.943391}]},
    {"kind": "work", "stops": [{"c": "03011", "n": "Fullerton Sq", "r": "Fullerton Rd", "la": 1.285618, "lo": 103.853422}]}
  ],
  "lines": ["EWL"],
  "mrtAlerts": false,
  "onboarded": true
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a full household survives save and load unchanged', () async {
    SharedPreferences.setMockInitialValues({});
    await FavoritesStore().save(householdFavorites);
    final back = await FavoritesStore().load();
    expect(back.toJson(), householdFavorites.toJson());
  });

  test('favourites from the oldest format load with new fields at their defaults', () async {
    SharedPreferences.setMockInitialValues({'favorites.v1': _oldestFavoritesJson});
    final fav = await FavoritesStore().load();
    expect(fav.onboarded, isTrue, reason: 'an upgrade must not send the user back to Setup');
    expect(fav.places[PlaceKind.home]!.stops.single.code, '75009');
    expect(fav.places[PlaceKind.work]!.stops.single.code, '03011');
    expect(fav.lines, {'EWL'});
    expect(fav.mrtAlerts, isFalse, reason: 'a toggle the user changed must stay changed');
    expect(fav.places[PlaceKind.home]!.modes, [TravelMode.transit]);
    expect(fav.extraPlaces, isEmpty);
    expect(fav.compareBlocks, isEmpty);
  });

  test('keys written by a newer version are ignored, not fatal (downgrade/rollback)', () async {
    final json = householdFavorites.toJson()..['someFutureField'] = {'x': 1};
    SharedPreferences.setMockInitialValues({'favorites.v1': jsonEncode(json)});
    final fav = await FavoritesStore().load();
    expect(fav.onboarded, isTrue);
    expect(fav.places.length, householdFavorites.places.length);
  });

  test('corrupt stored favourites fall back to defaults instead of crashing', () async {
    SharedPreferences.setMockInitialValues({'favorites.v1': '{not json'});
    final fav = await FavoritesStore().load();
    expect(fav.onboarded, isFalse);
  });

  test('History saved by 2.2.0 (meals without a price) loads unchanged in 2.3.0', () async {
    // What 2.2.0 wrote under habits.v1: a hawker meal, a halal place with its name, a trip.
    const v220 = {
      'trips': [
        {'r': 'home>work', 's': '2026-11-03T07:30:00.000', 'm': 40},
      ],
      'meals': [
        {'h': 'h1', 'at': '2026-11-03T12:00:00.000'},
        {'h': 'p:1.35000,103.94000', 'at': '2026-11-04T13:00:00.000', 'n': 'Test Kitchen'},
      ],
    };
    SharedPreferences.setMockInitialValues({'habits.v1': jsonEncode(v220)});
    final h = await HabitsStore().load();
    expect(h.meals.map((m) => (m.hawkerId, m.name, m.priceCents)), [
      ('h1', null, null),
      ('p:1.35000,103.94000', 'Test Kitchen', null),
    ]);
    expect(h.meals.first.at, DateTime(2026, 11, 3, 12));
    expect(h.trips, hasLength(1));
    // Saved again by 2.3.0 it keeps the same keys, so going back to 2.2.0 still reads it.
    await HabitsStore().save(h);
    final raw = jsonDecode((await SharedPreferences.getInstance()).getString('habits.v1')!) as Map;
    expect(raw['meals'], v220['meals']);
  });

  test('alert history keeps working after an upgrade (no repeat notifications)', () async {
    SharedPreferences.setMockInitialValues({
      'alerts.sent': ['2026-10-20:rain:morning', 'mrt:2026-10-20:123'],
    });
    final log = AlertLog(await SharedPreferences.getInstance());
    expect(await log.alreadySent('2026-10-20:rain:morning'), isTrue);
    expect(log.sentToday('2026-10-20'), 1);
  });
}
