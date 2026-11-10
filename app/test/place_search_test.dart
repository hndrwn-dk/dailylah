// Place search for Plan a trip: which search a query goes to, and the
// fallback to OneMap when place search finds nothing or fails.
import 'package:dailylah/api.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// OneMap that answers every query with one address.
class FakeOneMap extends OneMapApi {
  final queries = <String>[];
  @override
  Future<Map<String, dynamic>> search(String query) async {
    queries.add(query);
    return {
      'results': [
        {
          'BLK_NO': '51',
          'ROAD_NAME': 'BENCOOLEN STREET',
          'BUILDING': 'NIL',
          'POSTAL': '189630',
          'LATITUDE': '1.29661',
          'LONGITUDE': '103.85220',
        },
      ],
    };
  }
}

/// /v1/places: one restaurant, nothing, or an error.
class FakePlaces extends PlacesApi {
  FakePlaces({this.empty = false, this.fails = false});
  final bool empty;
  final bool fails;
  final queries = <String>[];
  @override
  Future<Map<String, dynamic>> search(String query) async {
    queries.add(query);
    if (fails) throw DioException(requestOptions: RequestOptions(path: '/v1/places'));
    return {
      'fetched_at': 0,
      'data': [
        if (!empty)
          {
            'name': 'Putra Minang',
            'address': '51 Bencoolen Street, Singapore 189630, Singapore',
            'postal': '189630',
            'lat': 1.29942,
            'lng': 103.85051,
            'type': 'amenity',
          },
      ],
    };
  }
}

Future<PlaceHits> run(FakeOneMap oneMap, FakePlaces places, String q) async {
  final c = ProviderContainer(retry: noRetry, overrides: [
    oneMapProvider.overrideWithValue(oneMap),
    placesProvider.overrideWithValue(places),
  ]);
  addTearDown(c.dispose);
  final sub = c.listen(placeSearchProvider(q), (_, __) {});
  addTearDown(sub.close);
  return c.read(placeSearchProvider(q).future);
}

void main() {
  test('a name goes to place search, and its hits are marked as Geoapify', () async {
    final oneMap = FakeOneMap();
    final places = FakePlaces();
    final out = await run(oneMap, places, ' Putra Minang ');
    expect(places.queries, ['Putra Minang']);
    expect(oneMap.queries, isEmpty);
    expect(out.geoapify, isTrue);
    expect(out.hits.single.name, 'Putra Minang');
  });

  test('a postal code, a block number or "Blk 201" goes to OneMap only', () async {
    for (final q in ['560201', '201 Ang Mo Kio', 'Blk 201']) {
      final oneMap = FakeOneMap();
      final places = FakePlaces();
      final out = await run(oneMap, places, q);
      expect(places.queries, isEmpty, reason: q);
      expect(oneMap.queries, [q]);
      expect(out.geoapify, isFalse);
      expect(out.hits.single.postal, '189630');
    }
  });

  test('place search with no hits falls back to OneMap', () async {
    final oneMap = FakeOneMap();
    final places = FakePlaces(empty: true);
    final out = await run(oneMap, places, 'Ang Mo Kio View');
    expect(places.queries, ['Ang Mo Kio View']);
    expect(oneMap.queries, ['Ang Mo Kio View']);
    expect(out.geoapify, isFalse);
    expect(out.hits, hasLength(1));
  });

  test('place search failing (server asleep, no key) falls back to OneMap', () async {
    final oneMap = FakeOneMap();
    final places = FakePlaces(fails: true);
    final out = await run(oneMap, places, 'Jewel Changi');
    expect(oneMap.queries, ['Jewel Changi']);
    expect(out.geoapify, isFalse);
    expect(out.hits, hasLength(1));
  });

  test('fewer than 3 characters searches nothing', () async {
    final oneMap = FakeOneMap();
    final places = FakePlaces();
    final out = await run(oneMap, places, 'ab');
    expect(out.hits, isEmpty);
    expect(places.queries, isEmpty);
    expect(oneMap.queries, isEmpty);
  });
}
