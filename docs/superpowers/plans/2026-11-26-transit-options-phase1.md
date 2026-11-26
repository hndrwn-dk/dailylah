# Transit options, phase 1 (router core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pure-Dart router that finds up to 3 different door-to-door bus/MRT/walk options between two places, from the bundles the phone already has. No UI change.

**Architecture:** New pure-Dart file `app/lib/transit.dart` (no Flutter, no I/O, like logic.dart). `TransitNet` is built once from bus stops, bus routes and MRT stations; `transitOptions` runs a round-based search (RAPTOR style, rides = rounds, max 3 rides) on minutes, then rebuilds, ranks and de-duplicates journeys.

**Tech Stack:** Dart 3, flutter_test, bundles in `web/data/`.

**Spec:** `docs/superpowers/specs/2026-11-26-transit-options-design.md`

## Global Constraints
- Pure Dart: `transit.dart` imports only `dart:math`, `data.dart`, `models.dart`, `logic.dart`.
- Nothing is sent anywhere; no new endpoint, no new bundle.
- Max 3 options; max 3 rides (2 changes).
- Start: bus stops within 500 m, MRT stations within 1200 m. End: bus stops within 400 m, stations within 1200 m.
- Walk between stops/stations for a change: at most `transferWalkMetres` = 250.
- Minutes: walk `walkMinutesTo(m)`; bus `feederMinutesPerStop` (2) a stop; MRT `rideMinutesPerStop` (2) a stop; first bus wait `firstBusWaitMinutes` = 5 (replaced by live data in phase 2); later bus wait `busChangeWaitMinutes` = 6; MRT wait `mrtWaitMinutes` = 3; a change between MRT lines at one station `rideTransferMinutes` (5) instead of the wait.
- A structure change updates `app/CLAUDE.md` feature map and `docs/REPO_MAP.md` + `AGENTS.md` (`python3 scripts/repo_map.py`) in the same PR.
- Commits as Hendrawan, no AI trailers.

## Review Focus
- From and To within `samePlaceMetres`: no options (the UI says "You're already there").
- Empty bundles (offline first run): `transitOptions` returns `[]`, never throws.
- A loop service that passes the start stop twice (e.g. 966 passes Marine Parade both ways): board at the occurrence that leads to the end, never ride backwards.
- MRT lines with branches or loops (CE, BP, SE/SW/PE/PW LRT, CG): never ride between two stations that are not neighbours on the same prefix.
- A stop code in `bus_routes.json` that is missing from `bus_stops.json`: skipped, not a crash.

---

### Task 1: Models and the network

**Files:**
- Create: `app/lib/transit.dart`
- Test: `app/test/transit_test.dart`

**Interfaces:**
- Produces:
  - `enum LegKind { walk, bus, mrt }`
  - `class TransitLeg { LegKind kind; String from; String to; String fromName; String toName; String? service /* bus number or line code e.g. 'TEL' */; int stops; int minutes; double metres /* walk only */; String routeKey /* bus only */ }`
  - `class TransitOption { List<TransitLeg> legs; int minutes; int changes /* rides - 1 */; double walkMetres; List<TransitLeg> get rides; String get signature /* rides' services joined by '>' */ }`
  - `class TransitNet { static TransitNet build(List<BusStop> stops, BusRoutes routes, List<MrtStation> stations); bool get isEmpty; }` Node ids: a bus stop code, or `'mrt:<station name>'` (one node per station, interchanges shared). Holds node positions/names, patterns (ordered node lists with kind, service, routeKey; MRT: one pattern per code prefix and direction, stations sorted by the number in their code), per-node list of (pattern, index), and walk links within 250 m (grid buckets of ~250 m, not all pairs).

