/// Plain data types. No Flutter imports so they are usable in background isolates.
library;

enum PlaceKind { home, work, school }

extension PlaceKindLabel on PlaceKind {
  /// Indonesian label, kept for older call sites. Prefer S.placeLabel(kind.name).
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

/// One OneMap search result.
class AddressHit {
  const AddressHit({
    required this.label,
    required this.block,
    required this.road,
    required this.building,
    required this.postal,
    required this.lat,
    required this.lng,
  });

  final String label;
  final String block;
  final String road;
  final String building;
  final String postal;
  final double lat;
  final double lng;
}

/// A saved place: an address (from OneMap or the phone's location) and/or up to two
/// bus stops. Its location is the address when set, otherwise the first stop, so users
/// can set Work without being at the office. Stored only on the device.
class Place {
  const Place({
    required this.kind,
    this.stops = const [],
    this.address,
    this.postal,
    this.addrLat,
    this.addrLng,
  });

  final PlaceKind kind;
  final List<BusStop> stops;

  /// Short address label, e.g. "66 Marine Drive".
  final String? address;
  final String? postal;
  final double? addrLat;
  final double? addrLng;

  bool get hasAddress => addrLat != null && addrLng != null;
  double get lat => addrLat ?? stops.first.lat;
  double get lng => addrLng ?? stops.first.lng;

  /// What to show for this place: the address, else the first stop's name.
  String get label => address ?? (stops.isEmpty ? '' : stops.first.name);

  Place copyWith({List<BusStop>? stops}) => Place(
        kind: kind,
        stops: stops ?? this.stops,
        address: address,
        postal: postal,
        addrLat: addrLat,
        addrLng: addrLng,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'stops': [for (final s in stops) s.toJson()],
        if (address != null) 'addr': address,
        if (postal != null) 'postal': postal,
        if (addrLat != null) 'la': addrLat,
        if (addrLng != null) 'lo': addrLng,
      };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        kind: PlaceKind.values.byName(j['kind'] as String),
        stops: [
          for (final s in (j['stops'] as List? ?? const [])) BusStop.fromBundle(s as Map<String, dynamic>),
        ],
        address: j['addr'] as String?,
        postal: j['postal'] as String?,
        addrLat: (j['la'] as num?)?.toDouble(),
        addrLng: (j['lo'] as num?)?.toDouble(),
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
    this.hawkerAlerts = true,
    this.dengueAlerts = true,
    this.heatAlerts = true,
    this.homesAlerts = true,
    this.onboarded = false,
    this.lang,
    this.hawkers = const {},
    this.carparks = const {},
    this.watchedBlocks = const {},
    this.compareBlocks = const [],
  });

  final Map<PlaceKind, Place> places;
  final Set<String> lines;
  final TimeOfDayHM leaveHome;
  final TimeOfDayHM leaveWork;
  final bool mrtAlerts;
  final bool rainAlerts;
  final bool hawkerAlerts;
  final bool dengueAlerts;
  final bool heatAlerts;
  final bool homesAlerts;

  /// True after the user finished the first-run setup.
  final bool onboarded;

  /// "en" or "id"; null follows the phone's language.
  final String? lang;

  /// Favourite hawker centre ids (hawkers.json "id").
  final Set<String> hawkers;

  /// Saved HDB car park numbers (carparks.json "id").
  final Set<String> carparks;

  /// Watched HDB blocks: "BLOCK|STREET" -> resale transactions seen so far.
  final Map<String, int> watchedBlocks;

  /// Blocks picked for side-by-side comparison (max 3).
  final List<String> compareBlocks;

  bool get isSetUp => places.containsKey(PlaceKind.home);

  Favorites copyWith({
    Map<PlaceKind, Place>? places,
    Set<String>? lines,
    TimeOfDayHM? leaveHome,
    TimeOfDayHM? leaveWork,
    bool? mrtAlerts,
    bool? rainAlerts,
    bool? hawkerAlerts,
    bool? dengueAlerts,
    bool? heatAlerts,
    bool? homesAlerts,
    bool? onboarded,
    String? lang,
    Set<String>? hawkers,
    Set<String>? carparks,
    Map<String, int>? watchedBlocks,
    List<String>? compareBlocks,
  }) =>
      Favorites(
        places: places ?? this.places,
        lines: lines ?? this.lines,
        leaveHome: leaveHome ?? this.leaveHome,
        leaveWork: leaveWork ?? this.leaveWork,
        mrtAlerts: mrtAlerts ?? this.mrtAlerts,
        rainAlerts: rainAlerts ?? this.rainAlerts,
        hawkerAlerts: hawkerAlerts ?? this.hawkerAlerts,
        dengueAlerts: dengueAlerts ?? this.dengueAlerts,
        heatAlerts: heatAlerts ?? this.heatAlerts,
        homesAlerts: homesAlerts ?? this.homesAlerts,
        onboarded: onboarded ?? this.onboarded,
        lang: lang ?? this.lang,
        hawkers: hawkers ?? this.hawkers,
        carparks: carparks ?? this.carparks,
        watchedBlocks: watchedBlocks ?? this.watchedBlocks,
        compareBlocks: compareBlocks ?? this.compareBlocks,
      );

  Map<String, dynamic> toJson() => {
        'places': [for (final p in places.values) p.toJson()],
        'lines': lines.toList()..sort(),
        'leaveHome': leaveHome.toString(),
        'leaveWork': leaveWork.toString(),
        'mrtAlerts': mrtAlerts,
        'rainAlerts': rainAlerts,
        'hawkerAlerts': hawkerAlerts,
        'dengueAlerts': dengueAlerts,
        'heatAlerts': heatAlerts,
        'homesAlerts': homesAlerts,
        'onboarded': onboarded,
        if (lang != null) 'lang': lang,
        'hawkers': hawkers.toList()..sort(),
        'carparks': carparks.toList()..sort(),
        'watchedBlocks': watchedBlocks,
        'compareBlocks': compareBlocks,
      };

  factory Favorites.fromJson(Map<String, dynamic> j) {
    final places = <PlaceKind, Place>{};
    for (final p in (j['places'] as List? ?? const [])) {
      final place = Place.fromJson(p as Map<String, dynamic>);
      places[place.kind] = place;
    }
    Set<String> strings(String k) => {for (final v in (j[k] as List? ?? const [])) '$v'};
    return Favorites(
      places: places,
      lines: strings('lines'),
      leaveHome: TimeOfDayHM.parse((j['leaveHome'] ?? '7:30') as String),
      leaveWork: TimeOfDayHM.parse((j['leaveWork'] ?? '18:0') as String),
      mrtAlerts: (j['mrtAlerts'] ?? true) as bool,
      rainAlerts: (j['rainAlerts'] ?? true) as bool,
      hawkerAlerts: (j['hawkerAlerts'] ?? true) as bool,
      dengueAlerts: (j['dengueAlerts'] ?? true) as bool,
      heatAlerts: (j['heatAlerts'] ?? true) as bool,
      homesAlerts: (j['homesAlerts'] ?? true) as bool,
      onboarded: (j['onboarded'] ?? false) as bool,
      lang: j['lang'] as String?,
      hawkers: strings('hawkers'),
      carparks: strings('carparks'),
      watchedBlocks: {
        for (final e in ((j['watchedBlocks'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt(),
      },
      compareBlocks: [for (final v in (j['compareBlocks'] as List? ?? const [])) '$v'],
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
