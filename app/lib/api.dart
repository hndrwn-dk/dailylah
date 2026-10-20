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

/// Static site (Vercel) that serves /data/manifest.json and the data bundles.
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

  Future<Map<String, dynamic>> weather(String kind) => _get('/v1/weather/$kind');

  Future<Map<String, dynamic>> trainAlerts() => _get('/v1/train-alerts');

  Future<Map<String, dynamic>> busArrival(String stopCode) => _get('/v1/bus-arrival/$stopCode');

  Future<Map<String, dynamic>> crowd(String line, {String kind = 'realtime'}) =>
      _get('/v1/crowd/$line', {'kind': kind});

  /// Live availability for all HDB car parks: {"data": {"ACB": [total, available]}}.
  Future<Map<String, dynamic>> carparks() => _get('/v1/carpark');

  /// Available taxi positions, rounded: {"data": [[lat, lng], ...]}.
  Future<Map<String, dynamic>> taxis() => _get('/v1/taxi');

  /// CEA register lookup by registration number.
  Future<Map<String, dynamic>> agent(String regNo) => _get('/v1/agent/${Uri.encodeComponent(regNo)}');
}

/// Address search on OneMap (Singapore Land Authority). Only the text the user types
/// is sent; used to set Home/Work/School and to look up a postal code.
class OneMapApi {
  OneMapApi([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  final Dio _dio;

  Future<Map<String, dynamic>> search(String query) async => (await _dio.get<Map<String, dynamic>>(
        'https://www.onemap.gov.sg/api/common/elastic/search',
        queryParameters: {'searchVal': query, 'returnGeom': 'Y', 'getAddrDetails': 'Y', 'pageNum': 1},
      ))
          .data!;
}

/// Static data bundles listed in /data/manifest.json. Each file is cached on the
/// device and downloaded again only when its sha256 in the manifest changes.
/// Tries each base URL in [webUrls] until one answers.
class BundleRepository {
  BundleRepository({Dio? dio, List<String>? baseUrls, Future<Directory> Function()? storageDir})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 60),
            )),
        _baseUrls = baseUrls ?? (webUrlOverride.isNotEmpty ? [webUrlOverride] : webUrls),
        _storageDir = storageDir ?? getApplicationSupportDirectory;

  final Dio _dio;
  final List<String> _baseUrls;
  final Future<Directory> Function() _storageDir;
  Future<(String, Map<String, dynamic>)?>? _manifestFuture;
  final _memory = <String, Object?>{};

  Future<File> _file(String name) async => File('${(await _storageDir()).path}/$name');

  /// The manifest and the base URL that served it, or null when every host failed.
  Future<(String, Map<String, dynamic>)?> manifest() => _manifestFuture ??= _fetchManifest();

  Future<(String, Map<String, dynamic>)?> _fetchManifest() async {
    for (final base in _baseUrls) {
      try {
        final res = await _dio.get<Map<String, dynamic>>('$base/data/manifest.json');
        if (res.data != null) return (base, res.data!);
      } on DioException {
        continue; // try the next base URL
      }
    }
    _manifestFuture = null; // allow a retry later in this session
    return null;
  }

  /// Version string for one bundle: its sha256 from the manifest, or the manifest
  /// version for older manifests without per-file entries.
  static String? versionOf(Map<String, dynamic> manifest, String name) {
    final files = manifest['files'];
    if (files is Map && files[name] is Map) return '${(files[name] as Map)['sha256']}';
    return manifest['version'] as String?;
  }

  /// Decoded JSON of `/data/<name>.json`, or null when never downloaded and offline.
  Future<Object?> load(String name) async {
    if (_memory.containsKey(name)) return _memory[name];
    final cached = await _file('$name.json');
    final versionFile = await _file('$name.version');
    String? localVersion;
    if (await versionFile.exists()) localVersion = await versionFile.readAsString();

    try {
      final found = await manifest();
      if (found != null) {
        final (base, m) = found;
        final remoteVersion = versionOf(m, name);
        if (remoteVersion != null && (remoteVersion != localVersion || !await cached.exists())) {
          final res = await _dio.get<String>(
            '$base/data/$name.json',
            options: Options(responseType: ResponseType.plain),
          );
          await cached.writeAsString(res.data!);
          await versionFile.writeAsString(remoteVersion);
        }
      }
    } on DioException {
      // Offline or both hosts down: fall back to the cached copy below.
    }

    if (!await cached.exists()) return null;
    final value = jsonDecode(await cached.readAsString());
    _memory[name] = value;
    return value;
  }

  /// Forget the manifest and in-memory copies so the next load checks for new data
  /// (called when the app comes back to the foreground).
  void refresh() {
    _manifestFuture = null;
    _memory.clear();
  }

  /// True when the bundle changed since [knownVersion] (used to spot new HDB data).
  Future<String?> remoteVersion(String name) async {
    final found = await manifest();
    return found == null ? null : versionOf(found.$2, name);
  }
}

/// Offline bus stop list, on top of [BundleRepository].
class BusStopRepository {
  BusStopRepository({Dio? dio, List<String>? baseUrls, Future<Directory> Function()? storageDir})
      : _bundles = BundleRepository(dio: dio, baseUrls: baseUrls, storageDir: storageDir);

  BusStopRepository.fromBundles(this._bundles);

  final BundleRepository _bundles;
  List<BusStop>? _memory;

  Future<List<BusStop>> load() async {
    if (_memory != null) return _memory!;
    final rows = await _bundles.load('bus_stops');
    if (rows is! List) return const [];
    _memory = [for (final r in rows) BusStop.fromBundle(r as Map<String, dynamic>)];
    return _memory!;
  }
}
