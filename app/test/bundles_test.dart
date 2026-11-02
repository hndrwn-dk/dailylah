// BundleRepository: one download per bundle at a time, only valid JSON is saved, and a
// broken saved copy is replaced (the emulator runs once read a cut-off bus_routes.json).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dailylah/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Server implements HttpClientAdapter {
  _Server(this.files);

  /// Path -> body. A missing path answers 404.
  final Map<String, String> files;
  final hits = <String, int>{};
  bool offline = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (offline) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    final path = options.uri.path;
    hits[path] = (hits[path] ?? 0) + 1;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final body = files[path];
    if (body == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

String _manifest(String sha) => jsonEncode({
      'files': {
        'stops': {'sha256': sha},
      },
    });

void main() {
  late Directory dir;
  late _Server server;

  BundleRepository repo() => BundleRepository(
        dio: Dio()..httpClientAdapter = server,
        baseUrls: const ['https://test'],
        storageDir: () async => dir,
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bundles');
    server = _Server({
      '/data/manifest.json': _manifest('v1'),
      '/data/stops.json': '[1,2,3]',
    });
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('loads asked for at the same time download the bundle once', () async {
    final r = repo();
    final all = await Future.wait([r.load('stops'), r.load('stops'), r.load('stops')]);
    expect(all, everyElement([1, 2, 3]));
    expect(server.hits['/data/stops.json'], 1);
  });

  test('a cut-off download is not saved and the previous copy is kept', () async {
    expect(await repo().load('stops'), [1, 2, 3]);
    server.files['/data/manifest.json'] = _manifest('v2');
    server.files['/data/stops.json'] = '[1,2,'; // connection dropped mid-file
    expect(await repo().load('stops'), [1, 2, 3]);
    expect(File('${dir.path}/stops.json').readAsStringSync(), '[1,2,3]');
    expect(File('${dir.path}/stops.version').readAsStringSync(), 'v1');
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test('a broken saved copy is deleted and downloaded again', () async {
    File('${dir.path}/stops.json').writeAsStringSync('[1,2,');
    File('${dir.path}/stops.version').writeAsStringSync('v1'); // same version: no download needed
    expect(await repo().load('stops'), [1, 2, 3]);
    expect(File('${dir.path}/stops.json').readAsStringSync(), '[1,2,3]');
  });

  test('offline with a broken saved copy gives null instead of throwing', () async {
    File('${dir.path}/stops.json').writeAsStringSync('');
    server.offline = true;
    expect(await repo().load('stops'), isNull);
    expect(File('${dir.path}/stops.json').existsSync(), isFalse);
  });

  test('offline with a good saved copy uses it', () async {
    expect(await repo().load('stops'), [1, 2, 3]);
    server.offline = true;
    expect(await repo().load('stops'), [1, 2, 3]);
  });
}
