# DailyLah: handoff for the next chat

Start here, then read `CLAUDE.md` (root rules and where everything else lives), `app/CLAUDE.md`
(the feature map is kept current there), `backend/CLAUDE.md`, `docs/REPO_MAP.md` and `docs/PRD.md`.

## Status (24 Oct 2026)
- `main` is at PR #42. All feature branches are merged and deleted on GitHub, except
  `wip/floating-nav-edge`: an unmerged WIP from 20 Oct, kept for now.
- The repo is public with an all-rights-reserved LICENSE. "Require approval for all external
  contributors" is on.
- GitHub Actions runs again: app (APK), backend, and data (daily bundles, about 40 min).
  - Dispatch data with `gh api -X POST repos/hndrwn-dk/dailylah/actions/workflows/389579101/dispatches -f ref=main`.
  - Persona harness: branch `probe/persona2` was deleted. Recreate it if needed.
- Proxy limits in Claude sessions:
  - Use REST, not GraphQL. Merge with `gh api -X PUT repos/hndrwn-dk/dailylah/pulls/N/merge -f merge_method=squash`.
  - Repo settings are blocked from Claude sessions; give Hendrawan the steps.
  - Merged branches are deleted automatically on GitHub ("Automatically delete head branches" is on
    since 25 Oct 2026). Do not send branch delete commands after a merge.

## Where to live? (Nov 2026, plan: docs/WHERE_TO_LIVE.md)
Web tool on dailylah.sg: HDB towns ranked by transit time to an office area and HDB median
rent/resale. Static page and JSON, no browser API calls, no Render. One PR per phase.
- Phase 1 (data pipeline, branch `feat/where-to-live-data`): `backend/app/where_to_live.py`,
  weekly `.github/workflows/where-to-live.yml`, output `web/data/where-to-live.json`, route cache
  `backend/data/where_to_live_routes.json`.
  - A dry run on the branch (7 Nov) read the real dataset columns and 154 OneMap routes; its
    temporary `push` trigger was removed before the PR.
  - After merge: run Actions > where-to-live > Run workflow once and check that it commits.
  - Once the `main` ruleset is on, this workflow needs the same bypass as `data.yml`.
- Phase 2 (page `/where-to-live`), Phase 3 (per-town SEO pages), Phase 4 (launch with production).

## CI/CD hardening (Nov 2026, 8 phases, one PR each)
Layers: deterministic scans → AI review → a person decides. Existing gates (analyze, test,
emulator e2e, Play upload gate) stay as they are.
- Phase 1 (security scans, branch `security/phase1-deterministic-scan`): `security.yml`
  (CodeQL actions/python/java-kotlin, osv-scanner, zizmor), ruff `S` + `pip-audit`, Dependabot,
  committed `app/pubspec.lock`, every action pinned to a SHA, minimal `permissions`. Old findings
  were fixed in the same PR; baselines hold Low only. Rules are in CLAUDE.md "CI security" and
  docs/QA.md "Security scans".
- Phase 2 (agent docs, branch `docs/phase2-memory-repo-map`): CLAUDE.md split into root,
  `app/CLAUDE.md` (feature map, UI, build/release, tests) and `backend/CLAUDE.md` (free tier, API,
  data pipeline), with no line lost. `AGENTS.md` in each folder is now made from the CLAUDE.md
  next to it. `scripts/repo_map.py` writes `docs/REPO_MAP.md` (files, public symbols, providers,
  endpoints) and the AGENTS.md copies; the `docs` workflow fails when either is stale.
  `.omc/` is ignored except `.omc/skills/`.
