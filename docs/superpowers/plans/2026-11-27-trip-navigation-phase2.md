# Trip navigation, phase 2 (the navigator) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A `TripNavigator` that runs the right existing tool for the active step of a trip with changes and moves to the next step, behind a switch that stays off until phase 3 adds the UI.

**Architecture:** Pure rules in logic.dart (`navToolFor`, `mrtRunEnd`, `navGetOffDue`, `navRideOver`); `Habits.tripStepAt` (when the active step began); `lib/trip_nav.dart` with `tripNavigationOnProvider` (false) and `tripNavProvider` (Notifier) that listens to the trip, Bus arriving and Wake me, ticks every 30 s, and starts/stops `busWatchProvider`, `wakeProvider`, `rideProvider`.

**Spec:** `docs/superpowers/specs/2026-11-26-trip-navigation-design.md`

## Global Constraints
- Never asks for location: Wake me gets `ask: false` (new parameter, default true) and then runs only when location is already allowed.
- Off in the app until phase 3 (`tripNavigationOnProvider` false); tests override it.
- One tool at a time (the existing tools already stop Bus arriving when Wake me or a ride starts).
- No release bump.

## Review Focus
- The trip ends (Arrived) while a tool runs: every tool stops, no timer left.
- Bus arriving ends with the bus gone but the rider not seen leaving: the step stays (no guess).
- Steps with an unknown stop code or station name: that tool is skipped, the trip goes on by taps.
- `next()` on the last step: stays there.
- App reopened mid-trip: the navigator picks up the active step from Habits and starts its tool once.

---

### Task 1: Rules and the step clock
**Files:** `app/lib/logic.dart`, `app/lib/models.dart`, `app/lib/providers.dart`, test `app/test/trip_nav_test.dart`
- Produces: `enum NavTool { none, watchBus, wake, ride }`; `({NavTool tool, int at}) navToolFor(List<TripStep> steps, int i)` (walk before a bus: watchBus at that bus step; walk before an MRT step or the end: none; bus: wake at i; mrt: ride at i); `int mrtRunEnd(List<TripStep> steps, int i)` (last index of the MRT steps that follow on from i); `bool navGetOffDue(TripStep bus, DateTime at, DateTime now)` (elapsed ≥ minutes − `feederMinutesPerStop`); `bool navRideOver(List<TripStep> steps, int i, DateTime at, DateTime now)` (elapsed ≥ the run's minutes); `Habits.tripStepAt` (JSON `sa`, cleared with the trip, set by `startTrip` to the start); `HabitsNotifier.setTripStep(int i, DateTime at)`.
- [ ] Tests for each rule on a walk/bus/bus/walk and a walk/mrt/mrt/walk trip; `setTripStep` stores both and survives save/load.
- [ ] Implement; commit "Rules for which tool runs on each step".

### Task 2: The navigator
**Files:** `app/lib/trip_nav.dart` (new), `app/lib/wake_session.dart`, test `app/test/trip_nav_session_test.dart` (style of `bus_watch_session_test.dart`)
- Produces: `tripNavigationOnProvider = Provider<bool>((ref) => false)`; `tripNavProvider = NotifierProvider<TripNavigator, int?>` (state: the step it drives); `TripNavigator.next()`, `tick(DateTime now)`, `wakeChanged(WakeState?)`, `watchChanged(BusWatchState?)` (the last two are what its listeners call; public for tests); `WakeNotifier.start(..., {bool ask = true})`.
- Behaviour: on the active step start `navToolFor`'s tool once (Bus arriving: stop and bus of the ride step, `minutes` = the walk's minutes, `ask: false`; Wake me: alight and the stop before it from the step's route, `ask: false`; ride: `MrtRide` over the MRT run, stations by name, legs by `mrtLeg`). Advance: Bus arriving done with the rider over `busLeftStopMetres` from the stop → the bus step; Wake me arrived or passed → the step after the bus; a ride run over by time → the step after the run (ride stopped). Without location on a bus step, `tick` posts the get-off note once (`wakeNote(s, WakeEvent.arriving, stop)`). `next()` stops the running tool and advances.
- [ ] Tests: off → nothing starts; on → I'm leaving with steps starts Bus arriving for the first bus; `next()` → Wake me on the bus step (location allowed) and Bus arriving stopped; `wakeChanged(arrived)` → the next step; no location: `tick` past the due time posts one note and only one; MRT run: ride starts over both legs, `tick` after the run moves to the last walk and stops the ride; Arrived stops everything; unknown stop code → no tool, no crash.
- [ ] Implement; full `flutter test`, `flutter analyze`; commit "Trip navigator that runs each step's tool (off until the UI comes)".

### Task 3: Docs
- [ ] Feature map (navigator, switch, `tripStepAt`), `python3 scripts/repo_map.py`; commit "Map the trip navigator in the docs"; push; PR.
