# DailyLah — guide for AI coding agents

Product: free Android app (Flutter) for Singapore residents. Daily morning/evening cards
built from data.gov.sg (NEA, HDB, CEA) and LTA DataMall. Tourist mode is out of scope.

## Where the rules live
- This file: app identity, repo layout, commands, privacy, CI security, Git workflow and style.
  It holds for every change.
- `app/CLAUDE.md`: the Flutter app — code layout and UI rules, the feature map, build and release
  (R8, keep rules, Play upload), store assets, testing.
- `backend/CLAUDE.md`: the API and data pipeline — free-tier hard rules (Upstash Redis, QStash,
  Neon, Render, Vercel), endpoint conventions, static bundles, OneMap, upstream keys.
- `.claude/security-profile.md`: threat model (attackers, surfaces, sensitive data, where security
  findings are reported). `.github/prompts/review.md` + `.claude/skills/review-pr`: the advisory AI
  review of PRs (docs/QA.md "AI review"). The repo is public: security findings never go in PR
  comments or issues, only to the owner's private security notes repo (named in the owner's
  private agent config, never in this repo).
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
- `web/` — static site on Vercel; its only build step, `web/build.sh`, lays the published data from the branch `data` over the site once `web/data-source.txt` says `data` (today it says `main` and the step does nothing): landing page, the "Where to live?" page
  (`web/where-to-live/`) and its generated town pages
  (`web/where-to-live-towns/`, never hand-edited) with their share images (`web/og/where-to-live/`,
  made by `scripts/build_og_images.py`), the Play button as plain HTML on every page (no script; `web/tests` checks all pages carry the same link), the landing
  page motion (`web/shared/day.js` timeline, `web/shared/screens.js` tab deck; the hero scenes are CSS
  only; each works without JS and respects reduced motion), vendored Leaflet (`web/vendor/`), static data bundles in `web/data/`, tests in `web/tests/`.
- `contracts/v1/` — one example per `/v1/*` endpoint, checked by the backend and app tests
  (docs/QA.md "Contract tests").
- `docs/` — public docs: QA and release process (`QA.md`), setup (`DEPLOY.md`), code index
  (`REPO_MAP.md`), legal text, store assets.
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
- Web: `node --test 'web/tests/*.test.mjs'` (Node 22, no packages). Layout at 360 px in a real browser:
  `cd web/tests/e2e && npm ci --ignore-scripts && node --test layout.e2e.mjs` (playwright-core only, pinned in
  its lockfile; set `CHROME_PATH` when Chrome is not installed as `chrome`)
- Repo map and agent docs: `python3 scripts/repo_map.py` writes `docs/REPO_MAP.md` and every
  `AGENTS.md`; `--check` fails when either is stale.

## Privacy rules
- Published policy and terms: https://www.tursinalabs.com/dailylah/privacy and /terms.
  Source text lives in `docs/legal/`. Any change to what data the app or server handles
  (new permission, SDK, endpoint, log field) must update `docs/legal/privacy.md` in the same PR,
  and the "Privacy and safety" questions on the landing page (`web/index.html`) when they no longer match.
