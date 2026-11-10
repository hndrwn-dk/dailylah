# DailyLah: deploy and secrets

How the hosted parts of DailyLah are set up. The app itself ships through GitHub Actions to
Google Play (docs/QA.md); this page covers the backend, the website and the data workflow.

## Services

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
6. **Data bundles**: add the repo secrets `LTA_ACCOUNT_KEY`, `ONEMAP_EMAIL` and `ONEMAP_PASSWORD`
   (`DATAGOV_API_KEY` and `GEOAPIFY_API_KEY` are optional; see the header of `data.yml`). The push
   job also needs the `data-push` environment with its deploy key `DATA_PUSH_SSH_KEY`, set up as in
   [`docs/HANDOFF.md`](HANDOFF.md). Then run the `data` workflow once (Actions > data > Run
   workflow). After that it runs daily.

## Secrets

Backend env vars (see [`backend/.env.example`](../backend/.env.example)):

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

Never commit `.env`, API keys or keystores. In CI, the data build keys are repo secrets; the
signing, Play and data-push keys live in their own GitHub environments (`signing`, `play`,
`play-production`, `data-push`). See "CI security" in [`CLAUDE.md`](../CLAUDE.md).
