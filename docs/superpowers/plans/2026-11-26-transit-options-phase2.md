# Transit options, phase 2 and 3 (UI, privacy, release) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Show up to 3 bus/MRT/walk options on a Bus/MRT trip, fix the "No direct bus" dead end, update the privacy text and ship it as release 2.21.0 (together with the 2.20.2 trip bar fix already on the branch).

**Architecture:** `transitNetProvider` builds the `TransitNet` off the UI thread (`Isolate.run`); `transitOptionsProvider` (family on the two ends) runs `transitOptions` (~12 ms). `TransitOptionsCard` in `ui/trip.dart` renders them; `_TransitBlock` places it.

**Spec:** `docs/superpowers/specs/2026-11-26-transit-options-design.md`

## Global Constraints
- Every string through `S`; 48 dp tap targets; holds at 200% text and 320 dp (wrap, no fixed widths).
- Sticker style: `Panel`, `BusPlate`, `LineChip`; a raised card opens something.
- Nothing new is sent to the server.
- Release: minor bump to 2.21.0, `whatsnew-en-US` and `S.whatsNewNotes` the same text, max 500 characters.

## Review Focus
- Bundles still loading (net not built): the block renders as today, no crash, no spinner loop.
- Option 1 starts with MRT: no bus card is invented; the By MRT card stays.
- Trip with direct buses on Today: Today looks as before (goldens unchanged).
- 200% text on 320 dp: summary rows wrap.
- "Here" as the start: the phone's position is only used on the phone (no provider sends it).

---

### Task 1: Providers and strings
**Files:** `app/lib/providers.dart`, `app/lib/l10n.dart`, test `app/test/transit_test.dart`
- Produces: `final transitNetProvider = FutureProvider<TransitNet>`; `final transitOptionsProvider = Provider.autoDispose.family<List<TransitOption>, (double, double, double, double)>` (from lat, from lng, to lat, to lng; `[]` while the net loads).
- Strings: `transitOptionsTitle` "Ways with changes", `transitMinutes(int)` "~38 min", `transitWalk(String metres, int min)` "Walk 250 m · 3 min", `transitBus(String service, int stops, String to)` "Bus 966 · 12 stops to Opp St. Andrew's Village", `transitTrain(String line, int stops, String to)` "TEL · 6 stops to Marina Bay", `transitFrom(String name)` "From Opp D'Ecosia", `transitEstimate` "Times after the first bus are estimates".
- [ ] Test `'the options provider finds the Marine Parade trip once the net is built'` with a `ProviderContainer(retry: noRetry)` overriding the three bundle providers from `web/data`; expect 3 options.
- [ ] Implement, run, commit "Build the transit network off the UI thread".

### Task 2: TransitOptionsCard and its place in the trip
**Files:** `app/lib/ui/trip.dart`, tests `app/test/features_test.dart`, `app/test/screens_matrix_test.dart`
- `TransitOptionsCard({required Place from, required Place to, required List<TransitOption> options})`: Panel, title + estimate note; one row per option (48 dp, `InkWell`, `Semantics(selected:)`): walk minutes, plates/chips joined by chevrons, `~N min`; the open one (state, first by default) lists its legs (`transitWalk`/`transitBus`/`transitTrain`, `transitFrom` on the first ride).
- `_TransitBlock`: when no stop has a direct bus and options exist, children are `[options card, TripBusCard(stop: first bus ride's stop, to: Place at its alighting stop, toLabel: that stop's name) when option 1 starts by bus, By MRT card]` instead of the "No direct bus" cards. With direct buses, the planner page (not Today) adds the options card after the bus and MRT cards.
- [ ] features_test `'Plan a trip without a direct bus offers ways with changes'`: planner from adhoc Marine Parade (1.3050, 103.9085) to adhoc ST Engineering Hub (1.3917, 103.8480), mode transit: `TransitOptionsCard` found, text `Buses to Opp St. Andrew's Village`, no `No direct bus from this stop`, tapping the second option row shows its legs.
- [ ] Screens matrix: the planner on that trip under every condition (`expectAccessible`).
- [ ] Implement, run tests, commit "Show bus, MRT and walking options on a trip".

### Task 3: Privacy, docs, release
- [ ] `docs/legal/privacy.md` section 5: "Which buses go to your destination" becomes the bus and train options with changes, worked out on the phone; landing page privacy answers checked (`web/index.html`).
- [ ] `app/CLAUDE.md` feature map (options in the UI, providers), `python3 scripts/repo_map.py`.
- [ ] Maestro flow 09 checked for strings it taps that changed.
- [ ] `version: 2.21.0+59`, `whatsnew-en-US` and `S.whatsNewNotes`: options with changes + the trip bar fix.
- [ ] Full `flutter test`, `flutter analyze`, `python3 scripts/repo_map.py --check`; commit "Release 2.21.0: ways with changes on a bus and MRT trip"; push.
