/// Pure functions behind the cards and alerts. No Flutter, no I/O: easy to test and
/// safe to call from the background isolate.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'data.dart';
import 'l10n.dart';
import 'models.dart';

// ---------------------------------------------------------------- geo

double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

List<BusStop> nearestStops(List<BusStop> all, double lat, double lng, {int limit = 5}) {
  final sorted = [...all]
    ..sort((a, b) => distanceMeters(lat, lng, a.lat, a.lng)
        .compareTo(distanceMeters(lat, lng, b.lat, b.lng)));
  return sorted.take(limit).toList();
}

List<BusStop> searchStops(List<BusStop> all, String query, {int limit = 30}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <BusStop>[];
  for (final s in all) {
    if (s.code.startsWith(q) ||
        s.name.toLowerCase().contains(q) ||
        s.road.toLowerCase().contains(q)) {
      out.add(s);
      if (out.length >= limit) break;
    }
  }
  return out;
}

// ---------------------------------------------------------------- weather

/// Reads our API's wrapped data.gov.sg two-hr-forecast:
/// {"data": {"data": {"area_metadata": [...], "items": [{"forecasts": [...]}]}}}
class AreaForecast {
  const AreaForecast({required this.area, required this.forecast, this.validText});
  final String area;
  final String forecast;
  final String? validText;

  bool get isRainy => isRainyForecast(forecast);
}

AreaForecast? forecastNear(Map<String, dynamic> apiBody, double lat, double lng) {
  final upstream = apiBody['data'];
  if (upstream is! Map) return null;
  final data = upstream['data'];
  if (data is! Map) return null;
  final meta = data['area_metadata'];
  final items = data['items'];
  if (meta is! List || items is! List || items.isEmpty) return null;

  String? bestArea;
  var bestDist = double.infinity;
  for (final m in meta) {
    final loc = (m as Map)['label_location'] as Map?;
    if (loc == null) continue;
    final d = distanceMeters(
      lat,
      lng,
      (loc['latitude'] as num).toDouble(),
      (loc['longitude'] as num).toDouble(),
    );
    if (d < bestDist) {
      bestDist = d;
      bestArea = m['name'] as String?;
    }
  }
  if (bestArea == null) return null;

  final latest = items.last as Map;
  for (final f in (latest['forecasts'] as List? ?? const [])) {
    final fm = f as Map;
    if (fm['area'] == bestArea) {
      final valid = latest['valid_period'];
      return AreaForecast(
        area: bestArea,
        forecast: '${fm['forecast']}',
        validText: valid is Map ? valid['text'] as String? : null,
      );
    }
  }
  return null;
}

bool isRainyForecast(String forecast) {
  final f = forecast.toLowerCase();
  return f.contains('rain') || f.contains('shower') || f.contains('thunder');
}

// ---------------------------------------------------------------- bus

/// Parses our API's wrapped LTA BusArrival v3 response into the next buses per service.
List<BusEta> parseBusArrival(Map<String, dynamic> apiBody, DateTime now, {int perService = 2}) {
  final upstream = apiBody['data'];
  if (upstream is! Map) return const [];
  final services = upstream['Services'];
  if (services is! List) return const [];
  final out = <BusEta>[];
  for (final s in services) {
    final sm = s as Map;
    final no = '${sm['ServiceNo']}';
    var taken = 0;
    for (final key in const ['NextBus', 'NextBus2', 'NextBus3']) {
      if (taken >= perService) break;
      final nb = sm[key];
      if (nb is! Map) continue;
      final eta = DateTime.tryParse('${nb['EstimatedArrival'] ?? ''}');
      if (eta == null) continue;
      final mins = eta.difference(now).inSeconds / 60;
      out.add(BusEta(service: no, minutes: mins < 0 ? 0 : mins.floor(), load: '${nb['Load']}'));
      taken++;
    }
  }
  out.sort((a, b) => a.minutes.compareTo(b.minutes));
  return out;
}

String loadLabel(String code) => switch (code) {
      'SEA' => 'Ada kursi',
      'SDA' => 'Berdiri',
      'LSD' => 'Penuh',
      _ => '',
    };

// ---------------------------------------------------------------- MRT

class LineStatus {
  const LineStatus({required this.line, required this.disrupted, this.detail});
  final String line;
  final bool disrupted;
  final String? detail;
}

/// Reads our API's wrapped LTA TrainServiceAlerts. Status 1 = normal, 2 = disrupted.
List<LineStatus> lineStatuses(Map<String, dynamic> apiBody, Set<String> lines) {
  final value = (apiBody['data'] is Map) ? (apiBody['data'] as Map)['value'] : null;
  final affected = <String, String>{};
  if (value is Map && '${value['Status']}' == '2') {
    for (final seg in (value['AffectedSegments'] as List? ?? const [])) {
      final m = seg as Map;
      final line = '${m['Line']}';
      final parts = [
        if ((m['Stations'] ?? '').toString().isNotEmpty) 'Stasiun: ${m['Stations']}',
        if ((m['FreePublicBus'] ?? '').toString().isNotEmpty) 'Bus gratis tersedia',
        if ((m['FreeMRTShuttle'] ?? '').toString().isNotEmpty) 'Shuttle tersedia',
      ];
      affected[line] = parts.join(' · ');
    }
    final messages = value['Message'];
    if (messages is List && messages.isNotEmpty && affected.isEmpty) {
      // Disruption without segment detail: mark all chosen lines as possibly affected.
      for (final l in lines) {
        affected[l] = '${(messages.first as Map)['Content'] ?? ''}';
      }
    }
  }
  final sorted = lines.toList()..sort();
  return [
    for (final l in sorted)
      LineStatus(line: l, disrupted: affected.containsKey(l), detail: affected[l]),
  ];
}

/// Share of stations at high crowd level ('h') in a PCDRealTime response, or null.
double? highCrowdShare(Map<String, dynamic> apiBody) {
  final value = (apiBody['data'] is Map) ? (apiBody['data'] as Map)['value'] : null;
  if (value is! List || value.isEmpty) return null;
  final known = value.where((s) => '${(s as Map)['CrowdLevel']}' != 'NA').toList();
  if (known.isEmpty) return null;
  final high = known.where((s) => '${(s as Map)['CrowdLevel']}' == 'h').length;
  return high / known.length;
}

