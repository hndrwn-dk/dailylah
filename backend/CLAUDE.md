# DailyLah backend (FastAPI) and data pipeline — guide for AI coding agents

Read the root `CLAUDE.md` first (identity, privacy, CI security, Git workflow). Paths below are
relative to `backend/` when they start with `app/`. Endpoint index: `docs/REPO_MAP.md`.

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

## API conventions
- Public endpoints under `/v1/*`, read-only, return `{"fetched_at": <unix>, "data": <upstream>}`.
- `/internal/*` endpoints require a valid `Upstash-Signature` (QStash) outside `ENV=dev`.
- Upstream headers: data.gov.sg uses `x-api-key` (optional, higher limits); LTA uses `AccountKey`.
- Geoapify (`app/geoapify.py`, env `GEOAPIFY_API_KEY`, Render only, never in the app): `/v1/places`
  searches place names for Plan a trip (Autocomplete, `filter=countrycode:sg`, no location bias),
  cuts each answer down to name, address, postal, lat, lng and type, and keeps it in memory only
  (`places_ttl`). Geoapify takes the key in the URL, so errors are re-raised as `GeoapifyError`
  without the httpx exception and the httpx request log line is redacted (key and typed text).
  No key: 503; Geoapify error, timeout or 429: 502. The app then searches OneMap instead.
  The Geoapify account (Free plan, 3,000 credits a day, 5 requests a second; DailyLah's key is
  capped at 2,000 a day) is shared with another app, so a call that is not cached first passes
  four guards (`app/limits.py`): a pause after Geoapify refuses (`Breaker`: 60 s after 429,
  10 min after 401/403), a per-second cap (`RateGate`, `places_per_second` = 4), one client's
  share (`places_client_limit` = 60 per `places_client_window` = 3,600 s) and a daily budget
  (`places_daily_budget` = 1,900 per UTC day, below the key's cap so the daily data build keeps
  credits). A client over its share gets 429 with `Retry-After`; the other guards answer 503.
  - The client is `client_address`: Cloudflare's `CF-Connecting-IP` (Render serves every request
    through Cloudflare, which overwrites it), else the last public `X-Forwarded-For` entry, else
    the socket peer; IPv6 by /64. Never read an `X-Forwarded-For` entry further left: the client
    writes those. Uvicorn's own proxy handling stays off (it trusts 127.0.0.1 only), so
    `request.client` and the access log show Render's proxy.
  - Counts are Redis INCRs with an expiry (`Cache.incr_shared`): the client's under a keyed hash
    of the address (`client_key`, never the address) for one window, the day's for two days.
    A client over its share is remembered in memory (`Blocked`) and a spent day in
    `places_spent_day`, so neither costs further Redis commands.
  - No shared count (Redis off, failing, or failed in the last minute): the day's calls count in
    memory against `places_memory_budget` = 50 instead of the full budget, because a memory
    count starts again at every restart.
  - `PLACES_DAILY_BUDGET`, `PLACES_MEMORY_BUDGET`, `PLACES_PER_SECOND`, `PLACES_CLIENT_LIMIT` and
    `PLACES_CLIENT_WINDOW` on Render change them without a code change. Keep
    `places_client_limit * 86400 / places_client_window` below `places_daily_budget`, and
    `places_daily_budget + places_memory_budget` below the key's cap, with room for the data
    build (about 30 credits a run).
- Uvicorn's access log goes through `_RedactAccessLog` (`app/main.py`, installed at import and at
  startup): it keeps client, method, endpoint and status, drops every query string and shows
  `/v1/bus-arrival/*`, `/v1/ev/*` and `/v1/agent/*` without the code. A new endpoint that takes
  user input in its path adds itself to `_PRIVATE_PATH` (`tests/test_access_log.py`).
- `/v1/trip-extras?mode=&lat=&lng=` (`app/trip_extras.py`): LTA details for one mode of a planned
  trip near one point, as a short filtered list (never the dataset). `car`/`motorcycle`: the
  nearest 3 car parks within 1 km with lot type C/Y, from the polled `lta:parking`; `taxi`: free
  taxis within 500 m, from the polled `lta:taxi`; `bicycle`: the nearest 3 within 500 m from LTA
  `BicycleParkingv2` (`Lat`, `Long`, `Dist`, 500 a page), which LTA answers per location, so it is
  asked per 0.01 degree cell (`area`, radius `BICYCLE_DIST_KM`) and kept in memory for a day
  (`bicycle_per_second` new cells a second, else 503). One endpoint, not one per mode: same
  input, checks and privacy rule. `fetched_at` is when LTA's data was read ("as of"). The point
  is rounded to 4 decimals, must be in Singapore (422), and is never logged or used as a cache
  key; the httpx request log masks `Lat`/`Long` (`_RedactArea`). The app never sends the phone's
  own position here (app `tripExtrasProvider`).
