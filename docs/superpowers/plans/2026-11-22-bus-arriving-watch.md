# Bus Arriving Watch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After I'm leaving on a bus trip, the app watches one bus at the boarding stop, shows it in the trip banner and on Today, and alerts with rich notifications when it is 2 minutes away and when it arrives.

**Architecture:** A pure rule (`busWatchStep`) in `logic.dart` decides what each poll means; a Riverpod session (`lib/bus_watch.dart`, shaped like `WakeNotifier`) keeps the app alive on geolocator's foreground service, polls the stop every 30 s and posts `RichNote`s. The running trip's destination, stop and bus are stored in `Habits` so the banner, a small trip page and Today can rebuild the board after a restart.

**Tech Stack:** Flutter 3.47.9 (pinned, see `.github/workflows/app.yml`), Riverpod, geolocator, the in-repo `dailylah_notify` plugin. No new package, permission, Kotlin or backend change.

**Spec:** `docs/superpowers/specs/2026-11-22-bus-arriving-watch-design.md`. Read it and `app/CLAUDE.md` before any task.

## Global Constraints

- All commands run in `app/`. Each task ends with `flutter analyze` (infos are fatal) and `flutter test` green.
- Rules, wording and pills live in `lib/logic.dart` and `lib/l10n.dart`; no business logic in widgets.
- The phone's position is never stored or sent. `Habits.tripTo` is never written for a "Here" destination.
- No system permission prompt at I'm leaving; only a bell tap prompts.
- Notifications use `RichNote` through `showNote` / `showOngoingNote` only. No new layout, channel or Kotlin.
- Constants (exact values): `busNearMinutes = 2`, `busTrackToleranceMinutes = 4`, `busStaleAfter = Duration(seconds: 90)`, `busLeftStopMetres = 300.0`, `busWatchLimit = Duration(minutes: 45)`; polling is the existing `busRefreshEvery`; "at the stop" is the existing `atStopMetres`.
- Notification id for both alerts: `24` (free: 1 to 12, 13 to 17 and 20 to 23 are taken). The ongoing note uses `locationServiceNoteId`.
- I'm leaving exists only while `Favorites.learnHabits` is on (`_TripTimer`); so does everything here.
- Tap targets 48 dp; strings that can wrap use `noOrphan` as their neighbours do; dark mode keeps mint with ink text.
- Commits: English, imperative, authored as the repo owner, no AI attribution. Branch `ccr-030993d3-wvq158`; no pull request unless asked.
- Structure changes update `app/CLAUDE.md` "Feature map" and `python3 scripts/repo_map.py` output (Task 8).

## Review Focus

1. A poll fails or the phone is offline mid-watch: the last reading stays, after 90 s the pill reads "Updated HH:mm", no alert fires from it, and the watch recovers on the next good poll. (Task 1 test `stale`, Task 4 test `failed fetch`.)
2. Two buses of the same service a minute or two apart: the watch stays on the one it tracked, not the earlier one. (Task 1 test `bunched`.)
3. The rider switches bus with a bell after the 2-minute alert was sent: the new bus gets its own alerts. (Task 4 test `switch resets alerts`.)
4. The app restarts with a trip running and `tripStop` is not in the current bus stop bundle: banner without a board, no crash. (Task 6 test `unknown stop`.)
5. Wake me or I'm on the train starts while a bus is watched, or is running at I'm leaving: one watcher at a time, never two foreground streams. (Task 4 test `one watcher`.)

---

### Task 1: The rule (`busWatchStep`)

**Files:**
- Modify: `app/lib/logic.dart` (next to `leaveBy`, around line 2437)
- Create: `app/test/bus_watch_test.dart`

**Interfaces:**
- Produces:

