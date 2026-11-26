// Bus, MRT and walking options between two places, worked out on the phone from the bundles
// (bus stops, bus routes, MRT stations). Pure Dart: no Flutter, no I/O, nothing sent anywhere.
import 'data.dart';
import 'logic.dart';
import 'models.dart';

/// Longest walk between two stops or stations for a change.
const transferWalkMetres = 250.0;

enum LegKind { walk, bus, mrt }

/// One part of an option: a walk, a bus ride or an MRT ride.
class TransitLeg {
  const TransitLeg({
    required this.kind,
    required this.from,
    required this.to,
    required this.fromName,
    required this.toName,
    required this.minutes,
    this.service,
    this.stops = 0,
    this.metres = 0,
    this.routeKey = '',
  });
  final LegKind kind;

  /// Node ids: a bus stop code, `mrt:<station name>`, or '' for the trip's own start or end.
  final String from;
  final String to;
  final String fromName;
  final String toName;

  /// Bus number, or the MRT line ("TEL"); null for a walk.
  final String? service;
  final int stops;
  final int minutes;

  /// Walking distance (walk legs only).
  final double metres;

  /// `<service>|<direction>` of the bus route, or `<code prefix>|<direction>` for MRT.
  final String routeKey;

  bool get isRide => kind != LegKind.walk;
}

/// A door-to-door option: walk, rides with changes, walk.
class TransitOption {
  const TransitOption(this.legs);
  final List<TransitLeg> legs;

  int get minutes => legs.fold(0, (sum, l) => sum + l.minutes);
  List<TransitLeg> get rides => [for (final l in legs) if (l.isRide) l];
  int get changes => rides.length - 1;
  double get walkMetres => legs.fold(0.0, (sum, l) => sum + l.metres);

  /// The rides' services in order ("55>854"): two options with the same one are the same option.
  String get signature => rides.map((r) => r.service).join('>');
}

class _Pattern {
  _Pattern(this.kind, this.service, this.routeKey, this.nodes);
  final LegKind kind;
  final String service;
  final String routeKey;
  final List<int> nodes;
}

/// The network the search runs on: bus stops and MRT stations as nodes, bus routes and MRT
/// lines as patterns (ordered nodes), and short walks between nodes.
class TransitNet {
  TransitNet._(this._ids, this._names, this._lats, this._lngs, this._index, this._patterns, this._at, this._walks);

  final List<String> _ids;
  final List<String> _names;
  final List<double> _lats;
  final List<double> _lngs;
  final Map<String, int> _index;
  final List<_Pattern> _patterns;

  /// Per node: (pattern, position in it); a loop route can hold a node twice.
  final List<List<(int, int)>> _at;
  final List<List<(int, double)>> _walks;

  int get nodeCount => _ids.length;
  bool get isEmpty => _patterns.isEmpty;
  bool hasNode(String id) => _index.containsKey(id);