// ---------------------------------------------------------------- cards & alerts

enum CardKind { morning, evening }

/// Work or school place in use today: work if today is one of its days, else school.
Place? commutePlace(Favorites fav, DateTime now) {
  for (final k in const [PlaceKind.work, PlaceKind.school]) {
    final p = fav.places[k];
    if (p != null && p.days.contains(now.weekday)) return p;
  }
  return null;
}

/// Usual (go, back) times for today's commute, falling back to the global defaults.
(TimeOfDayHM, TimeOfDayHM) commuteTimes(Favorites fav, DateTime now) {
  final p = commutePlace(fav, now) ?? fav.places[PlaceKind.work] ?? fav.places[PlaceKind.school];
  return (p?.go ?? fav.leaveHome, p?.back ?? fav.leaveWork);
}

/// Morning card until halfway between the usual go and back times (14:00 without
/// settings), evening card after.
CardKind cardFor(DateTime now, [Favorites? fav]) {
  final m = now.hour * 60 + now.minute;
  if (fav == null) return m < 14 * 60 ? CardKind.morning : CardKind.evening;
  final (go, back) = commuteTimes(fav, now);
  if (back.minutes <= go.minutes) return m < 14 * 60 ? CardKind.morning : CardKind.evening;
  return m < (go.minutes + back.minutes) ~/ 2 ? CardKind.morning : CardKind.evening;
}

/// True when today is a work or school day for one of those places.
bool isCommuteDay(Favorites fav, DateTime now) => commutePlace(fav, now) != null;

/// MRT lines to watch for alerts: the starred ones, or every line when none is starred.
Set<String> watchedLines(Favorites fav) => fav.lines.isEmpty ? trainLines.keys.toSet() : fav.lines;

/// Custom places that fit today (weekday or weekend).
List<int> extrasForToday(Favorites fav, DateTime now) {
  final weekend = now.weekday >= 6;
  return [
    for (var i = 0; i < fav.extraPlaces.length; i++)
      if (fav.extraPlaces[i].when == PlaceWhen.anytime ||
          (weekend ? fav.extraPlaces[i].when == PlaceWhen.weekends : fav.extraPlaces[i].when == PlaceWhen.weekdays))
        i,
  ];
}

/// The place whose stops/weather the card should show: the work/school place on a
/// commute evening, otherwise home (also on days off).
PlaceKind originFor(CardKind kind, Favorites fav, [DateTime? now]) {
  if (kind == CardKind.evening) {
    final p = commutePlace(fav, now ?? DateTime.now());
    if (p != null) return p.kind;
  }
  return PlaceKind.home;
}

/// The place the user is heading to (used for rain at destination), or null on a day off.
PlaceKind? destinationFor(CardKind kind, Favorites fav, [DateTime? now]) {
  final p = commutePlace(fav, now ?? DateTime.now());
  if (p == null) return null;
  return kind == CardKind.morning ? p.kind : PlaceKind.home;
}

bool isQuietHour(DateTime now) => now.hour >= 22 || now.hour < 6;

/// True when now is within [leave - 60 min, leave].
bool inRainWindow(DateTime now, TimeOfDayHM leave) {
  final m = now.hour * 60 + now.minute;
  return m >= leave.minutes - 60 && m <= leave.minutes;
}

String dayKey(DateTime now) =>
    '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

// ================================================================ Phase 2, 3 and Homes
// Everything below works on the static bundles (lib/data.dart) and live endpoints.

/// Items within [radius] metres of a point, nearest first, with their distance.
List<(T, double)> within<T>(
  Iterable<T> items,
  double lat,
  double lng,
  double radius, {
  required double Function(T) latOf,
  required double Function(T) lngOf,
  int? limit,
}) {
  final out = <(T, double)>[];
  for (final it in items) {
    final d = distanceMeters(lat, lng, latOf(it), lngOf(it));
    if (d <= radius) out.add((it, d));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return limit == null ? out : out.take(limit).toList();
}

/// Nearest item and its distance, or null when the list is empty.
(T, double)? nearest<T>(
  Iterable<T> items,
  double lat,
  double lng, {
  required double Function(T) latOf,
  required double Function(T) lngOf,
}) {
  (T, double)? best;
  for (final it in items) {
    final d = distanceMeters(lat, lng, latOf(it), lngOf(it));
    if (best == null || d < best.$2) best = (it, d);
  }
  return best;
}

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

String shortDate(DateTime d) => '${d.day}/${d.month}';

/// "S$612,000" → compact "S$612k", "S$1.05M".
String sgd(int amount, {bool compact = false}) {
  if (compact) {
    if (amount >= 1000000) return 'S\$${(amount / 1000000).toStringAsFixed(2)}M';
    if (amount >= 1000) return 'S\$${(amount / 1000).round()}k';
  }
  final s = amount.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return 'S\$$b';
}

/// "2026-08" → "Aug 2026".
String monthLabel(String ym) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final p = ym.split('-');
  if (p.length < 2) return ym;
  final i = int.tryParse(p[1]) ?? 0;
  return i < 1 || i > 12 ? ym : '${m[i - 1]} ${p[0]}';
}

// ---------------------------------------------------------------- dengue