```dart
const busNearMinutes = 2;
const busTrackToleranceMinutes = 4;
const busStaleAfter = Duration(seconds: 90);
const busLeftStopMetres = 300.0;
const busWatchLimit = Duration(minutes: 45);

enum BusWatchEvent { none, near, arriving, gone, left, stale }

/// The one arrival being followed. [due] is when it is expected at the stop.
class BusTrack {
  const BusTrack({required this.service, required this.due,
      this.nearSent = false, this.arrivingSent = false, this.wasAtStop = false});
  final String service; final DateTime due;
  final bool nearSent, arrivingSent, wasAtStop;
  BusTrack copyWith({DateTime? due, bool? nearSent, bool? arrivingSent, bool? wasAtStop});
}

typedef BusWatchResult = ({BusTrack track, BusWatchEvent event, BusEta? eta});

/// [etas]: every arrival at the stop (parseBusArrival with perService: 3), read at [fetchedAt].
BusWatchResult busWatchStep(BusTrack t, List<BusEta> etas, DateTime now,
    {required DateTime? fetchedAt, double? metresToStop});
```

- [ ] **Step 1: Write the failing tests** in `test/bus_watch_test.dart`, one `test` each, with `now = DateTime(2026, 11, 22, 12, 10)`, `fetchedAt = now`, a helper `eta(String service, int minutes)`:
  - `near once`: track due in 5 min; etas `[197: 2]` gives `near`, `track.nearSent` true, `eta.minutes == 2`; the same call again with the returned track gives `none`.
  - `arriving once`: etas `[197: 0]` gives `arriving` with `nearSent` and `arrivingSent` both true (no `near` first); again gives `none`.
  - `too soon ignored`: track due in 12 min; etas `[197: 1, 197: 12]` gives `none`, `eta.minutes == 12`, flags false.
  - `bunched`: track due in 3 min; etas `[197: 1, 197: 3]` gives `none` with `eta.minutes == 3`.
  - `follows drift`: track due in 6 min; etas `[197: 8]` gives `none` and `track.due == now + 8 min`.
  - `gone`: track with `nearSent: true` due in 1 min; etas `[197: 14]` gives `gone`; etas `[48: 3]` gives `gone`.
  - `re-anchors before near`: track `nearSent: false` due in 6 min; etas `[197: 15]` gives `none` and `track.due == now + 15 min`; etas `[]` gives `none`, track unchanged.
  - `stale`: `fetchedAt = now - 91 s` gives `stale`, track unchanged, even with etas `[197: 0]`; `fetchedAt: null` gives `stale`.
  - `left the stop`: `metresToStop: 40` sets `wasAtStop`; then a track with `wasAtStop: true, nearSent: true` and `metresToStop: 320` gives `left`; with `nearSent: false` gives no `left`; `wasAtStop: false` and 320 m gives no `left`.

- [ ] **Step 2: Run** `flutter test test/bus_watch_test.dart`. Expected: compile error, `busWatchStep` not defined.

- [ ] **Step 3: Implement** in `logic.dart`. Order inside `busWatchStep`:
  1. update `wasAtStop` when `metresToStop < atStopMetres`; return `left` when `wasAtStop && nearSent && metresToStop > busLeftStopMetres`;
  2. `stale` when `fetchedAt` is null or `now - fetchedAt > busStaleAfter`;
  3. among arrivals of `t.service`, expected time = `fetchedAt + minutes`; take the one nearest `t.due` with a difference of at most `busTrackToleranceMinutes`;
  4. none within tolerance: `gone` when `nearSent`; else re-anchor `due` to the earliest arrival expected after `t.due` (event `none`), or leave the track as is;
  5. found: set `due`; `arriving` when `minutes <= 0 && !arrivingSent` (sets both flags); else `near` when `minutes <= busNearMinutes && !nearSent`; else `none`.

- [ ] **Step 4: Run** `flutter test test/bus_watch_test.dart` and `flutter analyze`. Expected: all pass, no issues.

- [ ] **Step 5: Commit** `git commit -m "Add the bus watch rule: follow one arrival, near, arriving, gone"`.

