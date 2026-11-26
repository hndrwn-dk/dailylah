# Trip navigation, phase 1 (steps on the running trip) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** I'm leaving on a trip without a direct bus keeps the steps of the way that is open in "Ways with changes", with the active step, on the phone. No visible change yet.

**Architecture:** `TripStep` in models.dart (pure, JSON), `stepsOf(TransitOption)` in transit.dart, step rules in logic.dart, `openWayProvider` (index per trip ends) written by `TransitOptionsCard` and read by `_TripTimer._leave`.

**Spec:** `docs/superpowers/specs/2026-11-26-trip-navigation-design.md`

## Global Constraints
- Pure Dart in models/logic/transit; tests in `test/trip_nav_test.dart` (new) and `test/features_test.dart`.
- Steps live only on the phone (Habits), cleared with the trip, never in the share code.
- A trip with a direct bus is unchanged (no steps).
- No release bump in this phase (nothing visible).

## Review Focus
- Old saved Habits without `st`/`si` load as no steps.
- Corrupt `st` entries (missing kind) are dropped, not a crash.
- A new I'm leaving over a running trip drops the old steps (`clearTrip`).
- The open option index outliving its options (fewer options after a refresh) falls back to option 1.
- Arrived / Stop timing clears steps and index.

---

### Task 1: TripStep and Habits fields
**Files:** `app/lib/models.dart`, test `app/test/trip_nav_test.dart`
- Produces: `enum StepKind { walk, bus, mrt }`; `class TripStep { StepKind kind; String from, to, fromName, toName; String? service; int stops, minutes; double metres; String routeKey; toJson/fromJson }` (JSON keys `k f t fn tn s n m d r`); `Habits.tripSteps` (`List<TripStep>`, JSON `st`), `Habits.tripStepIndex` (`int`, JSON `si`), both cleared by `clearTrip`; `copyWith(tripSteps:, tripStepIndex:)`.
- [ ] Tests: JSON round trip of a 4-step trip; old JSON without `st` gives `[]` and 0; an entry with an unknown kind is dropped; `copyWith(clearTrip: true)` empties both.
- [ ] Implement; commit "Keep the steps of a trip with changes".

### Task 2: Steps from an option and the step rules
**Files:** `app/lib/transit.dart`, `app/lib/logic.dart`, test `app/test/trip_nav_test.dart`
- Produces: `List<TripStep> stepsOf(TransitOption o)` (one step per leg, same order and values); in logic.dart `int stepAfter(List<TripStep> steps, int i)` (next index, clamped to the last), `int remainingMinutes(List<TripStep> steps, int i)` (sum of `minutes` from `i`), `int? nextRideIndex(List<TripStep> steps, int i)` (first bus/mrt step at or after `i`).
- [ ] Tests on the Marine Parade option (real bundles, as transit_test): `stepsOf` length = legs, kinds walk,bus,bus,walk; `remainingMinutes(steps, 0)` = option minutes; `stepAfter` at the last stays; `nextRideIndex(steps, 0)` = 1.
- [ ] Implement; commit "Step rules for a trip with changes".

### Task 3: I'm leaving keeps the open way
**Files:** `app/lib/providers.dart`, `app/lib/ui/trip.dart`, test `app/test/features_test.dart`
- Produces: `final openWayProvider = StateProvider.family<int, (double, double, double, double)>((ref, ends) => 0)`; `HabitsNotifier.startTrip(..., List<TripStep> steps = const [])`; `TransitOptionsCard` takes `ends` and writes the provider on tap (its `_open` state goes); `_TripTimer._leave`: when no start stop has a direct bus and options exist, `steps: stepsOf(options[open or 0])`.
- [ ] features_test in "Plan a trip without a direct bus offers ways with changes": after opening option 2 and I'm leaving, `habitsProvider.tripSteps` rides match option 2's rides (services in order) and `tripStepIndex` is 0; Arrived clears them.
- [ ] Implement; full `flutter test`, `flutter analyze`; commit "I'm leaving keeps the way that is open".

### Task 4: Docs
- [ ] `app/CLAUDE.md` feature map (steps on the running trip, `openWayProvider`), `python3 scripts/repo_map.py`; commit "Map the trip steps in the docs".
