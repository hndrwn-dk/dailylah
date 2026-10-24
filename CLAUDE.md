# DailyLah — guide for AI coding agents

Read `docs/PRD.md` first. It is the source of truth for scope, phases and constraints.
Product: free Android app (Flutter) for Singapore residents. Daily morning/evening cards
built from data.gov.sg (NEA, HDB, CEA) and LTA DataMall. Tourist mode is out of scope.

## App identity (permanent — never change)
- Android `applicationId` and `namespace`: `com.tursinalabs.dailylah`
- iOS bundle identifier: `com.tursinalabs.dailylah`
- Dart package name: `dailylah`. Display name: `DailyLah`.
- Generate platform folders only with:
  `cd app && flutter create . --org com.tursinalabs --project-name dailylah --platforms android,ios`
- `scripts/check-app-id.sh` enforces this in CI. Do not rename the package or the folders.

## Repo layout
- `backend/` — Python 3.12, FastAPI. Deployed to Render (free) via `render.yaml`.
- `app/` — Flutter app (Riverpod, dio). Platform folders are generated with `flutter create`.
- `web/` — static site on Vercel: landing page, privacy policy, static data bundles in `web/data/`.
- `docs/PRD.md` — product requirements (Bahasa Indonesia).
- `scripts/` — one-off ops scripts (QStash schedule).

## App structure
- `lib/models.dart`, `lib/data.dart` (bundle models), `lib/logic.dart` and `lib/l10n.dart`
  (strings, class `S`) are pure Dart (no Flutter, no I/O) so the WorkManager isolate
  can use them. Put parsing and decision rules there, with tests in `test/logic_test.dart`.
  The app is English only; every user-facing string still goes through `S`.
- Religion-neutral by default: no onboarding question about religion. Faith-specific
  features (MUIS prayer times, halal food from the `halal.json` bundle built from Muslim.sg
  listings) are opt-in under More > Extras. Halal screens always say "Not affiliated with MUIS.
  Always verify halal status directly" (`S.halalDisclaimer`).
- `lib/providers.dart` holds all Riverpod providers; widgets in `lib/ui/` only render.
- UI: `ui/shell.dart` (tabs Today / Nearby / Home / More), `ui/theme.dart` (design tokens
  in `DL`, fonts Plus Jakarta Sans + Barlow Condensed in `assets/fonts/`), `ui/widgets.dart`
  (Panel, HeroHeader, BusPlate, PillRow, BentoTile...). Keep the sticker style: ink outlines
  and hard offset shadows (`Panel`), not soft Material cards. Signature elements (see `DL`):
  bus plates and the LED `BusBoard` for live arrivals, MRT `StationChip`/`LineChip` in official
  colours, `PaintedBlockNumber` as the Home hero, amber = look now / teal = go and nothing else.
  Layouts must hold at 200% system
  text (wrap, never fixed widths for text); secondary text keeps 4.5:1 contrast (`DL.mist`).
- Routines: each place has travel modes (`Place.modes`, first = default) and custom places a
  `when`; work/school places carry their own `days` and `go`/`back` times (`commutePlace`,
  `commuteTimes` in logic.dart). MRT: all lines show on Today; `Favorites.lines` are the
  starred ones (max 3), and alerts cover every line when none is starred (`watchedLines`). Today shows the commute trip
  (`TripSection` in `ui/trip.dart`) and a "Go somewhere" picker. "Buses to X" uses the
  `bus_routes.json` bundle (`directRides` in logic.dart; trip start stops are filtered to the
  side of the road with a direct bus, or nearby stops with one are suggested, `tripStops`;
  loop services that go the long way are dropped, `tripRides`). Bus/MRT also shows the nearest MRT
  station at each end from the `mrt_stations.json` bundle (`mrtPlan`). "Go somewhere" picks a
  start (home/work/school/here) and a destination (saved places or a searched address); driving uses `/v1/parking`
  (lot type C/Y) and `/v1/traffic-incidents`.
- Favourites, custom places, watched/compared blocks and extras are stored with SharedPreferences
  (`lib/store.dart`). Family share is a `DL1:` code built on-device (`encodeShareCode`).
- Alerts run on-device: WorkManager every 15 min (`lib/background.dart`) calls the API and
  reads the cached bundles, then shows local notifications. Keep the alert rules (quiet
  hours, one per event, max 3 rain alerts a day) in `logic.dart` / `AlertLog`.
- Static bundles (`/data/manifest.json` + `<name>.json`) come from
  `https://dailylah.sg`, falling back to `https://dailylah.tursinalabs.com` and `https://dailylah-web.vercel.app`
  (same Vercel deployment). Never hard-code a single host; use `webUrls` in `lib/api.dart`.
  `backend/app/build_static.py` + `backend/app/bundles.py` build them daily in
  `.github/workflows/data.yml` (secret `LTA_ACCOUNT_KEY`, optional `DATAGOV_API_KEY`).
  OneMap geocodes are cached in `backend/data/geocode.json` (committed by the workflow).
  Optional bundles are best effort: a failing upstream keeps yesterday's file.