---

### Task 2: The three rich notifications and their strings

**Files:**
- Modify: `app/lib/logic.dart` (note builders near `wakeNote` line 4149 and `wakeWatchNote` line 4318; `sampleNotes`), `app/lib/l10n.dart`
- Test: `app/test/bus_watch_test.dart`, `app/test/dailylah_notify_test.dart` (the sample list)

**Interfaces:**
- Consumes: `RichNote`, `NotePill`, `PillTone`, `NoteArt.phone`, `locationServiceNoteId`, `_todayLink`, `S.loadLabel`, `S.metres`, `BusWhere`.
- Produces:

```dart
const busAlertNoteId = 24;
RichNote busWatchNote(S s, {required String service, required String stop, int? minutes,
    DateTime? staleSince, int? stopsAway, double? metresToStop});
RichNote busNearNote(S s, {required String service, required String stop, required String to,
    required int minutes, String load = '', bool monitored = true});
RichNote busArrivingNote(S s, {required String service, required String stop, required String to,
    String? alight, bool monitored = true});
```

Strings in `S` (exact copy):
`busAlertTitle` "Bus arriving"; `busAtStop(stop)` "At $stop"; `busAtStopTo(stop, to)` "At $stop · to $to"; `busInTitle(service, m)` "$service in $m min"; `busArrivingTitle(service)` "$service is arriving"; `busMinPill(m)` "$m min"; `busArrivingPill` "Arriving"; `busStopsAwayPill(n)` "$n stops away" ("1 stop away" for 1, "Next stop" for 0); `busToStopPill(metres)` "$metres to the stop"; `busAtStopPill` "At the stop"; `busUpdatedPill(clock)` "Updated $clock"; `busGetOffPill(stop)` "Get off at $stop"; `busTimetableBody(body)` "$body · Timetable estimate". Reuse an existing string where one already says the same (check `updatedAt`, `stopsAway` in `busWhereLine`).

Pills (a pill with no value is left out, at most three):
- `busWatchNote`: id `locationServiceNoteId`, title `busAlertTitle`, body `busAtStop(stop)`; `service` (board); `busMinPill` or `busArrivingPill` when 0 (teal), or `busUpdatedPill` when `staleSince` is set (amber); then `busStopsAwayPill` when `stopsAway` is known, else `busAtStopPill` when `metresToStop < atStopMetres`, else `busToStopPill` rounded to 50 m (sky).
- `busNearNote`: id 24, title `busInTitle`, body `busAtStopTo`, pills `service` (board), `busMinPill` (amber), `loadLabel(load)` when not empty (mint); `art: NoteArt.phone`; `link: _todayLink`.
- `busArrivingNote`: id 24, title `busArrivingTitle`, same body, pills `service` (board), `busArrivingPill` (amber), `busGetOffPill(alight)` when known (sky); `art: NoteArt.phone`; `link: _todayLink`.
- `monitored: false` wraps the body in `busTimetableBody`.

- [ ] **Step 1: Write failing tests** (group `notes` in `bus_watch_test.dart`): for `busNearNote(s, service: '197', stop: 'Marine Pde Stn Exit 6', to: 'Bugis Junction', minutes: 2, load: 'SEA')` expect `id == 24`, `title == '197 in 2 min'`, `body == 'At Marine Pde Stn Exit 6 · to Bugis Junction'`, pill texts `['197', '2 min', s.loadLabel('SEA')]`, tones `[board, amber, mint]`, `art == NoteArt.phone`; with `load: ''` two pills; with `monitored: false` body ends with "Timetable estimate". For `busArrivingNote(..., alight: 'Bugis Stn')` title `'197 is arriving'`, pills `['197', 'Arriving', 'Get off at Bugis Stn']`; without `alight` two pills. For `busWatchNote`: `minutes: 5, stopsAway: 4` gives `['197', '5 min', '4 stops away']`; `minutes: 0` gives "Arriving"; `staleSince: DateTime(2026, 11, 22, 12, 7)` gives a second pill starting "Updated"; `metresToStop: 40` and no `stopsAway` gives "At the stop"; `metresToStop: 340` gives "350 m to the stop"; id is `locationServiceNoteId`. In the existing sample test, expect `sampleNotes` to contain ids 124 (once) and all ids still unique.

