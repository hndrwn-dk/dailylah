// Bus, MRT and walking options between two places, worked out on the phone from the bundles
// (bus stops, bus routes, MRT stations). Pure Dart: no Flutter, no I/O, nothing sent anywhere.
import 'data.dart';
import 'logic.dart';
import 'models.dart';

/// Longest walk between two stops or stations for a change.
const transferWalkMetres = 250.0;

enum LegKind { walk, bus, mrt }

/// Services that run only at peak hours or at night (express "e", City Direct 650-699,
/// NightRider, Nite): the routes bundle has no hours, so options never rely on them.
bool peakOnlyService(String service) => RegExp(r'^(6[5-9]\d|\d+e|NR\d+|\d+N)$').hasMatch(service);

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
      if (nodes.length >= 2 && !peakOnlyService(key.split('|').first)) patterns.add(_Pattern(LegKind.bus, key.split('|').first, key, nodes));
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

// ---------------------------------------------------------------- the search

/// Waits before a ride, in minutes: the first bus (until live arrivals replace it), a later
/// bus after a change, an MRT train. A change between MRT lines at one station costs
/// [rideTransferMinutes] instead.
const firstBusWaitMinutes = 5;
const busChangeWaitMinutes = 6;
const mrtWaitMinutes = 3;

/// Most rides in one option (two changes).
const transitMaxRides = 3;

/// An option this much slower than the fastest one is left out.
const transitSlackMinutes = 40;

const _startBusMetres = 500.0, _endBusMetres = 400.0, _stationMetres = 1200.0;
const _never = 1 << 30;

/// Up to [max] door-to-door options from [from] to [to], fastest first, each with a different
/// sequence of services. Empty when the two are the same place or the bundles are missing.
List<TransitOption> transitOptions(TransitNet net, Place from, Place to, {int max = 3}) =>
    net._options(from, to, max);

extension on TransitNet {
  bool _isStation(int n) => _ids[n].startsWith('mrt:');

  List<TransitOption> _options(Place from, Place to, int max) {
    if (isEmpty || distanceMeters(from.lat, from.lng, to.lat, to.lng) <= samePlaceMetres) return const [];
    // Three searches, so the answers differ: everything, buses only, and starting by train.
    final all = [
      ..._search(from, to, max * 4),
      ..._search(from, to, max * 4, mrt: false),
      ..._search(from, to, max * 4, startByTrain: true),
    ]..sort((a, b) {
        final m = a.minutes.compareTo(b.minutes);
        if (m != 0) return m;
        final c = a.changes.compareTo(b.changes);
        return c != 0 ? c : a.walkMetres.compareTo(b.walkMetres);
      });
    // Keep options that start with a different ride: what to board first is the choice.
    final out = <TransitOption>[];
    final firsts = <String>{};
    for (final o in all) {
      if (out.isNotEmpty && o.minutes > out.first.minutes + transitSlackMinutes) break;
      if (_roundabout(o, from, to)) continue;
      if (!firsts.add('${o.rides.first.kind.name}:${o.rides.first.service}')) continue;
      out.add(o);
      if (out.length == max) break;
    }
    return out;
  }

