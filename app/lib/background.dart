/// Background checks (every ~15 min via WorkManager): MRT, rain, hawker closures,
/// dengue, heat/lightning and watched HDB blocks, plus refreshing the home screen widget. Runs in its own isolate, so it only uses
/// plain Dart, SharedPreferences and plugins — no Riverpod.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'data.dart';
import 'l10n.dart';
import 'logic.dart';
import 'models.dart';
import 'store.dart';

const backgroundTask = 'dailylah-check';
const androidWidgetName = 'DailyLahWidgetProvider';

final notifications = FlutterLocalNotificationsPlugin();

AndroidNotificationDetails _channel(S s) => AndroidNotificationDetails(
      'dailylah_alerts',
      s.channelName,
      channelDescription: s.channelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );

Future<void> initNotifications() async {
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await notifications.initialize(settings: settings);
}

/// Shows one notification right away (used by screens, e.g. "Wake me at my stop").
Future<void> notifyNow(int id, String title, String body) => notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: _channel(const S())),
    );

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
Future<void> runChecks(DailyLahApi api, DateTime now, {BundleRepository? bundles}) async {
  final store = FavoritesStore();
  var fav = await store.load();
  if (!fav.isSetUp) return;
  await initNotifications();
  const s = S();
  final log = AlertLog(await SharedPreferences.getInstance());
  final day = dayKey(now);
  final kind = cardFor(now, fav);
  final quiet = isQuietHour(now);
  final repo = bundles ?? BundleRepository();

  Future<void> notify(int id, String title, String body) => notifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: _channel(s)),
      );

  // Each block runs on its own so one failing endpoint does not stop the rest.
  Future<void> guard(Future<void> Function() f) async {
    try {
      await f();
    } on Object catch (e) {
      debugPrint('background step failed: $e');
    }
  }

  String weatherLine = '';
  String mrtLine = '';

  // MRT: one notification per distinct disruption text.
  await guard(() async {
    final bad = lineStatuses(await api.trainAlerts(), watchedLines(fav)).where((x) => x.disrupted).toList();
    final lines = bad.map((x) => x.line).join(', ');
    mrtLine = bad.isEmpty ? 'MRT: ${s.mrtNormal}' : s.mrtAlert(lines);
    if (!fav.mrtAlerts || bad.isEmpty || quiet) return;
    final id = 'mrt:$day:${bad.map((x) => '${x.line}${x.detail}').join('|').hashCode}';
    if (await log.alreadySent(id)) return;
    await notify(1, s.mrtAlert(lines), bad.first.detail?.isNotEmpty == true ? bad.first.detail! : s.checkAlternatives);
    await log.markSent(id);
  });

  // Rain: only in the hour before the usual departure, once per window, max 3 a day.
  final origin = fav.places[originFor(kind, fav, now)];
  await guard(() async {
    final body = await api.forecast();
    if (origin != null) {
      final here = forecastNear(body, origin.lat, origin.lng);
      if (here != null) weatherLine = '${here.area}: ${here.forecast}';
    }
    if (!fav.rainAlerts || quiet) return;
    final (goAt, backAt) = commuteTimes(fav, now);
    final leave = kind == CardKind.morning ? goAt : backAt;
    final dest = destinationFor(kind, fav, now);
    final destPlace = dest == null ? null : fav.places[dest];
    final checkPlaces = <Place>[
      if (origin != null) origin,
      if (destPlace != null) destPlace,
    ];
    if (!inRainWindow(now, leave) || log.sentToday(day) >= 3) return;
    for (final p in checkPlaces) {
      final f = forecastNear(body, p.lat, p.lng);
      if (f == null || !f.isRainy) continue;
      final id = '$day:rain:${kind.name}';
      if (await log.alreadySent(id)) break;
      await notify(2, s.bringUmbrella, '${s.placeLabel(p.kind.name)} (${f.area}): ${f.forecast}');
      await log.markSent(id);
      break;
    }
  });

  // Leave by: one reminder near the usual departure, for the first bus worth leaving for.
  await guard(() async {
    if (!fav.leaveAlerts || quiet || kind != CardKind.morning || origin == null) return;
    final (goAt, _) = commuteTimes(fav, now);
    if (!inLeaveWindow(now, goAt) || await log.alreadySent('leave:$day')) return;
    final holiday = schoolHolidayOn(SchoolHoliday.fromBundle(await repo.load('school_holidays')), now);
    if (holiday != null && commutePlace(fav, now)?.kind == PlaceKind.school) return;
    final dest = destinationFor(kind, fav, now);
    final to = dest == null ? null : fav.places[dest];
    final stops = usableStops(origin);
    if (to == null || stops.isEmpty) return;
    final routesRaw = await repo.load('bus_routes');
    final stopsRaw = await repo.load('bus_stops');
    if (routesRaw is! Map<String, dynamic> || stopsRaw is! List) return;
    final routes = BusRoutes.fromBundle(routesRaw);
    final all = [for (final r in stopsRaw) BusStop.fromBundle(r as Map<String, dynamic>)];
    final destStops = destinationStops(to, all);
    for (final st in stops) {
      final services = tripRides(routes, st, to, destStops).keys.toSet();
      if (services.isEmpty) continue;
      final etas = groupEtas(parseBusArrival(await api.busArrival(st.code), now));
      final walk = walkMinutesTo(distanceMeters(origin.lat, origin.lng, st.lat, st.lng));
      final lb = leaveBy(etas, services, walk);
      if (lb == null || lb.leaveIn > 10) continue;
      await notify(9, s.leaveTitle, s.leaveIn(lb.service, lb.leaveIn, lb.walk));
      await log.markSent('leave:$day');
      return;
    }
  });

  // Parking time is up (set with "I parked here"): once per parking.
  await guard(() async {
    final p = (await HabitsStore().load()).parked;
    if (p == null || !parkReminderDue(p, now)) return;
    final id = 'park:${p.at.toIso8601String()}';
    if (await log.alreadySent(id)) return;
    await notify(11, s.parkTitle, s.parkReminder(p.name));
    await log.markSent(id);
  });

  // Weekly digest: Sunday evening, once a week, only when there is something to say.
  await guard(() async {
    if (!fav.digestAlerts || !inDigestWindow(now) || await log.alreadySent('digest:$day')) return;
    final hawkersRaw = await repo.load('hawkers');
    final dengueRaw = await repo.load('dengue');
    final aroundRaw = await repo.load('around');
    final lines = weeklyDigest(
      s: s,
      fav: fav,
      now: now,
      hawkers: [if (hawkersRaw is List) for (final r in hawkersRaw) Hawker.fromBundle(r as Map<String, dynamic>)],
      dengue: [
        if (dengueRaw is Map && dengueRaw['clusters'] is List)
          for (final c in dengueRaw['clusters'] as List) DengueCluster.fromBundle(c as Map<String, dynamic>),
      ],
      projects: aroundRaw is Map<String, dynamic> ? AroundSet.fromBundle(aroundRaw).projects : const [],
      holidays: Holiday.fromBundle(await repo.load('holidays')),
    );
    if (lines.isEmpty) return;
    await notifications.show(
      id: 12,
      title: s.digestTitle,
      body: lines.join('\n'),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'dailylah_alerts',
          s.channelName,
          channelDescription: s.channelDesc,
          styleInformation: BigTextStyleInformation(lines.join('\n')),
        ),
      ),
    );
    await log.markSent('digest:$day');
  });

  // Favourite hawker closed tomorrow: in the evening, once per hawker per day.
  await guard(() async {
    if (!fav.hawkerAlerts || fav.hawkers.isEmpty || now.hour < 18 || now.hour >= 22) return;
    final raw = await repo.load('hawkers');
    if (raw is! List) return;
    final tomorrow = dateOnly(now).add(const Duration(days: 1));
    final all = [for (final r in raw) Hawker.fromBundle(r as Map<String, dynamic>)];
    for (final h in all) {
      if (!fav.hawkers.contains(h.id) || h.closureOn(tomorrow) == null) continue;
      final id = 'hawker:$day:${h.id}';
      if (await log.alreadySent(id)) continue;
      final alt = openAlternatives(all, h, tomorrow, limit: 1);
      await notify(
        3,
        s.hawkerTomorrowTitle,
        alt.isEmpty
            ? s.hawkerClosedTomorrow(h.name)
            : '${s.hawkerClosedTomorrow(h.name)}. ${s.tryInstead(alt.first.$1.name, s.metres(alt.first.$2))}',
      );
      await log.markSent(id);
    }
  });

  // New dengue cluster within 1 km of home or school: once per cluster.
  await guard(() async {
    if (!fav.dengueAlerts || quiet) return;
    final raw = await repo.load('dengue');
    final list = raw is Map ? raw['clusters'] : null;
    if (list is! List) return;
    final clusters = [for (final c in list) DengueCluster.fromBundle(c as Map<String, dynamic>)];
    for (final kindToCheck in const [PlaceKind.home, PlaceKind.school]) {
      final p = fav.places[kindToCheck];
      if (p == null) continue;
      for (final (c, _) in dengueNear(clusters, p.lat, p.lng, km: 1)) {
        final id = 'dengue:${c.locality.hashCode}';
        if (await log.alreadySent(id)) continue;
        await notify(4, s.dengueTitle, '${c.locality} · ${s.dengueCases(c.cases)}');
        await log.markSent(id);
      }
    }
  });

  // High heat stress or lightning near school (or home) during the day.
  await guard(() async {
    if (!fav.heatAlerts || now.hour < 7 || now.hour >= 19) return;
    final p = fav.places[PlaceKind.school] ?? fav.places[PlaceKind.home];
    if (p == null) return;
    final place = s.placeLabel(p.kind.name);
    final heat = heatStressNear(await api.weather('wbgt'), p.lat, p.lng);
    if (isHighHeat(heat) && !await log.alreadySent('heat:$day')) {
      await notify(5, s.heatTitle, s.heatAt(place, heat!.toLowerCase()));
      await log.markSent('heat:$day');
    }
    final air = airNear(await api.weather('psi'), await api.weather('pm25'), p.lat, p.lng);
    if (air != null && air.level.index >= AirLevel.unhealthy.index) {
      final id = 'haze:$day:${air.level.name}';
      if (!await log.alreadySent(id)) {
        await notify(8, s.hazeTitle, s.airAdviceShort(air.level));
        await log.markSent(id);
      }
    }
    if (lightningNear(await api.weather('lightning'), p.lat, p.lng)) {
      final id = 'lightning:$day:${now.hour}';
      if (!await log.alreadySent(id)) {
        await notify(6, s.heatTitle, s.lightningNear);
        await log.markSent(id);
      }
    }
  });

  // New resale transactions at watched blocks, checked once a day after 09:00.
  await guard(() async {
    if (!fav.homesAlerts || fav.watchedBlocks.isEmpty || now.hour < 9 || quiet) return;
    if (await log.alreadySent('homes:$day')) return;
    final raw = await repo.load('hdb_resale');
    if (raw is! Map<String, dynamic>) return;
    final resale = ResaleData.fromBundle(raw);
    final updated = {...fav.watchedBlocks};
    for (final e in fav.watchedBlocks.entries) {
      final n = resale.countFor(e.key);
      if (n > e.value) await notify(7, s.homesTitle, s.newSales(e.key.replaceAll('|', ' '), n - e.value));
      updated[e.key] = n;
    }
    fav = fav.copyWith(watchedBlocks: updated);
    await store.save(fav);
    await log.markSent('homes:$day');
  });

  await updateWidget(
    title: kind == CardKind.morning ? s.morningCard : s.eveningCard,
    body: [weatherLine, mrtLine].where((x) => x.isNotEmpty).join('\n'),
    emptyText: s.loading,
  );
}

Future<void> updateWidget({required String title, required String body, String emptyText = 'DailyLah'}) async {
  try {
    await HomeWidget.saveWidgetData<String>('title', 'DailyLah · $title');
    await HomeWidget.saveWidgetData<String>('body', body.isEmpty ? emptyText : body);
    await HomeWidget.updateWidget(androidName: androidWidgetName);
  } on Object catch (e) {
    // No widget support (tests, iOS without an extension): nothing to update.
    debugPrint('widget update skipped: $e');
  }
}