- [ ] **Step 2: Run** the two test files. Expected: fail, builders not defined.

- [ ] **Step 3: Implement** the strings, the three builders, and add to `sampleNotes` one entry, `busNearNote(s, service: '197', stop: s.sampleStop, to: s.placeLabel('work'), minutes: 2, load: 'SEA')` (one sample: both alerts share the id).

- [ ] **Step 4: Run** `flutter test test/bus_watch_test.dart test/dailylah_notify_test.dart test/logic_test.dart` and `flutter analyze`. Expected: pass.

- [ ] **Step 5: Commit** `git commit -m "Add the bus arriving notes with pills"`.

---

### Task 3: What the phone remembers, and the switch

**Files:**
- Modify: `app/lib/models.dart` (`Habits` line 783, `Favorites` near `lunchAlerts`), `app/lib/providers.dart` (`startTrip` line 193), `app/lib/logic.dart` (`alertKinds`, `alertsOn` line 2322), `app/lib/ui/more.dart` (alert tiles near line 109), `app/lib/l10n.dart`
- Test: `app/test/logic_test.dart` (or the file that holds the `Habits`/`Favorites` JSON tests), `app/test/widget_test.dart` or the More test that checks "8 of 9"

**Interfaces:**
- Produces:

```dart
// Habits: new fields, JSON keys 'tt', 'tp', 'tb'; all three cleared by clearTrip.
final Place? tripTo;      // never the phone's position
final String? tripStop;   // bus stop code
final String? tripBus;    // service; '' is stored as null
Habits copyWith({..., Place? tripTo, String? tripStop, String? tripBus, bool clearTripBus = false});

// HabitsNotifier
Future<void> startTrip(String route, DateTime now,
    {bool rainy = false, String? mode, double? km, Place? to, String? stop, String? bus});
Future<void> setTripBus(String stop, String? bus);   // no-op when no trip runs

// Favorites
final bool busAlerts;     // default true, JSON key 'busAlerts'
const alertKinds = 10;
```

Strings: `alertBus` "Bus arriving"; `alertBusSub` "After I'm leaving, when your bus is 2 min away".

- [ ] **Step 1: Write failing tests:** `Habits` with `tripTo: Place(kind: PlaceKind.other, name: 'Bugis Junction', addrLat: 1.2996, addrLng: 103.8554)`, `tripStop: '92049'`, `tripBus: '197'` survives `Habits.fromJson(h.toJson())`; `copyWith(clearTrip: true)` nulls all three; `copyWith(clearTripBus: true)` nulls only `tripBus`; `Habits.fromJson` of a map without the keys loads with nulls. `Favorites()` has `busAlerts == true`, round-trips `false`, and old JSON without the key gives `true`. `alertsOn(const Favorites())` counts it; the More test expects the tile "Bus arriving" and the count out of 10.

- [ ] **Step 2: Run** those tests. Expected: fail.

- [ ] **Step 3: Implement.** `Place` already has `toJson`/`fromJson` (it is stored in `Favorites`); reuse them. The More tile is a `toggle(Icons.directions_bus_outlined, s.alertBus, fav.busAlerts, (f, v) => f.copyWith(busAlerts: v), sub: s.alertBusSub)` placed after "Leave by"; keep the grid without a hole (see how Lunch pairs with its time tile).

- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Golden tests that show More will differ: regenerate only those with `flutter test --update-goldens test/golden_test.dart` and look at the changed PNGs before committing.

