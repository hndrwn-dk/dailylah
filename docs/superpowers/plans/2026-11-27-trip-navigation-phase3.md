# Trip navigation, phase 3 (the UI, switched on) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Show the steps of a trip with changes in the trip bar and on `RunningTripPage`, let the rider move on by tap, switch the navigator on, and ship it as 2.22.0.

**Spec:** `docs/superpowers/specs/2026-11-26-trip-navigation-design.md`

## Global Constraints
- Strings through `S`; 48 dp targets; 200% text on 320 dp; TalkBack labels; sticker style.
- Motion: critically damped spring (damping 1.0, response ~0.35 s) for the active step; none with `MediaQuery.disableAnimations`.
- Haptics only on Got off.
- Privacy policy says what the navigator does with the position (on the phone, while a trip with changes runs, only when location is already allowed).
- Release: minor bump, What's new in `whatsnew-en-US` and `S.whatsNewNotes`.

## Review Focus
- A trip with no steps (direct bus): bar and page exactly as before.
- Last step: no button; Arrived still ends the trip.
- The open way changing between drawing and tapping (AI review of #233): I'm leaving saves the way by signature.
- Large text: the timeline rows wrap, buttons stay 48 dp.

---

### Task 1: Step words and the open way by signature
**Files:** `app/lib/logic.dart`, `app/lib/l10n.dart`, `app/lib/providers.dart`, `app/lib/ui/trip.dart`, tests `app/test/trip_nav_test.dart`
- Produces: `enum StepAction { none, onBus, onTrain, gotOff }`, `StepAction stepAction(List<TripStep> steps, int i)` (walk before a bus: onBus; walk before MRT: onTrain; bus or MRT: gotOff; last walk: none); `String stepLabel(S s, TripStep step)`; strings `stepOf`, `stepWalkTo`, `stepWalkEnd`, `stepBus`, `stepTrain`, `stepOnBus`, `stepOnTrain`, `stepGotOff`, `stepsTitle`; `openWayProvider` keeps the open way's `signature` (String?), card and I'm leaving look it up.
- [ ] Tests for `stepAction` and `stepLabel` on a bus and an MRT trip.

### Task 2: Bar, timeline page, switch on
**Files:** `app/lib/trip_nav.dart` (switch true), `app/lib/ui/shell.dart` (keeps `tripNavProvider` alive), `app/lib/ui/trip.dart` (`TripBanner` step line; `TripStepsCard`; `RunningTripPage` shows it and the bus card of the bus being waited for), tests `app/test/features_test.dart`, `app/test/screens_matrix_test.dart`
- [ ] features_test "A trip with changes walks the rider through its steps": start a trip with steps, the bar says "Step 1 of 4", open the page, the timeline lists every step, "I'm on 966" moves to step 2 and the button becomes "Got off".
- [ ] Screens matrix: the running trip with steps.

### Task 3: Privacy, docs, release
- [ ] `docs/legal/privacy.md` (navigation paragraph, date), feature map, `scripts/repo_map.py`, version 2.22.0, What's new; full tests; commit; push; PR.
