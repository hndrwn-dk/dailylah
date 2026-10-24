/// Types for the static bundles in web/data/ (built daily by backend/app/build_static.py).
/// Pure Dart: usable from the background isolate.
library;

double _d(Object? v) => (v as num).toDouble();

class Closure {
  const Closure(this.from, this.to, this.reason);
  final DateTime from; // inclusive, local date
  final DateTime to; // inclusive, local date
  final String reason;

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }
}

class Hawker {
  const Hawker({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.closures = const [],
  });

  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final List<Closure> closures;

  /// {"id","n","a","la","lo","c":[["2026-10-12","2026-10-15","Cleaning"]]}
  factory Hawker.fromBundle(Map<String, dynamic> j) => Hawker(
        id: '${j['id']}',
        name: '${j['n']}',
        address: '${j['a'] ?? ''}',
        lat: _d(j['la']),
        lng: _d(j['lo']),
        closures: [
          for (final c in (j['c'] as List? ?? const []))
            Closure(DateTime.parse('${c[0]}'), DateTime.parse('${c[1]}'), '${c.length > 2 ? c[2] : ''}'),
        ],
      );

  Closure? closureOn(DateTime day) {
    for (final c in closures) {
      if (c.covers(day)) return c;
    }
    return null;
  }

  Closure? nextClosure(DateTime today) {
    final d = DateTime(today.year, today.month, today.day);
    final upcoming = closures.where((c) => !c.to.isBefore(d)).toList()
      ..sort((a, b) => a.from.compareTo(b.from));
    return upcoming.isEmpty ? null : upcoming.first;
  }
}

class DengueCluster {
  const DengueCluster({
    required this.locality,
    required this.cases,
    required this.lat,
    required this.lng,
    required this.radius,
  });

  final String locality;
  final int cases;
  final double lat;
  final double lng;

  /// Approximate radius of the cluster area in metres.
  final double radius;

  /// {"loc","n","la","lo","r"}
  factory DengueCluster.fromBundle(Map<String, dynamic> j) => DengueCluster(
        locality: '${j['loc'] ?? ''}',
        cases: (j['n'] as num?)?.toInt() ?? 0,
        lat: _d(j['la']),
        lng: _d(j['lo']),
        radius: (j['r'] as num?)?.toDouble() ?? 150,
      );
}

/// A point of interest: MRT station, school, park, library, CC, sport facility, mosque.
class Poi {
  const Poi({required this.name, required this.lat, required this.lng, this.detail = ''});
  final String name;
  final double lat;
  final double lng;
  final String detail;

  /// {"n","la","lo","d"?}
  factory Poi.fromBundle(Map<String, dynamic> j) =>
      Poi(name: '${j['n']}', lat: _d(j['la']), lng: _d(j['lo']), detail: '${j['d'] ?? ''}');
}

enum PoiKind { mrt, primarySchool, school, preschool, park, library, cc, sport, mosque, supermarket }

class PoiSet {
  const PoiSet(this.byKind);
  final Map<PoiKind, List<Poi>> byKind;

  List<Poi> of(PoiKind k) => byKind[k] ?? const [];

  static const _keys = {
    PoiKind.mrt: 'mrt',
    PoiKind.primarySchool: 'primary',
    PoiKind.school: 'school',
    PoiKind.preschool: 'preschool',
    PoiKind.park: 'park',
    PoiKind.library: 'library',
    PoiKind.cc: 'cc',
    PoiKind.sport: 'sport',
    PoiKind.mosque: 'mosque',
    PoiKind.supermarket: 'supermarket',
  };

  factory PoiSet.fromBundle(Map<String, dynamic> j) => PoiSet({
        for (final e in _keys.entries)
          e.key: [for (final p in (j[e.value] as List? ?? const [])) Poi.fromBundle(p as Map<String, dynamic>)],
      });

  static const empty = PoiSet({});
}

class Carpark {
  const Carpark({
    required this.id,
    required this.address,
    required this.lat,
    required this.lng,
    this.type = '',
    this.freeParking = '',
    this.nightParking = '',
  });

