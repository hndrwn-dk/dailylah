// Google Play screenshots, rendered from the real screens with the app's fonts.
//
// Not part of `flutter test` (it lives outside test/). Run by .github/workflows/screenshots.yml:
//   flutter test test_store --update-goldens
// which writes test_store/goldens/*.png; scripts/frame_screenshots.py then adds the captions.
import 'dart:io';

import 'package:dailylah/main.dart';
import 'package:dailylah/models.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/ui/widgets.dart';
import 'package:dailylah/wake_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/harness.dart';

/// Screen area of one screenshot: 1080 x 1625 px, below a 295 px caption band.
const _logical = Size(412, 620);
const _dpr = 1080 / 412;

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

/// Live-looking answers relative to the real clock (bus times are computed from now).
class StoreApi extends FakeApi {
  StoreApi({super.disruptedLine});

  @override
  Future<Map<String, dynamic>> forecast() async {
    final body = await super.forecast();
    body['fetched_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return body;
  }

  @override
  Future<Map<String, dynamic>> busArrival(String stopCode) async {
    String at(int min) => DateTime.now().add(Duration(minutes: min, seconds: 20)).toIso8601String();
    Map<String, dynamic> bus(String no, int a, int b, String load, String type) => {
          'ServiceNo': no,
          'NextBus': {'EstimatedArrival': at(a), 'Load': load, 'Feature': 'WAB', 'Type': type},
          'NextBus2': {'EstimatedArrival': at(b), 'Load': 'SEA', 'Feature': 'WAB', 'Type': type},
        };
    return {
      'data': {
        'Services': [
          bus('10', 2, 11, 'SEA', 'DD'),
          bus('12', 4, 13, 'SDA', 'DD'),
          bus('14', 6, 17, 'SEA', 'SD'),
          bus('858', 1, 9, 'SEA', 'DD'),
          bus('293', 7, 19, 'LSD', 'SD'),
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> weather(String kind) async {
    Map<String, dynamic> wrap(Map<String, dynamic> d) => {'fetched_at': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'data': {'data': d}};
    final hour = DateTime.now().toIso8601String();
    return switch (kind) {
      'uv' => wrap({
          'records': [
            {
              'index': [
                {'hour': hour, 'value': 6},
              ],
            },
          ],
        }),
      'wbgt' => wrap({
          'records': [
            {
              'item': {
                'readings': [
                  {'location': {'latitude': '1.354', 'longitude': '103.944'}, 'wbgt': '29.4', 'heatStress': 'Moderate'},
                ],
              },
            },
          ],
        }),
      'psi' || 'pm25' => wrap({
          'regionMetadata': [
            {'name': 'east', 'labelLocation': {'latitude': 1.35735, 'longitude': 103.94}},
          ],
          'items': [
            {
              'readings': kind == 'psi'
                  ? {'psi_twenty_four_hourly': {'east': 42}}
                  : {'pm25_one_hourly': {'east': 12}},
            },
          ],
        }),
      _ => {'fetched_at': 0, 'data': {}},
    };
  }
}

final _fav = householdFavorites.copyWith(showPrayer: false, showHalal: false, learnHabits: true);

/// A week of logged trips and parkings (Mon to Sat before [now]), with fare and parking estimates.
Habits _week(DateTime now) {
  DateTime d(int daysAgo, int h, int m) => DateTime(now.year, now.month, now.day - daysAgo, h, m);
  return Habits(
    trips: [
      TripLog(route: 'home>work', start: d(5, 7, 52), minutes: 46, mode: 'transit', km: 15.6),
      TripLog(route: 'work>home', start: d(5, 18, 21), minutes: 51, mode: 'transit', km: 15.6),
      TripLog(route: 'home>work', start: d(4, 7, 48), minutes: 44, mode: 'transit', km: 15.6),
      TripLog(route: 'work>home', start: d(4, 18, 40), minutes: 58, mode: 'transit', km: 15.6, rainy: true),
      TripLog(route: 'home>work', start: d(2, 7, 50), minutes: 45, mode: 'transit', km: 15.6),
      TripLog(route: 'work>home', start: d(2, 18, 15), minutes: 49, mode: 'transit', km: 15.6),
      TripLog(route: 'home>work', start: d(1, 7, 49), minutes: 47, mode: 'transit', km: 15.6),
      TripLog(route: 'work>home', start: d(1, 19, 2), minutes: 52, mode: 'transit', km: 15.6),
    ],
    parkings: [
      ParkLog(name: 'Blk 156 Tampines St 12', start: d(0, 9, 10), minutes: 135, hdb: true),
      ParkLog(name: 'Tampines Mall', start: d(3, 19, 30), minutes: 95, costCents: 380),
    ],
  );
}

/// A "Wake me" ride in progress, without GPS or notifications.
class _DemoWake extends WakeNotifier {
  @override
  WakeState? build() => const WakeState(service: '858', alight: fullertonSq, left: 2300, closest: 2300);
}

/// Scrolls so [target] sits at the top of the screen, with a little room above it, so the
/// shot starts on a whole section instead of half a card.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final ctx = tester.element(target.first);
  await Scrollable.ensureVisible(ctx);
  await tester.pump();
  final pos = Scrollable.of(ctx).position;
  pos.jumpTo((pos.pixels - 12).clamp(0, pos.maxScrollExtent));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  DateTime? at,
  String? disruptedLine,
  bool wake = false,
  Future<void> Function(WidgetTester tester, ProviderContainer box)? setUp,
}) async {
  await applyCondition(tester, const Condition('store'));
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = _logical * _dpr;
  final now = at ?? tuesdayMorning;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      initialFavoritesProvider.overrideWithValue(_fav),
      apiProvider.overrideWithValue(StoreApi(disruptedLine: disruptedLine)),
      bundleRepoProvider.overrideWithValue(FileBundles()),
      clockProvider.overrideWith((ref) => Stream.value(now)),
      if (wake) wakeProvider.overrideWith(_DemoWake.new),
    ],
    child: const DailyLahApp(),
  ));
  await settle(tester);
  if (setUp != null) {
    await setUp(tester, containerOf(tester));
    await settle(tester);
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  setUpAll(_loadFonts);

  // Today: the trip to work with live buses.
  testWidgets('01 today', (t) => _shoot(t, '01-today', setUp: (t, box) => _scrollTo(t, find.text('Home → Work'))));

  testWidgets('02 wake me', (t) => _shoot(t, '02-wake', wake: true, setUp: (t, box) async {
        box.read(shellTabProvider.notifier).state = 1;
        box.read(nearbySectionProvider.notifier).state = 'bus';
      }));

  // EWL disrupted: the trip card puts buses first with a Plan B note.
  testWidgets('03 plan b', (t) => _shoot(t, '03-planb', disruptedLine: 'EWL', setUp: (t, box) => _scrollTo(t, find.textContaining('disrupted on your way'))));

  testWidgets('04 parks', (t) => _shoot(t, '04-parks', at: saturdayMorning, setUp: (t, box) async {
        box.read(shellTabProvider.notifier).state = 1;
        box.read(nearbySectionProvider.notifier).state = 'green';
      }));

  testWidgets('05 home', (t) => _shoot(t, '05-home', setUp: (t, box) async {
        box.read(shellTabProvider.notifier).state = 2;
      }));

  // History: the week's trips with fare and parking estimates.
  testWidgets('06 history', (t) => _shoot(t, '06-history', at: saturdayMorning, setUp: (t, box) async {
        await t.runAsync(() => box.read(habitsProvider.notifier).restore(_week(saturdayMorning)));
        box.read(shellTabProvider.notifier).state = 3;
        await settle(t);
        await _scrollTo(t, find.byType(BentoTile));
      }));

  // Home > Weekend: the chip row under the block hero, with places and events near home.
  testWidgets('07 weekend', (t) => _shoot(t, '07-weekend', at: saturdayMorning, setUp: (t, box) async {
        box.read(shellTabProvider.notifier).state = 2;
        box.read(homeSectionProvider.notifier).state = 'weekend';
      }));

  // More > Share with family: a QR code, no account.
  testWidgets('08 family', (t) => _shoot(t, '08-family', setUp: (t, box) async {
        box.read(shellTabProvider.notifier).state = 4;
        await settle(t);
        await t.tap(find.text('Share with family'));
        await settle(t);
      }));
}