/// Clusters whose area comes within [km] of a point (distance minus cluster radius).
List<(DengueCluster, double)> dengueNear(List<DengueCluster> all, double lat, double lng, {double km = 1}) {
  final out = <(DengueCluster, double)>[];
  for (final c in all) {
    final d = distanceMeters(lat, lng, c.lat, c.lng) - c.radius;
    if (d <= km * 1000) out.add((c, d < 0 ? 0 : d));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}

// ---------------------------------------------------------------- taxis and parking

/// Counts taxi coordinates ([[lat, lng], ...] from /v1/taxi) within [radius] metres.
int taxisWithin(Map<String, dynamic> apiBody, double lat, double lng, {double radius = 500}) {
  final pts = apiBody['data'];
  if (pts is! List) return 0;
  var n = 0;
  for (final p in pts) {
    if (p is List && p.length >= 2) {
      if (distanceMeters(lat, lng, (p[0] as num).toDouble(), (p[1] as num).toDouble()) <= radius) n++;
    }
  }
  return n;
}

/// Available car lots per car park id from /v1/carpark: {"data": {"ACB": [total, available]}}.
Map<String, (int, int)> carparkLots(Map<String, dynamic> apiBody) {
  final d = apiBody['data'];
  if (d is! Map) return const {};
  return {
    for (final e in d.entries)
      if (e.value is List && (e.value as List).length >= 2)
        '${e.key}': (((e.value as List)[0] as num).toInt(), ((e.value as List)[1] as num).toInt()),
  };
}

// ---------------------------------------------------------------- heat and lightning

/// Heat stress category from /v1/weather/wbgt for the station nearest a point,
/// e.g. "Low", "Moderate", "High". Null when unavailable.
String? heatStressNear(Map<String, dynamic> apiBody, double lat, double lng) {
  final readings = _wbgtReadings(apiBody);
  (String, double)? best;
  for (final r in readings) {
    final d = distanceMeters(lat, lng, r.$1, r.$2);
    if (best == null || d < best.$2) best = (r.$3, d);
  }
  return best?.$1;
}

bool isHighHeat(String? category) {
  final c = (category ?? '').toLowerCase();
  return c.contains('high') || c.contains('extreme');
}

/// (lat, lng, heatStress) from data.gov.sg v2 weather?api=wbgt.
List<(double, double, String)> _wbgtReadings(Map<String, dynamic> apiBody) {
  final out = <(double, double, String)>[];
  final data = (apiBody['data'] is Map) ? (apiBody['data'] as Map)['data'] : null;
  final records = data is Map ? data['records'] : null;
  if (records is! List || records.isEmpty) return out;
  final item = (records.last as Map)['item'];
  final readings = item is Map ? item['readings'] : null;
  if (readings is! List) return out;
  for (final r in readings) {
    if (r is! Map) continue;
    final loc = (r['location'] ?? r['station']) as Map?;
    final la = loc?['latitude'] ?? (loc?['location'] as Map?)?['latitude'];
    final lo = loc?['longitude'] ?? (loc?['location'] as Map?)?['longitude'];
    final hs = r['heatStress'] ?? r['heat_stress'];
    if (la == null || lo == null || hs == null) continue;
    out.add((double.parse('$la'), double.parse('$lo'), '$hs'));
  }
  return out;
}

/// True when a lightning strike was observed within [km] of a point in the latest
/// /v1/weather/lightning reading.
bool lightningNear(Map<String, dynamic> apiBody, double lat, double lng, {double km = 5}) {
  final data = (apiBody['data'] is Map) ? (apiBody['data'] as Map)['data'] : null;
  final records = data is Map ? data['records'] : null;
  if (records is! List || records.isEmpty) return false;
  final item = (records.last as Map)['item'];
  final readings = item is Map ? item['readings'] : null;
  if (readings is! List) return false;
  for (final r in readings) {
    if (r is! Map) continue;
    final loc = r['location'] as Map?;
    final la = loc?['latitude'];
    final lo = loc?['longitude'] ?? loc?['longtitude'];
    if (la == null || lo == null) continue;
    if (distanceMeters(lat, lng, double.parse('$la'), double.parse('$lo')) <= km * 1000) return true;
  }
  return false;
}

// ---------------------------------------------------------------- weekend and prayer

/// Indoor ideas when rain is expected at home, outdoor otherwise.
bool preferIndoor(AreaForecast? homeForecast) => homeForecast?.isRainy ?? false;

/// Index (0..5) of the next prayer after [now], or null when all have passed.
int? nextPrayerIndex(List<String> times, DateTime now) {
  final m = now.hour * 60 + now.minute;
  for (var i = 0; i < times.length; i++) {
    final p = times[i].split(':');
    if (p.length < 2) continue;
    final t = int.parse(p[0]) * 60 + int.parse(p[1]);
    if (t > m) return i;
  }
  return null;
}

// ---------------------------------------------------------------- homes

class BlockScore {
  const BlockScore({
    required this.nearestMrt,
    required this.busStops400,
    required this.hawkers1km,
    required this.primary1km,
    required this.primary2km,
    required this.parks1km,
    required this.dengue1km,
  });

  final (Poi, double)? nearestMrt;
  final int busStops400;
  final int hawkers1km;
  final int primary1km;
  final int primary2km;
  final int parks1km;
  final int dengue1km;
}

BlockScore scoreBlock(
  HdbBlock b, {
  required PoiSet pois,
  required List<BusStop> stops,
  required List<Hawker> hawkers,
  required List<DengueCluster> dengue,
}) {
  double pLat(Poi p) => p.lat;
  double pLng(Poi p) => p.lng;
  final primary = pois.of(PoiKind.primarySchool);
  return BlockScore(
    nearestMrt: nearest(pois.of(PoiKind.mrt), b.lat, b.lng, latOf: pLat, lngOf: pLng),
    busStops400: within(stops, b.lat, b.lng, 400, latOf: (s) => s.lat, lngOf: (s) => s.lng).length,
    hawkers1km: within(hawkers, b.lat, b.lng, 1000, latOf: (h) => h.lat, lngOf: (h) => h.lng).length,
    primary1km: within(primary, b.lat, b.lng, 1000, latOf: pLat, lngOf: pLng).length,
    primary2km: within(primary, b.lat, b.lng, 2000, latOf: pLat, lngOf: pLng).length,
    parks1km: within(pois.of(PoiKind.park), b.lat, b.lng, 1000, latOf: pLat, lngOf: pLng).length,
    dengue1km: dengueNear(dengue, b.lat, b.lng, km: 1).length,
  );
}

/// Matches blocks by "block street" words, e.g. "123 bedok nth" or "bedok north 123".
List<HdbBlock> searchBlocks(List<HdbBlock> all, String query, {int limit = 30}) {
  final q = query.trim();
  if (isPostalCode(q)) return [for (final b in all) if (b.postal == q) b];
  final words = query
      .toUpperCase()
      .replaceAll('NORTH', 'NTH')
      .replaceAll('SOUTH', 'STH')
      .replaceAll('AVENUE', 'AVE')
      .replaceAll('STREET', 'ST')
      .replaceAll('ROAD', 'RD')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  final out = <HdbBlock>[];
  for (final b in all) {
    final hay = '${b.block} ${b.street} ${b.town}';
    if (words.every((w) => b.block == w || hay.contains(w))) {
      out.add(b);
      if (out.length >= limit) break;
    }
  }
  return out;
}

// ---------------------------------------------------------------- family share

const _sharePrefix = 'DL1:';

/// Compact share code with places, lines and departure times. No account or server.
String encodeShareCode(Favorites fav) {
  final payload = {
    'p': [for (final p in fav.places.values) p.toJson()],
    'l': fav.lines.toList()..sort(),
    'h': fav.leaveHome.toString(),
    'w': fav.leaveWork.toString(),
  };
  return _sharePrefix + base64Url.encode(utf8.encode(jsonEncode(payload)));
}

/// Applies a share code on top of [current]. Returns null when the code is invalid.
Favorites? decodeShareCode(String code, Favorites current) {
  final c = code.trim();
  if (!c.startsWith(_sharePrefix)) return null;
  try {
    final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(c.substring(_sharePrefix.length)))))
        as Map<String, dynamic>;
    final places = <PlaceKind, Place>{};
    for (final p in (j['p'] as List? ?? const [])) {
      final place = Place.fromJson(p as Map<String, dynamic>);
      places[place.kind] = place;
    }
    if (!places.containsKey(PlaceKind.home)) return null;
    return current.copyWith(
      places: places,
      lines: {for (final l in (j['l'] as List? ?? const [])) '$l'},
      leaveHome: TimeOfDayHM.parse('${j['h'] ?? '7:30'}'),
      leaveWork: TimeOfDayHM.parse('${j['w'] ?? '18:0'}'),
    );
  } on Object {
    return null;
  }
}

