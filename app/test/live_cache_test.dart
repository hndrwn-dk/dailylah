import 'package:dailylah/api.dart';
import 'package:dailylah/logic.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Forecast endpoint that is down until [up] is set (a Render instance still asleep).
class SleepyApi extends DailyLahApi {
  bool up = false;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> forecast() async {
    calls++;
    if (!up) {
      throw DioException(requestOptions: RequestOptions(path: '/v1/weather/forecast'), type: DioExceptionType.receiveTimeout);
    }
    return {'fetched_at': 2000000000, 'data': {'live': true}};
  }
}

Future<AsyncValue<Map<String, dynamic>>> settle(ProviderContainer c) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return c.read(forecastProvider);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cached forecast shows while the server is asleep, live answer replaces it', () async {
    await LiveCache().write('forecast', {'fetched_at': 1, 'data': {'cached': true}});
    final api = SleepyApi();
    final c = ProviderContainer(overrides: [apiProvider.overrideWithValue(api)]);
    addTearDown(c.dispose);
    final sub = c.listen(forecastProvider, (_, __) {});
    addTearDown(sub.close);

    var v = await settle(c);
    expect(v.valueOrNull?['data'], {'cached': true});
    expect(api.calls, 2); // tried, then tried once more

    // Server is awake now; the app coming back to the foreground refetches.
    api.up = true;
    c.invalidate(forecastProvider);
    v = await settle(c);
    expect(v.valueOrNull?['data'], {'live': true});
    expect((await LiveCache().read('forecast'))!.$1['data'], {'live': true});
  });

  test('no cache and server asleep: an error, then data once it answers', () async {
    final api = SleepyApi();
    final c = ProviderContainer(overrides: [apiProvider.overrideWithValue(api)]);
    addTearDown(c.dispose);
    final sub = c.listen(forecastProvider, (_, __) {});
    addTearDown(sub.close);

    expect((await settle(c)).hasError, isTrue);
    api.up = true;
    c.invalidate(forecastProvider);
    expect((await settle(c)).valueOrNull?['data'], {'live': true});
  });

  test('an old cache is not shown', () async {
    await LiveCache().write('forecast', {'data': {'cached': true}}, DateTime.now().subtract(const Duration(hours: 9)));
    final c = ProviderContainer(overrides: [apiProvider.overrideWithValue(SleepyApi())]);
    addTearDown(c.dispose);
    final sub = c.listen(forecastProvider, (_, __) {});
    addTearDown(sub.close);
    expect((await settle(c)).hasError, isTrue);
  });

  test('liveStaleSince', () {
    final now = DateTime(2026, 10, 25, 7);
    int unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
    expect(liveStaleSince({'fetched_at': unix(now.subtract(const Duration(minutes: 5)))}, now), isNull);
    expect(liveStaleSince({'fetched_at': unix(DateTime(2026, 10, 24, 22, 10))}, now), DateTime(2026, 10, 24, 22, 10));
    expect(liveStaleSince({'fetched_at': 0}, now), isNull);
    expect(liveStaleSince(null, now), isNull);
  });
}