- Phase 3 (Maestro, branch `test/phase3-maestro`, PR #98): Maestro tests the release build;
  on a release it tests a universal APK made with bundletool from the very AAB that goes to Play
  (re-signed with a throwaway key), so the upload key never reaches the emulator job; on a PR it
  tests the R8 release APK built from the commit. `maestro` job in emulator.yml (Maestro 2.12.1 and
  bundletool 1.18.3 pinned by SHA-256), `scripts/emulator_maestro.sh`, flows 01–07 in
  `app/maestro/` (7/7 pass in about 4.5 min). How to write and run them: docs/QA.md "Maestro".
  - Not yet seen in CI: the release path (`aab_artifact`, bundletool). It first runs on the next
    release; if the `maestro` job fails there, read its log before re-running.
  - Since #109 a failed run prints why and runs all flows once more ("Maestro flaky" warning).
    Flows must pass on any day: the emulator runs on Singapore time and flow 02 makes Work an
    every-day place (flow 03 failed on the first Saturday, 7 Nov, when Today showed the weekend card).
- Phase 4 (contract tests, branch `test/phase4-contracts`): `contracts/v1/*.json` (17 examples:
  request, upstream, response), `backend/tests/test_contracts.py` (structure, with
  `UPDATE_CONTRACTS=1` to rewrite) and `app/test/contract_test.dart` (parsers read the same files).
  `backend` and `app` workflows also run on `contracts/**`.
- Phase 5 (golden tests, branch `test/phase5-goldens`): `app/test/golden_test.dart` (4 tabs x
  light/dark, Linux CI only via `GOLDENS=1`), images in `app/test/goldens/`, artifact
  `golden-failures` on a failed `app` run, `goldens.yml` rewrites and commits the images on a branch.
- Phase 6 (AI review, PR #101): no API key and no workflow. On request in a session,
  `.claude/skills/review-pr` runs with
  `.github/prompts/review.md` and `.claude/security-profile.md`; one advisory comment per PR,
  security through the owner's claude-toolkit (read from the private `hndrwn-dk/security-memory`,
  not installed: auto mode blocks writing hooks into `~/.claude`), details only in that repo.
  Merges after #101 get the toolkit's security gate first ("security gate for PR #N").
  The 8-hourly scheduled run was tried and removed: it needs a standing session with the repos
  attached, and since most PRs come from Claude sessions that already run the gate, it mostly spent
  plan usage.
- Phase 7 (release check) shrank to a checklist: docs/QA.md "Before promoting a release to
  production" (security green, a real phone in closed testing, /vuln-scan in a session); no new workflow, since the Play
  upload is already gated and production is promoted by hand.
- Phase 8 (web check, branch `ci/phase8-web-check`): `web-check.yml` daily at 07:23 SGT runs
  `scripts/web_check.sh` (curl): site, /privacy and /terms redirects, manifest on the 3 hosts, one
  bundle sha256. CI/CD hardening is done after this PR.
- Firebase Test Lab (`testlab.yml`) was removed: it never ran (its secret was never set), the app
  uses no Firebase, the emulators and Maestro cover API 29/35/36, and Test Lab shuts down on
  30 Sep 2027. Real phones are covered by closed testing.
- Riverpod 3 (3.4.3): `valueOrNull` became `.value`, `StateProvider` from `legacy.dart`, every
  ProviderScope/ProviderContainer passes `retry: noRetry` (own retry rules in `_live`). Goldens
  unchanged. Dependabot follows riverpod majors again.

## CI/CD review follow-ups (Nov 2026)
Seven findings from a second review of the pipeline, one PR per group. Gates stay as they are.
- PR 1 (release tags, branch `claude/practical-meitner-rz230k`): `app.yml` tests a release's
  upgrade from the last release tag `v*` (job output `base_ref`, warning when there is none),
  the new `release-tag` job (the only one with `contents: write`) tags each uploaded commit
  `v<versionName>` and, for production, keeps the AAB and mapping in a draft GitHub Release; `play`
  runs one at a time (`concurrency: play-upload`); `scripts/emulator_upgrade.sh` builds the old
  version with its own `pubspec.lock`. Rules: docs/QA.md "Release tags".
  - Not yet seen in CI: `release-tag`, the draft Release and the tag lookup on a real release push.
    On the next release check: the `analyze` notice "Upgrade test: from v1.9.2", the `e2e` upgrade
    job installing v1.9.2 first, then tag `v<new version>` on the release commit.
- PR 2 (release signing, branch `ci/release-signing`): `analyze` builds the AAB unsigned with no
  secrets; the new `sign` job (environment `signing`, main only, sparse checkout of
  `scripts/sign_aab.sh`, JDK only) signs it with jarsigner and checks the upload certificate
  against `UPLOAD_CERT_SHA256`; e2e, play and release-tag use that signed AAB; `play` runs in
  environment `play` or `play-production`. Rules: docs/QA.md "Release signing"; environments below.
- PR 3 (PR template, branch `ci/pr-template`): `.github/pull_request_template.md` with What / Why /
  How tested / Not testable before the next release / Settings by hand, and a one-line-per-item
  checklist: AI review and security gate on the head sha, privacy.md, release-only version and
  whatsnew, structure docs, no security details or AI attribution. No workflow, no required check;
  CLAUDE.md "Git workflow" points agent PRs at it. Rules: docs/QA.md "AI review".
- PR 4 (rulesets, branch `ci/rulesets`): `app`, `emulator` and `backend` run on every PR with a
  `what changed (<name>)` job and a final `<name> result` check, so they can be required; the
  gate comment counts only by `hndrwn-dk`. Rules: docs/QA.md "Required checks"; the ruleset steps
  below ("Rulesets: set up by hand").

### Release tags
`v1.9.1` (06c6e73) and `v1.9.2` (45dd485) were pushed by hand on 7 Nov 2026; later tags come from
the `release-tag` job. Older releases, only if a full archive is ever wanted (version bump commits
on `main`): 1.9.0 a9f29be, 1.8.0 cf5dc80, 1.7.0 52a8481, 1.6.2 5fb50a2, 1.6.1 3740839, 1.6.0 86dbd79,
1.5.0 43059ee, 1.4.0 eb09d8e, 1.3.0 f5192fe, 1.2.3 f0109c8, 1.2.2 6efc234, 1.2.1 ec06643,
1.2.0 dc7ca69. A tag ruleset must let GitHub Actions create `v*` tags.

### Release signing environments (PR 2): done (7 Nov 2026)
Set up by the owner under Settings > Environments, each limited to `main` with no admin bypass:
- `signing`: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD`, and the environment variable `UPLOAD_CERT_SHA256` (checked against
  keytool and Play Console). Its source in Play Console: Protected with Play > Play Store
  protection > Manage Play app signing > Upload key certificate > SHA-256. Do not use the
  "App signing key certificate" on the same page: that is Google's key, and every sign would fail.
- `play`: `PLAY_SERVICE_ACCOUNT_JSON`.
- `play-production`: `PLAY_SERVICE_ACCOUNT_JSON`, required reviewer Hendrawan (prevent
  self-review off).

Still to do: after the first release with the new setup reaches Google Play (`sign the App
Bundle` green with "App Bundle signed with the upload key" in the summary, `on-device tests /
Maestro flows (release APK)` green, `upload to Google Play (alpha)` green), delete the old
repo-level secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD` and `PLAY_SERVICE_ACCOUNT_JSON` under Settings > Secrets and variables >
Actions. Until then they keep a revert of PR 2 working. If Play rejects the signature, revert PR 2.

### Rulesets: set up by hand (PR 4), after it is merged
Turn them on only after PR 4 is on `main`: before that, `app result`, `emulator result` and
`backend result` do not exist and every PR would wait for them. Settings > Rules > Rulesets > New.

**`main`** (New branch ruleset; Enforcement: Active; Target: Include default branch):
1. Restrict deletions; Block force pushes.
2. Require a pull request before merging: required approvals **0** (the owner cannot approve their
   own PR); Allowed merge methods: **Squash** only.
3. Require status checks to pass, "Require branches to be up to date" **off**. Add these, source
   GitHub Actions (names exactly as GitHub shows them; docs/QA.md "Required checks"):
   `app result`, `emulator result`, `backend result`, `repo map and AGENTS.md up to date`,
   `CodeQL (actions)`, `CodeQL (python)`, `osv-scanner (dependencies)`, `zizmor (workflows)`.
4. Bypass list: the daily `data.yml` pushes the data bundles straight to `main` with the job token,
   which the rules above would refuse. Pick one route:
   - **Route A (first choice):** Add bypass > **GitHub Actions** (if the picker offers it on this
     personal repository), mode Always. Nothing else changes.
   - **Route B (if GitHub Actions is not offered):** a deploy key with bypass. Create an SSH key
     pair on the laptop (`ssh-keygen -t ed25519 -f dailylah-data-push -N ""`); Settings > Deploy
     keys > Add: the public key, **Allow write access**; create environment **`data-push`**
     (Deployment branches: `main` only, no admin bypass) with secret `DATA_PUSH_SSH_KEY` = the
     private key; delete the local key files; in the ruleset, Add bypass > Deploy keys, mode Always.
     Then ask a session for the follow-up PR that makes `data.yml` push over SSH with that key in
     environment `data-push` (not done yet: it needs the key to test).
   - Check it: Actions > data > Run workflow; the "Commit if changed" step must succeed (or say
     "No data changes"). `screenshots.yml` never pushes to `main` and `goldens.yml` skips `main`,
     so only `data.yml` needs the bypass.
5. Do not add yourself as a bypass actor: merges go through PRs like everything else.

**`v*` tags** (New tag ruleset; Enforcement: Active; Target: Include by pattern `v*`):
1. Restrict updates (a release tag never moves); Restrict deletions; Block force pushes.
2. Restrict creations: **only** if GitHub Actions could be added as a bypass actor (route A
   above), with GitHub Actions as bypass (Always), because `release-tag` creates the tags. If not,
   leave Restrict creations off: only the owner and Actions can write to this repository.

After both are on, check: a docs-only PR shows all eight checks green and can be squash-merged;
`git push --force` to `main` and `git push --delete origin v1.9.2` are refused.

### GitHub settings to set by hand (Phase 1)
Settings > Advanced Security (or Code security):
1. **Secret scanning**: Enable. Then **Push protection**: Enable.
2. **Dependabot alerts**: Enable. **Dependabot security updates**: Enable.
3. **Code scanning**: leave **Default setup** off (or switch it off). `security.yml` is an
   advanced setup, and GitHub rejects its CodeQL uploads while default setup is on.
No new secrets are needed for Phase 1.

## Recent batches (22 to 24 Oct)
- #36 to #39:
  - Nearby section chips.
  - Plan B for MRT disruptions, leave-by and wake-me.
  - Habits: parked car, trip times, Ate here.
  - Weekly digest, with holidays.json and the hand-kept school_holidays.json.
  - Compare UX fixes.
- #40: Plan a trip page (Here first), and a weekend card on Today on days without a commute.
- #41: events from Eventfinda (`backend/app/events.py`, secrets `EVENTFINDA_USER`/`EVENTFINDA_PASSWORD`).
  - Eventbrite was removed: it has no public search. The unused `EVENTBRITE_TOKEN` secret can be deleted.
- #42: parks.
  - Facility chips from NParks Park Facilities (`attach_facilities`, key `f` in poi.json).
  - "Good time to go?" line (`parkTime`).
  - Spelled-out names (`expandPlaceName`).
  - 2-line details in lists.
  - **Check after the data build:** confirm the facility chips actually appear. The CLASS values in
    that dataset were not visible from the sandbox, so `FACILITY_LABELS` in bundles.py may need tuning.

## Open ideas / not possible
- Wikimedia photos for big parks: not started.
- OnePA and NParks events: written permission needed. A short email to PA was drafted, not sent.
- Return Right machine locations: the website terms forbid reuse; ask BCRS.
- ERP on the route: LTA removed the ERP rates API in Sep 2024.
- QStash sometimes stops polling (unresolved on Upstash). Fetch-on-miss in the backend covers it.

## Domains
- `dailylah.sg` is the website and the first host for data bundles; `dailylah.tursinalabs.com`
  and `dailylah-web.vercel.app` are fallbacks (same Vercel deployment, `webUrls` in `api.dart`).
- Privacy and terms stay at `tursinalabs.com/dailylah/privacy` and `/terms`;
  `dailylah.sg/privacy` and `/terms` redirect there (`web/vercel.json`).

## Build locally (if Actions minutes run out again)
- App: `cd app && flutter pub get && flutter analyze && flutter test`.
- Release APK:
  - Set `ANDROID_KEYSTORE_PATH` (`C:\Users\hendr\Deployment\signed\dailylah\dailylah-upload.jks`),
    `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` as env vars. Never commit them.
  - Run `scripts/build-apk.ps1` (Windows) or `scripts/build-apk.sh`. They pass `APP_VERSION` and
    `GIT_SHA` so About shows the version and commit, e.g. `1.0.0 (build 294 · a8d2bba)`.
- Backend: `cd backend && pip install -r requirements-dev.txt && pytest && ruff check .`
- Bundles:
  - Run `cd backend && python -m app.build_static`. It needs the secrets in `.env`.
  - Copy the output into `web/data/` and push.

## How Hendrawan works
- Chats in Indonesian. The app is English only.
- "diskusi dulu" = discuss only, do not build.
- One PR and one APK per batch. Ask before merging unless he already said merge.
- Track every to-do so nothing is missed.
- Never ask for secrets in chat. Keep the app religion-neutral: halal and prayer times are opt-in.
- Keep the sticker theme: amber = look now, teal = go.
- Drafts to outside parties stay short, so the idea is not given away.
- CI rules:
  - Analyzer infos are fatal.
  - The Dart SDK is >=3.5, so no `?x` null-aware elements; use `if (x case final v?)`.
