/// Background checks (every ~15 min via WorkManager): MRT disruption and rain alerts,
/// plus refreshing the home screen widget. Runs in its own isolate, so it only uses
/// plain Dart, SharedPreferences and plugins — no Riverpod.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'logic.dart';
import 'models.dart';
import 'store.dart';

const backgroundTask = 'dailylah-check';
const androidWidgetName = 'DailyLahWidgetProvider';

final notifications = FlutterLocalNotificationsPlugin();

const _channel = AndroidNotificationDetails(
  'dailylah_alerts',
  'Peringatan DailyLah',
  channelDescription: 'Gangguan MRT dan hujan sebelum berangkat',
  importance: Importance.high,
  priority: Priority.high,
);

Future<void> initNotifications() async {
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await notifications.initialize(settings: settings);
}

Future<void> requestNotificationPermission() async {
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<void> registerBackgroundWork() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    backgroundTask,
    backgroundTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await runChecks(DailyLahApi(), DateTime.now());
    } on Object catch (e) {
      debugPrint('background check failed: $e');
    }
    return true; // never ask WorkManager to retry aggressively
  });
}

/// One background pass. Public for testing.
Future<void> runChecks(DailyLahApi api, DateTime now) async {
  final fav = await FavoritesStore().load();
  if (!fav.isSetUp) return;
  await initNotifications();
  final log = AlertLog(await SharedPreferences.getInstance());
  final day = dayKey(now);
  final kind = cardFor(now);

  String weatherLine = '';
  String mrtLine = '';

  // MRT: always allowed from 06:00, one notification per distinct disruption text.
  if (fav.lines.isNotEmpty) {
    final statuses = lineStatuses(await api.trainAlerts(), fav.lines);
    final bad = statuses.where((s) => s.disrupted).toList();
    mrtLine = bad.isEmpty ? 'MRT normal' : 'Gangguan ${bad.map((s) => s.line).join(', ')}';
    if (fav.mrtAlerts && bad.isNotEmpty && !isQuietHour(now)) {
      final id = 'mrt:$day:${bad.map((s) => '${s.line}${s.detail}').join('|').hashCode}';
      if (!await log.alreadySent(id)) {
        await _notify(1, 'Gangguan ${bad.map((s) => s.line).join(', ')}',
            bad.first.detail?.isNotEmpty == true ? bad.first.detail! : 'Cek jalur alternatif.');
        await log.markSent(id);
      }
    }
  }

  // Rain: only in the hour before the usual departure, once per window per day, max 3/day.
  final origin = fav.places[originFor(kind, fav)];
  final body = await api.forecast();
  if (origin != null) {
    final here = forecastNear(body, origin.lat, origin.lng);
    if (here != null) weatherLine = '${here.area}: ${here.forecast}';
  }
  if (fav.rainAlerts && !isQuietHour(now)) {
    final leave = kind == CardKind.morning ? fav.leaveHome : fav.leaveWork;
    final dest = destinationFor(kind, fav);
    final destPlace = dest == null ? null : fav.places[dest];
    final checkPlaces = <Place>[
      if (origin != null) origin,
      if (destPlace != null) destPlace,
    ];
    if (inRainWindow(now, leave) && log.sentToday(day) < 3) {
      for (final p in checkPlaces) {
        final f = forecastNear(body, p.lat, p.lng);
        if (f == null || !f.isRainy) continue;
        final id = '$day:rain:${kind.name}';
        if (await log.alreadySent(id)) break;
        await _notify(2, 'Bawa payung', '${p.kind.label} (${f.area}): ${f.forecast}');
        await log.markSent(id);
        break;
      }
    }
  }

  await updateWidget(
    title: kind == CardKind.morning ? 'Pagi' : 'Sore',
    body: [weatherLine, mrtLine].where((s) => s.isNotEmpty).join('\n'),
  );
}

Future<void> _notify(int id, String title, String body) =>
    notifications.show(id: id, title: title, body: body, notificationDetails: const NotificationDetails(android: _channel));

Future<void> updateWidget({required String title, required String body}) async {
  try {
    await HomeWidget.saveWidgetData<String>('title', 'DailyLah · $title');
    await HomeWidget.saveWidgetData<String>('body', body.isEmpty ? 'Buka app untuk memuat' : body);
    await HomeWidget.updateWidget(androidName: androidWidgetName);
  } on Object catch (e) {
    // No widget support (tests, iOS without an extension): nothing to update.
    debugPrint('widget update skipped: $e');
  }
}
