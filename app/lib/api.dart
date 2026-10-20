import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// DailyLah API (Render). Override at build time:
/// flutter run --dart-define=API_URL=http://10.0.2.2:8000
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://dailylah-api.onrender.com',
);

/// Static site (Vercel) that serves /data/manifest.json and /data/bus_stops.json.
/// Override with --dart-define=WEB_URL=... to use a single base URL.
const webUrlOverride = String.fromEnvironment('WEB_URL');

/// Tried in order: our own domain first, then the Vercel URL in case DNS for the
/// custom domain breaks. Both serve the same deployment.
const webUrls = <String>[
  'https://dailylah.tursinalabs.com',
  'https://dailylah-web.vercel.app',
];

class DailyLahApi {
  DailyLahApi([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: apiUrl,
              // Render free instances can take a while to wake up.
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
            ));

  final Dio _dio;

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async =>
      (await _dio.get<Map<String, dynamic>>(path, queryParameters: query)).data!;

  Future<Map<String, dynamic>> forecast() => _get('/v1/weather/forecast');

  Future<Map<String, dynamic>> trainAlerts() => _get('/v1/train-alerts');

  Future<Map<String, dynamic>> busArrival(String stopCode) => _get('/v1/bus-arrival/$stopCode');

  Future<Map<String, dynamic>> crowd(String line, {String kind = 'realtime'}) =>
      _get('/v1/crowd/$line', {'kind': kind});
}

/// Offline bus stop list. Cached as a file on the device and refreshed only when the
/// manifest version changes. Tries each base URL in [webUrls] until one answers.
class BusStopRepository {
  BusStopRepository({Dio? dio, List<String>? baseUrls, Future<Directory> Function()? storageDir})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            )),
        _baseUrls = baseUrls ?? (webUrlOverride.isNotEmpty ? [webUrlOverride] : webUrls),
        _storageDir = storageDir ?? getApplicationSupportDirectory;

  final Dio _dio;
  final List<String> _baseUrls;
  final Future<Directory> Function() _storageDir;
  List<BusStop>? _memory;

  Future<File> _file(String name) async => File('${(await _storageDir()).path}/$name');

  /// Returns the manifest and the base URL that served it, or null if all failed.
  Future<(String, Map<String, dynamic>)?> _manifest() async {
    for (final base in _baseUrls) {
      try {
        final res = await _dio.get<Map<String, dynamic>>('$base/data/manifest.json');
        if (res.data != null) return (base, res.data!);
      } on DioException {
        continue; // try the next base URL
      }
    }
    return null;
  }

  Future<List<BusStop>> load() async {
    if (_memory != null) return _memory!;
    final cached = await _file('bus_stops.json');
    final versionFile = await _file('bus_stops.version');
    String? localVersion;
    if (await versionFile.exists()) localVersion = await versionFile.readAsString();

    try {
      final found = await _manifest();
      if (found != null) {
        final (base, manifest) = found;
        final remoteVersion = manifest['version'] as String;
        if (remoteVersion != localVersion || !await cached.exists()) {
          final res = await _dio.get<String>(
            '$base/data/bus_stops.json',
            options: Options(responseType: ResponseType.plain),
          );
          await cached.writeAsString(res.data!);
          await versionFile.writeAsString(remoteVersion);
        }
      }
    } on DioException {
      // Offline or both hosts down: fall back to the cached copy below.
    }

    if (!await cached.exists()) return const [];
    final rows = jsonDecode(await cached.readAsString()) as List;
    _memory = [for (final r in rows) BusStop.fromBundle(r as Map<String, dynamic>)];
    return _memory!;
  }
}
