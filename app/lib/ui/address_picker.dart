import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models.dart';
import '../providers.dart';
import 'widgets.dart';

/// Search an address on OneMap (postal code, block and street, or building), or use the
/// phone's location. Pops with an [AddressHit].
class AddressPickerPage extends ConsumerStatefulWidget {
  const AddressPickerPage({super.key, required this.title});
  final String title;

  @override
  ConsumerState<AddressPickerPage> createState() => _AddressPickerPageState();
}

class _AddressPickerPageState extends ConsumerState<AddressPickerPage> {
  String _query = '';
  Timer? _debounce;
  bool _locating = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  Future<void> _useLocation() async {
    final s = ref.read(stringsProvider);
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _error = s.locationDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      Navigator.of(context).pop(AddressHit(
        label: s.myLocation,
        block: '',
        road: '',
        building: '',
        postal: '',
        lat: pos.latitude,
        lng: pos.longitude,
      ));
    } on Object {
      setState(() => _error = s.locationUnavailable);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final results = _query.length < 3 ? null : ref.watch(addressSearchProvider(_query));
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.addressHint),
            onChanged: _onChanged,
            onSubmitted: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 8),
          Panel(
            child: ListTile(
              leading: _locating
                  ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              title: Text(s.useMyLocation),
              subtitle: _error == null ? null : Text(_error!),
              onTap: _locating ? null : _useLocation,
            ),
          ),
          if (results != null)
            results.when(
              loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              error: (_, __) => Panel(child: EmptyNote(s.serverWaking)),
              data: (hits) => hits.isEmpty
                  ? Panel(child: EmptyNote(s.noAddressFound))
                  : Panel(
                      child: Column(
                        children: [
                          for (final h in hits.take(12))
                            ListTile(
                              leading: const Icon(Icons.place_outlined),
                              title: Text(h.label),
                              subtitle: h.postal.isEmpty ? null : Text('Singapore ${h.postal}'),
                              onTap: () => Navigator.of(context).pop(h),
                            ),
                        ],
                      ),
                    ),
            ),
          const SizedBox(height: 8),
          Text(s.addressPrivacy, style: t.bodySmall),
        ],
      ),
    );
  }
}