// ---------------------------------------------------------------- today alerts

enum AlertKind { rain, mrt, hawker, dengue, heat, lightning, haze }

class TodayAlert {
  const TodayAlert(this.kind, this.text);
  final AlertKind kind;
  final String text;
}

/// The short list of things worth knowing right now, most urgent first.
/// Every input is optional so the list fills in as data arrives.
List<TodayAlert> todayAlerts({
  required Favorites fav,
  required DateTime now,
  required S s,
  Map<String, dynamic>? forecast,
  Map<String, dynamic>? trainAlerts,
  List<Hawker> hawkers = const [],
  List<DengueCluster> dengue = const [],
  Map<String, dynamic>? wbgt,
  Map<String, dynamic>? lightning,
  Map<String, dynamic>? psi,
  Map<String, dynamic>? pm25,
}) {
  final out = <TodayAlert>[];
  final kind = cardFor(now, fav);

  final homePlace = fav.places[PlaceKind.home];
  if (homePlace != null && (psi != null || pm25 != null)) {
    final air = airNear(psi, pm25, homePlace.lat, homePlace.lng);
    if (air != null && air.level.index >= AirLevel.unhealthy.index) {
      out.add(TodayAlert(AlertKind.haze, s.airAdviceShort(air.level)));
    }
  }

  if (trainAlerts != null) {
    final bad = lineStatuses(trainAlerts, watchedLines(fav)).where((l) => l.disrupted).map((l) => l.line).toList();
    if (bad.isNotEmpty) out.add(TodayAlert(AlertKind.mrt, s.mrtAlert(bad.join(', '))));
  }

  final school = fav.places[PlaceKind.school];
  final home = fav.places[PlaceKind.home];
  if (lightning != null) {
    final spots = <Place>[if (home != null) home, if (school != null) school];
    if (spots.any((p) => lightningNear(lightning, p.lat, p.lng))) {
      out.add(TodayAlert(AlertKind.lightning, s.lightningNear));
    }
  }

  if (forecast != null) {
    final dest = destinationFor(kind, fav, now);
    final candidates = [fav.places[originFor(kind, fav, now)], if (dest != null) fav.places[dest]];
    for (final p in candidates) {
      if (p == null) continue;
      final f = forecastNear(forecast, p.lat, p.lng);
      if (f != null && f.isRainy) {
        out.add(TodayAlert(AlertKind.rain, s.rainAt(s.placeLabel(p.kind.name))));
        break;
      }
    }
  }

  if (wbgt != null && school != null) {
    final level = heatStressNear(wbgt, school.lat, school.lng);
    if (isHighHeat(level)) {
      out.add(TodayAlert(AlertKind.heat, s.heatAt(s.placeLabel('school'), level!.toLowerCase())));
    }
  }

  final today = dateOnly(now);
  for (final h in hawkers.where((h) => fav.hawkers.contains(h.id))) {
    final tomorrow = today.add(const Duration(days: 1));
    final day = h.closureOn(today) != null ? today : (h.closureOn(tomorrow) != null ? tomorrow : null);
    if (day == null) continue;
    final alt = openAlternatives(hawkers, h, day, limit: 1);
    final base = day == today ? s.hawkerClosedToday(h.name) : s.hawkerClosedTomorrow(h.name);
    out.add(TodayAlert(
      AlertKind.hawker,
      alt.isEmpty ? base : '$base. ${s.tryInstead(alt.first.$1.name, s.metres(alt.first.$2))}',
    ));
  }

  for (final p in <Place>[if (home != null) home, if (school != null) school]) {
    final n = dengueNear(dengue, p.lat, p.lng, km: 1).length;
    if (n > 0) out.add(TodayAlert(AlertKind.dengue, s.dengueNear(s.placeLabel(p.kind.name), n)));
  }
  return out;
}


