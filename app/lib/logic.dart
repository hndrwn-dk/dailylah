/// Pure functions behind the cards and alerts. No Flutter, no I/O: easy to test and
/// safe to call from the background isolate.
library;

import 'dart:math' as math;

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

/// Morning card until 14:00, evening card after.
CardKind cardFor(DateTime now) => now.hour < 14 ? CardKind.morning : CardKind.evening;

/// The place whose stops/weather the card should show.
PlaceKind originFor(CardKind kind, Favorites fav) {
  if (kind == CardKind.evening && fav.places.containsKey(PlaceKind.work)) return PlaceKind.work;
  return PlaceKind.home;
}

/// The place the user is heading to (used for rain at destination).
PlaceKind? destinationFor(CardKind kind, Favorites fav) {
  if (kind == CardKind.morning) {
    if (fav.places.containsKey(PlaceKind.work)) return PlaceKind.work;
    if (fav.places.containsKey(PlaceKind.school)) return PlaceKind.school;
    return null;
  }
  return PlaceKind.home;
}

bool isQuietHour(DateTime now) => now.hour >= 22 || now.hour < 6;

/// True when now is within [leave - 60 min, leave].
bool inRainWindow(DateTime now, TimeOfDayHM leave) {
  final m = now.hour * 60 + now.minute;
  return m >= leave.minutes - 60 && m <= leave.minutes;
}

String dayKey(DateTime now) =>
    '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
