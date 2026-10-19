import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../logic.dart';
import '../models.dart';
import '../providers.dart';

/// Search the offline bus stop list by name, road or code, or list stops near the
/// phone's current location. Pops with the chosen [BusStop].
class StopPickerPage extends ConsumerStatefulWidget {
  const StopPickerPage({super.key, this.title = 'Pilih halte'});
  final String title;

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
        setState(() => _error = 'Izin lokasi ditolak. Cari halte lewat nama saja.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      setState(() => _nearby = nearestStops(all, pos.latitude, pos.longitude, limit: 8));
    } on Object {
      setState(() => _error = 'Lokasi tidak tersedia. Cari halte lewat nama saja.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = ref.watch(busStopsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: stops.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Gagal memuat daftar halte')),
        data: (all) {
          if (all.isEmpty) {
            return const Center(child: Text('Daftar halte belum tersedia. Coba lagi nanti.'));
          }
          final results = _query.isEmpty ? (_nearby ?? const <BusStop>[]) : searchStops(all, _query);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Nama halte, jalan, atau kode 5 digit',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (_query.isEmpty)
                ListTile(
                  leading: _locating
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator())
                      : const Icon(Icons.my_location),
                  title: const Text('Halte terdekat dari lokasi saya'),
                  subtitle: _error == null ? null : Text(_error!),
                  onTap: _locating ? null : () => _findNearby(all),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final s = results[i];
                    return ListTile(
                      leading: const Icon(Icons.directions_bus_outlined),
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