- User locations and favourites stay on the device. The server only sees what a request needs: bus
  stop codes, search text, postal codes for EV chargers, CEA registration numbers and, for the Car,
  Motorbike, Bicycle and Taxi cards of a trip, that trip's destination or start as a rounded point
  (`/v1/trip-extras`; never the phone's own position), never logged.
  Alerts are made on the phone (no push service).
- No accounts, no identifying analytics.
- Secrets only via env vars. Never commit `.env`, API keys, or keystores.

## CI security (docs/QA.md, "Security scans")
- `app/pubspec.lock` is committed and every workflow runs `flutter pub get --enforce-lockfile`, so
  builds are reproducible and osv-scanner sees the exact versions. The Flutter SDK is pinned too
  (`flutter-version:` beside `channel: stable` in every workflow that installs it, one version for
  all): a new stable release changes the SDK-pinned packages in the lockfile and can add analyzer
  infos, which are fatal. An SDK upgrade is its own PR: the version in every workflow, `pubspec.lock`
  from `flutter pub get` with that SDK, and whatever the new analyzer asks for. In that PR the emulator
  `upgrade` job may fail once: it builds the previous version with its own lockfile
  (`scripts/emulator_upgrade.sh`), which the new SDK may not accept. Quote a two-part version
  (`"3.50"`). Backend: direct dependencies
  live in `backend/requirements*.in`; `requirements*.txt` are the full locked trees with hashes,
  made with `uv pip compile --python-version 3.12 --generate-hashes <file>.in -o <file>.txt`
  (Render installs `requirements.txt`). A dependency change updates the lockfile in the same PR.
- The Gradle wrapper download is pinned with `distributionSha256Sum` in
  `app/android/gradle/wrapper/gradle-wrapper.properties` (the `-all.zip` checksum from
  services.gradle.org); a wrapper upgrade updates it in the same PR.
- Every `uses:` is pinned to a full commit SHA with the version in a comment
  (`actions/checkout@<sha> # v7.0.1`); Dependabot bumps both. Never use a tag or branch.
- Every workflow sets `permissions:` at the top (read-only or `{}`) and widens it per job only where
  needed. Checkouts use `persist-credentials: false`; a job that pushes passes the token only to
  that `git push`. `data.yml` and `where-to-live.yml` build in a read-only job and hand a patch to a
  separate `push` job (environment `data-push`, deploy key `DATA_PUSH_SSH_KEY`, deploy hook
  `VERCEL_DEPLOY_HOOK`) that runs `scripts/push_data.sh` and nothing from pip. Where it publishes is
  `web/data-source.txt` on `main` (docs/DEPLOY.md "Data branch"): `main` (today) pushes to `main`
  with the deploy key, the `main` ruleset's one bypass, and copies the data files to the branch
  `data`, which nothing reads; `data` pushes to that branch and never to `main` (no bypass then)
  and starts a Vercel deploy, whose build step (`web/build.sh`) lays the branch over `main`. The
  `data` branch holds only data files (`BRANCH_PATHS` in the script): the script refuses a branch
  that holds anything else, reads `main` and `data` by full ref name, and `build.sh` takes only
  plain `.json`, town page `.html` and a plain sitemap from it. Then the copies on `main` are
  for the tests, except `web/data/school_holidays.json` (written by hand: main's wins). Never
  change `web/data-source.txt` together with anything else; that pull request needs the security
  gate and the `data` branch ruleset in place. The patch may carry only
  JSON files that parse; files the site serves as pages (the where-to-live town pages, the sitemap)
  are made in the push job by main's own stdlib generator (`push_data.sh --generate`), never taken
  from the patch. The build jobs start from the published data (`push_data.sh --baseline`, no key). When run on main, both build jobs check out the newest `main` (`ref: main`), so a
  run that waited in its concurrency group builds on the data the earlier run pushed; the push
  jobs keep the queued commit (and its `push_data.sh`). A run queued before a merge that changes
  the build's outputs, secrets or allowlist may fail once (fails closed); run it again.
  `web/vercel.json` sends `nosniff` for `/data/*`. In `app.yml` only
  `release-tag` writes (`contents: write`, the release tag and draft Release); `play`, which holds
  the Play key, stays read-only. The upload key is only in the `sign` job (environment `signing`:
  sparse checkout of `scripts/sign_aab.sh`, JDK only, no Gradle, pub or cache); the Play key only in
  `play` (environment `play`, testing tracks only: its key goes to a third-party upload action, so
  `app.yml` has no production track). Production (docs/QA.md "Production release (automatic)") is "merge, one tap,
  shipped": three jobs hold the production key (a production-only service account, never the one
  in `play`, checked against the variable `PLAY_TESTING_ACCOUNT`, without which only a dry run
  works), in two environments limited to `main`. `play-production` has the owner as required
  reviewer, for good: the `promote` job of `app.yml` (only a push to `main` whose `play` job
  uploaded to `alpha` and whose `release-tag` tagged the commit, only for the versionCode this run
  built, and only while the repository variable `AUTO_PROMOTE` is `on`) and `promote.yml` (manual
  only: the override). `play-rollout` has no reviewer and is used by `rollout-guard.yml` alone
  (schedule and manual, skipped while the variable `AUTO_ROLLOUT` is off unless a dry run;
  `issues: write` for its log and the `release-halted` issue). Each job has `contents: read`, the
  secret only on the step that runs `scripts/play_promote.py` or `scripts/rollout_guard.py`
  (standard library and openssl; no pip, no action besides checkout), and shares the concurrency
  group `play-promote`. Never give one of them a pull request, `workflow_run` or fork path, a
  third-party action or `contents: write`, never name `play-rollout` in another workflow, and
  never move the promote job or `promote.yml` to it; a change to their triggers, conditions or
  environments needs the security gate. A commit on `main` can use the key in `play-rollout` with
  no approval: nothing but a merged pull request may reach `main` (no ruleset bypass, no workflow
  that pushes there: `web/data-source.txt` must say `data` first).
  This protects the keys, not the contents of the
  AAB, which third-party build code still makes. Never use `pull_request_target`. Expressions from
  inputs, vars or step outputs go through `env:`, not straight into `run:`.
- Required checks (docs/QA.md "Required checks"): a workflow that may skip work on a pull request
  runs on every PR, decides in a `what changed (<name>)` job, and ends with a `<name> result` job
  (`if: always()`, fails on any failed or cancelled job). Never add a workflow-level `paths:` filter
  to `pull_request` for a workflow whose result is required: the check would never report.
- `security.yml` (every PR and push to main, weekly on Monday): CodeQL for actions, python and
  java-kotlin (Kotlin only when `app/android/` changes, plus the weekly run), osv-scanner and
  zizmor. osv-scanner and zizmor fail on High/Critical; Medium/Low are warnings. Dart is not
  supported by CodeQL: `dart analyze` covers it. Baselines (`osv-scanner.toml`,
  `.github/zizmor.yml`) take Low findings only, each with a reason.
- Backend: ruff includes the bandit rules (`S`); an exception is an inline `# noqa: Sxxx` with the
  reason. `backend` also runs `pip-audit`.
- Dependabot (`.github/dependabot.yml`): pub, gradle, pip, github-actions and npm (`web/tests/e2e`, with a
  7-day cooldown), weekly on Monday, minor/patch grouped per ecosystem.

## Git workflow
- One branch and one PR per batch, squash-merged into `main`.
- GitHub deletes the head branch automatically after a merge ("Automatically delete head
  branches" is on), so there is no branch cleanup step.
- Commits and PR descriptions carry no AI attribution: no `Co-Authored-By: Claude` or
  `Claude-Session` trailers, and no "Generated with/by Claude Code" line.
- In `hndrwn-dk/dailylah`, PR descriptions follow `.github/pull_request_template.md`. The AI review
  is the `review-pr` skill in `.claude/skills/review-pr/SKILL.md` (rules in
  `.github/prompts/review.md`); its PR comment by `hndrwn-dk` starts with
  `<!-- dailylah-ai-review sha=<head sha> -->`. The security gate ("security gate for PR #N", same
  skill) posts `Security gate: pass at <short sha>.`; only that comment by `hndrwn-dk` counts (the
  repo is public: anyone can write the text), and a later commit needs a new gate. GitHub fills
  the template in only in the web UI: a PR opened through the GitHub API or `gh` copies its sections
  and checklist. PRs by `dependabot[bot]` and `dailylah-bot` skip it.
- A PR that changes the structure (adds, moves, renames or removes a file in `app/lib`, a provider,
  a public class or function, or an endpoint) updates the feature map (`app/CLAUDE.md` "Feature map"
  or `backend/CLAUDE.md`) and `docs/REPO_MAP.md` in the same PR.

## Style
- Python: ruff (line length 100), type hints, async httpx.
- Dart: flutter_lints, Riverpod providers, no business logic in widgets.
- Commit messages in English, imperative mood.
