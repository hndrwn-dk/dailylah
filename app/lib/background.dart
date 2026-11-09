/// Background checks (every ~15 min via WorkManager): MRT, rain, hawker closures,
/// dengue, heat/lightning and watched HDB blocks, plus refreshing the home screen widget. Runs in its own isolate, so it only uses
/// plain Dart, SharedPreferences and plugins — no Riverpod.
library;

import 'dart:io';

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

/// The same widget on the Galaxy Z Flip cover screen (Flex Window).
const androidCoverWidgetName = 'DailyLahCoverWidgetProvider';

final notifications = FlutterLocalNotificationsPlugin();

AndroidNotificationDetails _channel(S s, {StyleInformation? styleInformation}) => AndroidNotificationDetails(
      'dailylah_alerts',
      s.channelName,
      channelDescription: s.channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: styleInformation,
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
      // Marker for the release smoke test (scripts/emulator_release.sh).
      debugPrint('background check done');
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
  // Public and school holidays, loaded once for every check below.
  var off = const DaysOff();
  try {
    off = DaysOff(
      holidays: Holiday.fromBundle(await repo.load('holidays')),
      school: SchoolHoliday.fromBundle(await repo.load('school_holidays')),
    );
  } on Object catch (e) {
    debugPrint('holidays not loaded: $e');
  }

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

  final live = LiveCache();
  // What the home screen widget shows, gathered by the checks below.
  Map<String, dynamic>? forecastBody, trainBody, wbgtBody, lightningBody, psiBody, pm25Body;
  AreaForecast? here;
  List<LineStatus>? lineList;
  LeaveBy? bus;

  // MRT: one notification per distinct disruption text.
  await guard(() async {
    final train = await api.trainAlerts();
    await live.write('train-alerts', train);
    trainBody = train;
    lineList = lineStatuses(train, watchedLines(fav));
    final bad = lineList!.where((x) => x.disrupted).toList();
    final lines = bad.map((x) => x.line).join(', ');
    if (!fav.mrtAlerts || bad.isEmpty || quiet) return;
    final id = 'mrt:$day:${bad.map((x) => '${x.line}${x.detail}').join('|').hashCode}';
    if (await log.alreadySent(id)) return;
    await notify(1, s.mrtAlert(lines), bad.first.detail?.isNotEmpty == true ? bad.first.detail! : s.checkAlternatives);
    await log.markSent(id);
  });

  // Rain: only in the hour before the usual departure, once per window, max 3 a day.
  final origin = fav.places[originFor(kind, fav, now, off)];
  await guard(() async {
    final body = await api.forecast();
    // Warm the app's cache, so opening the app shows this right away.
    await live.write('forecast', body);
    forecastBody = body;
    if (origin != null) here = forecastNear(body, origin.lat, origin.lng);
    if (!fav.rainAlerts || quiet) return;
    final (goAt, backAt) = commuteTimes(fav, now);
    final leave = kind == CardKind.morning ? goAt : backAt;
    // No destination on a public holiday or day off: only the forecast at home counts.
    final dest = destinationFor(kind, fav, now, off);
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
  // On a public holiday it is replaced by one holiday notification (weather, events nearby).
  await guard(() async {
    if (kind != CardKind.morning || origin == null) return;
    final (goAt, _) = commuteTimes(fav, now);
    if (!inLeaveWindow(now, goAt)) return;
    if (off.publicOn(now) != null) {
      if (!fav.leaveAlerts || quiet || await log.alreadySent('holiday:$day')) return;
      final eventsRaw = await repo.load('events');
      final note = holidayNote(s, fav, now, off,
          homeWeather: here,
          events: [
            if (eventsRaw is List)
              for (final r in eventsRaw)
                if (r is Map<String, dynamic>)
                  if (PublicEvent.fromBundle(r) case final e?) e,
          ]);
      if (note == null) return;
      await notifications.show(
        id: 20,
        title: note.$1,
        body: note.$2,
        notificationDetails: NotificationDetails(
          android: _channel(s, styleInformation: BigTextStyleInformation(note.$2)),
        ),
      );
      await log.markSent('holiday:$day');
      return;
    }
    final remind = fav.leaveAlerts && !quiet && !await log.alreadySent('leave:$day');
    final dest = destinationFor(kind, fav, now, off);
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
      if (lb == null) continue;
      // The widget shows the first bus worth leaving for (stops are nearest first).
      bus ??= lb;
      if (!remind || lb.leaveIn > 10) continue;
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

  // Leave by for custom places with a usual time (e.g. school pick-up): once per place a day.
  await guard(() async {
    if (!fav.leaveAlerts || quiet) return;
    final home = fav.places[PlaceKind.home];
    final due = extrasDueNow(fav, now);
    if (home == null || due.isEmpty) return;
    final routesRaw = await repo.load('bus_routes');
    final stopsRaw = await repo.load('bus_stops');
    if (routesRaw is! Map<String, dynamic> || stopsRaw is! List) return;
    final routes = BusRoutes.fromBundle(routesRaw);
    final all = [for (final r in stopsRaw) BusStop.fromBundle(r as Map<String, dynamic>)];
    for (final i in due) {
      final id = 'leave:$day:extra:$i';
      if (await log.alreadySent(id)) continue;
      final to = fav.extraPlaces[i];
      final destStops = destinationStops(to, all);
      for (final st in usableStops(home)) {
        final services = tripRides(routes, st, to, destStops).keys.toSet();
        if (services.isEmpty) continue;
        final lb = leaveBy(groupEtas(parseBusArrival(await api.busArrival(st.code), now)), services,
            walkMinutesTo(distanceMeters(home.lat, home.lng, st.lat, st.lng)));
        if (lb == null || lb.leaveIn > 10) continue;
        await notify(13 + i, s.leaveTitle, s.leaveForPlace(to.name ?? '', s.leaveIn(lb.service, lb.leaveIn, lb.walk)));
        await log.markSent(id);
        break;
      }
    }
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
    for (final kindToCheck in [PlaceKind.home, if (isSchoolDay(fav, now, off)) PlaceKind.school]) {
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
    // School while there is class; otherwise home (weekends, school holidays).
    final schoolDay = isSchoolDay(fav, now, off);
    final p = (schoolDay ? fav.places[PlaceKind.school] : null) ?? fav.places[PlaceKind.home];
    if (p == null) return;
    final place = s.placeLabel(p.kind.name);
    wbgtBody = await api.weather('wbgt');
    final heat = heatStressNear(wbgtBody!, p.lat, p.lng);
    if (isHighHeat(heat) && !await log.alreadySent('heat:$day')) {
      await notify(5, s.heatTitle, s.heatAt(place, heat!.toLowerCase()));
      await log.markSent('heat:$day');
    }
    psiBody = await api.weather('psi');
    pm25Body = await api.weather('pm25');
    final air = airNear(psiBody, pm25Body, p.lat, p.lng);
    if (air != null && air.level.index >= AirLevel.unhealthy.index) {
      final id = 'haze:$day:${air.level.name}';
      if (!await log.alreadySent(id)) {
        await notify(8, s.hazeTitle, s.airAdviceShort(air.level));
        await log.markSent(id);
      }
    }
    lightningBody = await api.weather('lightning');
    if (lightningNear(lightningBody!, p.lat, p.lng)) {
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

  // Home screen widget: weather, MRT, today's trip, the first bus and the top alert.
  await guard(() async {
    List<T> rows<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
        [if (raw is List) for (final r in raw) f(r as Map<String, dynamic>)];
    final dengueRaw = await repo.load('dengue');
    final alerts = todayAlerts(
      fav: fav,
      now: now,
      s: s,
      forecast: forecastBody,
      trainAlerts: trainBody,
      hawkers: rows(await repo.load('hawkers'), Hawker.fromBundle),
      dengue: rows(dengueRaw is Map ? dengueRaw['clusters'] : null, DengueCluster.fromBundle),
      wbgt: wbgtBody,
      lightning: lightningBody,
      psi: psiBody,
      pm25: pm25Body,
      off: off,
    );
    await updateWidget(widgetData(
      s: s,
      fav: fav,
      now: now,
      here: here,
      lines: lineList,
      alerts: alerts,
      bus: bus,
      busChecked: true,
      off: off,
    ));
  });
}

Map<String, String>? _lastWidget;
DateTime? _lastWidgetAt;

/// Saves [data] (keys from `widgetData`) for the home screen widget and redraws it.
/// The same content within 10 minutes is skipped, so the app can call this on every rebuild.
Future<void> updateWidget(Map<String, String> data) async {
  final content = {...data}..remove('dl_updated');
  final now = DateTime.now();
  if (_lastWidget != null &&
      _lastWidgetAt != null &&
      now.difference(_lastWidgetAt!) < const Duration(minutes: 10) &&
      _sameMap(_lastWidget!, content)) {
    return;
  }
  try {
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData<String>(e.key, e.value);
    }
    await HomeWidget.updateWidget(androidName: androidWidgetName);
    await HomeWidget.updateWidget(androidName: androidCoverWidgetName);
    _lastWidget = content;
    _lastWidgetAt = now;
  } on Object catch (e) {
    // No widget support (tests, iOS without an extension): nothing to update.
    debugPrint('widget update skipped: $e');
  }
}

/// Forgets the last widget update, so the next one is always written (tests).
@visibleForTesting
void resetWidgetCache() {
  _lastWidget = null;
  _lastWidgetAt = null;
}

bool _sameMap(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// Taps on the home screen widget, as the tab to open (dailylah://today, nearby, home).
/// Nothing under `flutter test`, where no plugin answers the channel.
Stream<int> widgetTabTaps() async* {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    if (tabForWidgetUri(await HomeWidget.initiallyLaunchedFromHomeWidget()) case final tab?) yield tab;
  } on Object catch (e) {
    debugPrint('widget launch check skipped: $e');
  }
  yield* HomeWidget.widgetClicked.map(tabForWidgetUri).where((t) => t != null).cast<int>();
}
