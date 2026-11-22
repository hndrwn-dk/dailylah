# Bus arriving: watch the bus of a running trip

Date: 2026-11-22. Status: approved by the owner on 2026-11-22.

## Why

The owner planned a trip on a Sunday (Home to Bugis Junction), pressed I'm leaving and walked to
the stop. To check when the bus comes they had to scroll to the end of Today, open "Plan a trip"
again and scroll past the From/To form. Nothing told them the bus was close. On a work day the
commute card on Today already answers this; on any other day, and for any planned trip, it does not.

What they want: after I'm leaving, standing at the stop, the bus status is one glance or one tap
away, and the phone says when the chosen bus is arriving, with the screen off.

How it works today:

- `TripBanner` (`app/lib/ui/trip.dart`) shows the running trip above the tabs: route, "On the way
  since", Stop timing and Arrived. It is not tappable and knows nothing about buses.
- The running trip is `Habits.tripRoute` (names only, "Home>Bugis Junction") and `tripStart`. The
  planner's ends live in memory (`goKeyProvider`, `goAdhocDestProvider`, ...), so after Android
  drops the app nothing knows where the trip goes.
- Today shows a `TripSection` only for the commute; `PlanTripCard` is near the end of the list.
- "Leave in N min" as a notification exists for the commute only and runs in the 15-minute
  WorkManager pass, which is too coarse for "arriving".
- "Wake me at my stop" (`lib/wake_session.dart`) and "I'm on the train" (`lib/mrt_ride.dart`) keep
  the app alive with geolocator's foreground service and rewrite its ongoing notification through
  `showOngoingNote`. `mrt_ride.dart` also polls the server on a timer while it runs.

## Goals

- After I'm leaving on a Bus/MRT trip with a direct bus, the app watches one bus at the boarding
  stop: an ongoing notification counts down ("197 · 3 min · 2 stops away"), and the phone alerts
  when the bus is about 2 minutes away and again when it is arriving. Works with the screen off.
- The rider chooses the bus: the one the card says to leave for is picked at I'm leaving, and any
  other direct bus on the board can be picked instead with one tap.
- The trip banner shows the watched bus and its minutes, and a tap on it opens that stop's board.
- Today shows the running trip's buses near the top on any day, and a planned trip that has not
  started yet is one tap away from the top of Today.
- All of it survives the app being dropped by Android while a trip runs.

## Non-goals

- An alert while still at home ("leave now"). The owner wants the alert at the stop.
- Trips with a transfer, MRT-only trips, and Car, Motorbike, Bicycle, Taxi, Walk: unchanged.
- Starting "Wake me at my stop" automatically when the bus arrives. The rider may not have
  boarded (full bus); it stays one tap.
- A map, a new backend endpoint, a new Android permission, new Kotlin.
- A separate foreground service of another type (new native code and a Play declaration, no gain).

## Anti-goals

- A location service that starts without the rider having asked, or that runs on after the trip.
- An alert that fires late or for the wrong bus because of stale data, with no sign it is stale.
- The phone's position stored or sent anywhere.

## Approaches

1. **Live watch on the existing foreground service (picked).** A session like Wake me: geolocator's
   foreground service keeps the app alive, a timer polls `/v1/bus-arrival/{stop}` every 30 s, the
   ongoing notification is rewritten when its text changes. No new permission or native code, and
   the hand-over to Wake me is natural. Cost: location is active while waiting.
2. **One scheduled notification** at the predicted arrival time. No service, but arrival times
   drift by minutes and the alert cannot follow them once the app is closed.
3. **In-app only.** The banner counts down while the app is on screen. Useless in a pocket.

The owner picked 1 on 2026-11-22.

## Design

### The watch (`lib/bus_watch.dart`, `busWatchProvider`)

A `Notifier<BusWatchState?>` shaped like `WakeNotifier`.

- State: the boarding `BusStop`, the service, the alight `BusStop` (from `tripRides`), the
  destination label, the last `BusEta` with its fetch time, where the bus is (`busWhere`), which
  alerts were sent, an error.
- `start(stop, service, alight, toLabel)`: asks for location and notification permission the way
  `WakeNotifier.start` does, then opens `Geolocator.getPositionStream` with a
  `ForegroundNotificationConfig` (wake lock on). A `Timer.periodic(busRefreshEvery)` fetches the
  stop's arrivals and updates the state.
- The position is used, on the phone only and never stored or sent (balanced accuracy, 50 m
  filter): the metres to the boarding stop. It gives the ongoing notification "at the stop" or
  "350 m to the stop", and it ends the watch when the rider, having been within `atStopMetres`,
  is more than `busLeftStopMetres` (300) from the stop after the bus was near: they are on the bus
  (or gave up), and Wake me is offered. So the location service does location work, as its type says.