- [ ] **Step 5: Commit** `git commit -m "Remember the running trip's destination, stop and bus; add the Bus arriving switch"`.

---

### Task 4: The session (`busWatchProvider`)

**Files:**
- Create: `app/lib/bus_watch.dart`
- Modify: `app/lib/wake_session.dart` and `app/lib/mrt_ride.dart` (their `start` stops the bus watch), `app/lib/providers.dart` (`cancelTrip`/`finishTrip`/`arrivedAt` callers stop it; see Step 3)
- Test: `app/test/bus_watch_session_test.dart`

**Interfaces:**
- Consumes: Task 1 (`busWatchStep`, `BusTrack`, constants), Task 2 (note builders), Task 3 (`setTripBus`, `Favorites.busAlerts`), `apiProvider.busArrival`, `parseBusArrival(body, now, perService: 3)`, `busWhere`, `busRoutesProvider`, `busStopsByCodeProvider`, `showNote`, `showOngoingNote`, `requestNotificationPermission`, `wakeProvider`, `rideProvider`.
- Produces:

```dart
class BusWatchState {
  final BusStop stop; final String service; final BusStop? alight; final String toLabel;
  final BusTrack track; final BusEta? eta; final DateTime? fetchedAt;
  final int? stopsAway; final double? metresToStop;
  final bool background;   // the foreground service is running
  final bool done;         // bus gone or rider left: offer Wake me
  bool get stale;          // reading older than busStaleAfter
}

class BusWatchNotifier extends Notifier<BusWatchState?> {
  /// [minutes]: the arrival picked (leaveBy's bus or the row tapped). [ask]: a bell tap may
  /// raise the permission prompts; I'm leaving passes false.
  Future<void> start({required BusStop stop, required String service, required int minutes,
      BusStop? alight, required String toLabel, required bool ask});
  void stop();
}
final busWatchProvider = NotifierProvider<BusWatchNotifier, BusWatchState?>(BusWatchNotifier.new);

/// Seams for tests (override in ProviderScope): the clock, the position stream factory and
/// the two note posters.
```

- [ ] **Step 1: Write failing tests** with a `ProviderContainer`, a fake API returning scripted arrival bodies, a fake clock, `fake_async`, and the note posters overridden to record calls:
  - `counts down and alerts`: bodies giving 197 at 5, 2, 0 min post `busNearNote` once then `busArrivingNote` once; the ongoing note is rewritten only when its pills change.
  - `failed fetch`: a throwing poll keeps `eta`; after 90 s `state.stale` is true and no alert is posted; the next good poll clears it.
  - `switch resets alerts`: after `near` for 197, `start(service: '48', ...)` then 48 at 2 min posts a second `busNearNote` for 48, and `habits.tripBus == '48'`.
  - `gone`: after near, a body with 197 at 14 min sets `done`, cancels the stream and the timer, and leaves the state (for the Wake me offer).
  - `limit`: 45 min after `start`, the state is null.
  - `one watcher`: with `wakeProvider` or `rideProvider` non-null, `start` leaves the state null; starting Wake me while watching stops the watch.
  - `no permission, no ask`: with location not granted and `ask: false`, the watch runs with `background == false`, no position stream is opened and no permission is requested; with `ask: true` the request is made.
  - `switch off`: with `Favorites.busAlerts == false`, `start` does nothing.

- [ ] **Step 2: Run** `flutter test test/bus_watch_session_test.dart`. Expected: fail to compile.

