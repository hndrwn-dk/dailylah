/// Plain data types. No Flutter imports so they are usable in background isolates.
library;

enum PlaceKind { home, work, school }

extension PlaceKindLabel on PlaceKind {
  String get label => switch (this) {
        PlaceKind.home => 'Rumah',
        PlaceKind.work => 'Kantor',
        PlaceKind.school => 'Sekolah',
      };
}

class BusStop {
  const BusStop({
    required this.code,
    required this.name,
    required this.road,
    required this.lat,
    required this.lng,
  });

  final String code;
  final String name;
  final String road;
  final double lat;
  final double lng;

  /// Compact bundle format from web/data/bus_stops.json: {c, n, r, la, lo}.
  factory BusStop.fromBundle(Map<String, dynamic> j) => BusStop(
        code: j['c'] as String,
        name: j['n'] as String,
        road: (j['r'] ?? '') as String,
        lat: (j['la'] as num).toDouble(),
        lng: (j['lo'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'c': code, 'n': name, 'r': road, 'la': lat, 'lo': lng};
}

/// A saved place. Its location is the location of its main bus stop, so users can
/// set "Kantor" without being at the office. Stored only on the device.
class Place {
  const Place({required this.kind, required this.stops});

  final PlaceKind kind;
  final List<BusStop> stops;

  double get lat => stops.first.lat;
  double get lng => stops.first.lng;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'stops': [for (final s in stops) s.toJson()],
      };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        kind: PlaceKind.values.byName(j['kind'] as String),
        stops: [
          for (final s in (j['stops'] as List)) BusStop.fromBundle(s as Map<String, dynamic>),
        ],
      );
}

/// Simple HH:MM time of day.
class TimeOfDayHM {
  const TimeOfDayHM(this.hour, this.minute);
  final int hour;
  final int minute;

  int get minutes => hour * 60 + minute;

  String format() => '${hour.toString().padLeft(2, '0')}.${minute.toString().padLeft(2, '0')}';

  @override
  String toString() => '$hour:$minute';

  static TimeOfDayHM parse(String s) {
    final p = s.split(':');
    return TimeOfDayHM(int.parse(p[0]), int.parse(p[1]));
  }
}

class Favorites {
  const Favorites({
    this.places = const {},
    this.lines = const {},
    this.leaveHome = const TimeOfDayHM(7, 30),
    this.leaveWork = const TimeOfDayHM(18, 0),
    this.mrtAlerts = true,
    this.rainAlerts = true,
    this.onboarded = false,
  });

  final Map<PlaceKind, Place> places;
  final Set<String> lines;
  final TimeOfDayHM leaveHome;
  final TimeOfDayHM leaveWork;
  final bool mrtAlerts;
  final bool rainAlerts;

  /// True after the user finished the first-run setup.
  final bool onboarded;

  bool get isSetUp => places.containsKey(PlaceKind.home);

  Favorites copyWith({
    Map<PlaceKind, Place>? places,
    Set<String>? lines,
    TimeOfDayHM? leaveHome,
    TimeOfDayHM? leaveWork,
    bool? mrtAlerts,
    bool? rainAlerts,
    bool? onboarded,
  }) =>
      Favorites(
        places: places ?? this.places,
        lines: lines ?? this.lines,
        leaveHome: leaveHome ?? this.leaveHome,
        leaveWork: leaveWork ?? this.leaveWork,
        mrtAlerts: mrtAlerts ?? this.mrtAlerts,
        rainAlerts: rainAlerts ?? this.rainAlerts,
        onboarded: onboarded ?? this.onboarded,
      );

  Map<String, dynamic> toJson() => {
        'places': [for (final p in places.values) p.toJson()],
        'lines': lines.toList()..sort(),
        'leaveHome': leaveHome.toString(),
        'leaveWork': leaveWork.toString(),
        'mrtAlerts': mrtAlerts,
        'rainAlerts': rainAlerts,
        'onboarded': onboarded,
      };

  factory Favorites.fromJson(Map<String, dynamic> j) {
    final places = <PlaceKind, Place>{};
    for (final p in (j['places'] as List? ?? const [])) {
      final place = Place.fromJson(p as Map<String, dynamic>);
      places[place.kind] = place;
    }
    return Favorites(
      places: places,
      lines: {for (final l in (j['lines'] as List? ?? const [])) l as String},
      leaveHome: TimeOfDayHM.parse((j['leaveHome'] ?? '7:30') as String),
      leaveWork: TimeOfDayHM.parse((j['leaveWork'] ?? '18:0') as String),
      mrtAlerts: (j['mrtAlerts'] ?? true) as bool,
      rainAlerts: (j['rainAlerts'] ?? true) as bool,
      onboarded: (j['onboarded'] ?? false) as bool,
    );
  }
}

/// One upcoming bus for a service at a stop.
class BusEta {
  const BusEta({required this.service, required this.minutes, required this.load});
  final String service;
  final int minutes;

  /// LTA load code: SEA (seats), SDA (standing), LSD (limited standing).
  final String load;
}

/// MRT/LRT lines. Codes match LTA DataMall TrainLine / AffectedSegments.Line.
const trainLines = <String, String>{
  'NSL': 'North-South',
  'EWL': 'East-West',
  'CCL': 'Circle',
  'DTL': 'Downtown',
  'NEL': 'North East',
  'TEL': 'Thomson-East Coast',
  'BPL': 'Bukit Panjang LRT',
  'SLRT': 'Sengkang LRT',
  'PLRT': 'Punggol LRT',
};