- [ ] **Step 1: Write the failing tests** in `test/transit_test.dart`, loading the real bundles from `../web/data/` like `logic_test.dart` "pick a line for today":
  - `'the net has every bus stop that a route uses and one node per MRT station'`: `net.nodeCount` > 5000; `net.hasNode('92271')` and `net.hasNode('mrt:Marine Parade')`.
  - `'MRT neighbours are on the same prefix'`: `net.mrtNext('mrt:Marine Parade', 'TE')` contains `'mrt:Marine Terrace'` and `'mrt:Tanjong Katong'`; `net.mrtNext('mrt:Bukit Panjang', 'BP')` never contains a DT station.
  - `'walk links stay within 250 m'`: every `net.walkLinks('92271')` entry has metres <= 250 and includes `'92279'` (D'Ecosia across the road).
  - `'empty bundles give an empty net'`: `TransitNet.build([], BusRoutes.empty, []).isEmpty`.
- [ ] **Step 2: Run** `cd app && flutter test test/transit_test.dart` — expect FAIL (missing file).
- [ ] **Step 3: Implement** the models and `TransitNet.build` (plus the small read helpers the tests use: `nodeCount`, `hasNode`, `mrtNext(node, prefix)`, `walkLinks(node)` returning `List<(String, double)>`). Route stops missing from `stops` are skipped.
- [ ] **Step 4: Run** the tests — expect PASS. Run `flutter analyze` — no issues.
- [ ] **Step 5: Commit** `git commit -m "Add the transit network built from the bus and MRT bundles"`

### Task 2: The search and the options

**Files:**
- Modify: `app/lib/transit.dart`
- Test: `app/test/transit_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces: `List<TransitOption> transitOptions(TransitNet net, Place from, Place to, {int max = 3})`.

Search (the part the signature does not determine):
```
access = walk from `from` to start nodes (limits above), minutes = walkMinutesTo
for round k in 1..3:
  for each pattern touched by a node improved in round k-1 (or access when k = 1):
    board at the earliest index whose node was improved, ride forward only;
    boarding cost = wait (first bus 5 / later bus 6 / MRT 3; MRT->MRT at same node: rideTransferMinutes);
    each later node: arrival = board time + per-stop minutes × stops; keep if better than best[k][node]
  then relax walk links (one walk only, not after another walk)
end time per node per round = arrival + walkMinutesTo(distance to `to`) for end nodes
```
Keep a parent pointer per (round, node) to rebuild legs. Candidates: every (round, end node) reached; rebuild, then sort by minutes, changes, walkMetres; drop a candidate whose `signature` equals one kept, or whose total exceeds the best by more than 40 min; take `max`. Merge consecutive walk legs. Return `[]` when `distanceMeters(from, to) <= samePlaceMetres` or the net is empty.

- [ ] **Step 1: Write the failing tests:**
  - `'Marine Parade to ST Engineering Hub has a bus option with a change and an MRT option'`: from `Place(kind: PlaceKind.custom, addrLat: 1.3050, addrLng: 103.9085)` to `Place(..., addrLat: 1.3917, addrLng: 103.8480)`: `options.length` is 3; some option has only bus rides and `changes >= 1`; some option has an MRT ride with `service == 'TEL'`; signatures are all different; `options` sorted by `minutes`.
  - `'a trip with a direct bus puts a one-ride option first or second'`: pick a pair from `bus_routes.json` with a known direct service (e.g. two stops 8+ stops apart on 966|1), expect an option with `rides.length == 1` and that service among the first two.
  - `'the same place gives no options'` and `'an empty net gives no options'`: `isEmpty`.
  - `'a ride never goes backwards on a loop'`: every bus leg's `to` comes after `from` in its `routeKey` route.
  - `'legs add up'`: for each option, `legs.fold(minutes)` == `option.minutes`; first leg starts at `from` (walk), last ends at `to` (walk).
  - `'fast enough'`: a `Stopwatch` around `transitOptions` (net already built) < 1500 ms in the test VM.
- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement** `transitOptions` as above, constants as top-level `const`s in `transit.dart` (`transferWalkMetres`, `firstBusWaitMinutes`, `busChangeWaitMinutes`, `mrtWaitMinutes`).
- [ ] **Step 4: Run** tests and `flutter analyze` — expect PASS / no issues.
- [ ] **Step 5: Commit** `git commit -m "Find up to three bus, MRT and walking options on the phone"`

### Task 3: Docs for the new file

**Files:**
- Modify: `app/CLAUDE.md` (feature map, Routines bullet: one sentence on `transit.dart`, `TransitNet`, `transitOptions`, not used by the UI yet)
- Regenerate: `docs/REPO_MAP.md`, every `AGENTS.md`

- [ ] **Step 1:** Edit `app/CLAUDE.md`, run `python3 scripts/repo_map.py`, then `python3 scripts/repo_map.py --check` — expect exit 0.
- [ ] **Step 2: Run** `cd app && flutter test` — all pass.
- [ ] **Step 3: Commit** `git commit -m "Map the transit router in the docs"`, push `ccr-d153196a-k68rlw`.