  final String id;
  final String address;
  final double lat;
  final double lng;
  final String type;
  final String freeParking;
  final String nightParking;

  /// {"id","a","la","lo","t","f","n"}
  factory Carpark.fromBundle(Map<String, dynamic> j) => Carpark(
        id: '${j['id']}',
        address: '${j['a'] ?? ''}',
        lat: _d(j['la']),
        lng: _d(j['lo']),
        type: '${j['t'] ?? ''}',
        freeParking: '${j['f'] ?? ''}',
        nightParking: '${j['n'] ?? ''}',
      );
}

class HdbBlock {
  const HdbBlock({
    required this.block,
    required this.street,
    required this.town,
    required this.yearCompleted,
    required this.floors,
    required this.lat,
    required this.lng,
    this.postal = '',
  });

  final String block;
  final String street;
  final String postal;
  final String town;
  final int yearCompleted;
  final int floors;
  final double lat;
  final double lng;

  /// Same key format as hdb_resale.json: "BLOCK|STREET".
  String get key => '$block|$street';
  String get label => '$block $street';

  /// HDB flats have 99-year leases; lease start is roughly the completion year.
  int leaseLeft(int year) => (yearCompleted + 99 - year).clamp(0, 99);

  /// {"b","s","t","y","f","la","lo","p"}
  factory HdbBlock.fromBundle(Map<String, dynamic> j) => HdbBlock(
        block: '${j['b']}',
        street: '${j['s']}',
        town: '${j['t'] ?? ''}',
        yearCompleted: (j['y'] as num?)?.toInt() ?? 0,
        floors: (j['f'] as num?)?.toInt() ?? 0,
        lat: _d(j['la']),
        lng: _d(j['lo']),
      );
}

class ResaleStat {
  const ResaleStat({
    required this.flatType,
    required this.median,
    required this.count,
    required this.lastMonth,
    required this.lastPrice,
  });

  final String flatType;
  final int median;
  final int count;
  final String lastMonth;
  final int lastPrice;
}

class ResaleData {
  const ResaleData({required this.from, required this.to, required this.blocks, required this.towns});

  final String from;
  final String to;
  final Map<String, List<ResaleStat>> blocks;
  final Map<String, Map<String, int>> towns;

  /// {"from","to","blocks":{"KEY":{"4 ROOM":[median,count,"2026-08",price]}},"towns":{"BEDOK":{"4 ROOM":median}}}
  factory ResaleData.fromBundle(Map<String, dynamic> j) {
    final blocks = <String, List<ResaleStat>>{};
    (j['blocks'] as Map? ?? const {}).forEach((k, v) {
      final stats = <ResaleStat>[];
      (v as Map).forEach((ft, a) {
        final l = a as List;
        stats.add(ResaleStat(
          flatType: '$ft',
          median: (l[0] as num).toInt(),
          count: (l[1] as num).toInt(),
          lastMonth: '${l[2]}',
          lastPrice: (l[3] as num).toInt(),
        ));
      });
      stats.sort((a, b) => a.flatType.compareTo(b.flatType));
      blocks['$k'] = stats;
    });
    final towns = <String, Map<String, int>>{};
    (j['towns'] as Map? ?? const {}).forEach((t, v) {
      towns['$t'] = {for (final e in (v as Map).entries) '${e.key}': (e.value as num).toInt()};
    });
    return ResaleData(from: '${j['from'] ?? ''}', to: '${j['to'] ?? ''}', blocks: blocks, towns: towns);
  }

  int countFor(String key) => (blocks[key] ?? const []).fold(0, (s, r) => s + r.count);

  static const empty = ResaleData(from: '', to: '', blocks: {}, towns: {});
}

class RentData {
  const RentData({required this.period, required this.towns});
  final String period;
  final Map<String, Map<String, int>> towns;

  /// {"period","towns":{"BEDOK":{"4-RM":2800}}}
  factory RentData.fromBundle(Map<String, dynamic> j) {
    final towns = <String, Map<String, int>>{};
    (j['towns'] as Map? ?? const {}).forEach((t, v) {
      towns['$t'] = {for (final e in (v as Map).entries) '${e.key}': (e.value as num).toInt()};
    });
    return RentData(period: '${j['period'] ?? ''}', towns: towns);
  }