- Permission: I'm leaving never raises a system prompt. Location already allowed: the watch starts
  with the service. Not allowed: the watch runs while the app is open only (banner and board count
  down) and the banner says once that a bell tap turns on alerts with the screen off. A bell tap is
  the rider asking: it prompts for location and notifications the way `WakeNotifier.start` does;
  still denied, it stays in-app only.
- Which bus: a service's arrivals are not identified (`BusEta` has no vehicle id), so the watch
  follows one arrival by its expected time. It starts from the arrival picked (`leaveBy`'s bus, or
  the row tapped; a row's first arrival) and at each poll takes the arrival of that service nearest
  to the tracked time, within `busTrackToleranceMinutes` (4). A bus of the same service that comes
  earlier ("Too soon" while the rider walks) is ignored: no alert for it and no "gone".
- Ongoing notification: `busWatchNote` in logic.dart (id `locationServiceNoteId`), pills: the
  service (board tone), minutes ("3 min" / "Arriving"), "2 stops away" when known. Rewritten only
  when the pills change, like `wakeWatchNote`.
- Alerts, each once per watched bus, as a `RichNote` through `showNote` with a haptic:
  `busNearNote` when the watched bus is at most `busNearMinutes` (2) away and `busArrivingNote`
  when it shows 0 min. One new notification id shared by both (the second replaces the first), not
  used by any other alert. A tap opens Today (`dailylah://today`, as the other alerts do), where the
  running trip's board is on top.
- The rule that decides what to do with each poll is a pure function in logic.dart (`busWatchStep`:
  previous state + new etas -> near / arriving / gone / nothing), so it is tested without timers.
  "Gone": after the tracked bus was at most 2 min away, no arrival of that service is within the
  tolerance of the tracked time any more (the next one is later, or there is none).
- Ends when: the bus is gone (state keeps `done` so the banner can offer Wake me, service stops),
  Arrived or Stop timing ends the trip, the rider stops it, Wake me or I'm on the train starts (one
  watcher at a time; starting the bus watch likewise replaces neither of them: while one of those
  runs, the bus watch does not start), or after `busWatchLimit` (45 min).
- A failed fetch keeps the last reading; when the reading is older than 90 s the minutes pill
  becomes "Updated HH:mm" and no alert fires from it.
- Timetable estimates (LTA `Monitored` 0) are watched too; the notes then say "Timetable estimate".
- Switch: a tenth tile in More > Alerts, "Bus arriving" (`Favorites.busAlerts`, on by default,
  `alertKinds` 10, a sample in "Show me an example"). Off: I'm leaving starts no watch and the bell
  on the board is hidden.

### Notifications: the existing rich layout

All three notifications are `RichNote`s built in logic.dart and drawn by the existing
`dailylah_notify` layout (`dl_note.xml`), with the plain notification as the fallback
(`showNote`, `showOngoingNote`). No new layout, picture, channel or Kotlin; wording in `l10n.dart`.

- `busWatchNote` (ongoing, on the location service's notification like `wakeWatchNote`): title
  "Bus arriving", body the stop ("At Marine Pde Stn Exit 6"), pills: `197` (`PillTone.board`),
  "5 min" (teal), then "4 stops away" or "350 m to the stop" (sky).
- `busNearNote`: title "197 in 2 min", body "At Marine Pde Stn Exit 6 · to Bugis Junction", pills:
  `197` (board), "2 min" (amber), "Seats free" / "Standing" / "Full" from LTA's load when known
  (mint), `NoteArt.phone`.
- `busArrivingNote`: title "197 is arriving", same body, pills: `197` (board), "Arriving" (amber),
  "Get off at Bugis Stn" (sky), `NoteArt.phone`.
- A pill whose value is not known is left out, as in the other notes. A timetable estimate adds
  nothing to the pills; the body says "Timetable estimate".
- Both alerts appear in More > Alerts > "Show me an example" and in the notification tests
  (`test/dailylah_notify_test.dart`, the sample list with unique ids).

### Choosing the bus

- I'm leaving (`_TripTimer`) on a transit trip whose first part is a bus (not a trip started with
  "I'm on the train"): `tripStop` is the trip's first stop card, always. When that card has a bus to
  leave for (`leaveBy`, the mint card), `tripBus` is that bus and the watch starts. The builder
  decides how `_TripTimer` learns it (the same inputs `TripBusCard` uses). No such bus (far from the
  stop, arrivals not loaded, "not faster than walking"): `tripBus` stays empty and no watch starts;
  the banner still opens the board, where a bell picks one.