- [ ] **Step 3: Implement**, following `WakeNotifier` line by line where it applies: permission flow (`ask` gates `requestPermission` and `requestNotificationPermission`), `Geolocator.getPositionStream` with `AndroidSettings(accuracy: LocationAccuracy.medium, distanceFilter: 50, foregroundNotificationConfig: ForegroundNotificationConfig(notificationTitle: s.busAlertTitle, notificationText: s.busAtStop(stop.name), enableWakeLock: true))`, each fix only updates `metresToStop` and runs `busWatchStep`; `Timer.periodic(busRefreshEvery)` plus one fetch at once; `Timer(busWatchLimit, stop)`. `start` builds `BusTrack(service, due: now + minutes)` and calls `habitsProvider.notifier.setTripBus`. On `near`/`arriving`: `HapticFeedback.heavyImpact()` then `showNote`. On `gone`/`left`: cancel timers and stream, keep the state with `done: true`. `ref.listen(habitsProvider.select((h) => h.tripStart), ...)` in `build` stops the watch when the trip ends (so `providers.dart` needs no change if that works; otherwise call `stop` from `cancelTrip`/`finishTrip`).

- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: pass.

- [ ] **Step 5: Commit** `git commit -m "Add the bus watch session on the location service"`.

---

### Task 5: Choosing the bus (I'm leaving and the bells)

**Files:**
- Modify: `app/lib/ui/trip.dart` (`_TripTimer` line 321 and its call line 124, `TripBusCard` line 888, the board row widget it builds near line 1005), `app/lib/logic.dart`, `app/lib/l10n.dart`
- Test: `app/test/bus_watch_test.dart` (rule), `app/test/widget_test.dart` or a new `app/test/bus_watch_ui_test.dart`

**Interfaces:**
- Consumes: Task 3 `startTrip(..., to:, stop:, bus:)`, Task 4 `busWatchProvider`.
- Produces:

```dart
/// What I'm leaving remembers and watches for a transit trip: the trip's first stop card, and
/// the bus to leave for there when there is one. Null when the trip has no bus stop card.
typedef TripLeave = ({BusStop stop, String? service, int? minutes, BusStop? alight});
TripLeave? tripLeave({required Place from, required Place to, required List<BusStop> stops,
    required BusRoutes routes, required List<BusStop> all, required List<BusEta>? etas});
```

`tripLeave` uses the same inputs and rules as `TripBusCard` (`tripRides`, `destinationStops`, `groupEtas`, the walk rule with 1500 m and `atStopMetres`, `leaveBy`, and no bus when `busNotFaster` folds it). Move that shared calculation out of the widget into logic.dart if needed so both call it once.

Strings: `busAlertMe` "Alert me when this bus is arriving" (tooltip); `busAlerting` "Alerting"; `busAlertStop` "Stop alerting" (tooltip on the filled bell).

- [ ] **Step 1: Write failing tests.** Rule: `tripLeave` returns the first stop with `service: '197'`, `minutes: 5` for a fixture where 197 is the bus to leave for; `service: null` when arrivals are null, when the start is 1.5 km or more from the stop, and when the bus is not faster than walking; null when `stops` is empty. Widgets (pump a `TripSection` for a planned trip with overridden providers): no bell while no trip runs; after tapping I'm leaving, `habits.tripStop`, `tripBus` and `tripTo` are set and `busWatchProvider` is started with `ask: false`; each direct row has a bell with the tooltip, the watched row's is filled with "Alerting"; tapping another bell calls `start(..., ask: true)` for that service; tapping the filled one stops the watch and clears `tripBus`; with `busAlerts` off there are no bells and no watch; destination "Here" stores no `tripTo` and shows no bells; row tap still opens "Where's my bus?"; at text scale 2.0 and width 320 nothing overflows.

- [ ] **Step 2: Run** the tests. Expected: fail.

- [ ] **Step 3: Implement.** `_TripTimer` gets the trip's stops (pass what `TripSection` already has), computes `tripLeave` on tap, calls `startTrip(..., to: endsHere ? null : to, stop: leave?.stop.code, bus: leave?.service)` and, when `leave.service` is set and the mode is transit and no ride or wake runs, `busWatchProvider.notifier.start(..., ask: false)`. The bell is an `IconButton` (48 dp, `Icons.notifications_none` / `Icons.notifications_active`) at the end of each direct row, shown only when `habits.tripStart != null`, `tripTo != null` and `busAlerts`; in the narrow `_BoardRowLayout` it goes on the number's line.

