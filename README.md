# DailyLah

<img src="docs/marketing/icon-512.png" width="96" alt="DailyLah app icon">

Know before you go lah. DailyLah is a free Android app for people living in Singapore. It turns
open data from data.gov.sg and LTA DataMall into one morning card, one evening card, and only the
alerts that matter: the next buses at your stops, MRT disruptions, rain before you leave, and
what is around your HDB block.

No account, no tracking. Saved places stay on the phone, and alerts are made on the device.

**Status:** closed testing on Google Play since 26 Oct 2026. Website: [dailylah.sg](https://dailylah.sg).

<p>
  <img src="docs/store/screenshots/01-today.png" width="180" alt="Today tab with the morning card">
  <img src="docs/store/screenshots/03-planb.png" width="180" alt="Plan B buses when an MRT line is disrupted">
  <img src="docs/store/screenshots/05-home.png" width="180" alt="Home tab: facts about your HDB block">
  <img src="docs/store/screenshots/07-weekend.png" width="180" alt="Parks and events near your block for the weekend">
</p>

## Repository layout

| Path | What it holds |
| --- | --- |
| `app/` | Flutter app (Riverpod, dio), released on Android |
| `backend/` | Python 3.12 FastAPI service that polls the upstream APIs |
| `web/` | Static site on Vercel: landing page, "Where to live?", data bundles |
| `contracts/v1/` | One example per `/v1/*` endpoint, checked by both app and backend tests |
| `docs/` | Product requirements, QA and release process, legal text, store assets |
| `scripts/` | Ops scripts: app ID check, release signing, data push, repo map |
| `.github/workflows/` | CI/CD: tests, emulator runs, security scans, Play upload, daily data |

## Documentation

| Read this | For |
| --- | --- |
| [`docs/PRD.md`](docs/PRD.md) | Scope, phases and constraints (Bahasa Indonesia) |
| [`docs/QA.md`](docs/QA.md) | Every test layer, required checks, security scans, and how a release ships |
| [`docs/REPO_MAP.md`](docs/REPO_MAP.md) | Every file in `app/lib`, every provider and endpoint (generated) |
| [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md) | Rules for AI coding agents, plus [`app/CLAUDE.md`](app/CLAUDE.md) and [`backend/CLAUDE.md`](backend/CLAUDE.md) |
| [`docs/legal/`](docs/legal/) | Source of the published privacy policy and terms |

## Stack

| Part | Tech | Hosting (free tier) |
| --- | --- | --- |
| App | Flutter, Riverpod, dio | Google Play |
| API | Python 3.12, FastAPI | Render |
| Poll scheduler | Upstash QStash | Upstash |
| Real-time cache | Upstash Redis | Upstash |
| Static and spatial data | PostgreSQL + PostGIS | Neon |
| Website, data bundles | Static HTML/JSON, no build step | Vercel |
| Alerts | On-device (WorkManager, local notifications) | none |

Upstream data: data.gov.sg (NEA, HDB, CEA), LTA DataMall, OneMap, URA and Geoapify.

## Quick start

### Backend

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env        # fill in the keys (see Secrets below)
pytest && ruff check . && ruff format --check .
uvicorn app.main:app --reload
curl -X POST localhost:8000/internal/poll
curl localhost:8000/v1/weather/forecast
```

### App

The platform folders are committed, so there is nothing to generate.

```bash
cd app
flutter pub get --enforce-lockfile
flutter analyze && flutter test
flutter run --dart-define=API_URL=http://10.0.2.2:8000   # Android emulator → local API
```

App ID (Android and iOS) is **`com.tursinalabs.dailylah`** and is permanent.
`scripts/check-app-id.sh` enforces it in CI. If the platform folders ever need regenerating, use
only the `flutter create` command in [`CLAUDE.md`](CLAUDE.md).

### Web

```bash
node --test 'web/tests/*.test.mjs'          # Node 22, no packages
```

The 360 px layout test in a real browser is in [`CLAUDE.md`](CLAUDE.md) under Commands.

## How a release ships

Every pull request runs the app tests (including a screen matrix, golden images and API
contracts), emulator tests on Android 10, 15 and 16, and security scans (CodeQL, osv-scanner,
zizmor). Nine of these are required checks on `main`.

A push to `main` that raises `version:` in `app/pubspec.yaml` becomes a release:

1. The AAB is built without signing keys, then signed in a separate job.
2. That signed AAB is tested again: an upgrade from the last release tag, the R8 release build,
   and 10 Maestro flows.
3. It is uploaded to closed testing on Google Play, and the commit is tagged `v<version>`.

Production is a manual run that needs approval and arrives in Play Console as a draft. The full
process, including the checklist before production, is in [`docs/QA.md`](docs/QA.md).

## Deploy

1. **Render**: New > Blueprint > pick this repo (uses `render.yaml`). Set the secret env vars.
2. **Upstash**: create a Redis database (Singapore region if available) and set `REDIS_URL`.
   In QStash, copy the signing keys into `QSTASH_CURRENT_SIGNING_KEY` and `QSTASH_NEXT_SIGNING_KEY`.
3. **Schedule the poller** once Render is live:
   `QSTASH_TOKEN=... API_URL=https://<your-service>.onrender.com ./scripts/create-qstash-schedule.sh`
4. **Neon**: create a project, enable PostGIS (`CREATE EXTENSION postgis;`) and set `DATABASE_URL`.
5. **Vercel**: import the repo, set Root Directory to `web`, no build command. The app tries
   `https://dailylah.sg`, then `https://dailylah.tursinalabs.com`, then
   `https://dailylah-web.vercel.app`. To use a single other host, build with
   `--dart-define=WEB_URL=https://<host>`.
6. **Bus stop bundle**: add the repo secret `LTA_ACCOUNT_KEY`, then run the `data` workflow once
   (Actions > data > Run workflow). After that it runs daily.

## Secrets

Backend env vars (see [`backend/.env.example`](backend/.env.example)):

| Env var | Where to get it |
| --- | --- |
| `DATAGOV_API_KEY` | data.gov.sg developer portal |
| `LTA_ACCOUNT_KEY` | LTA DataMall account |
| `ONEMAP_EMAIL`, `ONEMAP_PASSWORD` | OneMap API registration |
| `URA_ACCESS_KEY` | URA Data Service |
| `GEOAPIFY_API_KEY` | Geoapify dashboard (backend only, never in the app) |
| `REDIS_URL` | Upstash Redis console |
| `QSTASH_*_SIGNING_KEY` | Upstash QStash console |
| `DATABASE_URL` | Neon console |
| `PUBLIC_BASE_URL` | Your Render service URL |

Never commit `.env`, API keys or keystores. CI secrets live in GitHub environments (`signing`,
`play`, `play-production`, `data-push`); see "CI security" in [`CLAUDE.md`](CLAUDE.md).

## Contributing and security

This is a personal project. Changes go through one pull request per batch, squash-merged into
`main`, using [the PR template](.github/pull_request_template.md).

Found a security issue? Please don't open a public issue. Email support@tursinalabs.com instead.

## Data and license

Data from data.gov.sg, LTA DataMall, OneMap and URA. Not affiliated with the Singapore Government.
A Tursina Labs project.

Copyright (c) 2026 Hendrawan Daryono Karso (Tursina Labs). All rights reserved. The source is public
to read; no licence is granted to use or redistribute it. See [LICENSE](LICENSE).