  /// True when a later ride boards where walking from the start would get to no later, or an
  /// earlier ride gets off where walking to the end would arrive no later: such an option goes
  /// the long way round. A feeder bus to a station 1 km away is quicker than the walk, so it stays.
  bool _roundabout(TransitOption o, Place from, Place to) {
    int? walkFrom(String id, Place p, double busMetres) {
      final x = _index[id];
      if (x == null) return null;
      final d = distanceMeters(p.lat, p.lng, _lats[x], _lngs[x]);
      return d <= (_isStation(x) ? _stationMetres : busMetres) ? walkMinutesTo(d) : null;
    }

    final legs = o.legs;
    var before = 0;
    var rideIndex = 0;
    final last = o.rides.length - 1;
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      if (leg.isRide) {
        if (rideIndex > 0) {
          final walk = walkFrom(leg.from, from, _startBusMetres);
          if (walk != null && walk <= before) return true;
        }
        if (rideIndex < last) {
          final after = legs.skip(i + 1).fold(0, (sum, l) => sum + l.minutes);
          final walk = walkFrom(leg.to, to, _endBusMetres);
          if (walk != null && walk <= after) return true;
        }
        rideIndex++;
      }
      before += leg.minutes;
    }
    return false;
  }

  List<TransitOption> _search(Place from, Place to, int max, {bool mrt = true, bool startByTrain = false}) {
    final n = nodeCount;
    // arr[k][x]: best minutes at x after k rides (a walk after the last ride allowed);
    // ride[k][x]: the same, ending on the ride itself.
    final arr = [for (var k = 0; k <= transitMaxRides; k++) List.filled(n, _never)];
    final ride = [for (var k = 0; k <= transitMaxRides; k++) List.filled(n, _never)];
    final rideFrom = [for (var k = 0; k <= transitMaxRides; k++) <int, (int, int, int)>{}]; // x -> (pattern, board, alight)
    final walkFrom = [for (var k = 0; k <= transitMaxRides; k++) <int, (int, double)>{}]; // x -> (node, metres)
    final access = <int, double>{};
    final egress = <int, double>{};
    for (var x = 0; x < n; x++) {
      final station = _isStation(x);
      final dFrom = distanceMeters(from.lat, from.lng, _lats[x], _lngs[x]);
      if (dFrom <= (station ? _stationMetres : _startBusMetres) && (station ? mrt : !startByTrain)) {
        access[x] = dFrom;
        arr[0][x] = walkMinutesTo(dFrom);
      }
      final dTo = distanceMeters(to.lat, to.lng, _lats[x], _lngs[x]);
      if (dTo <= (station ? _stationMetres : _endBusMetres)) egress[x] = dTo;
    }
    if (access.isEmpty || egress.isEmpty) return const [];

    for (var k = 1; k <= transitMaxRides; k++) {
      final prev = arr[k - 1];
      final touched = <int>{
        for (var x = 0; x < n; x++)
          if (prev[x] < _never)
            for (final (p, _) in _at[x])
              if (mrt || _patterns[p].kind == LegKind.bus) p,
      };
      int wait(int p, int x) {
        final pat = _patterns[p];
        if (pat.kind == LegKind.bus) return k == 1 ? firstBusWaitMinutes : busChangeWaitMinutes;
        final came = k > 1 && !walkFrom[k - 1].containsKey(x) ? rideFrom[k - 1][x] : null;
        return came != null && _patterns[came.$1].kind == LegKind.mrt ? rideTransferMinutes : mrtWaitMinutes;
      }

      for (final p in touched) {
        final pat = _patterns[p];
        final per = pat.kind == LegKind.bus ? feederMinutesPerStop : rideMinutesPerStop;
        int? board;
        var boardAt = 0;
        for (var j = 0; j < pat.nodes.length; j++) {
          final x = pat.nodes[j];
          if (board != null) {
            final t = boardAt + per * (j - board);
            if (t < ride[k][x]) {
              ride[k][x] = t;
              rideFrom[k][x] = (p, board, j);
            }
          }
          if (prev[x] < _never) {
            final t = prev[x] + wait(p, x);
            if (board == null || t <= boardAt + per * (j - board)) {
              board = j;
              boardAt = t;
            }
          }
        }
      }
      for (var x = 0; x < n; x++) {
        if (ride[k][x] < arr[k][x]) arr[k][x] = ride[k][x];
      }
      for (var x = 0; x < n; x++) {
        if (ride[k][x] == _never) continue;
        for (final (y, d) in _walks[x]) {
          final t = ride[k][x] + walkMinutesTo(d);
          if (t < arr[k][y]) {
            arr[k][y] = t;
            walkFrom[k][y] = (x, d);
          }
        }
      }
    }

    final candidates = <(int, int, int)>[]; // (minutes, rides, end node)
    for (var k = 1; k <= transitMaxRides; k++) {
      egress.forEach((x, d) {
        if (ride[k][x] < _never) candidates.add((ride[k][x] + walkMinutesTo(d), k, x));
      });
    }
    candidates.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    final built = <TransitOption>[];
    final seen = <String>{};
    for (final (minutes, k, x) in candidates) {
      if (built.isNotEmpty && minutes > built.first.minutes + transitSlackMinutes) break;
      final option = _rebuild(k, x, egress[x]!, access, rideFrom, walkFrom, ride, arr);
      if (option == null || !seen.add(option.signature)) continue;
      built.add(option);
      if (built.length >= max) break;
    }
    return built;
  }

  TransitOption? _rebuild(
    int rides,
    int end,
    double endMetres,
    Map<int, double> access,
    List<Map<int, (int, int, int)>> rideFrom,
    List<Map<int, (int, double)>> walkFrom,
    List<List<int>> ride,
    List<List<int>> arr,
  ) {
    final legs = <TransitLeg>[
      TransitLeg(
          kind: LegKind.walk,
          from: _ids[end],
          to: '',
          fromName: _names[end],
          toName: '',
          minutes: walkMinutesTo(endMetres),
          metres: endMetres),
    ];
    var x = end;
    var t = ride[rides][end];
    for (var k = rides; k >= 1; k--) {
      final r = rideFrom[k][x];
      if (r == null) return null;
      final (p, b, a) = r;
      final pat = _patterns[p];
      final boardNode = pat.nodes[b];
      final before = arr[k - 1][boardNode];
      legs.add(TransitLeg(
        kind: pat.kind,
        from: _ids[boardNode],
        to: _ids[x],
        fromName: _names[boardNode],
        toName: _names[x],
        service: pat.service,
        stops: a - b,
        minutes: t - before,
        routeKey: pat.routeKey,
      ));
      x = boardNode;
      t = before;
      if (k - 1 == 0) break;
      final w = walkFrom[k - 1][x];
      if (w != null) {
        final (y, d) = w;
        final atY = ride[k - 1][y];
        legs.add(TransitLeg(
            kind: LegKind.walk,
            from: _ids[y],
            to: _ids[x],
            fromName: _names[y],
            toName: _names[x],
            minutes: t - atY,
            metres: d));
        x = y;
        t = atY;
      }
    }
    final d = access[x];
    if (d == null) return null;
    legs.add(TransitLeg(
        kind: LegKind.walk, from: '', to: _ids[x], fromName: '', toName: _names[x], minutes: t, metres: d));
    return TransitOption(legs.reversed.toList());
  }
}

