# DailyLah: deploy and secrets

How the hosted parts of DailyLah and the GitHub side of CI are set up. The app ships through
GitHub Actions to Google Play ([QA.md](QA.md)); this page covers the backend, the website, the data
workflow, the release environments and the rulesets.

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
   [Rulesets](#rulesets) below. Then run the `data` workflow once (Actions > data > Run
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
| `PLACES_DAILY_BUDGET` | Optional, default 1,900: place search calls to Geoapify per UTC day. Keep it below the key's daily cap in the Geoapify dashboard (2,000), because the daily data build uses the same key |
| `REDIS_URL` | Upstash Redis console |
| `QSTASH_*_SIGNING_KEY` | Upstash QStash console |
| `DATABASE_URL` | Neon console |
| `PUBLIC_BASE_URL` | Your Render service URL |

Never commit `.env`, API keys or keystores. In CI, the data build keys are repo secrets; the
signing, Play and data-push keys live in their own GitHub environments (`signing`, `play`,
`play-production`, `data-push`); none of them is a repository secret. See "CI security" in [`CLAUDE.md`](../CLAUDE.md).

## Release signing environments
Set up by hand under Settings > Environments, each limited to `main` with no admin bypass:
- `signing`: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD`, and the environment variable `UPLOAD_CERT_SHA256` (checked against
  keytool and Play Console). Its source in Play Console: Protected with Play > Play Store
  protection > Manage Play app signing > Upload key certificate > SHA-256. Do not use the
  "App signing key certificate" on the same page: that is Google's key, and every sign would fail.
- `play`: `PLAY_SERVICE_ACCOUNT_JSON`, the key of the testing service account (testing tracks
  only; uploads from `app.yml`).
- `play-production`: `PLAY_SERVICE_ACCOUNT_JSON`, the key of the production service account (a
  different account, see below), required reviewer: the repo owner (prevent self-review off).
  Used by `promote.yml` and by an `app.yml` run with track `production`.

## Production releases from the phone
One-time settings for docs/QA.md "Production release from the phone". All of them work in a phone
browser (github.com and play.google.com/console; the GitHub mobile app does not show repository
settings).

1. **Version bumps go to closed testing.** GitHub > the repository > Settings > Secrets and
   variables > Actions > Variables tab > New repository variable: Name `PLAY_PUSH_TRACK`, Value
   `alpha`. (See "Release track for a version bump" below to turn it off again.)
2. **Production has a service account of its own.** Environment `play` asks nobody for approval
   and hands its key to the upload action on every closed-testing release, so that account must
   never be able to release to production. Two accounts:
   - The existing one (in `play`): Play Console > Users and permissions > the service account
     (its email ends in `.iam.gserviceaccount.com`) > App permissions > DailyLah. Under Releases
     keep only **"Release apps to testing tracks"**; "Release to production, exclude devices, and
     use Play App Signing" stays **off**. Save changes.
   - A new one, for production only: Google Cloud Console > IAM & Admin > Service accounts >
     Create service account (no project role) > Keys > Add key > JSON. Play Console > Users and
     permissions > Invite new users: its email, App permissions > DailyLah: **"Release to
     production, exclude devices, and use Play App Signing"**, "Release apps to testing tracks"
     and "View app information and download bulk reports (read-only)"; nothing else (no financial
     data, no store presence, no admin). Play Console sometimes renames permissions: pick the one
     in the Releases group that names production.
   - GitHub > Settings > Environments > `play-production` > `PLAY_SERVICE_ACCOUNT_JSON`: replace
     it with the new key file (all of it), then delete the downloaded file. Never paste the key
     in a chat. `play` keeps the old key.
   - Settings > Secrets and variables > Actions > Variables > New repository variable: Name
     `PLAY_TESTING_ACCOUNT`, Value the email of the **existing** (testing) service account. It is
     not a secret. `promote` refuses to run when the production key belongs to that account, and
     warns while the variable is missing.
3. **`play-production` still asks the owner.** Settings > Environments > `play-production`:
   Required reviewers lists the owner, "Prevent self-review" is off (the owner starts the run and
   approves it), Deployment branches is `main` only, "Allow administrators to bypass" is off, and
   the secret `PLAY_SERVICE_ACCOUNT_JSON` is listed.
4. **Check it.** GitHub mobile > Actions > promote > Run workflow on `main` with `dry_run` on.
   The run waits for the approval (a notification; Approve and deploy), then its summary shows
   what `alpha` and production hold, with no warning about `PLAY_TESTING_ACCOUNT`. A permission
   error from Google here means step 2 is not done.

## Release track for a version bump
Repository variable `PLAY_PUSH_TRACK` (Settings > Secrets and variables > Actions > Variables tab)
decides what a version bump on `main` does (docs/QA.md "Manual releases"):
- Not set, or `manual`: build, test, sign, tag `v<version>` and a draft GitHub Release with the AAB,
  mapping and release notes. No Google Play upload; the owner uploads in Play Console by hand.
- `alpha`: the same, and the `play` job uploads to closed testing. Production then follows with
  Actions > promote ("Production releases from the phone" above).
- Switch the automatic upload back on: New repository variable (or edit), Name `PLAY_PUSH_TRACK`,
  Value `alpha`, Add variable. Turn it off again: set it to `manual` or delete it.
- Check it on the next release: the `analyze` job says `Release (manual upload)` or
  `Release ... goes to alpha`, and `upload to Google Play (…)` is skipped or runs.

## Rulesets
Set up by hand: Settings > Rules > Rulesets > New.

**`main`** (New branch ruleset; Enforcement: Active; Target: Include default branch):
1. Restrict deletions; Block force pushes.
2. Require a pull request before merging: required approvals **0** (the owner cannot approve their
   own PR); Allowed merge methods: **Squash** only.
3. Require status checks to pass, "Require branches to be up to date" **off**. Add these, source
   GitHub Actions (names exactly as GitHub shows them; docs/QA.md "Required checks"):
   `app result`, `emulator result`, `backend result`, `web result`, `repo map and AGENTS.md up to date`, `CodeQL (actions)`, `CodeQL (python)`,
   `osv-scanner (dependencies)`, `zizmor (workflows)`.
4. Bypass list: one bypass, Deploy keys (Always). GitHub Actions cannot be a bypass actor on a
   personal repository, so `data.yml` and `where-to-live.yml` build in a read-only job, then a `push` job in environment
   `data-push` applies the patch to the newest `main` and pushes over SSH with
   `scripts/push_data.sh` (GitHub's host key pinned, key file removed after).
   - The key, set up by hand once: create a pair (`ssh-keygen -t ed25519 -f dailylah-data-push
     -N ""`, on a laptop or in Termux); Settings > Deploy keys > Add: the `.pub` file, title
     `data-push`, **Allow write access**; Settings > Environments > New `data-push`: Deployment
     branches `main` only, no admin bypass; Add secret `DATA_PUSH_SSH_KEY` = the private key file
     (all lines, including BEGIN and END); then delete both local key files. Never paste the
     private key in a chat.
   - Check it: Actions > data > Run workflow, then Actions > where-to-live > Run workflow; the
     `push` job must say "Pushed: ..." or the build must say "No data changes".
     `screenshots.yml` never pushes to `main` and `goldens.yml` skips `main`.
5. Do not add yourself as a bypass actor: merges go through PRs like everything else.

**`v*` tags** (New tag ruleset; Enforcement: Active; Target: Include by pattern `v*`):
1. Restrict updates (a release tag never moves); Restrict deletions; Block force pushes.
2. Restrict creations: leave off. `release-tag` creates the tags and GitHub Actions cannot be a
   bypass actor on a personal repository; only the owner and Actions can write to this repository.

After both are on, check: a docs-only PR shows all nine checks green and can be squash-merged;
`git push --force` to `main` and `git push --delete origin v1.9.2` are refused.

## GitHub security settings
Settings > Advanced Security (or Code security):
1. **Secret scanning**: Enable. Then **Push protection**: Enable.
2. **Dependabot alerts**: Enable. **Dependabot security updates**: Enable.
3. **Code scanning**: leave **Default setup** off (or switch it off). `security.yml` is an
   advanced setup, and GitHub rejects its CodeQL uploads while default setup is on.

## Domains
- `dailylah.sg` is the website and the first host for data bundles; `dailylah.tursinalabs.com`
  and `dailylah-web.vercel.app` are fallbacks (same Vercel deployment, `webUrls` in `api.dart`).
- Privacy and terms stay at `tursinalabs.com/dailylah/privacy` and `/terms`;
  `dailylah.sg/privacy` and `/terms` redirect there (`web/vercel.json`).

## Build locally
- App: `cd app && flutter pub get && flutter analyze && flutter test`.
- Release APK:
  - Set `ANDROID_KEYSTORE_PATH` (the path to your local upload keystore file),
    `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` as env vars. Never commit them.
  - Run `scripts/build-apk.ps1` (Windows) or `scripts/build-apk.sh`. They pass `APP_VERSION` and
    `GIT_SHA` so About shows the version and commit, e.g. `2.0.0 (build 294 · a8d2bba)`.
- Backend: `cd backend && pip install -r requirements-dev.txt && pytest && ruff check .`
- Bundles:
  - Run `cd backend && python -m app.build_static`. It needs the secrets in `.env`.
  - Copy the output into `web/data/` and push.
