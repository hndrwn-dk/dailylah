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
  production" (security green, Test Lab, /vuln-scan in a session); no new workflow, since the Play
  upload is already gated and production is promoted by hand.
- Phase 8 (web check, branch `ci/phase8-web-check`): `web-check.yml` daily at 07:23 SGT runs
  `scripts/web_check.sh` (curl): site, /privacy and /terms redirects, manifest on the 3 hosts, one
  bundle sha256. CI/CD hardening is done after this PR.

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
- Riverpod 3 migration (from 2.6): ~177 analyzer errors (StateProvider moved to `legacy.dart`,
  AsyncValue API changes). Dependabot ignores riverpod majors until it lands (`.github/dependabot.yml`).
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
