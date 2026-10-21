import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'theme.dart';
import 'widgets.dart';

const _mapW = 512;
const _mapH = 360;
const _mapZoom = 16;

/// OneMap static map (Singapore Land Authority), no key needed. Only the destination is
/// sent, never the user's position.
String oneMapStatic(double lat, double lng, {int zoom = _mapZoom, int width = _mapW, int height = _mapH}) {
  final pin = '[${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)},"237,173,43","A"]';
  return Uri.https('www.onemap.gov.sg', '/api/staticmap/getStaticImage', {
    'layerchosen': 'default',
    'latitude': lat.toStringAsFixed(5),
    'longitude': lng.toStringAsFixed(5),
    'zoom': '$zoom',
    'width': '$width',
    'height': '$height',
    'points': pin,
  }).toString();
}

/// Directions in the phone's Google Maps app (falls back to the browser). The origin is
/// left out, so Maps uses the current location on the phone itself.
Future<void> openDirections(double lat, double lng, {double? distance, String? mode}) {
  mode ??= distance != null && distance <= 1500 ? 'walking' : 'transit';
  return launchUrl(
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=$mode'),
    mode: LaunchMode.externalApplication,
  );
}

/// Google Maps route between two points (used for the MRT option).
Future<void> openRoute(double fromLat, double fromLng, double toLat, double toLng, {String mode = 'transit'}) =>
    launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&origin=$fromLat,$fromLng'
          '&destination=$toLat,$toLng&travelmode=$mode'),
      mode: LaunchMode.externalApplication,
    );

Future<void> openInMaps(double lat, double lng, String name) => launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
      mode: LaunchMode.externalApplication,
    );

/// Web Mercator pixel offset of [lat,lng] from the map centre at [zoom] (256 px tiles).
Offset mercatorOffset(double cLat, double cLng, double lat, double lng, int zoom) {
  final scale = 256 * math.pow(2, zoom).toDouble();
  double x(double lo) => (lo + 180) / 360 * scale;
  double y(double la) {
    final r = la * math.pi / 180;
    return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * scale;
  }

  return Offset(x(lng) - x(cLng), y(lat) - y(cLat));
}

/// Place view: map with the destination and your position, a big distance, travel modes
/// with rough times, and one button that hands off to Google Maps.
Future<void> showPlaceSheet(
  BuildContext context, {
  required S s,
  required String title,
  required double lat,
  required double lng,
  String? subtitle,
  double? distance,
  String? phone,
  TravelMode? mode,
  List<Widget> extra = const [],
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlaceView(
        title: title,
        lat: lat,
        lng: lng,
        subtitle: subtitle,
        distance: distance,
        phone: phone,
        mode: mode,
        extra: extra,
      ),
    );

/// The four ways shown in the place view, with their Google Maps travel modes.
enum _Way { walk, transit, bike, car }

class _PlaceView extends ConsumerStatefulWidget {
  const _PlaceView({
    required this.title,
    required this.lat,
    required this.lng,
    this.subtitle,
    this.distance,
    this.phone,
    this.mode,
    this.extra = const [],
  });
  final String title;
  final double lat;
  final double lng;
  final String? subtitle;
  final double? distance;
  final String? phone;
  final TravelMode? mode;
  final List<Widget> extra;

  @override
  ConsumerState<_PlaceView> createState() => _PlaceViewState();
}

class _PlaceViewState extends ConsumerState<_PlaceView> {
  Position? _me;
  _Way? _way;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  /// Uses the phone's position only if location was already allowed; never asks here.
  Future<void> _locate() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 6)),
      );
      if (mounted) setState(() => _me = pos);
    } on Object {
      // No position: fall back to the distance from the selected place.
    }
  }

  _Way _defaultWay(double? d) => switch (widget.mode) {
        TravelMode.car || TravelMode.motorcycle || TravelMode.taxi => _Way.car,
        TravelMode.bicycle => _Way.bike,
        TravelMode.transit => d != null && d <= 1200 ? _Way.walk : _Way.transit,
        null => d != null && d <= 1500 ? _Way.walk : _Way.transit,
      };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final me = _me;
    final dMe = me == null ? null : distanceMeters(me.latitude, me.longitude, widget.lat, widget.lng);
    final d = dMe ?? widget.distance;
    final way = _way ?? _defaultWay(d);

    // Direct bus from a stop near you (or the selected place) to a stop near the place.
    String? busHint;
    final routes = ref.watch(busRoutesProvider).valueOrNull;
    final stops = ref.watch(busStopsProvider).valueOrNull;
    if (me != null && routes != null && routes.routes.isNotEmpty && stops != null) {
      final dest = Place(kind: PlaceKind.other, addrLat: widget.lat, addrLng: widget.lng);
      final destStops = destinationStops(dest, stops);
      for (final (st, _) in within(stops, me.latitude, me.longitude, 400,
          latOf: (x) => x.lat, lngOf: (x) => x.lng, limit: 3)) {
        final rides = directRides(routes, st.code, destStops);
        if (rides.isNotEmpty) {
          final best = rides.values.reduce((a, b) => a.km <= b.km ? a : b);
          busHint = s.busNo(best.service);
          break;
        }
      }
    }

    String minutes(double metresPerMin, {double factor = 1.3, int extra = 0}) =>
        d == null ? '–' : '~${(d * factor / metresPerMin).ceil() + extra}';

    final tiles = <(_Way, IconData, String, String, String)>[
      (_Way.walk, Icons.directions_walk, s.wayWalk, minutes(80), s.min),
      (_Way.transit, Icons.directions_bus_outlined, s.wayTransit, busHint ?? '–', busHint == null ? s.seeInMaps : ''),
      (_Way.bike, Icons.pedal_bike, s.wayBike, minutes(250), s.min),
      (_Way.car, Icons.directions_car_outlined, s.wayCar, minutes(450, factor: 1.4, extra: 3), s.min),
    ];
    final gmode = switch (way) {
      _Way.walk => 'walking',
      _Way.transit => 'transit',
      _Way.bike => 'bicycling',
      _Way.car => 'driving',
    };

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(14, 0, 18, 24),
        children: [
          _MapPanel(lat: widget.lat, lng: widget.lng, me: me),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d == null ? widget.title : (dMe != null ? s.fromYou(s.metres(d)) : s.away(s.metres(d))),
                        style: t.displayMedium,
                      ),
                      if (d != null) ...[
                        const SizedBox(height: 6),
                        Text(widget.title, style: t.titleMedium),
                      ],
                      if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(widget.subtitle!, style: t.bodySmall),
                        ),
                    ],
                  ),
                ),
                StickerIconButton(
                  icon: Icons.map_outlined,
                  tooltip: s.openInMaps,
                  onPressed: () => openInMaps(widget.lat, widget.lng, widget.title),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Travel modes with rough times.
          Row(
            children: [
              for (final (i, (w, icon, label, value, unit)) in tiles.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _WayTile(icon: icon, label: label, value: value, unit: unit, selected: w == way, onTap: () => setState(() => _way = w))),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(s.estimateNote, style: t.bodySmall),
          const SizedBox(height: 14),
          ...widget.extra,
          FilledButton.icon(
            icon: const Icon(Icons.directions),
            label: Text(s.getDirections),
            onPressed: () => openDirections(widget.lat, widget.lng, mode: gmode),
          ),
          if (widget.phone != null && widget.phone!.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.call_outlined),
              label: Text('${s.callLabel} ${widget.phone}'),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: widget.phone)),
            ),
          ],
          const SizedBox(height: 10),
          Text(s.mapNote, style: t.bodySmall?.copyWith(color: DL.mist)),
        ],
      ),
    );
  }
}

