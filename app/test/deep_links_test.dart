import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Widget and alert taps open MainActivity with a dailylah:// link that home_widget and the app
  // read themselves. With Flutter's own deep linking on, the same link reached the navigator as
  // "/" while the app was open, which pushed a second copy of the tabs: two trip bars, one inline.
  test('Flutter deep linking is off, so a widget tap never pushes a second copy of the tabs', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      RegExp(r'android:name="flutter_deeplinking_enabled"\s+android:value="false"').hasMatch(manifest),
      isTrue,
    );
  });
}