  static const empty = RentData(period: '', towns: {});
}

/// Six daily times: Subuh, Syuruk, Zohor, Asar, Maghrib, Isyak ("HH:MM", 24h).
class PrayerTimes {
  const PrayerTimes(this.days);
  final Map<String, List<String>> days;

  /// {"days":{"2026-10-20":["05:41","07:02","13:06","16:15","19:08","20:19"]}}
  factory PrayerTimes.fromBundle(Map<String, dynamic> j) => PrayerTimes({
        for (final e in (j['days'] as Map? ?? const {}).entries)
          '${e.key}': [for (final t in (e.value as List)) '$t'],
      });

  List<String>? on(String dayKey) => days[dayKey];

  static const empty = PrayerTimes({});
}


/// One emergency point: AED, A&E hospital, fire station, CHAS clinic or CD shelter.
/// {"n","la","lo","a"?,"d"?,"h"?,"t"?}
class EPoint {
  const EPoint({
    required this.name,
    required this.lat,
    required this.lng,
    this.address = '',
    this.detail = '',
    this.hours = '',
    this.tel = '',
  });

  final String name;
  final double lat;
  final double lng;
  final String address;
  final String detail;
  final String hours;
  final String tel;

  factory EPoint.fromBundle(Map<String, dynamic> j) => EPoint(
        name: cleanPlaceName('${j['n'] ?? ''}'),
        lat: _d(j['la']),
        lng: _d(j['lo']),
        address: '${j['a'] ?? ''}',
        detail: cleanDetail('${j['d'] ?? ''}'),
        hours: '${j['h'] ?? ''}',
        tel: '${j['t'] ?? ''}',
      );
}

/// Readable place names: ALL-CAPS names (CHAS clinics) in title case, and the long
/// "NEA Producer Responsibility Scheme - " prefix on e-waste points dropped.
String cleanPlaceName(String s) {
  var n = s.trim();
  const prefix = 'NEA Producer Responsibility Scheme - ';
  if (n.startsWith(prefix)) n = n.substring(prefix.length);
  final letters = n.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.length > 3 && letters == letters.toUpperCase()) {
    n = n
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
  return n;
}

/// Detail text without empty "; ;" parts left by the source data.
String cleanDetail(String s) =>
    s.split(';').map((x) => x.trim()).where((x) => x.isNotEmpty).join('; ');

/// Places a source marks as closed for now (e.g. "... (Temporarily Closed)").
bool isTemporarilyClosed(String name) => name.toLowerCase().contains('temporarily closed');

enum EmergencyKind { ae, aed, fire, clinic, shelter }

class EmergencySet {
  const EmergencySet(this.byKind);
  final Map<EmergencyKind, List<EPoint>> byKind;

  static const empty = EmergencySet({});
  List<EPoint> of(EmergencyKind k) => byKind[k] ?? const [];

  factory EmergencySet.fromBundle(Map<String, dynamic> j) => EmergencySet({
        for (final k in EmergencyKind.values)
          k: [for (final r in (j[k.name] as List? ?? const [])) EPoint.fromBundle(r as Map<String, dynamic>)],
      });
}


/// MRT/LRT station with its line codes, e.g. Promenade [CC4, DT15].
/// {"n","c":[codes],"la","lo"}
class MrtStation {
  const MrtStation({required this.name, required this.codes, required this.lat, required this.lng});
  final String name;
  final List<String> codes;
  final double lat;
  final double lng;

  factory MrtStation.fromBundle(Map<String, dynamic> j) => MrtStation(
        name: '${j['n']}',
        codes: [for (final c in (j['c'] as List? ?? const [])) '$c'],
        lat: _d(j['la']),
        lng: _d(j['lo']),
      );
}


/// Upgrading or construction work from the "around" bundle.
/// {"k","n","s","from","to","by","t","la","lo","r"}
class Project {
  const Project({
    required this.kind,
    required this.name,
    required this.lat,
    required this.lng,
    this.status = '',
    this.from = '',
    this.to = '',
    this.by = '',
    this.contact = '',
    this.radius = 0,
    this.points = const [],
  });

