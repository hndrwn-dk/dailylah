// Notification rules from the PRD ("Aturan notifikasi proaktif"), checked by running the
// real background pass (runChecks) with a fake API and capturing what would be shown.
//
// Tests marked `skip: 'PRD gap …'` describe what the PRD asks for but the app does not do
// yet. They are listed in docs/QA.md; remove the skip once the gap is fixed.
import 'dart:convert';

import 'package:dailylah/background.dart';
import 'package:dailylah/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

const _notifChannel = MethodChannel('dexterous.com/flutter/local_notifications');
const _widgetChannel = MethodChannel('home_widget');

/// Notifications "shown" during a test, as the plugin's method-channel arguments.
final shown = <Map<Object?, Object?>>[];

Future<void> _withFavorites(Favorites fav, {List<String> sent = const []}) async {
  SharedPreferences.setMockInitialValues({
    'favorites.v1': jsonEncode(fav.toJson()),
    if (sent.isNotEmpty) 'alerts.sent': sent,
  });
}

Iterable<String> get titles => shown.map((m) => '${m['title']}');

/// MRT alerts are titled "Disruption on <lines>" (S.mrtAlert).
Iterable<String> get mrtTitles => titles.where((t) => t.startsWith('Disruption'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    shown.clear();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_notifChannel, (call) async {
      if (call.method == 'show') shown.add((call.arguments as Map).cast<Object?, Object?>());
      if (call.method == 'initialize') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(_widgetChannel, (call) async => true);
  });

  // Commute: leave home 08:00 on weekdays (household fixture).
  final rainyBeforeWork = DateTime(2026, 10, 20, 7, 20); // Tuesday, 40 min before leaving
  final lateNight = DateTime(2026, 10, 20, 23, 0);
  final earlyMorning = DateTime(2026, 10, 20, 5, 30);

  group('MRT disruption', () {
    test('sends one alert for a disruption on a starred line', () async {
      await _withFavorites(householdFavorites);
      await runChecks(FakeApi(disruptedLine: 'EWL'), rainyBeforeWork, bundles: FileBundles());
      expect(mrtTitles, isNotEmpty);
    });

    test('does not repeat the same disruption on the next run', () async {
      await _withFavorites(householdFavorites);
      await runChecks(FakeApi(disruptedLine: 'EWL'), rainyBeforeWork, bundles: FileBundles());
      final first = shown.length;
      await runChecks(FakeApi(disruptedLine: 'EWL'), rainyBeforeWork.add(const Duration(minutes: 15)),
          bundles: FileBundles());
      expect(shown.length, first, reason: 'one event = one notification');
    });

    test('stays silent when the MRT toggle is off', () async {
      await _withFavorites(householdFavorites.copyWith(mrtAlerts: false));
      await runChecks(FakeApi(disruptedLine: 'EWL'), rainyBeforeWork, bundles: FileBundles());
      expect(mrtTitles, isEmpty);
    });

    test('ignores lines that are not starred', () async {
      await _withFavorites(householdFavorites.copyWith(lines: {'NSL'}));
      await runChecks(FakeApi(disruptedLine: 'EWL'), rainyBeforeWork, bundles: FileBundles());
      expect(mrtTitles, isEmpty);
    });

    test('still alerts in the early morning (PRD: quiet hours except morning MRT disruptions)', () async {
      await _withFavorites(householdFavorites);
      await runChecks(FakeApi(disruptedLine: 'EWL'), earlyMorning, bundles: FileBundles());
      expect(mrtTitles, isNotEmpty);
    }, skip: 'PRD gap 3: background.dart skips MRT alerts during quiet hours (22:00-06:00)');
  });

  group('Rain', () {
    test('alerts before the usual departure when rain is forecast at home', () async {
      await _withFavorites(householdFavorites);
      await runChecks(FakeApi(), rainyBeforeWork, bundles: FileBundles());
      expect(titles.where((t) => t.toLowerCase().contains('umbrella')), hasLength(1));
    });

    test('only once per window', () async {
      await _withFavorites(householdFavorites);
      await runChecks(FakeApi(), rainyBeforeWork, bundles: FileBundles());
      await runChecks(FakeApi(), rainyBeforeWork.add(const Duration(minutes: 15)), bundles: FileBundles());
      expect(titles.where((t) => t.toLowerCase().contains('umbrella')), hasLength(1));
    });

    test('stays silent when the rain toggle is off', () async {
      await _withFavorites(householdFavorites.copyWith(rainAlerts: false));
      await runChecks(FakeApi(), rainyBeforeWork, bundles: FileBundles());
      expect(titles.where((t) => t.toLowerCase().contains('umbrella')), isEmpty);
    });

    test('no more than 3 a day', () async {
      const day = '2026-10-20';
      await _withFavorites(householdFavorites, sent: ['$day:a', '$day:b', '$day:c']);
      await runChecks(FakeApi(), rainyBeforeWork, bundles: FileBundles());
      expect(titles.where((t) => t.toLowerCase().contains('umbrella')), isEmpty);
    });
  });

  group('Quiet hours 22:00-06:00', () {
    test('nothing but MRT at 23:00', () async {
      await _withFavorites(householdFavorites);
      await runChecks(FakeApi(), lateNight, bundles: FileBundles());
      expect(shown, isEmpty);
    });
  });

  group('Set-up guard', () {
    test('a phone that was never set up gets no notifications', () async {
      await _withFavorites(const Favorites());
      await runChecks(FakeApi(disruptedLine: 'EWL'), rainyBeforeWork, bundles: FileBundles());
      expect(shown, isEmpty);
    });

    test('a failing API does not stop the run', () async {
      await _withFavorites(householdFavorites);
      await expectLater(runChecks(OfflineApi(), rainyBeforeWork, bundles: FileBundles()), completes);
    });
  });

  group('PRD notification requirements', () {
    test('every notification has a "don\'t show this type again" action', () async {
      await _withFavorites(householdFavorites);
      await runChecks(FakeApi(disruptedLine: 'EWL'), rainyBeforeWork, bundles: FileBundles());
      expect(shown, isNotEmpty);
      for (final n in shown) {
        final android = (n['platformSpecifics'] as Map?) ?? const {};
        expect(android['actions'], isNotEmpty, reason: 'notification "${n['title']}" has no actions');
      }
    }, skip: 'PRD gap 1: no notification actions are set in background.dart');

    test('default settings match the PRD table (heat stress off by default)', () {
      const f = Favorites();
      expect(f.mrtAlerts, isTrue);
      expect(f.rainAlerts, isTrue);
      expect(f.hawkerAlerts, isTrue);
      expect(f.dengueAlerts, isTrue);
      expect(f.heatAlerts, isFalse);
    }, skip: 'PRD gap 5: heatAlerts defaults to true; the PRD says heat stress is off by default');

    test('religion-neutral defaults: prayer times and halal are off', () {
      const f = Favorites();
      expect(f.showPrayer, isFalse);
      expect(f.showHalal, isFalse);
    });
  });
}
