import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// OneMap static map (Singapore Land Authority), no key needed. Only the destination is
/// sent, never the user's position.
String oneMapStatic(double lat, double lng, {int zoom = 17, int width = 512, int height = 320}) {
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
Future<void> openDirections(double lat, double lng, {double? distance}) {
  final mode = distance != null && distance <= 1500 ? 'walking' : 'transit';
  return launchUrl(
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=$mode'),
    mode: LaunchMode.externalApplication,
  );
}

Future<void> openInMaps(double lat, double lng, String name) => launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
      mode: LaunchMode.externalApplication,
    );

/// A light place preview: a static map of the area, details, and buttons that hand off
/// to Google Maps for directions. No map SDK in the app.
Future<void> showPlaceSheet(
  BuildContext context, {
  required S s,
  required String title,
  required double lat,
  required double lng,
  String? subtitle,
  double? distance,
  String? phone,
  List<Widget> extra = const [],
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: t.titleLarge),
                if (subtitle != null && subtitle.isNotEmpty) Text(subtitle, style: t.bodySmall),
                if (distance != null) ...[
                  const SizedBox(height: 4),
                  Text('${s.metres(distance)} · ${s.walkMinutes(distance)}', style: t.labelLarge),
                ],
                const SizedBox(height: 14),
                Panel(
                  child: AspectRatio(
                    aspectRatio: 512 / 320,
                    child: Image.network(
                      oneMapStatic(lat, lng),
                      fit: BoxFit.cover,
                      loadingBuilder: (c, child, p) =>
                          p == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      errorBuilder: (c, e, st) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(s.mapUnavailable, style: t.bodySmall, textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ),
                ),
                ...extra,
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.directions),
                        label: Text(s.directions),
                        onPressed: () => openDirections(lat, lng, distance: distance),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                        icon: const Icon(Icons.map_outlined),
                        label: Text(s.openInMaps),
                        onPressed: () => openInMaps(lat, lng, title),
                      ),
                    ),
                  ],
                ),
                if (phone != null && phone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    icon: const Icon(Icons.call_outlined),
                    label: Text('${s.callLabel} $phone'),
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                  ),
                ],
                const SizedBox(height: 8),
                Text(s.mapNote, style: t.bodySmall?.copyWith(color: DL.mist)),
              ],
            ),
          ),
        );
      },
    );