- Every new endpoint gets a pytest test with `respx` mocks; no real network calls in tests.
- Every `/v1/*` endpoint has an example in `contracts/v1/` (request, upstream, response), checked by
  `tests/test_contracts.py` and by the app's `test/contract_test.dart`. A new endpoint adds one and
  its `UPSTREAM` entry; a changed response rewrites them with
  `UPDATE_CONTRACTS=1 pytest tests/test_contracts.py` and updates the app parser in the same PR
  (docs/QA.md "Contract tests").

## Data pipeline
- Static bundles (`/data/manifest.json` + `<name>.json`) come from
  `https://dailylah.sg`, falling back to `https://dailylah.tursinalabs.com` and `https://dailylah-web.vercel.app`
  (same Vercel deployment). Never hard-code a single host; use `webUrls` in `lib/api.dart`.
  `backend/app/build_static.py` + `backend/app/bundles.py` build them daily in
  `.github/workflows/data.yml` (secret `LTA_ACCOUNT_KEY`, optional `DATAGOV_API_KEY`,
  `GEOAPIFY_API_KEY` for `toilets.json`).
  data.gov.sg keys expire: every data.gov.sg call goes through `DataGovKey` (`app/datagov.py`),
  which retries without the key on 401/403 and logs a warning; the data workflow then fails
  its last step ("Check data.gov.sg key") so the expiry is visible. Renew it in both GitHub and Render.
  OneMap geocodes are cached in `backend/data/geocode.json` (committed by the workflow).
  Optional bundles are best effort: a failing upstream keeps yesterday's file.
  On the phone `BundleRepository.load` runs one load per bundle at a time, saves a download only when
  it is valid JSON (temp file + rename) and re-downloads a saved copy that does not decode.
- "Where to live?" (dailylah.sg page): `app/where_to_live.py` builds
  `web/data/where-to-live.json` weekly in `.github/workflows/where-to-live.yml` from the HDB quarterly
  median rent and resale datasets and OneMap transit routes (weekday 08:30) from 26 town centres to
  6 office areas (`backend/data/where_to_live_points.json`). Routes are cached for 30 days in
  `backend/data/where_to_live_routes.json`; a town that is itself the office area gets
  `{"min": null, "transfers": null, "same_area": true}`. The website and the app both read it; the
  daily `build_static.py` lists it in the manifest like every bundle, so after a Monday update the
  app sees it with the next daily run. `generated_at` only changes
  when the data does; `--dry-run` prints the report and writes nothing. Each route keeps OneMap's
  adult card `fare` in cents (null when OneMap gives none). `app/where_to_live_pages.py` then
  writes the "Living in <town>" pages to `web/where-to-live-towns/` (served at
  `/where-to-live/<id>` and `/where-to-live/towns` by rewrites in `web/vercel.json`) and
  `web/sitemap.xml`; every JSON value goes through `html.escape`, and files are only rewritten when
  their content changed. The build job's patch may change only the two JSON files (each must parse
  as a JSON object or array); the push job runs main's own `where_to_live_pages.py` with the
  runner's `python3` (stdlib, no pip) on the patched main and commits only `*.html` in that folder
  and the sitemap (`scripts/push_data.sh --generate/--generated`). Each town page's `og:image` is a
  static PNG in `web/og/where-to-live/` made by hand with `scripts/build_og_images.py` (Pillow, a
  dev tool, not in the requirements) and committed; a new town needs that script run.
- Toilets ("Need a toilet?"): `build_toilets` in `app/bundles.py` makes
  `toilets.json` in the daily `data.yml` from Geoapify Places (`/v2/places`,
  `categories=amenity.toilet`, Singapore rect, 500 a page until a short or empty page, max 20
  pages), the NParks park toilets that `build_poi` finds in Park Facilities
  (`park_toilet_points`, `LAST_PARK_TOILETS`; yesterday's park toilets when NParks fails) and every hawker centre (yesterday's
  `hawkers.json` when today's hawker build failed). Points closer than 30 m are one toilet
  (`merge_toilets`: clearest name, a specific kind wins over "other"); each has a kind `k`
  (`toilet_kind`: mall, station, hawker, park, other, from the name, then Geoapify's categories).
  Format `[{"n","la","lo","k"}]`. The key is the GitHub secret `GEOAPIFY_API_KEY` (CI only for
  this bundle, never in the app); without it, or when Geoapify fails, the previous file stays.
  Geoapify takes the key in the URL, so errors are raised without the httpx exception and the
  httpx request log line is redacted (`app/geoapify.py`, imported by `bundles.py`). Places is
  billed by places returned: a full run is 2 requests a day under DailyLah's 2,000-credit daily
  cap, which `/v1/places` shares and stays below (`places_daily_budget`; the account allows 3,000, the rest is Prayer Cast). Data is OpenStreetMap (ODbL): the app
  shows "Powered by Geoapify · © OpenStreetMap contributors" with it.
- OneMap needs a token: the backend (`app/onemap.py`) logs in with `ONEMAP_EMAIL` /
  `ONEMAP_PASSWORD` (Render env and GitHub secrets) and renews it; the app searches via
  `/v1/search`. Never put OneMap credentials or tokens in the app.
