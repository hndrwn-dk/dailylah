# DailyLah backend (FastAPI) and data pipeline — guide for AI coding agents (Cursor, Codex, etc.)

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
  `.github/workflows/data.yml` (secret `LTA_ACCOUNT_KEY`, optional `DATAGOV_API_KEY`).
  data.gov.sg keys expire: every data.gov.sg call goes through `DataGovKey` (`app/datagov.py`),
  which retries without the key on 401/403 and logs a warning; the data workflow then fails
  its last step ("Check data.gov.sg key") so the expiry is visible. Renew it in both GitHub and Render.
  OneMap geocodes are cached in `backend/data/geocode.json` (committed by the workflow).
  Optional bundles are best effort: a failing upstream keeps yesterday's file.
  On the phone `BundleRepository.load` runs one load per bundle at a time, saves a download only when
  it is valid JSON (temp file + rename) and re-downloads a saved copy that does not decode.
- OneMap needs a token: the backend (`app/onemap.py`) logs in with `ONEMAP_EMAIL` /
  `ONEMAP_PASSWORD` (Render env and GitHub secrets) and renews it; the app searches via
  `/v1/search`. Never put OneMap credentials or tokens in the app.
