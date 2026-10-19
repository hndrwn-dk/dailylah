# DailyLah

Your daily SG kaki. A free Flutter app that turns Singapore open data (data.gov.sg and
LTA DataMall) into one morning card, one evening card, and only the alerts that matter.

- Product requirements: [`docs/PRD.md`](docs/PRD.md)
- Guide for AI coding agents: [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md)

## Stack
| Part | Tech | Hosting (free tier) |
| --- | --- | --- |
| App | Flutter, Riverpod, dio | Google Play |
| API | Python 3.12, FastAPI | Render |
| Poll scheduler | Upstash QStash | Upstash |
| Real-time cache | Upstash Redis | Upstash |
| Static + spatial data | PostgreSQL + PostGIS | Neon |
| Landing, privacy, data bundles | Static HTML/JSON | Vercel |
| Push | Firebase Cloud Messaging | Firebase |

## Quick start

### Backend
```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env        # fill DATAGOV_API_KEY and LTA_ACCOUNT_KEY
pytest
uvicorn app.main:app --reload
curl -X POST localhost:8000/internal/poll
curl localhost:8000/v1/weather/forecast
```

### App
```bash
cd app
flutter create . --org com.tursinalabs --project-name dailylah --platforms android,ios
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

## Deploy
1. **Render**: New > Blueprint > pick this repo (uses `render.yaml`). Set the secret env vars.
2. **Upstash**: create a Redis database (Singapore region if available) → set `REDIS_URL`.
   In QStash, copy the signing keys → set `QSTASH_CURRENT_SIGNING_KEY` and `QSTASH_NEXT_SIGNING_KEY`.
3. **Schedule the poller** once Render is live:
   `QSTASH_TOKEN=... API_URL=https://<your-service>.onrender.com ./scripts/create-qstash-schedule.sh`
4. **Neon**: create a project, enable PostGIS (`CREATE EXTENSION postgis;`) → set `DATABASE_URL`.
5. **Vercel**: import the repo, set Root Directory to `web`, no build command.

## Secrets
| Env var | Where to get it |
| --- | --- |
| `DATAGOV_API_KEY` | data.gov.sg developer portal |
| `LTA_ACCOUNT_KEY` | LTA DataMall account |
| `REDIS_URL` | Upstash Redis console |
| `QSTASH_*_SIGNING_KEY` | Upstash QStash console |
| `DATABASE_URL` | Neon console |
| `PUBLIC_BASE_URL` | Your Render service URL |

Data from data.gov.sg and LTA DataMall. Not affiliated with the Singapore Government. A Tursina Labs project.