// ---------------------------------------------------------------- addresses (OneMap)

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Results of https://www.onemap.gov.sg/api/common/elastic/search, de-duplicated by postal code.
List<AddressHit> parseOneMap(Map<String, dynamic> body) {
  final out = <AddressHit>[];
  final seen = <String>{};
  for (final r in (body['results'] as List? ?? const [])) {
    if (r is! Map) continue;
    final lat = double.tryParse('${r['LATITUDE']}');
    final lng = double.tryParse('${r['LONGITUDE']}');
    if (lat == null || lng == null) continue;
    String clean(Object? v) => v == null || '$v' == 'NIL' ? '' : '$v'.trim();
    final block = clean(r['BLK_NO']);
    final road = clean(r['ROAD_NAME']);
    final building = clean(r['BUILDING']);
    final postal = clean(r['POSTAL']);
    if (!seen.add(postal.isEmpty ? '$lat,$lng' : postal)) continue;
    final street = _titleCase([block, road].where((x) => x.isNotEmpty).join(' '));
    final label = building.isNotEmpty && !building.contains('HDB-') && building != road
        ? '$street (${_titleCase(building)})'
        : street;
    out.add(AddressHit(
      label: label.isEmpty ? clean(r['SEARCHVAL']) : label,
      block: block,
      road: road,
      building: building,
      postal: postal,
      lat: lat,
      lng: lng,
    ));
  }
  return out;
}

/// The HDB block matching a OneMap hit: same block number, closest within 250 m.
HdbBlock? blockForAddress(List<HdbBlock> blocks, AddressHit hit) {
  HdbBlock? best;
  var bestD = 250.0;
  for (final b in blocks) {
    if (b.block.toUpperCase() != hit.block.toUpperCase()) continue;
    final d = distanceMeters(hit.lat, hit.lng, b.lat, b.lng);
    if (d < bestD) {
      best = b;
      bestD = d;
    }
  }
  return best;
}

bool isPostalCode(String q) => RegExp(r'^\d{6}$').hasMatch(q.trim());

// ---------------------------------------------------------------- weather details

/// Rainfall (mm in the last 5 minutes) at the station nearest a point, from
/// /v1/weather/rainfall: (station name, mm, distance in metres).
(String, double, double)? rainfallNear(Map<String, dynamic> apiBody, double lat, double lng) {
  final data = (apiBody['data'] is Map) ? (apiBody['data'] as Map)['data'] : null;
  if (data is! Map) return null;
  final stations = <String, (String, double, double)>{};
  for (final s in (data['stations'] as List? ?? const [])) {
    if (s is! Map) continue;
    final loc = s['location'] as Map?;
    final la = double.tryParse('${loc?['latitude']}');
    final lo = double.tryParse('${loc?['longitude']}');
    if (la == null || lo == null) continue;
    stations['${s['id']}'] = ('${s['name'] ?? s['id']}', la, lo);
  }
  final readings = data['readings'] as List?;
  if (readings == null || readings.isEmpty) return null;
  final latest = readings.first as Map;
  (String, double, double)? best;
  for (final r in (latest['data'] as List? ?? const [])) {
    if (r is! Map) continue;
    final st = stations['${r['stationId']}'];
    final v = double.tryParse('${r['value']}');
    if (st == null || v == null) continue;
    final d = distanceMeters(lat, lng, st.$2, st.$3);
    if (best == null || d < best.$3) best = (st.$1, v, d);
  }
  return best;
}

/// Latest UV index from /v1/weather/uv, or null.
int? uvIndex(Map<String, dynamic> apiBody) {
  final data = (apiBody['data'] is Map) ? (apiBody['data'] as Map)['data'] : null;
  final records = data is Map ? data['records'] : null;
  if (records is! List || records.isEmpty) return null;
  final index = (records.first as Map)['index'];
  if (index is! List || index.isEmpty) return null;
  Map? latest;
  for (final i in index) {
    if (i is! Map) continue;
    if (latest == null || '${i['hour']}'.compareTo('${latest['hour']}') > 0) latest = i;
  }
  return int.tryParse('${latest?['value']}') ?? (latest?['value'] as num?)?.round();
}

/// WBGT in °C at the station nearest a point, with its heat stress category.
(double, String)? wbgtNear(Map<String, dynamic> apiBody, double lat, double lng) {
  final data = (apiBody['data'] is Map) ? (apiBody['data'] as Map)['data'] : null;
  final records = data is Map ? data['records'] : null;
  if (records is! List || records.isEmpty) return null;
  final item = (records.last as Map)['item'];
  final readings = item is Map ? item['readings'] : null;
  if (readings is! List) return null;
  (double, String, double)? best;
  for (final r in readings) {
    if (r is! Map) continue;
    final loc = r['location'] as Map?;
    final la = double.tryParse('${loc?['latitude']}');
    final lo = double.tryParse('${loc?['longitude']}');
    final w = double.tryParse('${r['wbgt']}');
    if (la == null || lo == null || w == null) continue;
    final d = distanceMeters(lat, lng, la, lo);
    if (best == null || d < best.$3) best = (w, '${r['heatStress'] ?? ''}', d);
  }
  return best == null ? null : (best.$1, best.$2);
}

// ---------------------------------------------------------------- hawker alternatives

/// Hawker centres open on [day] near a closed one, nearest first.
List<(Hawker, double)> openAlternatives(List<Hawker> all, Hawker closed, DateTime day,
    {double radius = 2500, int limit = 2}) {
  return within(all, closed.lat, closed.lng, radius, latOf: (h) => h.lat, lngOf: (h) => h.lng)
      .where((e) => e.$1.id != closed.id && e.$1.closureOn(day) == null)
      .take(limit)
      .toList();
}

// ---------------------------------------------------------------- schools

/// Schools of one kind within 1 km and between 1 and 2 km of a point (straight line).
(List<(Poi, double)>, List<(Poi, double)>) schoolsByBand(List<Poi> schools, double lat, double lng) {
  final all = within(schools, lat, lng, 2000, latOf: (p) => p.lat, lngOf: (p) => p.lng);
  return (all.where((e) => e.$2 <= 1000).toList(), all.where((e) => e.$2 > 1000).toList());
}


// ---------------------------------------------------------------- air quality (haze)

class AirQuality {
  const AirQuality({required this.region, this.psi24, this.pm25, required this.level});
  final String region; // north, south, east, west, central
  final int? psi24;
  final int? pm25; // 1-hour PM2.5 concentration, µg/m³
  final AirLevel level;
}

AirLevel psiLevel(int psi) => psi > 300
    ? AirLevel.hazardous
    : psi > 200
        ? AirLevel.veryUnhealthy
        : psi > 100
            ? AirLevel.unhealthy
            : psi > 50
                ? AirLevel.moderate
                : AirLevel.good;