- [ ] **Step 4: Run** `flutter test` and `flutter analyze`; regenerate only goldens that show a running trip, and look at them.

- [ ] **Step 5: Commit** `git commit -m "Pick the bus to watch at I'm leaving and with a bell on the board"`.

---

### Task 6: The banner and the running trip page

**Files:**
- Modify: `app/lib/ui/trip.dart` (`TripBanner` line 1908; add `RunningTripPage`), `app/lib/l10n.dart`
- Test: `app/test/bus_watch_ui_test.dart`

**Interfaces:**
- Consumes: `busWatchProvider`, `Habits.tripTo/tripStop/tripBus`, `busStopsByCodeProvider`, `TripBusCard`, `wakeProvider`, `WakeMePage`, `stopBefore`.
- Produces: `class RunningTripPage extends ConsumerWidget { const RunningTripPage({super.key}); }`

Strings: `busBannerIn(service, m)` "$service in $m min"; `busBannerArriving(service)` "$service arriving"; `busBannerUpdated(service, clock)` "$service · Updated $clock"; the stops part reuses `busStopsAwayPill`; `openTrip` "Open trip" (semantics label); `busAlertsNeedLocation` "Tap a bell to get alerts with the screen off"; `openPlanner` "Change this trip".

- [ ] **Step 1: Write failing tests:**
  - banner line 2 is "197 in 5 min · 4 stops away" while watching, "197 arriving" at 0, "197 · Updated 12:07" when stale, and "On the way since 12:01 · 9 min" with no watch;
  - with `done`, a "Wake me at Bugis Stn" button shows, and tapping it starts `wakeProvider` for 197 and that stop and pushes `WakeMePage`;
  - tapping the banner's left part pushes `RunningTripPage` when `tripStop` resolves; Stop timing and Arrived still work and are separate tap targets;
  - `unknown stop`: `tripStop: '00000'` not in the bundle, or `tripTo == null`: no tap action, timer line, no exception;
  - `background == false` shows `busAlertsNeedLocation` once under the line;
  - `RunningTripPage`: title is the route label, it shows the inline banner, one `TripBusCard` for the stop and `tripTo` with bells, and a "Change this trip" link that pushes `TripPlannerPage`; when the trip ends while it is open it pops.
  - the banner at text scale 2.0, width 320: no overflow.

- [ ] **Step 2: Run** the tests. Expected: fail.

- [ ] **Step 3: Implement.** In `RunningTripPage` the banner is inline, as on the planner (see how `_TripTimer` returns `TripBanner` at line 339 and how the shell hides it there); `TripBusCard(stop: ..., fromKey: null, to: tripTo, toLabel: tripTo.name, from: null, walkCard: false)`.

- [ ] **Step 4: Run** `flutter test` and `flutter analyze`.

- [ ] **Step 5: Commit** `git commit -m "Show the watched bus in the trip banner and open its board"`.

---

### Task 7: Today

**Files:**
- Modify: `app/lib/ui/today.dart` (the `dests` list near line 183; `PlanTripCard` lives in `ui/trip.dart` line 1861), `app/lib/logic.dart`, `app/lib/l10n.dart`
- Test: `app/test/bus_watch_test.dart` (rule), `app/test/bus_watch_ui_test.dart`

**Interfaces:**
- Produces:

```dart
enum TodayTripSlot { none, running, planned }
/// What sits under the weather tiles: the running trip's board, the planned trip's card, or nothing.
TodayTripSlot todayTripSlot({required Habits h, required bool commuteShown,
    required String? commuteRoute, required String? plannedKey});
```

Rule: `running` when `h.tripStart`, `h.tripStop` and `h.tripTo` are set and not (`commuteShown` and `h.tripRoute == commuteRoute`); else `planned` when `plannedKey` (`goKeyProvider`) is set and no trip runs; else `none`.