/// The steps of [o] to keep with the running trip: one per leg, in order.
List<TripStep> stepsOf(TransitOption o) => [
      for (final l in o.legs)
        TripStep(
          kind: switch (l.kind) {
            LegKind.walk => StepKind.walk,
            LegKind.bus => StepKind.bus,
            LegKind.mrt => StepKind.mrt,
          },
          from: l.from,
          to: l.to,
          fromName: l.fromName,
          toName: l.toName,
          service: l.service,
          stops: l.stops,
          minutes: l.minutes,
          metres: l.metres,
          routeKey: l.routeKey,
        ),
    ];

/// While walking to the first ride of what is left of a trip with changes, or waiting for it:
/// a way from [options] that ends at least [betterWayMinutes] sooner than the rest of the plan
/// (estimates) and rides something else. Null on a ride, on the last walk, or when none is.
TransitOption? betterWay(List<TripStep> steps, int i, List<TransitOption> options) {
  if (i < 0 || i >= steps.length || steps[i].kind != StepKind.walk) return null;
  if (nextRideIndex(steps, i) == null) return null;
  final left = remainingMinutes(steps, i);
  final mine = [for (final st in steps.skip(i)) if (st.isRide) st.service].join('>');
  for (final o in [...options]..sort((a, b) => a.minutes.compareTo(b.minutes))) {
    if (o.signature == mine) continue;
    if (o.minutes <= left - betterWayMinutes) return o;
  }
  return null;
}
