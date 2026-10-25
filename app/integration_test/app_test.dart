// On-device regression flows (docs/QA.md sections 1 and 3), run on Android emulators by
// .github/workflows/emulator.yml. These use the real plugins: SharedPreferences,
// notifications, location permission and the home screen widget storage.
//
// Live-data checks call the production API and bundles (dailylah.sg) on purpose: they are a
// smoke test of the release setup. They only assert that screens render without crashing.
//
// The workflow revokes location and grants notifications before this runs.
import 'dart:convert';

import 'package:dailylah/background.dart';
import 'package:dailylah/main.dart';
import 'package:dailylah/providers.dart';
import 'package:dailylah/store.dart';
import 'package:dailylah/ui/nearby.dart';
import 'package:dailylah/ui/setup.dart';
import 'package:dailylah/ui/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_widget/home_widget.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/harness.dart' show FakeApi, householdFavorites;

/// Starts the app the way main() does: load stored favourites, then show the app.
Future<void> launch(WidgetTester tester) async {
  final fav = await FavoritesStore().load();
  await tester.pumpWidget(ProviderScope(
    overrides: [initialFavoritesProvider.overrideWithValue(fav)],
    child: const DailyLahApp(),
  ));
}

/// Waits for live data (the free server may need up to a minute to wake up).
Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 90)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 500));
    if (f.evaluate().isNotEmpty) return;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  testWidgets('first launch opens Setup with no religion question', (tester) async {
    await launch(tester);
    await waitFor(tester, find.byType(SetupPage), timeout: const Duration(seconds: 10));
    expect(find.byType(SetupPage), findsOneWidget);
    expect(find.textContaining(RegExp('relig|muslim|prayer', caseSensitive: false)), findsNothing);
  });

  testWidgets('saved household survives a restart and opens on Today', (tester) async {
    await FavoritesStore().save(householdFavorites);
    // "Restart": a fresh widget tree reading only what is on disk.
    await launch(tester);
    await waitFor(tester, find.byType(TodayPage), timeout: const Duration(seconds: 10));
    expect(find.byType(TodayPage), findsOneWidget);
    final reloaded = await FavoritesStore().load();
    expect(reloaded.toJson(), householdFavorites.toJson());
  });

  testWidgets('Today renders live data from production without crashing', (tester) async {
    await FavoritesStore().save(householdFavorites);
    await launch(tester);
    await waitFor(tester, find.byType(TodayPage), timeout: const Duration(seconds: 10));
    // Give live calls and bundle downloads time to land.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(tester.takeException(), isNull);
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 6; i++) {
      await tester.drag(list, const Offset(0, -500), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nearby with location revoked shows the fallback, not a crash', (tester) async {
    await FavoritesStore().save(householdFavorites);
    await launch(tester);
    await waitFor(tester, find.byType(TodayPage), timeout: const Duration(seconds: 10));
    await tester.tap(find.byTooltip('Nearby'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(NearbyPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background pass posts an MRT notification on the real system', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('favorites.v1', jsonEncode(householdFavorites.toJson()));
    await runChecks(FakeApi(disruptedLine: 'EWL'), DateTime(2026, 10, 20, 7, 20));
    final sent = prefs.getStringList('alerts.sent') ?? const [];
    expect(sent.any((id) => id.startsWith('mrt:')), isTrue);
    // Ask Android which notifications are on screen right now.
    final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()!;
    final active = await android.getActiveNotifications();
    expect(active.map((n) => n.title ?? ''), contains(startsWith('Disruption on')),
        reason: 'the MRT alert was not posted to the Android notification shade');
  });

  testWidgets('home screen widget receives the card text', (tester) async {
    await updateWidget(title: 'Morning', body: 'Tampines: Thundery Showers');
    expect(await HomeWidget.getWidgetData<String>('title'), 'DailyLah · Morning');
    expect(await HomeWidget.getWidgetData<String>('body'), 'Tampines: Thundery Showers');
  });

  testWidgets('first install with no saved data does not crash the background pass', (tester) async {
    await expectLater(runChecks(FakeApi(), DateTime(2026, 10, 20, 7, 20)), completes);
  });
}
