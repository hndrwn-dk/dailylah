# DailyLah — guide for AI coding agents

Read `docs/PRD.md` first. It is the source of truth for scope, phases and constraints.
Product: free Android app (Flutter) for Singapore residents. Daily morning/evening cards
built from data.gov.sg (NEA, HDB, CEA) and LTA DataMall. Tourist mode is out of scope.

## Where the rules live
- This file: app identity, repo layout, commands, privacy, CI security, Git workflow and style.
  It holds for every change.
- `app/CLAUDE.md`: the Flutter app — code layout and UI rules, the feature map, build and release
  (R8, keep rules, Play upload), store assets, testing.
- `backend/CLAUDE.md`: the API and data pipeline — free-tier hard rules (Upstash Redis, QStash,
  Neon, Render, Vercel), endpoint conventions, static bundles, OneMap, upstream keys.
- `docs/REPO_MAP.md`: every file in `app/lib` with its public classes and functions, every Riverpod
  provider and every backend endpoint. Made by `scripts/repo_map.py`; CI fails when it is out of date.
- Read the file for the folder you change. A change that touches both app and backend (a new
  endpoint the app calls) reads both. Claude Code loads `app/CLAUDE.md` and `backend/CLAUDE.md`
  when it works in those folders; other agents read the matching `AGENTS.md`.
- `AGENTS.md` next to each `CLAUDE.md` is the same text for other agents (Cursor, Codex). Edit only
  `CLAUDE.md`, then run `python3 scripts/repo_map.py`, which rewrites every `AGENTS.md` (only the
  title line differs); the `docs` workflow fails when they do not match.

## App identity (permanent — never change)
- Android `applicationId` and `namespace`: `com.tursinalabs.dailylah`
- iOS bundle identifier: `com.tursinalabs.dailylah`
- Dart package name: `dailylah`. Display name: `DailyLah`.
- Generate platform folders only with:
  `cd app && flutter create . --org com.tursinalabs --project-name dailylah --platforms android,ios`
- `scripts/check-app-id.sh` enforces this in CI. Do not rename the package or the folders.

- Supported Android: 10 and newer (`minSdk = 29` in `android/app/build.gradle.kts`; Android 12+ alone
  is about 94% of Android use in Singapore). The emulator workflow tests API 29 as the lowest version.

## Repo layout
- `backend/` — Python 3.12, FastAPI. Deployed to Render (free) via `render.yaml`.
- `app/` — Flutter app (Riverpod, dio). Platform folders are generated with `flutter create`.
- `web/` — static site on Vercel: landing page, privacy policy, static data bundles in `web/data/`.
- `contracts/v1/` — one example per `/v1/*` endpoint, checked by the backend and app tests
  (docs/QA.md "Contract tests").
- `docs/PRD.md` — product requirements (Bahasa Indonesia).
- `scripts/` — one-off ops scripts (QStash schedule).
- Free-tier hard rules for the backend and data (Redis, QStash, Neon, Render, Vercel) are in
  `backend/CLAUDE.md`. Read them before adding features.

## Commands
- Backend: `cd backend && pip install -r requirements-dev.txt && pytest && ruff check . && ruff format --check .`
  (CI also runs `pip-audit -r requirements.txt --require-hashes --disable-pip --strict`)
- Run API locally: `cd backend && cp .env.example .env && uvicorn app.main:app --reload`
- Trigger a poll locally: `curl -X POST localhost:8000/internal/poll`
- App: `cd app && flutter pub get && flutter analyze && flutter test`
- Run app against local API (Android emulator): `flutter run --dart-define=API_URL=http://10.0.2.2:8000`
- Repo map and agent docs: `python3 scripts/repo_map.py` writes `docs/REPO_MAP.md` and every
  `AGENTS.md`; `--check` fails when either is stale.

## Privacy rules
- Published policy and terms: https://www.tursinalabs.com/dailylah/privacy and /terms.
  Source text lives in `docs/legal/`. Any change to what data the app or server handles
  (new permission, SDK, endpoint, log field) must update `docs/legal/privacy.md` in the same PR.
- User locations and favourites stay on the device. The server only sees stop codes and FCM topics.
- No accounts, no identifying analytics.
- Secrets only via env vars. Never commit `.env`, API keys, or keystores.

## CI security (docs/QA.md, "Security scans")
- `app/pubspec.lock` is committed and every workflow runs `flutter pub get --enforce-lockfile`, so
  builds are reproducible and osv-scanner sees the exact versions. Backend: direct dependencies
  live in `backend/requirements*.in`; `requirements*.txt` are the full locked trees with hashes,
  made with `uv pip compile --python-version 3.12 --generate-hashes <file>.in -o <file>.txt`
  (Render installs `requirements.txt`). A dependency change updates the lockfile in the same PR.
- Every `uses:` is pinned to a full commit SHA with the version in a comment
  (`actions/checkout@<sha> # v7.0.1`); Dependabot bumps both. Never use a tag or branch.
- Every workflow sets `permissions:` at the top (read-only or `{}`) and widens it per job only
  where needed. Checkouts use `persist-credentials: false`; a job that pushes passes the token only
  to that `git push`. Never use `pull_request_target`. Expressions from inputs, vars or step
  outputs go through `env:`, not straight into `run:`.
- `security.yml` (every PR and push to main, weekly on Monday): CodeQL for actions, python and
  java-kotlin (Kotlin only when `app/android/` changes, plus the weekly run), osv-scanner and
  zizmor. osv-scanner and zizmor fail on High/Critical; Medium/Low are warnings. Dart is not
  supported by CodeQL: `dart analyze` covers it. Baselines (`osv-scanner.toml`,
  `.github/zizmor.yml`) take Low findings only, each with a reason.
- Backend: ruff includes the bandit rules (`S`); an exception is an inline `# noqa: Sxxx` with the
  reason. `backend` also runs `pip-audit`.
- Dependabot (`.github/dependabot.yml`): pub, gradle, pip and github-actions, weekly on Monday,
  minor/patch grouped per ecosystem.

## Git workflow
- One branch and one PR per batch, squash-merged into `main`.
- GitHub deletes the head branch automatically after a merge ("Automatically delete head
  branches" is on), so there is no branch cleanup step.
- Commits and PR descriptions carry no AI attribution: no `Co-Authored-By: Claude` or
  `Claude-Session` trailers, and no "Generated with/by Claude Code" line.
- A PR that changes the structure (adds, moves, renames or removes a file in `app/lib`, a provider,
  a public class or function, or an endpoint) updates the feature map (`app/CLAUDE.md` "Feature map"
  or `backend/CLAUDE.md`) and `docs/REPO_MAP.md` in the same PR.

## Style
- Python: ruff (line length 100), type hints, async httpx.
- Dart: flutter_lints, Riverpod providers, no business logic in widgets.
- Commit messages in English, imperative mood.
