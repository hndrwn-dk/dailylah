# Bus arriving: watch the bus of a running trip

Date: 2026-11-22. Status: draft, waiting for the owner's approval.

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
  `ForegroundNotificationConfig` (wake lock on). The position itself is not read: low accuracy and
  a large distance filter, fixes ignored. A `Timer.periodic(busRefreshEvery)` fetches the stop's
  arrivals and updates the state.
- Location denied: the watch still runs while the app is open (banner and board count down) and the
  banner says once that alerts need location for the screen-off case. No background alert.
- Ongoing notification: `busWatchNote` in logic.dart (id `locationServiceNoteId`), pills: the
  service (board tone), minutes ("3 min" / "Arriving"), "2 stops away" when known. Rewritten only
  when the pills change, like `wakeWatchNote`.
- Alerts, each once per watched bus, as a `RichNote` through `showNote` with a haptic:
  `busNearNote` when the watched bus is at most `busNearMinutes` (2) away and `busArrivingNote`
  when it shows 0 min. One new notification id shared by both (the second replaces the first), not
  used by any other alert. A tap opens the running trip page (below).
- The rule that decides what to do with each poll is a pure function in logic.dart (`busWatchStep`:
  previous state + new etas -> near / arriving / gone / nothing), so it is tested without timers.
  "Gone": after "arriving" was sent, or after the bus was at most 2 min away, the first arrival
  for that service jumps later by more than `busGoneJumpMinutes` (4), or the service has no arrival.
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

### Choosing the bus

- I'm leaving (`_TripTimer`) on a transit trip: when the first stop card of the trip has a bus to
  leave for (`leaveBy`, the mint card), the watch starts for that stop and bus. The builder decides
  how `_TripTimer` learns it (the same inputs `TripBusCard` uses). No such bus: no watch; the
  rider can still pick one.
- While a trip runs, every direct row of a trip board has a bell button (48 dp, tooltip "Alert me
  when this bus is arriving"); the watched row shows it filled and says "Alerting". A tap on
  another bell switches the watch to that stop and bus; a tap on the filled one stops the watch.
  The row tap keeps opening "Where's my bus?".
- No trip running: no bells (the alert belongs to a trip the rider has left for).

### The running trip remembered on the phone

`Habits` gains, next to `tripRoute`/`tripStart` and cleared with them (`clearTrip`):

- `tripTo`: the destination as a `Place` (name and point). Not written when the destination is
  "Here" (the phone's position is never kept).
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
  position is not read, stored or sent, and the server gets the bus stop code every 30 s as it does
  while the board is open. Landing page "Privacy and safety" answers checked against this.
- `app/CLAUDE.md` feature map, `docs/REPO_MAP.md`, `AGENTS.md` (`scripts/repo_map.py`).
- Play listing / What's new note for the release; version bump as the repo does for a feature.

### Tests

- logic: `busWatchStep` (near once, arriving once, gone by jump and by no arrival, stale reading,
  timetable estimate), `busWatchNote`/`busNearNote`/`busArrivingNote` pills, unique ids (the
  existing sample test), `alertsOn` with ten kinds.
- models: `Habits` round trip with the new fields, cleared by `clearTrip`, old JSON still loads.
- widgets: banner line and tap, bells on a running trip only, Today placement (running, planned,
  commute not doubled), `RunningTripPage`; goldens and the screens matrix updated where they show
  the banner or Today.
- Maestro `09_plan_trip.yaml`: I'm leaving, banner tap, board visible.

## Calls made by the writer (not decided by the owner)

- The watch starts by itself at I'm leaving, with an off switch in More > Alerts.
- Alerts at 2 min and at arriving; 45 min limit; 30 s polling; "gone" after a 4 min jump.
- The destination and stop of the running trip are stored on the phone until it ends.
- A separate small page for the banner tap instead of reopening the planner.
- Wake me is offered, not started, when the bus is gone.
- With location denied the watch is in-app only.

## Left to the builder

Names of strings and private widgets, how `_TripTimer` gets the first stop's bus, the exact
notification id, the JSON keys in `Habits`, layout details of the bell at large text sizes
(`_BoardRowLayout`), and how many PRs (one release is expected).