Strings: `planTripTo(name)` "To $name"; `planTripSee` "See buses and leave".

- [ ] **Step 1: Write failing tests:** the four cases of the rule (running; running but it is the commute shown; planned; none), and widgets: with a running planned trip on a Sunday the `TripBusCard` comes before the MRT card and the bottom `PlanTripCard` stays; with a destination picked and no trip, the card under the weather tiles reads "To Bugis Junction" / "See buses and leave", opens the planner, and the bottom `PlanTripCard` is not shown twice; with neither, Today is unchanged.

- [ ] **Step 2: Run** the tests. Expected: fail.

- [ ] **Step 3: Implement** the rule and place the slot right after `_WeatherTiles` in `dests`. The planned name comes from the same lookup the planner's title uses (the picked key or `goAdhocDestProvider`).

- [ ] **Step 4: Run** `flutter test` and `flutter analyze`; regenerate only Today goldens that changed, and look at them.

- [ ] **Step 5: Commit** `git commit -m "Put the running or planned trip under the weather on Today"`.

---

### Task 8: Privacy text, docs and the release

**Files:**
- Modify: `docs/legal/privacy.md` (the location paragraph, line 27), `web/index.html` ("Privacy and safety" answers, only if one no longer matches), `app/CLAUDE.md` (Feature map: Trip extras, Alerts, More), `docs/REPO_MAP.md` and every `AGENTS.md` (generated), `app/pubspec.yaml` (`version: 2.17.0+51`), `app/lib/l10n.dart` (`whatsNewNotes`), `app/maestro/09_plan_trip.yaml`, `app/maestro/14_alert_examples.yaml` if it counts the examples, `docs/store` release notes if the repo keeps them per release (check `git show --stat 67b0660`)

- [ ] **Step 1: Privacy.** In the paragraph that names "Wake me at my stop" and "I'm on the train" add "Bus arriving": started by I'm leaving or a bell on a trip, location only if already allowed or asked at the bell, an ongoing notification, ends when the bus has come, the trip ends or after 45 minutes; the position is compared with the bus stop on the phone and never stored or sent; the app asks the server for that stop's arrivals every 30 seconds, by stop code only. Add that the destination and bus stop of a trip being timed are kept on the phone until it ends.

- [ ] **Step 2: Landing page.** Read the "Privacy and safety" questions in `web/index.html`; change an answer only if it now says something untrue; run `node --test 'web/tests/*.test.mjs'`. Expected: pass.

- [ ] **Step 3: Feature map and repo map.** Describe `bus_watch.dart`, `busWatchStep`, the notes (id 24), `RunningTripPage`, `todayTripSlot`, `tripLeave`, the tenth alert tile and the `Habits` fields in `app/CLAUDE.md`; run `python3 scripts/repo_map.py` then `python3 scripts/repo_map.py --check`. Expected: no output from the check.

- [ ] **Step 4: Release.** Version `2.17.0+51`; one `whatsNewNotes` line: "Trips: after I'm leaving, DailyLah watches your bus and tells you when it is arriving. Tap the trip bar to see the board." Follow the last release commit for any other file a release touches.

- [ ] **Step 5: Maestro.** Extend `09_plan_trip.yaml`: tap I'm leaving, assert the trip bar, tap it, assert the board title ("Buses to") is visible. Flows are not run here; CI's emulator job runs them.

- [ ] **Step 6: Run everything:** `cd app && flutter analyze && flutter test`, `python3 scripts/repo_map.py --check`, `bash scripts/check-app-id.sh`. Expected: all pass.

- [ ] **Step 7: Commit** `git commit -m "Release 2.17.0: bus arriving alerts on a running trip"` and push the branch.

---

## Not in this plan

- The Play Console foreground service declaration (owner, by hand, before the release goes out).
- A pull request: opened only when the owner asks.
