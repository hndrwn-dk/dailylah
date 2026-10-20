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

## App structure (Phase 1)
- `lib/models.dart` and `lib/logic.dart` are pure Dart (no Flutter, no I/O) so the
  WorkManager isolate can use them. Put parsing and decision rules there, with tests in
  `test/logic_test.dart`.
- `lib/providers.dart` holds all Riverpod providers; widgets in `lib/ui/` only render.
- Favourites are stored with SharedPreferences (`lib/store.dart`). Drift is planned for
  Phase 2 when HDB/hawker data needs local queries.
- Alerts in Phase 1 run on-device: WorkManager every 15 min (`lib/background.dart`) calls
  the API and shows local notifications. FCM topics come later; keep the alert rules
  (quiet hours, one per event, max 3 rain alerts a day) in `logic.dart` either way.
- The offline bus stop list comes from `/data/manifest.json` + `bus_stops.json` on
  `https://dailylah.tursinalabs.com`, falling back to `https://dailylah-web.vercel.app`
  (same Vercel deployment). Never hard-code a single host; use `webUrls` in `lib/api.dart`.
  The list is rebuilt daily by `.github/workflows/data.yml` (needs repo secret `LTA_ACCOUNT_KEY`).
- CI builds a debug APK, so native changes (manifest, Kotlin widget) are compile-checked.

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