- While a trip runs, every direct row of a trip board has a bell button (48 dp, tooltip "Alert me
  when this bus is arriving"); the watched row shows it filled and says "Alerting". A tap on
  another bell switches the watch to that stop and bus; a tap on the filled one stops the watch.
  The row tap keeps opening "Where's my bus?".
- No trip running: no bells (the alert belongs to a trip the rider has left for).

### The running trip remembered on the phone

`Habits` gains, next to `tripRoute`/`tripStart` and cleared with them (`clearTrip`):

- `tripTo`: the destination as a `Place` (name and point). Not written when the destination is
  "Here" (the phone's position is never kept); such a trip has no board, bells or watch, and its
  banner stays as it is today.
- `tripStop` (bus stop code) and `tripBus` (service): the watched stop and bus, updated on a switch.

After the app restarts with a trip running, the banner and Today rebuild from these and the bundles.
The watch itself does not restart by itself after a restart (no service starts unasked); the bell
is one tap.

### Trip banner

- Line 2, while a bus is watched: "197 in 5 min · 4 stops away" ("197 arriving", "197 · Updated
  12:07"); otherwise "On the way since 12:01 · 9 min" as now.
- After the bus is gone: a "Wake me at <alight>" text button in place of line 2, which starts
  `wakeProvider` for that bus and alight stop and opens the Wake page.
- The left part (icon and text) is a button (TalkBack: "Open trip") that opens `RunningTripPage`
  when `tripStop` is known. Stop timing and Arrived stay as they are.

### Running trip page (`RunningTripPage` in `ui/trip.dart`)

A page with the route as its title: the banner inline (as the planner does), then the
`TripBusCard` for `tripStop` and `tripTo` (the board with bells, "Wake me at my stop", "Tap a bus
to see where it is"). `from` is not passed, so there is no walk and no "Too soon". A link at the
end opens the planner. Nothing else.

### Today

- While a transit trip with a known `tripStop` runs and Today is not already showing that trip as
  the commute `TripSection`: the same `TripBusCard` sits right under the weather tiles, any day.
- A destination picked in the planner but not left for (memory only, `goKeyProvider` set): the
  `PlanTripCard` moves up to that same place and names the trip ("To Bugis Junction", "See buses
  and leave"). Otherwise it stays where it is.

### Privacy and docs

- `docs/legal/privacy.md`: the destination and the bus stop of a trip being timed are kept on the
  phone until the trip ends; "Bus arriving" joins Wake me and I'm on the train as a case where the
  location service runs (ongoing notification, ends with the bus or the trip, at most 45 min), the
  position is compared with the bus stop on the phone and never stored or sent, and the server gets the bus stop code every 30 s as it does
  while the board is open. Landing page "Privacy and safety" answers checked against this.
- `app/CLAUDE.md` feature map, `docs/REPO_MAP.md`, `AGENTS.md` (`scripts/repo_map.py`).
- Play listing / What's new note for the release; version bump as the repo does for a feature.

### Tests

- logic: `busWatchStep` (near once, arriving once, a too-soon bus ignored, gone, left the stop,
  stale reading, timetable estimate), `busWatchNote`/`busNearNote`/`busArrivingNote` pills, unique ids (the
  existing sample test), `alertsOn` with ten kinds.
- models: `Habits` round trip with the new fields, cleared by `clearTrip`, old JSON still loads.
- widgets: banner line and tap, bells on a running trip only, Today placement (running, planned,
  commute not doubled), `RunningTripPage`; goldens and the screens matrix updated where they show
  the banner or Today.
- Maestro `09_plan_trip.yaml`: I'm leaving, banner tap, board visible.

## Calls made by the writer (not decided by the owner)

- The watch starts by itself at I'm leaving, with an off switch in More > Alerts.
- Alerts at 2 min and at arriving; 45 min limit; 30 s polling; the bus is followed by its expected
  time (4 min tolerance), so a too-soon bus of the same service is ignored.
- The phone's position is read (on the phone only) for the distance to the stop and to end the
  watch once the rider has left the stop.
- I'm leaving never shows a permission prompt; only a bell tap does.
- With no bus to leave for, the stop is still remembered so the banner opens its board.
- The destination and stop of the running trip are stored on the phone until it ends.
- A separate small page for the banner tap instead of reopening the planner.
- Wake me is offered, not started, when the bus is gone.
- With location denied the watch is in-app only.

## For the owner to check

- Play Console, App content > Foreground service permissions: the declaration for the location
  type today describes Wake me at my stop and I'm on the train. "Bus arriving" is a third use of
  the same service (rider-started trip, ongoing notification, position compared with a bus stop on
  the phone). The declaration text and its video may need to mention it before the release.

## Left to the builder

Names of strings and private widgets, how `_TripTimer` gets the first stop's bus, the exact
notification id, the JSON keys in `Habits`, layout details of the bell at large text sizes
(`_BoardRowLayout`), and how many PRs (one release is expected).
