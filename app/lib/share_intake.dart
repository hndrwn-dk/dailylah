import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'logic.dart';

const _channel = MethodChannel('dailylah/share');

/// Places shared to DailyLah from another app (Android's Share sheet, e.g. from Google Maps):
/// the one that opened the app first, then any shared while it runs. Only texts that name a
/// place, postal code or point come through. The text is read on the phone and not kept;
/// only the postal code is searched, like a typed search. Nothing under `flutter test`.
Stream<SharedPlace> sharedPlaces() {
  if (!Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) return const Stream.empty();
  final out = StreamController<SharedPlace>();
  void add(Object? args) {
    if (args is! Map) return;
    final p = parseSharedPlace(args['text'] as String?, subject: args['subject'] as String?);
    if (p != null && !out.isClosed) out.add(p);
  }

  _channel.setMethodCallHandler((call) async {
    if (call.method == 'shared') add(call.arguments);
  });
  out.onListen = () async {
    try {
      add(await _channel.invokeMethod<Object?>('take'));
    } on Object catch (e) {
      debugPrint('share check skipped: $e');
    }
  };
  out.onCancel = () {
    _channel.setMethodCallHandler(null);
    return out.close();
  };
  return out.stream;
}