/// NEA 1-hour PM2.5 bands: I 0–55, II 56–150, III 151–250, IV 251+.
AirLevel pm25Level(int v) => v > 250
    ? AirLevel.hazardous
    : v > 150
        ? AirLevel.veryUnhealthy
        : v > 55
            ? AirLevel.unhealthy
            : AirLevel.good;

/// Air quality for the NEA region nearest a point, from /v1/weather/psi and /pm25.
/// The level is the worse of the 24-hour PSI band and the 1-hour PM2.5 band.
AirQuality? airNear(Map<String, dynamic>? psiBody, Map<String, dynamic>? pm25Body, double lat, double lng) {
  Map? inner(Map<String, dynamic>? b) => (b?['data'] is Map) ? (b!['data'] as Map)['data'] as Map? : null;
  final psi = inner(psiBody);
  final pm = inner(pm25Body);
  final meta = (psi?['regionMetadata'] ?? pm?['regionMetadata']) as List?;
  if (meta == null) return null;
  String? region;
  var best = double.infinity;
  for (final r in meta) {
    if (r is! Map || r['name'] == 'national') continue;
    final loc = r['labelLocation'] as Map?;
    final la = double.tryParse('${loc?['latitude']}');
    final lo = double.tryParse('${loc?['longitude']}');
    if (la == null || lo == null) continue;
    final d = distanceMeters(lat, lng, la, lo);
    if (d < best) {
      best = d;
      region = '${r['name']}';
    }
  }
  if (region == null) return null;
  int? reading(Map? data, String key) {
    final items = data?['items'] as List?;
    if (items == null || items.isEmpty) return null;
    final readings = (items.last as Map)['readings'] as Map?;
    final v = (readings?[key] as Map?)?[region];
    return v is num ? v.round() : int.tryParse('$v');
  }

  final psi24 = reading(psi, 'psi_twenty_four_hourly');
  final pm25 = reading(pm, 'pm25_one_hourly');
  if (psi24 == null && pm25 == null) return null;
  final a = psi24 == null ? AirLevel.good : psiLevel(psi24);
  final b = pm25 == null ? AirLevel.good : pm25Level(pm25);
  return AirQuality(region: region, psi24: psi24, pm25: pm25, level: a.index >= b.index ? a : b);
}

// ---------------------------------------------------------------- emergency

/// Nearest points of one emergency layer.
List<(EPoint, double)> nearestPoints(List<EPoint> all, double lat, double lng, {int limit = 3, double radius = 30000}) =>
    within(all, lat, lng, radius, latOf: (p) => p.lat, lngOf: (p) => p.lng, limit: limit);


// ---------------------------------------------------------------- taxis (detail)

/// Taxi positions from /v1/taxi as (lat, lng).
List<(double, double)> taxiPoints(Map<String, dynamic> apiBody) {
  final pts = apiBody['data'];
  if (pts is! List) return const [];
  return [
    for (final p in pts)
      if (p is List && p.length >= 2) ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
  ];
}

/// Taxis within 200 m, 500 m and 1 km of a point.
(int, int, int) taxiBands(List<(double, double)> pts, double lat, double lng) {
  var a = 0, b = 0, c = 0;
  for (final (la, lo) in pts) {
    final d = distanceMeters(lat, lng, la, lo);
    if (d <= 200) a++;
    if (d <= 500) b++;
    if (d <= 1000) c++;
  }
  return (a, b, c);
}

/// Offset in metres (east, north) of a point from an origin; good enough within a few km.
(double, double) offsetMetres(double lat0, double lng0, double lat, double lng) =>
    ((lng - lng0) * 111320 * math.cos(lat0 * math.pi / 180), (lat - lat0) * 110540);


// ---------------------------------------------------------------- trips: buses that go there

/// LTA bus routes bundle: "<service>|<direction>" -> stops in order with km from start.
class BusRoutes {
  const BusRoutes(this.routes);
  final Map<String, List<(String, double)>> routes;
  static const empty = BusRoutes({});

  factory BusRoutes.fromBundle(Map<String, dynamic> j) => BusRoutes({
        for (final e in j.entries)
          if (e.value is List)
            e.key: [
              for (final r in e.value as List)
                if (r is List && r.length >= 2) ('${r[0]}', (r[1] as num).toDouble()),
            ],
      });
}

/// How a service gets from the origin stop to the destination.
class DirectRide {
  const DirectRide({required this.service, required this.alightAt, required this.stops, required this.km});
  final String service;
  final String alightAt; // bus stop code to get off
  final int stops;
  final double km;
}

/// Services that stop at [origin] and later at one of [destStops], best option per service.
Map<String, DirectRide> directRides(BusRoutes routes, String origin, Set<String> destStops) {
  final out = <String, DirectRide>{};
  routes.routes.forEach((key, stops) {
    final service = key.split('|').first;
    final i = stops.indexWhere((s) => s.$1 == origin);
    if (i < 0) return;
    for (var j = i + 1; j < stops.length; j++) {
      if (!destStops.contains(stops[j].$1)) continue;
      final ride = DirectRide(service: service, alightAt: stops[j].$1, stops: j - i, km: stops[j].$2 - stops[i].$2);
      final best = out[service];
      if (best == null || ride.km < best.km) out[service] = ride;
      break;
    }
  });
  return out;
}

/// Direct rides from [stop] to [to] without long detours: a loop service that goes the
/// long way round (more than 3x the straight distance + 2 km) is left out.
Map<String, DirectRide> tripRides(BusRoutes routes, BusStop stop, Place to, Set<String> destStops) {
  final straightKm = distanceMeters(stop.lat, stop.lng, to.lat, to.lng) / 1000;
  return {
    for (final e in directRides(routes, stop.code, destStops).entries)
      if (e.value.km <= straightKm * 3 + 2) e.key: e.value,
  };
}

/// Stops to look for at the destination: the place's own stops plus any within [radius] m.
Set<String> destinationStops(Place dest, List<BusStop> all, {double radius = 400}) => {
      for (final s in dest.stops) s.code,
      for (final (s, _) in within(all, dest.lat, dest.lng, radius, latOf: (s) => s.lat, lngOf: (s) => s.lng)) s.code,
    };

