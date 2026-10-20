import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'widgets.dart';

/// Search the offline bus stop list by name, road or code, or list stops near the
/// phone's current location. Pops with the chosen [BusStop].
class StopPickerPage extends ConsumerStatefulWidget {
  const StopPickerPage({super.key, this.title});
  final String? title;

  @override
  ConsumerState<StopPickerPage> createState() => _StopPickerPageState();
}

class _StopPickerPageState extends ConsumerState<StopPickerPage> {
  String _query = '';
  List<BusStop>? _nearby;
  String? _error;
  bool _locating = false;

  Future<void> _findNearby(List<BusStop> all) async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _error = ref.read(stringsProvider).locationDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      setState(() => _nearby = nearestStops(all, pos.latitude, pos.longitude, limit: 8));
    } on Object {
      setState(() => _error = ref.read(stringsProvider).locationUnavailable);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = ref.watch(busStopsProvider);
    final str = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? str.pickStop)),
      body: stops.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: EmptyNote(str.stopsUnavailable)),
        data: (all) {
          if (all.isEmpty) {
            return Center(child: EmptyNote(str.stopsUnavailable));
          }
          final results = _query.isEmpty ? (_nearby ?? const <BusStop>[]) : searchStops(all, _query);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: str.stopSearchHint,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (_query.isEmpty)
                ListTile(
                  leading: _locating
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator())
                      : const Icon(Icons.my_location),
                  title: Text(str.nearestStops),
                  subtitle: _error == null ? null : Text(_error!),
                  onTap: _locating ? null : () => _findNearby(all),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final s = results[i];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.directions_bus_outlined, color: Theme.of(context).colorScheme.primary),
                      ),
                      title: Text(s.name),
                      subtitle: Text('${s.code} · ${s.road}'),
                      onTap: () => Navigator.of(context).pop(s),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