class _WayTile extends StatelessWidget {
  const _WayTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = selected ? DL.ink : null;
    return Semantics(
      selected: selected,
      button: true,
      label: '$label $value $unit',
      child: Panel(
        margin: EdgeInsets.zero,
        color: selected ? DL.amber : null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.displaySmall?.copyWith(fontSize: 22, color: fg)),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 2),
                      Flexible(child: Text(unit, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: fg))),
                    ],
                  ],
                ),
                Text(label, style: t.labelMedium?.copyWith(color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Static OneMap picture with your position drawn on the phone (or an edge arrow when
/// you are outside the picture).
class _MapPanel extends StatelessWidget {
  const _MapPanel({required this.lat, required this.lng, required this.me});
  final double lat;
  final double lng;
  final Position? me;

  @override
  Widget build(BuildContext context) {
    const s = S();
    return Panel(
      child: AspectRatio(
        aspectRatio: _mapW / _mapH,
        child: LayoutBuilder(
          builder: (context, box) {
            final k = box.maxWidth / _mapW;
            Offset? mine;
            if (me != null) {
              final o = mercatorOffset(lat, lng, me!.latitude, me!.longitude, _mapZoom);
              mine = Offset(box.maxWidth / 2 + o.dx * k, box.maxHeight / 2 + o.dy * k);
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  oneMapStatic(lat, lng),
                  fit: BoxFit.cover,
                  loadingBuilder: (c, child, p) =>
                      p == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  errorBuilder: (c, e, st) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(s.mapUnavailable, textAlign: TextAlign.center),
                    ),
                  ),
                ),
                if (mine != null) CustomPaint(painter: _MePainter(mine, DL.edge(context))),
                // OneMap requires its logo and credit on its maps.
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () => launchUrl(Uri.parse('https://www.onemap.gov.sg/legal/opendatalicence.html'),
                        mode: LaunchMode.externalApplication),
                    child: Container(
                      color: const Color(0xCCFFFFFF),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.network(
                            'https://www.onemap.gov.sg/web-assets/images/logo/om_logo.png',
                            height: 14,
                            errorBuilder: (c, e, st) => const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 4),
                          Text(s.oneMapCredit,
                              style: const TextStyle(fontSize: 9, color: DL.ink), textScaler: TextScaler.noScaling),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MePainter extends CustomPainter {
  _MePainter(this.at, this.edge);
  final Offset at;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 16.0;
    final inside = at.dx >= pad && at.dy >= pad && at.dx <= size.width - pad && at.dy <= size.height - pad;
    if (inside) {
      canvas.drawCircle(at, 18, Paint()..color = const Color(0x553CC4B6));
      canvas.drawCircle(at, 9, Paint()..color = edge);
      canvas.drawCircle(at, 6, Paint()..color = DL.teal);
      return;
    }
    // Outside: an arrow on the edge pointing towards you.
    final c = size.center(Offset.zero);
    final dir = at - c;
    final sx = (size.width / 2 - pad) / dir.dx.abs();
    final sy = (size.height / 2 - pad) / dir.dy.abs();
    final p = c + dir * math.min(sx, sy);
    final a = math.atan2(dir.dy, dir.dx);
    final path = Path()
      ..moveTo(p.dx + 14 * math.cos(a), p.dy + 14 * math.sin(a))
      ..lineTo(p.dx + 10 * math.cos(a + 2.4), p.dy + 10 * math.sin(a + 2.4))
      ..lineTo(p.dx + 10 * math.cos(a - 2.4), p.dy + 10 * math.sin(a - 2.4))
      ..close();
    canvas.drawPath(path, Paint()..color = DL.teal);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(_MePainter old) => old.at != at || old.edge != edge;
}


