// Visual regression: the four main tabs in light and dark, and Today and History on an unfolded
// foldable held on its side, compared pixel by pixel with test/goldens/*.png (docs/QA.md,
// "Golden tests").
//
// Text rendering differs between operating systems, so the reference images are made and checked
// on Linux CI only: the `app` workflow sets GOLDENS=1, elsewhere these tests are skipped. After a
// deliberate UI change, run the `goldens` workflow on the branch; it rewrites the images and
// commits them. A failed run uploads the expected, actual and diff images as `golden-failures`.
import 'dart:io';

import 'package:dailylah/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

final _skip = !(Platform.isLinux && Platform.environment['GOLDENS'] == '1');

/// Tabs in the shell, by index.
const _tabs = {'today': 0, 'nearby': 1, 'home': 2, 'more': 4};

/// Tabs also checked on a wide window (a Galaxy Z Fold opened flat and held on its side): the
/// app stays in a centred column (`AppFrame`, `kMaxContentWidth`) with the page colour beside it.
const _wideTabs = {'today': 0, 'history': 3};
const _foldLandscape = Size(880, 600);

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  await load('PlusJakartaSans', ['assets/fonts/PlusJakartaSans-Variable.ttf']);
  await load('BarlowCondensed', ['assets/fonts/BarlowCondensed-SemiBold.ttf', 'assets/fonts/BarlowCondensed-Bold.ttf']);
  // Material icons from the Flutter SDK, so icons are drawn instead of boxes.
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
}

void main() {
  setUpAll(() async {
    if (!_skip) await _loadFonts();
  });

  for (final dark in [false, true]) {
    for (final MapEntry(key: tab, value: index) in _tabs.entries) {
      final name = '$tab-${dark ? 'dark' : 'light'}';
      testWidgets('golden $name', skip: _skip, (tester) async {
        // Fixed household, clock (Tuesday 7 am), API answers, bundles and location.
        final c = Condition(name, dark: dark);
        await applyCondition(tester, c);
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = c.size * 2;
        await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
        await settle(tester);
        containerOf(tester).read(shellTabProvider.notifier).state = index;
        await settle(tester);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
      });
    }
  }

  for (final MapEntry(key: tab, value: index) in _wideTabs.entries) {
    final name = '$tab-fold-landscape';
    testWidgets('golden $name', skip: _skip, (tester) async {
      final c = Condition(name, size: _foldLandscape);
      await applyCondition(tester, c);
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = c.size * 2;
      await tester.pumpWidget(appUnder(c, householdFavorites, tuesdayMorning));
      await settle(tester);
      containerOf(tester).read(shellTabProvider.notifier).state = index;
      await settle(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    });
  }
}