// ---------------------------------------------------------------- trips: driving and cycling

/// One car park with live lots: from /v1/parking.
class ParkingLot {
  const ParkingLot({
    required this.id,
    required this.agency,
    required this.lat,
    required this.lng,
    required this.lotType,
    required this.available,
    required this.name,
  });
  final String id;
  final String agency;
  final double lat;
  final double lng;
  final String lotType; // C car, Y motorcycle
  final int available;
  final String name;
}

List<ParkingLot> parseParking(Map<String, dynamic> apiBody) {
  final rows = apiBody['data'];
  if (rows is! List) return const [];
  return [
    for (final r in rows)
      if (r is List && r.length >= 7)
        ParkingLot(
          id: '${r[0]}',
          agency: '${r[1]}',
          lat: (r[2] as num).toDouble(),
          lng: (r[3] as num).toDouble(),
          lotType: '${r[4]}',
          available: (r[5] as num).toInt(),
          name: '${r[6]}',
        ),
  ];
}

/// Car parks with [lotType] lots near a point, nearest first.
List<(ParkingLot, double)> parkingNear(List<ParkingLot> all, double lat, double lng, String lotType,
        {double radius = 600, int limit = 5}) =>
    within(all.where((p) => p.lotType == lotType), lat, lng, radius,
        latOf: (p) => p.lat, lngOf: (p) => p.lng, limit: limit);

/// Distance in metres from a point to the straight segment a–b (good enough in Singapore).
double distanceToSegment(double lat, double lng, double aLat, double aLng, double bLat, double bLng) {
  final (px, py) = offsetMetres(aLat, aLng, lat, lng);
  final (bx, by) = offsetMetres(aLat, aLng, bLat, bLng);
  final len2 = bx * bx + by * by;
  final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
  final dx = px - t * bx, dy = py - t * by;
  return math.sqrt(dx * dx + dy * dy);
}

/// Traffic incidents ([[type, lat, lng, message]]) within [corridor] m of the trip line.
List<(String, String)> incidentsOnTrip(Map<String, dynamic>? apiBody, Place from, Place to, {double corridor = 2500}) {
  final rows = apiBody?['data'];
  if (rows is! List) return const [];
  return [
    for (final r in rows)
      if (r is List &&
          r.length >= 4 &&
          distanceToSegment((r[1] as num).toDouble(), (r[2] as num).toDouble(), from.lat, from.lng, to.lat, to.lng) <=
              corridor)
        ('${r[0]}', '${r[3]}'),
  ];
}


/// Start stops for a trip and whether they were suggested instead of the saved ones.
class TripStops {
  const TripStops(this.stops, {this.suggested = false});
  final List<BusStop> stops;

  /// True when no saved stop has a direct bus and these are nearby stops that do.
  final bool suggested;
}

/// Start stops for a trip: the [saved] ones with a direct bus to [to] (the right side of
/// the road). When none has one, nearby stops within [radius] m of [from] that do,
/// nearest first. Without route data (or nothing direct anywhere near), the saved
/// stops (or the two nearest when nothing is saved).
TripStops tripStops(List<BusStop> saved, List<BusStop> all, BusRoutes routes, Place from, Place to,
    {double radius = 500}) {
  final nearest = [
    for (final (st, _) in within(all, from.lat, from.lng, radius, latOf: (x) => x.lat, lngOf: (x) => x.lng, limit: 12)) st,
  ];
  final fallback = saved.isNotEmpty ? saved : nearest.take(2).toList();
  final destStops = destinationStops(to, all);
  if (routes.routes.isEmpty || destStops.isEmpty) return TripStops(fallback);
  bool ok(BusStop st) => tripRides(routes, st, to, destStops).isNotEmpty;
  final good = [for (final st in saved) if (ok(st)) st];
  if (good.isNotEmpty) return TripStops(good);
  final near = [for (final st in nearest) if (!saved.any((x) => x.code == st.code) && ok(st)) st];
  if (near.isNotEmpty) return TripStops(near.take(2).toList(), suggested: saved.isNotEmpty);
  return TripStops(fallback.take(saved.isNotEmpty ? 1 : 2).toList());
}

/// Group arrivals per service in arrival order: (first, next minutes or null).
List<(BusEta, int?)> groupEtas(List<BusEta> list) {
  final out = <String, (BusEta, int?)>{};
  for (final e in list) {
    final have = out[e.service];
    if (have == null) {
      out[e.service] = (e, null);
    } else if (have.$2 == null) {
      out[e.service] = (have.$1, e.minutes);
    }
  }
  return out.values.toList();
}

/// Short name for a long NEA label: "Tampines St 11 Blk 137 (Tampines Round Market)"
/// becomes "Tampines Round Market".
String shortPlaceName(String name) {
  final m = RegExp(r'\(([^)]+)\)\s*$').firstMatch(name);
  return m == null ? name : m.group(1)!;
}

/// Walking is the better answer under this straight-line distance.
const walkInsteadMetres = 1000.0;

// ---------------------------------------------------------------- trips: MRT

/// Line key (as in [trainLines]) for a station code like "TE26" or "CG1".
String? lineOfCode(String code) {
  final m = RegExp(r'^([A-Z]+)').firstMatch(code);
  return switch (m?.group(1)) {
    'NS' => 'NSL',
    'EW' || 'CG' => 'EWL',
    'CC' || 'CE' => 'CCL',
    'DT' => 'DTL',
    'NE' => 'NEL',
    'TE' => 'TEL',
    'BP' => 'BPL',
    'SE' || 'SW' || 'STC' => 'SLRT',
    'PE' || 'PW' || 'PTC' => 'PLRT',
    _ => null,
  };
}

/// Nearest stations at both ends and, when they share a line, the rough number of stops.
class MrtPlan {
  const MrtPlan({
    required this.board,
    required this.walkToBoard,
    required this.alight,
    required this.walkFromAlight,
    this.line,
    this.stops,
    this.via,
  });

  /// Where to change trains (e.g. Jurong East) when there is no shared line.
  final MrtStation? via;
  final MrtStation board;
  final double walkToBoard;
  final MrtStation alight;
  final double walkFromAlight;

