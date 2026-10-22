import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../background.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Wake me at my stop": follows the phone's position during one bus ride and buzzes as
/// the bus leaves the stop before [alight]. Location is used only while this page runs
/// (kept alive with the screen off by a foreground notification) and never stored.
class WakeMePage extends ConsumerStatefulWidget {
  const WakeMePage({super.key, required this.service, required this.alight, this.before});
  final String service;
  final BusStop alight;
  final BusStop? before;

  @override
  ConsumerState<WakeMePage> createState() => _WakeMePageState();
}

class _WakeMePageState extends ConsumerState<WakeMePage> {
  StreamSubscription<Position>? _sub;
  double? _left;
  bool _woke = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final s = ref.read(stringsProvider);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _error = s.locationDenied);
        return;
      }
      await requestNotificationPermission();
      final radius = wakeRadius(widget.before, widget.alight);
      _sub = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: s.wakeTitle,
            notificationText: '${s.wakeRunning}: ${widget.alight.name}',
            enableWakeLock: true,
          ),
        ),
      ).listen((p) async {
        final d = distanceMeters(p.latitude, p.longitude, widget.alight.lat, widget.alight.lng);
        if (!mounted) return;
        setState(() => _left = d);
        if (!_woke && d <= radius) {
          _woke = true;
          setState(() {});
          await HapticFeedback.heavyImpact();
          await notifyNow(10, s.wakeTitle, '${s.wakeNow} ${widget.alight.name}');
          await _sub?.cancel();
          _sub = null;
        }
      }, onError: (_) {
        if (mounted) setState(() => _error = s.locationUnavailable);
      });
    } on Object {
      if (mounted) setState(() => _error = s.locationUnavailable);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(s.wakeTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Panel(
            color: _woke ? DL.amber : null,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.wakeRiding(widget.service, widget.alight.name), style: t.titleMedium?.copyWith(color: _woke ? DL.ink : null)),
                  const SizedBox(height: 10),
                  if (_error != null)
                    Text(_error!, style: t.bodyMedium)
                  else if (_woke)
                    Text(s.wakeNow, style: t.headlineSmall?.copyWith(color: DL.ink))
                  else if (_left == null)
                    const LinearProgressIndicator()
                  else
                    Text(s.wakeLeft(s.metres(_left!)), style: t.displaySmall),
                ],
              ),
            ),
          ),
          Text(s.wakeHow, style: t.bodySmall),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_woke ? s.wakeDone : s.wakeStop),
          ),
        ],
      ),
    );
  }
}
