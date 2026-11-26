# Trip navigation: step by step through a way with changes

## Why
2.21.0 shows up to three ways with changes (966 > 857, bus + MRT) but only shows them: I'm leaving on
such a trip times it and keeps no stop or bus. The owner wants the app to walk them through it like
Google Maps: which step they are on, when their bus comes, when to get off, when the next bus comes,
and a better way when one appears.

## Goals
- I'm leaving on a Bus/MRT trip follows the way that is open in "Ways with changes" (option 1 when none
  was touched; a trip with a direct bus keeps today's behaviour: one step, its first stop card).
- The trip is a list of steps (walk, bus, MRT, walk) with one active step, kept on the phone with the
  running trip (Habits), so it survives closing the app.
- The trip bar (`TripBanner`) says the active step; a tap opens `RunningTripPage`, now a timeline of
  every step: done ones dimmed, the active one large with its live board, the rest light.
- Steps advance by hand always (I'm on 966 / Got off / On the train), and by themselves when location is
  already allowed (owner's pick C): a bus step starts when Bus arriving sees the rider leave the stop
  with the bus (`busLeftStopMetres`), ends when Wake me says the stop is reached; an MRT step ends by
  the ride's estimate (`rideAlertDue` / arrival). A tap always wins over a guess.
- Alerts, reusing the existing ones and IDs: the first bus near and arriving (Bus arriving, ID 24),
  "Get off at the next stop" before a change (Wake me, ID 10, or the time estimate without location),
  the next bus at the change stop (Bus arriving again), the train (I'm on the train, 21/22).
- Proactive better way (owner's pick): while the rider waits at a stop (any step that starts with a
  wait), whenever live arrivals change, the app runs `transitOptions` from that stop to the end; when a
  way arrives at least `betterWayMinutes` (5) earlier than the current plan's estimate, a card shows
  "Faster: 70 from here, about 8 min earlier" with Switch and Keep. Switch replaces the remaining steps
  (Undo in a snackbar); Keep hides it for that step. In the background: at most one notification per
  step for it. The app never switches by itself.

## Non-goals
- Live positions of trains (LTA has none), timetables, fares per step.
- Re-planning while riding (only while waiting at a stop).
- Navigation for car, motorbike, bicycle, taxi or walk-only trips.
- iOS.

## Anti-goals
- Following the rider without location allowed, or asking for location just to navigate: without it the
  trip works by taps and estimates (the same rule as Bus arriving).
- Sending the position, the route or the stops anywhere: only bus stop codes for arrivals, as today.
- Switching routes without the rider's tap.
- More than one ongoing notification at a time.

## Constraints
- Android 10+, Flutter, Riverpod 3; pure rules in logic.dart / transit.dart with tests; strings via `S`.
- 48 dp targets, 200% text on 320 dp, TalkBack labels; sticker style (amber = look now, teal = go).
- Foreground location only through the existing geolocator foreground service, only while a step needs
  it, as Wake me and Bus arriving do today.
- `docs/legal/privacy.md` updated: navigation follows the position on the phone during a trip with
  changes when location is allowed; nothing is kept or sent.

## Approaches
- A. Chain what exists (picked): the running trip keeps its steps; a trip navigator provider runs the
  tool each step needs (Bus arriving while waiting, Wake me while riding a bus to a change, I'm on the
  train for MRT) and re-plans for the proactive card. Reuses tested alerts, ongoing notification and
  permission rules; History logs the trip as today. Cost: the hand-over between tools (today each stops
  the other) must be sequenced by the navigator.
- B. A separate navigation mode with its own location and alert logic: free of old code, but duplicates
  bus watching, stop alerts and the ongoing notification.
- C. Display only (timeline and suggestions while the app is open): small, but no "get off" alert.

## Design (A)
- Model (models.dart): `TripStep` {kind walk|bus|mrt, from, to (codes or `mrt:<name>`), fromName,
  toName, service, stops, minutes, routeKey} and on `Habits`: `tripSteps` (List, JSON `st`) and
  `tripStepIndex` (JSON `si`), cleared with the trip. Built from the open `TransitOption`.
- Rules (logic.dart, pure, tested): `stepAfter(steps, i)`, `stepFromWatch` (bus left the stop →
  ride step), `stepFromWake` (stop reached → next walk/wait step), `remainingMinutes(steps, i, etas)`,
  `betterWay(current, options, now)` (5-min rule, same first ride as the plan never counts as better),
  `navNote(step)` texts for the ongoing notification.
- `TripNavigator` (lib/trip_nav.dart, NotifierProvider like `busWatchProvider`): listens to the trip,
  `busWatchProvider`, `wakeProvider`, `rideProvider`; on each active step starts the right tool:
  waiting for a bus → `busWatch.start(stop, service)`; on a bus to a change → `wake.start(service,
  alight, before)`; MRT → `ride.start(mrtRide)`; last walk → nothing. Advances on their events or a tap;
  re-plans while waiting (debounced to arrival refreshes, `busRefreshEvery`).
- UI (ui/trip.dart): `TripBanner` second line = active step ("Step 2 of 4 · 966 in 4 min"); a small
  step strip (dots and plates) under it. `RunningTripPage` = timeline (`_StepRow`), the active step's
  card (`TripBusCard` for a bus wait, the Wake me state while riding, the MRT ride card), the step
  button (I'm on 966 / Got off / I'm on the train), and the better-way card on top when due.
- Motion (Apple fluid interfaces, in Flutter): the timeline moves to the next step with a critically
  damped spring (damping 1.0, response ~0.35 s; `SpringSimulation`), from the current position, so a
  tap back mid-move reverses without a jump; the page opens from the bar and closes back into it (same
  path; Hero on the bar); haptics only on Got off and the get-off alert; reduced motion
  (`MediaQuery.disableAnimations`) cross-fades instead.
- Wayfinding: every state answers where am I (step N of M), what's next (the next stop or bus) and how
  to get out (Stop timing, Change this trip).

## Phases
1. Steps and rules: model, JSON, logic rules, tests; I'm leaving saves the open way's steps. No UI.
2. Navigator: `TripNavigator` sequencing the three tools, hand-over tests (bus_watch / wake / ride
   session tests style), the ongoing notification text per step.
3. UI: bar, timeline page, step buttons, motion, screens matrix, Maestro flow.
4. Better way: re-plan while waiting, card, notification, Undo; privacy text; release (minor).

## Left to the builder
- Exact spring values within the ranges above; the timeline's look within the sticker style.
- How the open option index reaches I'm leaving (a provider keyed by the trip ends is the obvious one).
- Debounce details for re-planning.

## Owner's decisions
- Pick C for advancing (estimates and taps, location helps when allowed).
- Proactive better way: suggest, never switch by itself; threshold 5 min (my call, adjustable).
- Approach A.