  /// Shared line (e.g. "TEL") when no change of train is needed.
  final String? line;
  final int? stops;
  bool get direct => line != null;
}

MrtPlan? mrtPlan(List<MrtStation> stations, Place from, Place to, {double maxWalk = 1200}) {
  final a = nearest(stations, from.lat, from.lng, latOf: (x) => x.lat, lngOf: (x) => x.lng);
  final b = nearest(stations, to.lat, to.lng, latOf: (x) => x.lat, lngOf: (x) => x.lng);
  if (a == null || b == null || a.$2 > maxWalk || b.$2 > maxWalk || a.$1.name == b.$1.name) return null;
  String? line;
  int? stops;
  int? num(String c) => int.tryParse(RegExp(r'(\d+)').firstMatch(c)?.group(1) ?? '');
  for (final ca in a.$1.codes) {
    for (final cb in b.$1.codes) {
      final la = lineOfCode(ca);
      final pa = RegExp(r'^[A-Z]+').firstMatch(ca)?.group(0);
      final pb = RegExp(r'^[A-Z]+').firstMatch(cb)?.group(0);
      if (la == null || pa != pb || la != lineOfCode(cb)) continue;
      final na = num(ca), nb = num(cb);
      final n = na == null || nb == null ? null : (na - nb).abs();
      if (line == null || (n != null && (stops == null || n < stops))) {
        line = la;
        stops = n;
      }
    }
  }
  MrtStation? via;
  if (line == null) {
    // One change: a station on one of the boarding lines and one of the alighting lines.
    String? prefix(String c) => RegExp(r'^[A-Z]+').firstMatch(c)?.group(0);
    var best = 1 << 30;
    for (final x in stations) {
      for (final ca in a.$1.codes) {
        for (final cx in x.codes) {
          if (prefix(ca) != prefix(cx)) continue;
          for (final cb in b.$1.codes) {
            for (final cy in x.codes) {
              if (prefix(cb) != prefix(cy) || prefix(cx) == prefix(cy)) continue;
              final n1 = num(ca), n2 = num(cx), n3 = num(cy), n4 = num(cb);
              if (n1 == null || n2 == null || n3 == null || n4 == null) continue;
              final cost = (n1 - n2).abs() + (n3 - n4).abs();
              if (cost < best) {
                best = cost;
                via = x;
              }
            }
          }
        }
      }
    }
  }
  return MrtPlan(board: a.$1, walkToBoard: a.$2, alight: b.$1, walkFromAlight: b.$2, line: line, stops: stops, via: via);
}


// ---------------------------------------------------------------- home

/// The HDB block of a saved home: same postal code, else the nearest block within 40 m.
HdbBlock? homeBlock(List<HdbBlock> blocks, Place home) {
  final postal = home.postal?.trim() ?? '';
  if (postal.isNotEmpty) {
    for (final b in blocks) {
      if (b.postal == postal) return b;
    }
  }
  final n = nearest(blocks, home.lat, home.lng, latOf: (b) => b.lat, lngOf: (b) => b.lng);
  return n != null && n.$2 <= 40 ? n.$1 : null;
}

/// True when a project's estimated end ("3Q 2026", "2026-03") is already past.
bool projectEnded(String to, DateTime now) {
  final q = RegExp(r'^([1-4])Q (\d{4})$').firstMatch(to);
  if (q != null) {
    final y = int.parse(q.group(2)!), m = int.parse(q.group(1)!) * 3;
    return y < now.year || (y == now.year && m < now.month);
  }
  final ym = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(to);
  if (ym != null) {
    final y = int.parse(ym.group(1)!), m = int.parse(ym.group(2)!);
    return y < now.year || (y == now.year && m < now.month);
  }
  return false;
}

/// Distance from a point to a work site: 0 inside a small site, else to its nearest part.
double distanceToProject(Project p, double lat, double lng) {
  final centre = distanceMeters(lat, lng, p.lat, p.lng);
  if (p.radius <= 300 && centre <= p.radius) return 0;
  if (p.points.isEmpty) return math.max(0.0, centre - p.radius);
  var best = double.infinity;
  for (final (la, lo) in p.points) {
    best = math.min(best, distanceMeters(lat, lng, la, lo));
  }
  return best;
}

/// Works within [radius] m of a point that are not finished yet, nearest first.
List<(Project, double)> projectsNear(List<Project> all, double lat, double lng,
    {double radius = 1000, DateTime? now}) {
  final today = now ?? DateTime.now();
  final out = <(Project, double)>[];
  for (final p in all) {
    if (projectEnded(p.to, today)) continue;
    final d = distanceToProject(p, lat, lng);
    if (d <= radius) out.add((p, d));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}

/// Upgrading that covers the home itself (inside or right next to the site).
List<Project> upgradingAtHome(List<(Project, double)> near) =>
    [for (final (p, d) in near) if (p.isUpgrading && d <= 60) p];

/// Hawker centres within [radius] m that close for cleaning or works in the next [days].
List<(Hawker, Closure, double)> upcomingClosures(List<Hawker> all, double lat, double lng, DateTime now,
    {double radius = 1500, int days = 30}) {
  final today = DateTime(now.year, now.month, now.day);
  final until = today.add(Duration(days: days));
  final out = <(Hawker, Closure, double)>[];
  for (final (h, d) in within(all, lat, lng, radius, latOf: (h) => h.lat, lngOf: (h) => h.lng, limit: 30)) {
    for (final c in h.closures) {
      if (!c.to.isBefore(today) && !c.from.isAfter(until)) {
        out.add((h, c, d));
        break;
      }
    }
  }
  out.sort((a, b) => a.$2.from.compareTo(b.$2.from));
  return out;
}

/// Median rent in a town for the flat type closest to [flatType] ("3 ROOM" -> "3-ROOM").
(String, int)? rentFor(Map<String, int> rents, String? flatType) {
  if (rents.isEmpty) return null;
  final want = (flatType ?? '').toUpperCase().replaceAll(' ', '-');
  if (rents[want] != null) return (want, rents[want]!);
  final keys = rents.keys.toList()..sort();
  return (keys.first, rents[keys.first]!);
}
