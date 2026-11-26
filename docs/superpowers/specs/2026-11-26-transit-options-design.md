# Transit options: bus, MRT and walking combined, worked out on the phone

## Why
A trip from Marine Parade to ST Engineering Hub showed only the MRT route and two "No direct bus
from this stop" cards. Google Maps offered 966 > 857 from Opp D'Ecosia. Root cause: the bus side
only knows direct rides (`directRides`, `tripRides`); when no stop within 500 m has one,
`tripStops` falls back to the two nearest stops, so D'Ecosia, Opp D'Ecosia, Tao Nan Sch and CHIJ
Katong were found and then dropped. The owner wants options as rich as Google Maps: bus with
changes, MRT then bus, bus then MRT, with walks between.

## Goals
- Up to 3 options on a Bus/MRT trip, each a door-to-door itinerary: walk, legs (bus or MRT),
  changes with the walk between stops, walk at the end, an estimated total in minutes.
- The 3 differ for real: no two with the same sequence of services/lines (a stop on the other
  side of the road is the same option).
- Option 1 open in full; options 2 and 3 as one-line summaries (`walk 5 > 55 > 854 > walk 3 ·
  ~52 min`) that open on tap.
- The first bus of an option keeps live arrivals (the existing board, "Leave in N min").
- Start stops shown on the bus cards follow the options (D'Ecosia when the best option leaves
  from there), not just the two nearest stops.

## Non-goals
- Timetables: LTA publishes none for buses or trains. Times after the first bus are estimates.
- Live arrivals for the second and later buses (could come later).
- Fares per option (History keeps its estimate).
- Routing in the background pass (leave-by alerts keep today's direct rules in this work).

## Anti-goals
- Sending the phone's position, or any trip end, to the server for routing. Everything is
  computed on the phone from the bundles it already has (`bus_routes.json`, `bus_stops.json`,
  `mrt_stations.json`).
- A slow planner: routing must not freeze the UI.

## Approaches
- A. Router on the phone (picked by the owner): a round-based search over bus routes, MRT lines
  and short walks, at most 2 changes. Private, works when the server is slow, free; times are
  estimates.
- B. OneMap public transport routing via our server: closest to Google, but the start (often
  the phone's position) would go to the server, which the privacy rules forbid; quota limits.
- C. Bus with one change only: small, but no MRT + bus combinations.

## Design (A)
- `logic.dart` (pure Dart, so tests and the background isolate can use it):
  - `TransitNet` built once from the bundles: bus patterns (route key > ordered stops with km),
    MRT lines (stations in code order per line prefix, branches kept apart as `mrtLeg` does),
    and walk links between stops/stations within `transferWalkMetres` (250 m).
  - `transitOptions(net, from, to)`: start points = stops and stations within 500 m (stations
    1200 m, like `mrtPlan`); end points = within 400 m of `to` (stations 1200 m). Round-based
    search (RAPTOR style), rounds = rides, max 3 rides (2 changes). Cost in minutes:
    walk `walkMinutesTo`, bus `feederMinutesPerStop` a stop, MRT `rideMinutesPerStop` a stop,
    a change `rideTransferMinutes` plus walk, first wait from live data when shown (else a fixed
    estimate), later bus waits a fixed estimate (`busChangeWaitMinutes`, 6).
  - Keep the best by minutes, then fewer changes, then less walking; drop options whose ride
    sequence repeats one kept; drop loop detours as `tripRides` does; max 3.
  - Model: `TransitOption` (legs, minutes, changes, walk metres), `TransitLeg` (walk | bus |
    mrt; board, alight, service or line, stops).
  - Direct bus and the current MRT plan stay valid answers: they come out of the same search.
- Providers: `transitOptionsProvider` (family on the trip ends), run with `compute` off the UI
  thread; the net is cached for the app's life.
- UI (`ui/trip.dart`): the Bus/MRT mode shows `_TransitOptions`: option 1 drawn with the
  existing route line (`_RouteStep` style: bus legs as `BusPlate`, MRT legs in line colours),
  its first bus card with live board; options 2-3 as summary rows. "I'm leaving", Bus arriving
  and Wake me use the open option's first bus leg. The MRT card and "Change line" stay as they
  are for an all-MRT option.
- Text through `S`; tap targets 48 dp; holds at 200% text and 320 dp (summary rows wrap).

## Phases (one PR each, on the session branch)
1. Router core: `TransitNet`, `transitOptions`, models, tests in `test/logic_test.dart` with
   real bundles (`FileBundles`): Marine Parade > ST Engineering Hub gives a bus-with-change
   option and an MRT option; a trip with a direct bus still puts it first. No UI change.
2. UI: options on the planner and Today trip, start stops from the options, provider in an
   isolate, `features_test`, screens matrix, goldens if Today changes, Maestro flow 09.
3. Finish: privacy policy section 5 ("which buses go to your destination" becomes the bus and
   train options, with changes, worked out on the phone), landing page privacy answers if they
   no longer match, feature map, `REPO_MAP.md`/`AGENTS.md`, release bump (minor) with What's new.

## Left to the builder
- Exact wait and speed constants (start from the existing ones above).
- How MRT stations join bus stops (walk links by distance).
- Performance budget: target under 300 ms on a mid phone in an isolate; precompute stop
  indexes in the net.

## Owner's decisions
- Approach A; max 3 options; privacy text updated; work in phases because of usage limits.
- Side note: Render is now the paid Starter plan ($7, no sleep). `backend/CLAUDE.md` still says
  "Render free sleeps"; that is a separate docs change, not part of this work.
