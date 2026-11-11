import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models.dart';
import '../providers.dart';
import 'widgets.dart';

/// Search an address on OneMap (postal code, block and street, or building), or use the
/// phone's location. Pops with an [AddressHit]. With [places] (Plan a trip only) place names
/// are searched too (`placeSearchProvider`).
class AddressPickerPage extends ConsumerStatefulWidget {
  const AddressPickerPage({super.key, required this.title, this.note, this.places = false});
  final String title;

  /// Also find shops and restaurants by name (Geoapify through /v1/places), with attribution.
  final bool places;

  /// Shown above the search box, e.g. when a place shared from Google Maps came without an address.
  final String? note;

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
      await popAfterKeyboard(context, AddressHit(
        label: s.myLocation,
        block: '',
        road: '',
        building: '',
        postal: '',
        lat: pos.latitude,
        lng: pos.longitude,
        here: true,
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
    final places = widget.places;
    final AsyncValue<PlaceHits>? results = _query.length < 3
        ? null
        : places
            ? ref.watch(placeSearchProvider(_query))
            : ref.watch(addressSearchProvider(_query)).whenData(PlaceHits.new);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.note case final note?) ...[
            Panel(child: EmptyNote(note)),
            const SizedBox(height: 8),
          ],
          TextField(
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: places ? s.placeHint : s.addressHint),
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
              data: (found) => found.hits.isEmpty
                  ? Panel(
                      child: EmptyNote(
                        s.noAddressFound,
                        action: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(places ? s.noPlaceTips : s.noAddressTips, style: t.bodySmall),
                        ),
                      ),
                    )
                  : Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final h in found.hits.take(12))
                            ListTile(
                              leading: const Icon(Icons.place_outlined),
                              title: Text(h.label),
                              subtitle: h.postal.isEmpty ? null : Text('Singapore ${h.postal}'),
                              onTap: () => popAfterKeyboard(context, h),
                            ),
                          if (found.geoapify)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                              child: Text(s.placesAttribution, style: t.bodySmall),
                            ),
                        ],
                      ),
                    ),
            ),
          const SizedBox(height: 8),
          Text(places ? s.placePrivacy : s.addressPrivacy, style: t.bodySmall),
        ],
      ),
    );
  }
}
