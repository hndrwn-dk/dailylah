import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dailylah/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves canned responses per URL; hosts in [down] fail like an unreachable server.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes, {this.down = const {}});
  final Map<String, Object> routes;
  final Set<String> down;
  final requested = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    if (down.contains(options.uri.host)) {
      throw DioException.connectionError(requestOptions: options, reason: 'host down');
    }
    final body = routes[url];
    if (body == null) return ResponseBody.fromString('not found', 404);
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const stops = [
  {'c': '75009', 'n': 'Tampines Int', 'r': 'Tampines Ctrl 1', 'la': 1.354, 'lo': 103.943},
];

Map<String, Object> routesFor(String base) => {
      '$base/data/manifest.json': {'version': 'v1'},
      '$base/data/bus_stops.json': jsonEncode(stops),
    };

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dailylah'));
  tearDown(() => dir.deleteSync(recursive: true));

  BusStopRepository repo(FakeAdapter adapter) => BusStopRepository(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrls: const ['https://primary.test', 'https://fallback.test'],
        storageDir: () async => dir,
      );

  test('uses the primary domain when it answers', () async {
    final adapter = FakeAdapter(routesFor('https://primary.test'));
    final result = await repo(adapter).load();
    expect(result.single.code, '75009');
    expect(adapter.requested, everyElement(startsWith('https://primary.test')));
  });

  test('falls back to the second domain when the first is down', () async {
    final adapter = FakeAdapter(
      routesFor('https://fallback.test'),
      down: {'primary.test'},
    );
    final result = await repo(adapter).load();
    expect(result.single.name, 'Tampines Int');
    expect(adapter.requested.last, 'https://fallback.test/data/bus_stops.json');
  });

  test('keeps the cached list when every host is down', () async {
    await repo(FakeAdapter(routesFor('https://primary.test'))).load();
    final offline = FakeAdapter(const {}, down: {'primary.test', 'fallback.test'});
    final result = await repo(offline).load();
    expect(result.single.code, '75009');
  });

  test('skips the download when the version is unchanged', () async {
    await repo(FakeAdapter(routesFor('https://primary.test'))).load();
    final adapter = FakeAdapter(routesFor('https://primary.test'));
    await repo(adapter).load();
    expect(adapter.requested, ['https://primary.test/data/manifest.json']);
  });
}