  static TransitNet build(List<BusStop> stops, BusRoutes routes, List<MrtStation> stations) {
    final ids = <String>[], names = <String>[], lats = <double>[], lngs = <double>[];
    final index = <String, int>{};
    void add(String id, String name, double lat, double lng) {
      if (index.containsKey(id)) return;
      index[id] = ids.length;
      ids.add(id);
      names.add(name);
      lats.add(lat);
      lngs.add(lng);
    }

    for (final s in stops) {
      add(s.code, s.name, s.lat, s.lng);
    }
    for (final s in stations) {
      add('mrt:${s.name}', s.name, s.lat, s.lng);
    }

    final patterns = <_Pattern>[];
    routes.routes.forEach((key, list) {
      final nodes = [for (final (code, _) in list) if (index[code] case final i?) i];
      if (nodes.length >= 2) patterns.add(_Pattern(LegKind.bus, key.split('|').first, key, nodes));
    });
    for (final (prefix, line) in _mrtLines(stations)) {
      final nodes = [for (final s in line) index['mrt:${s.name}']!];
      final service = lineOfCode(prefix) ?? prefix;
      patterns.add(_Pattern(LegKind.mrt, service, '$prefix|1', nodes));
      patterns.add(_Pattern(LegKind.mrt, service, '$prefix|2', nodes.reversed.toList()));
    }

    final at = [for (var i = 0; i < ids.length; i++) <(int, int)>[]];
    for (var p = 0; p < patterns.length; p++) {
      final nodes = patterns[p].nodes;
      for (var k = 0; k < nodes.length; k++) {
        at[nodes[k]].add((p, k));
      }
    }

    // Walk links: grid cells about as wide as the longest walk, then the 3x3 cells around.
    const cell = 0.00225; // ~250 m of latitude
    final grid = <(int, int), List<int>>{};
    (int, int) key(int i) => ((lats[i] / cell).floor(), (lngs[i] / cell).floor());
    for (var i = 0; i < ids.length; i++) {
      grid.putIfAbsent(key(i), () => []).add(i);
    }
    final walks = [for (var i = 0; i < ids.length; i++) <(int, double)>[]];
    for (var i = 0; i < ids.length; i++) {
      final (r, c) = key(i);
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          for (final j in grid[(r + dr, c + dc)] ?? const <int>[]) {
            if (j == i) continue;
            final d = distanceMeters(lats[i], lngs[i], lats[j], lngs[j]);
            if (d <= transferWalkMetres) walks[i].add((j, d));
          }
        }
      }
    }
    return TransitNet._(ids, names, lats, lngs, index, patterns, at, walks);
  }

  /// The stations next to [node] on lines with code [prefix] ("TE"), both directions.
  List<String> mrtNext(String node, String prefix) {
    final i = _index[node];
    if (i == null) return const [];
    return [
      for (final (p, k) in _at[i])
        if (_patterns[p].kind == LegKind.mrt &&
            _patterns[p].routeKey.split('|').first == prefix &&
            k + 1 < _patterns[p].nodes.length)
          _ids[_patterns[p].nodes[k + 1]],
    ];
  }

  /// Nodes within [transferWalkMetres] of [node], with the distance.
  List<(String, double)> walkLinks(String node) {
    final i = _index[node];
    if (i == null) return const [];
    return [for (final (j, d) in _walks[i]) (_ids[j], d)];
  }
}

/// MRT and LRT lines as station lists in travel order, one per code prefix. Stations are sorted
/// by the number in their code; short extensions join their trunk station (CE from Promenade,
/// CG from Tanah Merah), loops close on their hub (BP back to Bukit Panjang, the Sengkang and
/// Punggol LRT loops start and end at their hub).
List<(String, List<MrtStation>)> _mrtLines(List<MrtStation> stations) {
  final byCode = <String, MrtStation>{};
  final byPrefix = <String, List<(int, MrtStation)>>{};
  for (final s in stations) {
    for (final c in s.codes) {
      byCode[c] = s;
      final m = RegExp(r'^([A-Z]+)(\d+)').firstMatch(c);
      if (m == null) continue;
      byPrefix.putIfAbsent(m.group(1)!, () => []).add((int.parse(m.group(2)!), s));
    }
  }
  const joinAtStart = {'CE': 'CC4', 'CG': 'EW4', 'SE': 'STC', 'SW': 'STC', 'PE': 'PTC', 'PW': 'PTC'};
  const joinAtEnd = {'BP': 'BP6', 'SE': 'STC', 'SW': 'STC', 'PE': 'PTC', 'PW': 'PTC'};
  final out = <(String, List<MrtStation>)>[];
  byPrefix.forEach((prefix, list) {
    list.sort((a, b) => a.$1.compareTo(b.$1));
    final line = [for (final (_, s) in list) s];
    if (byCode[joinAtStart[prefix]] case final s?) line.insert(0, s);
    if (byCode[joinAtEnd[prefix]] case final s?) line.add(s);
    if (line.length >= 2) out.add((prefix, line));
  });
  return out;
}