  /// Sample points (lat, lng) of the site, to measure the distance to its nearest part.
  final List<(double, double)> points;
  final String kind;
  final String name;
  final String status;
  final String from;
  final String to;
  final String by;
  final String contact;
  final double lat;
  final double lng;

  /// Rough size of the site (centre to furthest corner), metres.
  final double radius;

  /// Lift Upgrading, Neighbourhood Renewal or Estate Upgrading: work on the estate itself.
  bool get isUpgrading => const {'lup', 'nrp', 'eup'}.contains(kind);

  factory Project.fromBundle(Map<String, dynamic> j) => Project(
        kind: '${j['k'] ?? ''}',
        name: '${j['n'] ?? ''}',
        status: '${j['s'] ?? ''}',
        from: '${j['from'] ?? ''}',
        to: '${j['to'] ?? ''}',
        by: '${j['by'] ?? ''}',
        contact: '${j['t'] ?? ''}',
        lat: _d(j['la']),
        lng: _d(j['lo']),
        radius: j['r'] == null ? 0 : _d(j['r']),
        points: [
          for (final pt in (j['p'] as List? ?? const []))
            if (pt is List && pt.length == 2) (_d(pt[0]), _d(pt[1])),
        ],
      );
}

/// Works plus services near homes (OneMap themes), see backend build_around.
class AroundSet {
  const AroundSet({this.projects = const [], this.points = const {}});
  final List<Project> projects;
  final Map<String, List<EPoint>> points;

  static const empty = AroundSet();
  List<EPoint> of(String key) => points[key] ?? const [];

  factory AroundSet.fromBundle(Map<String, dynamic> j) => AroundSet(
        projects: [for (final r in (j['projects'] as List? ?? const [])) Project.fromBundle(r as Map<String, dynamic>)],
        points: {
          for (final e in (j['points'] as Map? ?? const {}).entries)
            '${e.key}': [for (final r in (e.value as List? ?? const [])) EPoint.fromBundle(r as Map<String, dynamic>)],
        },
      );
}


/// Private residential project from URA (see backend app/ura.py).
/// {"n","s","la","lo","ten","pt","psf","pc","tx":[[ym,price,sqm,floor]],"rent":{"3":4600},"rc"}
class PrivateProject {
  const PrivateProject({
    required this.name,
    required this.street,
    required this.lat,
    required this.lng,
    this.tenure = '',
    this.type = '',
    this.psf,
    this.sales = 0,
    this.salesMonths = 12,
    this.recent = const [],
    this.rent = const {},
    this.rentals = 0,
  });
  final String name;
  final String street;
  final double lat;
  final double lng;
  final String tenure;
  final String type;

  /// Median price per sq ft over the last 12 months (36 when quiet), and how many sales.
  final int? psf;
  final int sales;
  final int salesMonths;

  /// Latest sales: (month "2026-08", price, sqm, floor range).
  final List<(String, int, int, String)> recent;

  /// Median monthly rent by bedrooms ("2", "3", "NA" for landed), last four quarters.
  final Map<String, int> rent;
  final int rentals;

  factory PrivateProject.fromBundle(Map<String, dynamic> j) => PrivateProject(
        name: '${j['n'] ?? ''}',
        street: '${j['s'] ?? ''}',
        lat: _d(j['la']),
        lng: _d(j['lo']),
        tenure: '${j['ten'] ?? ''}',
        type: '${j['pt'] ?? ''}',
        psf: (j['psf'] as num?)?.toInt(),
        sales: (j['pc'] as num?)?.toInt() ?? 0,
        salesMonths: (j['pm'] as num?)?.toInt() ?? 12,
        recent: [
          for (final t in (j['tx'] as List? ?? const []))
            if (t is List && t.length >= 4) ('${t[0]}', (t[1] as num).toInt(), (t[2] as num).toInt(), '${t[3]}'),
        ],
        rent: {for (final e in (j['rent'] as Map? ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
        rentals: (j['rc'] as num?)?.toInt() ?? 0,
      );
}
