/// Plain data types. No Flutter imports so they are usable in background isolates.
library;

/// `other` is a custom favourite place with its own name (Favorites.extraPlaces).
enum PlaceKind { home, work, school, other }

extension PlaceKindLabel on PlaceKind {
  /// Indonesian label, kept for older call sites. Prefer S.placeLabel(kind.name).
  String get label => switch (this) {
        PlaceKind.home => 'Rumah',
        PlaceKind.work => 'Kantor',
        PlaceKind.school => 'Sekolah',
        PlaceKind.other => 'Tempat',
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

/// How someone usually travels to a place.
enum TravelMode { transit, car, motorcycle, bicycle, taxi }

TravelMode travelModeFrom(String v) =>
    TravelMode.values.firstWhere((m) => m.name == v, orElse: () => TravelMode.transit);

/// When a custom place is usually visited.
enum PlaceWhen { anytime, weekdays, weekends }

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
    this.name,
    this.modes = const [TravelMode.transit],
    this.when = PlaceWhen.anytime,
    this.days = const {1, 2, 3, 4, 5},
    this.go,
    this.back,
  });

  /// Work/school days for this place (1 = Monday … 7 = Sunday).
  final Set<int> days;

  /// Usual time to leave home for this place, and to leave it again.
  final TimeOfDayHM? go;
  final TimeOfDayHM? back;

  final PlaceKind kind;

  /// How the user usually gets here; the first one is the default for the trip card.
  final List<TravelMode> modes;
  TravelMode get mode => modes.isEmpty ? TravelMode.transit : modes.first;

  /// For custom places: when it is usually visited.
  final PlaceWhen when;

  /// User's own name for a custom place, e.g. "Mum's house".
  final String? name;
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

  /// The same place at a new address; routines (modes, days, times) are kept.
  Place withAddress({
    required String address,
    String? postal,
    required double lat,
    required double lng,
    required List<BusStop> stops,
  }) =>
      Place(
        kind: kind,
        stops: stops,
        address: address,
        postal: postal,
        addrLat: lat,
        addrLng: lng,
        name: name,
        modes: modes,
        when: when,
        days: days,
        go: go,
        back: back,
      );

  Place copyWith({
    List<BusStop>? stops,
    String? name,
    List<TravelMode>? modes,
    PlaceWhen? when,
    Set<int>? days,
    TimeOfDayHM? go,
    TimeOfDayHM? back,
  }) =>
      Place(
        kind: kind,
        days: days ?? this.days,
        go: go ?? this.go,
        back: back ?? this.back,
        name: name ?? this.name,
        modes: modes ?? this.modes,
        when: when ?? this.when,
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
        if (name != null) 'name': name,
        'modes': [for (final m in modes) m.name],
        if (when != PlaceWhen.anytime) 'when': when.name,
        'days': days.toList()..sort(),
        if (go != null) 'go': go.toString(),
        if (back != null) 'back': back.toString(),
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
        name: j['name'] as String?,
        modes: j['modes'] is List && (j['modes'] as List).isNotEmpty
            ? [for (final m in j['modes'] as List) travelModeFrom('$m')]
            : const [TravelMode.transit],
        when: PlaceWhen.values.firstWhere((w) => w.name == j['when'], orElse: () => PlaceWhen.anytime),
        days: j['days'] is List ? {for (final d in j['days'] as List) (d as num).toInt()} : const {1, 2, 3, 4, 5},
        go: j['go'] == null ? null : TimeOfDayHM.parse('${j['go']}'),
        back: j['back'] == null ? null : TimeOfDayHM.parse('${j['back']}'),
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
    this.learnHabits = true,
    this.digestAlerts = true,
    this.leaveAlerts = true,
    this.onboarded = false,
    this.showPrayer = false,
    this.showHalal = false,
    this.hawkers = const {},
    this.carparks = const {},
    this.watchedBlocks = const {},
    this.compareBlocks = const [],
    this.extraPlaces = const [],
    this.workDays = const {1, 2, 3, 4, 5},
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

  /// Keep trip times and meals the user logs (on this phone only) for insights.
  final bool learnHabits;

  /// Weekly "This week around you" notification on Sunday evening.
  final bool digestAlerts;

  /// Leave-by reminder before the usual departure.
  final bool leaveAlerts;

  /// True after the user finished the first-run setup.
  final bool onboarded;

  /// Show MUIS prayer times in Nearby (opt-in, off by default).
  final bool showPrayer;

  /// Show halal places (Muslim.sg listings) in Nearby and Home (opt-in).
  final bool showHalal;

  /// Favourite hawker centre ids (hawkers.json "id").
  final Set<String> hawkers;

  /// Saved HDB car park numbers (carparks.json "id").
  final Set<String> carparks;

  /// Watched HDB blocks: "BLOCK|STREET" -> resale transactions seen so far.
  final Map<String, int> watchedBlocks;

  /// Blocks picked for side-by-side comparison (max 3).
  final List<String> compareBlocks;

  /// Custom favourite places (kind `other`), max [maxExtraPlaces].
  final List<Place> extraPlaces;
  static const maxExtraPlaces = 5;

  /// Weekdays (1 = Monday … 7 = Sunday) the user goes to work or school.
  final Set<int> workDays;

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
    bool? learnHabits,
    bool? digestAlerts,
    bool? leaveAlerts,
    bool? onboarded,
    bool? showPrayer,
    bool? showHalal,
    Set<String>? hawkers,
    Set<String>? carparks,
    Map<String, int>? watchedBlocks,
    List<String>? compareBlocks,
    List<Place>? extraPlaces,
    Set<int>? workDays,
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
        learnHabits: learnHabits ?? this.learnHabits,
        digestAlerts: digestAlerts ?? this.digestAlerts,
        leaveAlerts: leaveAlerts ?? this.leaveAlerts,
        onboarded: onboarded ?? this.onboarded,
        showPrayer: showPrayer ?? this.showPrayer,
        showHalal: showHalal ?? this.showHalal,
        hawkers: hawkers ?? this.hawkers,
        carparks: carparks ?? this.carparks,
        watchedBlocks: watchedBlocks ?? this.watchedBlocks,
        compareBlocks: compareBlocks ?? this.compareBlocks,
        extraPlaces: extraPlaces ?? this.extraPlaces,
        workDays: workDays ?? this.workDays,
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
        'learnHabits': learnHabits,
        'digestAlerts': digestAlerts,
        'leaveAlerts': leaveAlerts,
        'onboarded': onboarded,
        'showPrayer': showPrayer,
        'showHalal': showHalal,
        'hawkers': hawkers.toList()..sort(),
        'carparks': carparks.toList()..sort(),
        'watchedBlocks': watchedBlocks,
        'compareBlocks': compareBlocks,
        if (extraPlaces.isNotEmpty) 'extra': [for (final p in extraPlaces) p.toJson()],
        'workDays': workDays.toList()..sort(),
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
      learnHabits: (j['learnHabits'] ?? true) as bool,
      digestAlerts: (j['digestAlerts'] ?? true) as bool,
      leaveAlerts: (j['leaveAlerts'] ?? true) as bool,
      onboarded: (j['onboarded'] ?? false) as bool,
      showPrayer: (j['showPrayer'] ?? false) as bool,
      showHalal: (j['showHalal'] ?? false) as bool,
      hawkers: strings('hawkers'),
      carparks: strings('carparks'),
      watchedBlocks: {
        for (final e in ((j['watchedBlocks'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt(),
      },
      compareBlocks: [for (final v in (j['compareBlocks'] as List? ?? const [])) '$v'],
      extraPlaces: [
        for (final p in (j['extra'] as List? ?? const [])) Place.fromJson(p as Map<String, dynamic>),
      ],
      workDays: j['workDays'] is List
          ? {for (final d in j['workDays'] as List) (d as num).toInt()}
          : const {1, 2, 3, 4, 5},
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