- Nearby (`ui/nearby.dart`) is "I am here now": starts on Here, chips for one section at a time
  (`nearbySectionProvider`: bus, eat, park, taxi, prayer, help). Eat offers GrabFood/foodpanda only
  when it rains, the air is unhealthy or the nearest hawker is closed (`orderInReason`).
- Trip extras (`ui/trip.dart`, rules in logic.dart): Plan B when the trip's MRT line is disrupted
  (`planDisruption`), "Leave in N min" (`leaveBy`, plus one background reminder), weather tips per
  mode (`tripAdvice`), "Wake me at my stop" (`ui/wake.dart`, `wakeRadius`; foreground location only
  while it runs, never stored).
- Habits (`Habits` in models.dart, `HabitsStore` in store.dart, `habitsProvider`): parked car, trips
  logged with I'm leaving/Arrived (`tripStats`), "Ate here" meals (`mealNudge`). On the phone only,
  behind `Favorites.learnHabits`, never in the share code. Weekly Sunday digest (`weeklyDigest`)
  uses the `holidays.json` bundle (MOM public holidays). `school_holidays.json` (MOE, kept by hand,
  see web/data/README.md) turns off the school trip and its reminder on school holidays. Custom
  places can carry a usual time (`Place.go`) for a leave-by reminder (`extrasDueNow`).
- Weekend card on Today (days without a work/school trip) and Home > Weekend: places (`weekendPicks`)
  and events (`eventsNear`) from `events.json`, built daily by `backend/app/events.py` from
  Eventfinda (secrets `EVENTFINDA_USER`/`EVENTFINDA_PASSWORD`) and Eventbrite organizers listed in
  `backend/data/eventbrite_organizers.json` (secret `EVENTBRITE_TOKEN`; no public search). Keys stay
  in CI; each event links to its source page with attribution.
- Home tab (`ui/home.dart`) is about the saved home, one section at a time (chips under the hero,
  `homeSectionProvider`): its HDB block (`homeBlock`) or private project (`private_homes.json` from
  URA, `privateProjectFor`; backend `app/ura.py`, secret `URA_ACCESS_KEY`), upgrading and
  works (`around.json` bundle from OneMap themes, `projectsNear`), schools, health, community,
  recycling, weekend, parking; block search is `BlockSearchPage`. HDB data is computed on the
  phone from bundles; only CEA lookups hit the API.
- OneMap needs a token: the backend (`app/onemap.py`) logs in with `ONEMAP_EMAIL` /
  `ONEMAP_PASSWORD` (Render env and GitHub secrets) and renews it; the app searches via
  `/v1/search`. Never put OneMap credentials or tokens in the app.
- CI builds an APK (release, signed with the upload key from secrets `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`; debug without them),
  so native changes (manifest, Kotlin widget, `dailylah/apps` channel) are compile-checked.
  Analyze and test failures are emitted as annotations on the commit.

## Commands
- Backend: `cd backend && pip install -r requirements-dev.txt && pytest && ruff check . && ruff format --check .`
- Run API locally: `cd backend && cp .env.example .env && uvicorn app.main:app --reload`
- Trigger a poll locally: `curl -X POST localhost:8000/internal/poll`
- App: `cd app && flutter pub get && flutter analyze && flutter test`
- Run app against local API (Android emulator): `flutter run --dart-define=API_URL=http://10.0.2.2:8000`

## Hard rules (free-tier budget — read before adding features)
- Upstash Redis free = 500K commands/month. Serve reads from in-process memory; write to
  Redis only when content changed (`Cache.set` already does this). Never call Redis per request
  in a hot path without memory caching first.
- QStash free = 1,000 messages/day, max 10 schedules. One schedule (`*/2 * * * *`) calls
  `/internal/poll`; per-dataset intervals live in `backend/app/sources.py`. Do not add schedules.
- Bus arrival is fetched on demand per stop with a short memory TTL. Never poll all stops.
- Neon free = 0.5 GB, 100 CU-hours, sleeps after 5 min idle. Use it for static/spatial data only;
  the poller must not write to Neon every cycle.
- Render free sleeps after 15 min without traffic and has an ephemeral filesystem. No local state.
- Vercel Hobby cron runs once per day only. Daily data rebuilds run in GitHub Actions.

## Privacy rules
- Published policy and terms: https://www.tursinalabs.com/dailylah/privacy and /terms.
  Source text lives in `docs/legal/`. Any change to what data the app or server handles
  (new permission, SDK, endpoint, log field) must update `docs/legal/privacy.md` in the same PR.
- User locations and favourites stay on the device. The server only sees stop codes and FCM topics.
- No accounts, no identifying analytics.
- Secrets only via env vars. Never commit `.env`, API keys, or keystores.

## API conventions
- Public endpoints under `/v1/*`, read-only, return `{"fetched_at": <unix>, "data": <upstream>}`.
- `/internal/*` endpoints require a valid `Upstash-Signature` (QStash) outside `ENV=dev`.
- Upstream headers: data.gov.sg uses `x-api-key` (optional, higher limits); LTA uses `AccountKey`.
- Every new endpoint gets a pytest test with `respx` mocks; no real network calls in tests.

## Style
- Python: ruff (line length 100), type hints, async httpx.
- Dart: flutter_lints, Riverpod providers, no business logic in widgets.
- Commit messages in English, imperative mood.
