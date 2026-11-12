# DailyLah — QA and regression tests

The full release test plan lives in the Claude doc "DailyLah — Rencana Uji Regresi Rilis".
This file maps that plan to the automated tests in this repo and describes how a release ships.

## What runs where

| Layer | Where | When | Covers (plan section) |
| --- | --- | --- | --- |
| Logic tests `app/test/logic_test.dart` | GitHub Actions `app` | every push | parsing and rules |
| Screen matrix `app/test/screens_matrix_test.dart` | GitHub Actions `app` | every push | 2 (every tab, section and page) × 4 (normal, offline with cache, offline first install, location denied, 200% text, dark mode, 320 dp screen, 200% text on a 320 dp screen) |
| Alert rules `app/test/background_rules_test.dart` | GitHub Actions `app` | every push | 2 Notifications, 3B: runs the real `runChecks` pass |
| Upgrade formats `app/test/upgrade_test.dart` | GitHub Actions `app` | every push | 5: old stored data still loads |
| On-device flows `app/integration_test/app_test.dart` | GitHub Actions `emulator` (API 29 = minSdk / Android 10, API 35, API 36 = Play's required target) | every PR touching `app/` | 1, 3A, 3B, 3C: real SharedPreferences, notification read back from Android's active notifications, widget provider in the package, location revoked |
| Upgrade on device `scripts/emulator_upgrade.sh` | GitHub Actions `emulator` | every PR (from `origin/main`), every release (from the last release tag `v*`), or by hand with a `base_ref` | 5: previous build installed (with its own `pubspec.lock`), data seeded, new build installed with `adb install -r`; see "Release tags" below |
| Release build (R8) `scripts/emulator_release.sh` | GitHub Actions `emulator` (API 35) | every PR touching `app/` | release build with R8 starts with saved data, runs the WorkManager job and widget; fails on missing classes/plugins in logcat |
| Maestro flows `app/maestro/` (`scripts/emulator_maestro.sh`) | GitHub Actions `emulator` job `maestro` (API 35) | every PR touching `app/`, and every release before the upload | 1, 3A, 3C as a person uses the release build: onboarding, Setup saved over a restart, Today bus arrivals, Nearby sections, Home block, location denied then allowed, Appearance, the block's commute and all-in cost, Plan a trip (route card, swap, search, the bus to leave for), Compare blocks (add a block from the block page); see "Maestro" below |
| Contract tests `contracts/v1/` | GitHub Actions `backend` (`tests/test_contracts.py`) and `app` (`test/contract_test.dart`) | every push touching `backend/`, `app/` or `contracts/` | the app and the server agree on every `/v1/*` response; see "Contract tests" below |
| Golden tests `app/test/golden_test.dart` | GitHub Actions `app` (Linux only, `GOLDENS=1`) | every push touching `app/` | Today, Nearby, Home and More in light and dark, pixel by pixel against `app/test/goldens/`; see "Golden tests" below |
| AI review (advisory) `.claude/skills/review-pr` | a Claude Code session, on request | "review PR #N" or "security gate for PR #N" before a merge | bugs, CLAUDE.md rules and security on a PR; one comment, never blocks; see "AI review" below |
| Web check `scripts/web_check.sh` | GitHub Actions `web-check` | daily 07:23 Singapore time, and by hand | dailylah.sg opens, /privacy and /terms redirect to the policy pages, `data/manifest.json` valid on all three hosts, one bundle matches its sha256; see "Web check" below |
| Feature tests `app/test/features_test.dart` | GitHub Actions `app` (flutter test) | every PR | each feature through the real widgets: Ate here at halal places, meal time in History, live bus position |
| Release gate | GitHub Actions `app` jobs `e2e` + `play` + `release-tag` | every version bump on `main` and manual releases | the whole `emulator` workflow must pass on the commit before the AAB is tagged or goes to Google Play; where a version bump goes is the repository variable `PLAY_PUSH_TRACK` (unset = `manual`: no upload, see "Manual releases"); one upload at a time; the released commit is tagged `v<versionName>` and its files kept in a draft GitHub Release |
| Production release `app.yml` job `promote` (`scripts/play_promote.py`) | GitHub Actions `app` | every version bump on `main`, after `play` and `release-tag`, while `AUTO_PROMOTE` is `on` | after the owner's approval, puts the versionCode just uploaded to `alpha` on production as a staged rollout at 20%; see "Production release (automatic)" |
| Rollout guard `rollout-guard.yml` (`scripts/rollout_guard.py`) | GitHub Actions `rollout-guard` | daily 10:17 Singapore time while `AUTO_ROLLOUT` is `on`, and by hand (`dry_run`) | raises the staged release 20% → 50% → 100% after the hold, or halts it and opens an issue when Android vitals are worse |
| Manual override `promote.yml` | GitHub Actions `promote`, by hand | when the owner wants to act | promote, raise, halt or resume the production release from the phone; waits for his approval |
| Release script tests `backend/tests/test_play_promote.py`, `test_rollout_guard.py` | GitHub Actions `backend` | every PR touching `backend/`, the two scripts, `promote.yml`, `rollout-guard.yml` or `app.yml` | against a fake Google Play, a fake Reporting API and fake GitHub issues: what is sent, every refusal, wait / raise / halt, API errors, both switches (`AUTO_PROMOTE`, `AUTO_ROLLOUT`), dry run, and that the production key stays in `play-production` (promote) and `play-rollout` (the guard alone) |
| Security scans `security.yml` | GitHub Actions `security` | every PR, push to `main`, Mondays | CodeQL (actions, python, java-kotlin), osv-scanner (dependencies), zizmor (workflows); see below |
| Backend security `backend.yml` | GitHub Actions `backend` | every push touching `backend/` | ruff bandit rules (`S`), `pip-audit` on the installed dependency tree |
| Agent docs `docs.yml` | GitHub Actions `docs` | every PR and push to `main` | `docs/REPO_MAP.md` and every `AGENTS.md` match the code and CLAUDE.md (`scripts/repo_map.py --check`) |

The screen matrix uses the bundles committed in `web/data/`, so screens render with real data.
The data is published from the branch `data` (docs/DEPLOY.md "Data branch"), so that copy on
`main` is not updated daily; refresh it with a pull request when a test needs newer data.
The API, location and storage are faked. A test fails on any exception or layout overflow.

## Manual releases (no Play upload)

What a version bump on `main` does is set by the repository variable `PLAY_PUSH_TRACK`
(Settings > Secrets and variables > Actions > Variables):

| `PLAY_PUSH_TRACK` | A version bump on `main` |
| --- | --- |
| not set, or `manual` | analyze, tests, unsigned AAB, `sign` (with the `UPLOAD_CERT_SHA256` check), `e2e` (flows, upgrade from the last tag, Maestro on the signed AAB), then `release-tag`: tag `v<versionName>` and a draft GitHub Release with `dailylah.aab`, `dailylah-mapping.txt` and `whatsnew-en-US`. `play` is skipped and never reads the Play key. |
| `alpha` (or `internal`, `beta`) | the same tests, then `play` uploads to that track, then `release-tag` tags the commit and keeps the same three files in a draft GitHub Release. With `alpha` and `AUTO_PROMOTE=on`, production follows after one approval: "Production release (automatic)". |

A manual run (Actions > app > Run workflow on `main`) offers the same `manual` choice next to the
Play tracks and starts on it; pick a track to upload, or `none` for analyze and tests only.

Uploading a `manual` release by hand:
1. Actions > the `app` run > its summary: the `Manual upload` notice names the draft release. The
   three files are also the run artifact `dailylah-release` (30 days).
2. Releases > the draft `v<versionName>` > download `dailylah.aab`, `dailylah-mapping.txt` and
   `whatsnew-en-US`.
3. Play Console > Test and release > the track (e.g. Production) > Create new release > upload
   `dailylah.aab`; paste `whatsnew-en-US` into the release notes (en-US).
4. Play Console > App bundle explorer > that version > Downloads > ReTrace mapping file > upload
   `dailylah-mapping.txt`.
5. Review and roll out in Play Console. Leave the GitHub Release as a draft, or publish it by hand.

Switching the automatic upload back on: set the repository variable `PLAY_PUSH_TRACK` to `alpha`
(New repository variable, or edit it). The next version bump on `main` uploads to closed testing
again. Setting it back to `manual`, or deleting it, turns the upload off again. Nothing in the
repository changes.

## Release tags

Every release tags its commit `v<versionName>` (`app` job `release-tag`, after `play`, or after
`sign` and `e2e` for a `manual` release). The tags mark what users really run:
- A release tests the upgrade from the nearest tag below its commit (`git describe` on `HEAD^`),
  not from the commit before it, which may never have shipped. With no tag yet, it falls back to
  that commit with a `No release tag` warning.
- To fix that warning, tag the last version-bump commit that reached Google Play by hand:
  `git tag v<versionName> <sha> && git push origin v<versionName>` (the `v*` tag ruleset leaves
  creations open; it only blocks moving and deleting a tag).
- Pull requests still test the upgrade from `origin/main`: that catches a broken format before
  it reaches a release.
- The tag is the last release to any track, closed testing included, or the last `manual` release
  (which the owner uploads by hand). Users on production can be a version behind until it is
  promoted (right after the tag and the owner's approval, while `AUTO_PROMOTE` is on) or uploaded.
- The old version is built with its own `pubspec.lock` (`--enforce-lockfile`); a tag from before
  the lockfile was committed (v1.9.1 and older) resolves its dependencies fresh, with a warning.
- A tag is never moved. Uploading again without a new `version:` (a manual run on another track)
  keeps the tag on the first commit and says so in a warning.
- Every release also keeps the AAB, `dailylah-mapping.txt` and `whatsnew-en-US` in a draft GitHub
  Release of that tag, since run artifacts expire after 30 days. A closed-testing release is
  promoted to production as it is, so every production version has its files there.
  Drafts are visible only to the owner; publish it by hand if wanted.

## Release signing

The upload key never reaches a job that runs third-party build code:
- `analyze` builds the release AAB **unsigned** (`DAILYLAH_UNSIGNED_RELEASE=1` in
  `android/app/build.gradle.kts`), with no signing secrets, and keeps it with its R8 mapping as
  artifact `dailylah-aab-unsigned`.
- `sign` (environment `signing`, main only) checks out only `scripts/sign_aab.sh` and uses only the
  JDK: it refuses an AAB that already holds a signature (`META-INF/*.RSA|DSA|EC`), signs it with
  `jarsigner` (passwords through `-storepass:env`/`-keypass:env`), checks the signature, and fails
  unless the certificate's SHA-256 equals the environment variable `UPLOAD_CERT_SHA256` (compared
  without colons, upper case). The signed AAB and the same mapping become artifact `dailylah-aab`.
  `UPLOAD_CERT_SHA256` comes from Play Console > Protected with Play > Play Store protection >
  Manage Play app signing > Upload key certificate > SHA-256. Not the "App signing key
  certificate" on the same page: that is Google's key, so every sign would fail.
- `e2e` tests `dailylah-aab` on main, so Maestro runs the very file that goes to Play; a manual run
  on another branch skips `sign` and tests `dailylah-aab-unsigned`. A failed `sign` stops the run.
- `play` (environment `play`, testing tracks only; `app.yml` has no production track) and
  `release-tag` (tag and draft Release) only ever take `dailylah-aab`, so nothing unsigned is
  uploaded or archived. The `promote` job, `promote.yml` and `rollout-guard.yml` upload nothing:
  they move a versionCode Google Play already has.
- This protects the keys. It does not prove what is inside the AAB: Gradle plugins and pub packages
  still build it; the tests, R8 checks and Maestro are what catch a bad build.
- `jarsigner -verify -strict` is not used: an upload certificate is self-signed, which `-strict`
  always rejects. The signature check plus the certificate fingerprint cover it.

## Required checks

The `main` ruleset (set up by hand, docs/DEPLOY.md "Rulesets") requires these checks on every
pull request, by the names GitHub shows:

| Check | Workflow | What it stands for |
| --- | --- | --- |
| `app result` | `app.yml` | `analyze` (analyze, tests, unsigned AAB) when `app/`, `contracts/` or `app.yml` change |
| `emulator result` | `emulator.yml` | `flows (API 29/35/36)`, `upgrade (previous version → this build)`, `release build (R8) starts and runs`, `Maestro flows (release APK)` when `app/`, `scripts/emulator_*.sh` or `emulator.yml` change |
| `backend result` | `backend.yml` | `test` (ruff, pytest, pip-audit) when `backend/`, `contracts/`, `scripts/play_promote.py`, `scripts/rollout_guard.py`, `scripts/push_data.sh`, `web/build.sh`, `web/vercel.json`, `promote.yml`, `rollout-guard.yml`, `app.yml`, `data.yml`, `where-to-live.yml` or `backend.yml` change |
| `web result` | `web.yml` | `page logic (node --test)` and `layout (Playwright)` when `web/` (not `web/data/`) or `web.yml` change |
| `repo map and AGENTS.md up to date` | `docs.yml` | `scripts/repo_map.py --check` |
| `CodeQL (actions)`, `CodeQL (python)` | `security.yml` | CodeQL on workflows and Python |
| `osv-scanner (dependencies)` | `security.yml` | known vulnerabilities in the lockfiles |
| `zizmor (workflows)` | `security.yml` | workflow security |

- A required check must report on every PR, or GitHub waits for it forever ("Expected"). So `app`,
  `emulator`, `backend` and `web` run on every pull request (no `paths:` filter on `pull_request`); their
  first job, `what changed (<name>)`, compares the PR merge commit with its first parent (the base)
  and the real jobs run only when their paths changed. The last job, `<name> result`
  (`if: always()`), fails if any job failed or was cancelled and passes when they passed or were
  skipped. A job skipped by its `if:` counts as passed; a workflow that never started does not.
- Pushes keep their `paths:` filters, and a release (push to main or a manual run) always runs
  every job, so nothing changes for the release gate.
- Not required: `CodeQL (java-kotlin)` (a matrix entry that exists only when `app/android/`
  changes), the code scanning checks `CodeQL`, `osv-scanner` and `zizmor` (SARIF uploads, already
  covered by their jobs), `web-check` (only when its script changes), and the main-only jobs
  `sign the App Bundle`, `upload to Google Play (…)`, `tag the release` and
  `promote to production (staged, 20%)`.
- A new workflow whose result should be required follows the same pattern and is added to the
  ruleset by hand.

## Security scans

Layer order: deterministic scans (this section) → AI review (see "AI review") → a person decides.
None of these block the Google Play upload; a red `security` run is fixed before merging.

| Tool | Scans | Fails the run on | Baseline |
| --- | --- | --- | --- |
| CodeQL `actions`, `python` | workflows, `backend/`, `scripts/` | results show in Security > Code scanning (PR check) | dismiss in the Security tab with a reason |
| CodeQL `java-kotlin` | `app/android` (MainActivity, home screen widget), built with `flutter build apk --debug` | same | same |
| osv-scanner v2.7.0 | `app/pubspec.lock`, `backend/requirements*.txt`, `.github/tools/requirements.txt`, `web/tests/e2e/package-lock.json` | High/Critical (CVSS ≥ 7.0); Medium/Low are warnings | `osv-scanner.toml` |
| zizmor | `.github/workflows/` | High; Medium is a warning | `.github/zizmor.yml` |
| ruff `S` (bandit) | `backend/` | any finding | inline `# noqa: Sxxx` with the reason; tests may assert and use fake tokens |
| pip-audit | backend runtime lock `requirements.txt` (hashes required) | any known vulnerability | `--ignore-vuln ID` in `backend.yml`, with a comment |
| Dependabot | pub, gradle, pip, github-actions | opens update PRs weekly (Monday), minor/patch grouped | — |

- **Dart is not supported by CodeQL.** The app's Dart code is covered by `dart analyze`
  (infos are fatal) in the `app` workflow and by the AI review.
- The java-kotlin build takes about 10 minutes, so on PRs it only runs when `app/android/`
  or `security.yml` changes; the Monday run and manual runs always include it.
- A baseline takes **Low findings only**, each with a reason (and for osv a date to look
  again). Anything higher is fixed or the dependency is replaced.
- Lockfiles: `app/pubspec.lock` is committed and CI uses `flutter pub get --enforce-lockfile`.
  The backend's `requirements*.txt` are full locked trees with hashes made from
  `requirements*.in` (`uv pip compile`), so osv-scanner runs with `--no-resolve` and checks
  exactly what Render installs. Without a full lock, osv-scanner guesses transitive versions
  and reports old ones that are never installed (Phase 1 saw 23 such false High findings).
- GitHub settings that are not in the repo (one-time, by hand): secret scanning, push
  protection, Dependabot alerts and security updates. See docs/DEPLOY.md "GitHub security settings".

## Maestro (release build, black box)

`app/maestro/` holds flows that drive the installed release build through the screen, like a
person: no test hooks, the real API on Render and real bundles. `config.yaml` runs them in
order (01 sets up the household the others use) and stops at the first failure.

- Pull request: the R8 release APK built from the commit (debug key, no CI secrets).
- Release (`app` job `e2e` passes `aab_artifact: dailylah-aab`): bundletool makes a universal APK
  from the exact App Bundle that goes to Google Play and signs it with a throwaway key, so the
  upload key never reaches the emulator job. The script fails if the APK is debuggable.
- Maestro and bundletool are downloaded at pinned versions and checked by SHA-256 in
  `emulator.yml`; bump the version and checksum together.
- Before the flows the script waits until the emulator answers on adb (`sys.boot_completed`) and
  wakes the API on Render (`/health`, up to 90 s), so a cold start does not land inside a flow.
  The flows run with notifications denied (no live alerts on screen); `common/decline_notifications.yaml`
  answers Android's prompt after Setup's Done/Save.
- One retry: when a flow fails, the log shows why (each failed flow's message from `report.xml`,
  the last steps before the failure from the debug output, `adb logcat -b crash`, the app's log
  and the texts on screen), then every flow runs once more on a fresh install (01 sets up the
  household the others need, so a single flow cannot run alone). Passing the second time keeps
  the job green with a `Maestro flaky: passed on retry` warning naming the flow and its first
  reason; failing twice fails the job, which still blocks the Play upload. Read the warnings:
  a flaky flow can also be a real bug that shows only sometimes.
- The job summary lists each flow per attempt. The artifact `maestro-results` keeps the reports,
  debug output, videos, screenshots and error logcat of every failed attempt for 14 days.
- The flows use the live API and live data (LTA bus arrivals, OneMap search, weather). If they
  stay flaky, pull request runs could point the app at a fixture server built from
  `contracts/v1/`; releases keep the live API.

Writing flows:
- Flows must pass on any day and at any time. The emulator is set to Singapore time; flow 02 makes
  Work an every-day place (Sat and Sun chips in Setup), so Today shows the commute on weekends too
  instead of the weekend card. Live data that is empty at night (buses stopped) is accepted as an answer.
- Public holidays (`web/data/holidays.json`) switch off the commute on Today, also for that every-day Work:
  flow 03 then checks the holiday banner and that no trip shows, and skips the bus steps.
- Flutter merges the texts of a tile or card into one node, so match with `"(?s).*text.*"`, or
  anchor the start (`"(?s)Appearance.*"`) when a longer node also contains the text.
- Rows off screen are not in the hierarchy: `scrollUntilVisible` first; add `centerElement: true`
  when the row could end up under the floating tab bar.
- A TextField hint cannot be matched. The address search field has focus when the picker opens,
  so `common/search_address.yaml` just types the postal code.
- Test addresses: 560201 (Blk 201 Ang Mo Kio Ave 3, home) and 310201 (Toa Payoh, work). The first
  search wakes Render and can take about a minute; the shared flow retries once.
- `launchApp` grants every permission unless the flow lists `permissions`; a flow that needs
  location off says `location: deny` (Nearby otherwise switches itself to "Here").
- Live data changes: flow 03 passes on live arrivals and on "Buses have stopped" at night, and only
  fails on "Bus times not available".
- Run by hand on a branch: Actions > emulator > Run workflow (or
  `gh api -X POST repos/hndrwn-dk/dailylah/actions/workflows/emulator.yml/dispatches -f ref=<branch>`).
## Contract tests (app and backend)

`contracts/v1/<name>.json` holds, per `/v1/*` endpoint (each weather kind on its own): the
`request`, the `upstream` answer it is built from (made-up values in the real upstream format)
and the `response` the app reads.

- Backend (`backend/tests/test_contracts.py`): upstream is mocked with `upstream`, the endpoint
  is called, and the answer must have the structure of `response`: every key, list and value
  type in the example must be there. Values may differ and extra keys are allowed, so adding a
  field never breaks the app; removing or retyping one fails here.
- App (`app/test/contract_test.dart`): the real parsers (`forecastNear`, `parseBusArrival`,
  `parseParking`, `EvLive.fromApi`...) read each `response` and must find the expected values.
  A test fails when an example has no check, so a new endpoint gets one on both sides.
- Changing a response on purpose: change the backend, run
  `cd backend && UPDATE_CONTRACTS=1 pytest tests/test_contracts.py` to rewrite the examples, then
  update the app parser and `contract_test.dart` in the same PR. Both workflows run when
  `contracts/` changes. `fetched_at` stays fixed in the examples so the diff only shows real changes.
- Not covered: the upstream itself (data.gov.sg, LTA, OneMap) changing its format. The data
  workflow and live use catch that.

## Golden tests (visual regression)

`app/test/golden_test.dart` renders Today, Nearby, Home and More in light and dark (8 images,
824x1830, the app's fonts and Material icons) with the test household, a fixed clock (Tuesday
7 am), `FakeApi` and the committed bundles, and compares each with `app/test/goldens/<tab>-<mode>.png`.

- Linux CI only: fonts render a little differently on macOS and Windows, so the tests are skipped
  unless `GOLDENS=1` on Linux (the `app` workflow sets it). `flutter test` on a laptop skips them.
- A failure means the screen changed. The `app` run keeps the expected, actual and diff images as
  the artifact `golden-failures` (Actions > the run > Artifacts), readable on a phone.
- A deliberate UI change: run Actions > goldens > Run workflow on the PR branch. It renders the
  images on Linux, commits them as dailylah-bot and keeps them as the artifact `goldens`; review
  the new images in the PR diff. A commit made with the workflow token does not start other
  workflows, so the next push to the branch (or the merge to main) checks them again.
  `goldens` never runs on main.
- An unexpected change is a bug: fix the code, do not update the images.

## AI review (advisory)

The last layer before a person decides. It runs in a Claude Code cloud session on the owner's
Claude plan: no secret in GitHub Actions, no workflow, no laptop.

- On request, in any Claude Code session on this repo: "review PR #N" (or "review open PRs") runs
  the `review-pr` skill (`.claude/skills/review-pr/SKILL.md`). For open PRs it skips forks, drafts,
  bot PRs (dailylah-bot, Dependabot) and PRs already reviewed at their head commit (only its own
  marker comments count). There is no scheduled run: most PRs here come from Claude sessions that
  already run the security gate, so a timed reviewer mostly spent plan usage without new findings.
- What it checks and how it writes is in `.github/prompts/review.md` (change the prompt there, no
  workflow change needed). It reads `.claude/security-profile.md` for the threat model.
- Security uses the owner's private security toolkit: a fresh `security-reviewer` subagent per PR,
  the memory format of `/vuln-scan`. Its location is in the owner's private agent config, never in
  this repo. The toolkit is read from the clone, not installed into the session (auto mode
  blocks writing hooks into `~/.claude`).
- Security gate before a merge: ask the session for "security gate for PR #N"; it follows the
  toolkit's `/security-gate` and posts `Security gate: pass at <sha>.` on the PR.
- Output: one comment per PR, updated on each new commit: `SETUJUI` or `PERLU PERUBAHAN`, then
  findings by severity (Kritis, Tinggi, Sedang) with `file:line`.
- The repository is public, so a security finding shows only as a count in the PR. Its details go
  to the owner's private security notes repo.
- The PR template (`.github/pull_request_template.md`) asks for both on the current head commit:
  the review comment's marker sha, and `Security gate: pass at <short sha>.` when `app/`,
  `backend/`, `.github/` or `.claude/` change. Both count only when posted by `hndrwn-dk` (the repo
  is public, so anyone can write the same text). It is a reminder, not a check: before merging,
  compare those shas with the PR's head (a push after the gate needs a new gate).
- Advisory only: it never approves, blocks, merges or pushes. A review can be wrong; a person
  decides. It does not replace any gate above.

## Web check

`.github/workflows/web-check.yml` runs `scripts/web_check.sh` every morning (07:23 Singapore time),
by hand (Actions > web-check > Run workflow) and on PRs that change it. With curl only, it checks:
- `https://dailylah.sg` opens and is the DailyLah page;
- `/privacy` and `/terms` redirect to `https://www.tursinalabs.com/dailylah/privacy` and `/terms`
  (`web/vercel.json`), and those pages open;
- `data/manifest.json` loads from every host in `webUrls` (`app/lib/api.dart`) and has a version and
  a non-empty file list with paths and sha256 (different versions across hosts are only a warning:
  the same Vercel deployment sits behind all three, and `/data/` is cached for an hour);
- the smallest bundle on dailylah.sg matches its sha256 in the manifest.

A failed scheduled run emails the repository owner (GitHub's default for scheduled workflows); the
job summary lists each check. The backend on Render is not checked here: the app tolerates it
sleeping, and waking it daily would only spend free-tier hours.

## Layout bugs the matrix found (fixed in PR #51)

Text overflowed at 200% text or on 320 dp screens in: Setup go/back time buttons, the bus
load meter, section titles with a trailing button, HDB block tiles, the block page hero chips
and resale card. Text now wraps or scales down.

200% text on a 320 dp screen (added for 2.3.0) found: the bus plate left no room for the
arrival times (its number now grows up to 130%), the load meter, the EV charger count and the
"Where's my bus" stop strip. They now wrap or scale down.

## Known PRD gaps (tests marked `skip`)

Remove the `skip` when the gap is fixed (or change the PRD and delete the test).
The PRD is the owner's product requirements document; it is kept outside this repository.

1. Notifications have no "don't show this type again" action. `background_rules_test.dart`
2. No "last updated" label on real-time data when offline. `screens_matrix_test.dart`
3. MRT alerts are not sent during quiet hours, but the PRD exempts morning MRT disruptions. `background_rules_test.dart`
4. The PRD caps all non-MRT alerts at 3 a day; the app caps only rain. Not tested yet.
5. Heat-stress alerts default to on; the PRD says off. `background_rules_test.dart`

## Production release (automatic)

Merge, one tap, shipped. The owner works alone, so nobody else reviews a pull request; the one
thing that still needs him is approving the first step to production. Nothing below needs a
laptop or Play Console. It needs the one-time settings in docs/DEPLOY.md "Production releases"
(`PLAY_PUSH_TRACK=alpha`, `AUTO_PROMOTE=on`, `AUTO_ROLLOUT=on`, a production service account of
its own, the two environments). Until `AUTO_PROMOTE` is on, a release stops at closed testing and
production goes through Actions > promote.

1. **Merge the version bump** (`version:` and `whatsnew-en-US`). The `app` workflow analyzes,
   tests, signs, runs the on-device tests (Maestro on the signed AAB), uploads the AAB to closed
   testing (`alpha`), tags `v<version>` and keeps the AAB, mapping and release notes in a draft
   GitHub Release.
2. **Promote, after one tap** (`app` job `promote`, right after `release-tag`): the job waits in
   environment `play-production` for the owner's approval (a notification in the GitHub mobile
   app: Review deployments > Approve). Then the same versionCode goes to production as a staged
   rollout at **20%**. No rebuild, no upload, release notes from `whatsnew-en-US` of that commit.
3. **Rollout guard, no tap** (`rollout-guard.yml`, daily): after `ROLLOUT_HOLD_HOURS` at a
   fraction with health OK or unknown it raises 20% → 50% → 100% (100 completes the release).
   With health worse it halts the release and opens an issue.

What the owner does: approve step 2. After that nothing, unless an issue labelled
`release-halted` or a failed run arrives (GitHub notifies for both). Then, from the phone:
Actions > promote > `halt` or `resume`, or ship the fix as a new version through step 1 (it
replaces the unfinished release).

Why a tap, and why only there: with one developer and no second reviewer, nothing else stands
between a started workflow and production. The approval is a GitHub setting, not a file in the
repository, so no pull request can remove it from the promote job. It does not cover the guard's
environment, whose limits are under "Tooling and keys" ("What `play-rollout` means"). The first 20% is
where a version meets users; the later steps only widen a release the owner has already let out,
and the guard stops them when vitals get worse. Revisit both choices when there is a team or
enough users for vitals to say something.

### Auto promote (`app` job `promote`)
- Runs only when all of this holds: the run is a **push to `main`** (never a pull request, a fork
  or a manual run), `play` uploaded to `alpha` (so `PLAY_PUSH_TRACK` is `alpha`; with any other
  track nothing is promoted), `release-tag` put `v<version>` on this commit, and the repository
  variable **`AUTO_PROMOTE` is `on`**.
- It promotes only the versionCode this run built (`--code`, the run number): if the alpha
  release of that version holds another one, nothing is promoted.
- It waits for the owner's approval (environment `play-production`, required reviewer).
  Rejecting leaves the release on closed testing and fails the run (`app result` red). A request
  nobody answers stays "Waiting" for up to 30 days and can keep the guard and the manual
  workflow waiting meanwhile ("Tooling and keys"): reject it when the version should not ship.
- **Switches:** `AUTO_PROMOTE` is for this job, `AUTO_ROLLOUT` for the guard; each is `on` or off
  (anything else, or unset). Off means the job is skipped and never reads the production key; no
  code change. With `AUTO_PROMOTE` off, releases still reach closed testing; promote by hand with
  Actions > promote. With `AUTO_ROLLOUT` off, nothing raises a staged release and nothing halts
  it either: it stays at its fraction, unwatched, until the owner raises or halts it by hand.
- Why a job at the end of `app.yml` and not a `workflow_run` workflow: the job gets the track,
  the upload result and the tag as job outputs of the same run, so it cannot act on another run
  or on a pull request's run. A `workflow_run` workflow would have to work out from the API or
  from artifacts what the finished run did, and it also fires for runs started by pull requests,
  which is the classic way to leak a key.
- The same refusals as a manual promote (`scripts/play_promote.py`), each changing nothing and
  failing the run: the version is not a completed release on `alpha`, its versionCode is lower
  than anything production holds, or production already has it. The version on `alpha` is found
  by its release name: the versionName, which is what an upload through the API gets, or Play
  Console's `<versionCode> (<versionName>)`.
- A failed promote makes the `app` run red (`app result`). Re-run the failed job, or promote by
  hand.
- A staged rollout is one production release at a time: promoting a newer version over an
  unfinished or halted rollout replaces it, and the plan says so.
- Google reviews production releases: after the promote the release can sit "in review" before
  users get it. If the commit is refused because the app has changes that must be sent for review
  by hand, the run fails with Google's message; send them in Play Console once, then re-run.

### Rollout guard (`rollout-guard.yml`, `scripts/rollout_guard.py`)
Every day at 10:17 Singapore time, for the release that is staged on production:

| Production holds | Health | The guard |
| --- | --- | --- |
| in progress, at this fraction for less than `ROLLOUT_HOLD_HOURS` | OK or unknown | waits |
| in progress, held long enough | OK or unknown | raises one step: below 20 → 20, below 50 → 50, else 100 (completed) |
| in progress, any time | WORSE | halts it and opens an issue `release-halted`, assigned to the owner, with the versionCode, the fraction, the metric values and the halt time |
| halted, completed, a draft, or no release | – | nothing |

- **A halted release is never resumed or raised by the guard**, whoever halted it. After a manual
  `halt` it stays halted until the owner runs `resume` (the hold then starts again) or a new
  version replaces it. After a resume the guard judges only the vitals of the days from then
  on, so a release it halted is not halted again for the same days; it is halted again if the
  new days are worse too, and it is not raised before vitals cover one whole day since the
  resume (it waits for that until five days after it saw the resume, so an app without vitals
  is not stuck).
- The guard writes the reason into its log before it halts. If the `release-halted` issue then
  cannot be opened (the run fails), the next run opens it. A halt and a resume by hand between
  two daily runs are not seen by the guard: the hold and the health window go on as before.
- **Time at a fraction.** Google Play does not say when a release reached a fraction or left
  review. The guard keeps its own clock: one GitHub issue per versionCode (label
  `release-rollout`, "Production rollout: 2.4.0 (745)") with a marker for each state it saw; a
  new state (first sight, a fraction changed by hand, halted, resumed) adds a comment and starts
  the hold again. The time is the creation time GitHub gave that issue or comment, and only
  those written by `github-actions[bot]` count, so on this public repository a stranger's issue
  or comment cannot move the clock. The guard locks the issue when it opens it, so only people
  with write access can comment. Leave the issue open; the guard closes it at 100%.
  Why an issue: it survives between runs, needs only `issues: write` (which the halt issue needs
  anyway), and is a readable history of each rollout. A git note or tag would need
  `contents: write` in the job that holds the production key; the workflow token cannot write
  repository variables; no storage outside GitHub.
- The clock starts at the guard's first run after the promote, up to a day later; a raise by
  the guard starts the next hold in the same run. With the defaults that is 50% two to three
  days after the promote and 100% two days after that. The first day of slack also covers
  Google's review, which the API does not show: the hold cannot tell "in review" from "live".
  The daily run does not start at the same minute every day, so a run up to one hour short of
  the hold counts; otherwise a 48-hour hold would often take 72.
- **Health** is Android vitals from the Play Developer Reporting API (`v1beta1`,
  `crashRateMetricSet` and `anrRateMetricSet`, `DAILY`, dimension `versionCode`; daily data exists
  only for days in `America/Los_Angeles` and arrives a day or two late, so the guard asks up to
  the metric set's own freshness): `userPerceivedCrashRate` and `userPerceivedAnrRate` with
  `distinctUsers`, for the new versionCode and the one production had before it, over the days
  since the guard first saw the rollout, weighted by each day's users.
  - **WORSE** (either metric): at least `ROLLOUT_MIN_USER_DAYS` for the new version, AND its rate
    is above Google's bad behaviour threshold, AND above `ROLLOUT_WORSE_FACTOR` times the previous
    version's rate (when the previous version has no usable figure, above the threshold is enough).
  - **UNKNOWN**: no rows, or fewer user-days than the minimum. Expected for DailyLah today (a
    small user base; Google publishes no figure below its own privacy minimum). The guard then
    goes **by time only**, and every summary says "no vitals data".
  - **OK**: anything else with enough users.
  - An error from Google Play, the Reporting API or GitHub is never "unknown": the run fails,
    nothing is raised, and GitHub mails the owner.
- Repository variables (Settings > Secrets and variables > Actions > Variables; unset = default,
  a value that is not a number in range fails the run):

  | Variable | Default | Meaning |
  | --- | --- | --- |
  | `AUTO_PROMOTE` | off | `on` = the promote job of a release run asks for the approval and promotes |
  | `AUTO_ROLLOUT` | off | `on` = the guard acts |
  | `ROLLOUT_HOLD_HOURS` | `48` | hours at a fraction before the next step (the guard runs once a day, so use multiples of 24) |
  | `ROLLOUT_MIN_USER_DAYS` | `500` | daily users of the new version, summed over the days, below which health is unknown. At 1.09% that is about 5 affected users; fewer is noise |
  | `ROLLOUT_CRASH_BAD_PERCENT` | `1.09` | Google Play's overall bad behaviour threshold for the user-perceived crash rate |
  | `ROLLOUT_ANR_BAD_PERCENT` | `0.47` | the same for the user-perceived ANR rate |
  | `ROLLOUT_WORSE_FACTOR` | `1.5` | "clearly worse": the new rate must also be above this many times the previous version's |

- Actions > rollout-guard > Run workflow with `dry_run` shows the state, the hold, the health
  figures and the decision, lets Google Play check the change in a scratch edit, and changes
  nothing (no issue, no clock). It works while `AUTO_ROLLOUT` is off. Without `dry_run` a manual
  run is one more guard pass.
- Not yet seen against real figures: the Reporting API gives a rate as a share of users from 0 to
  1 (`0.0109` = 1.09%). A value outside 0 to 1 fails the run instead of deciding on it.

### Manual override (`promote.yml`)
Actions > promote > Run workflow on `main`, from the GitHub mobile app: `promote` (version empty =
the newest `v*` tag, rollout 10/20/50/100), `rollout` (only raises), `halt`, `resume`, and
`dry_run` for any of them. Every run waits for the owner's approval (environment
`play-production`), a dry run too, because it reads with the production key. `rollout`
needs a release in progress, `halt` too, `resume` a halted one; a completed (100%) release cannot
be halted from here.

### Every run's summary
The promote job, the guard and the manual workflow each write: the track before (versionCode,
versionName, status, rollout), the decision with its reason (hold time, health figures or "no
vitals data") or the plan, and production after it, read back from Google Play after the commit.
A run that changes nothing says so.

### Tooling and keys
- The scripts use only Python's standard library and the runner's `openssl` (to sign the service
  account's token request), so the jobs that hold the production key install nothing from pip and
  use no action besides `actions/checkout`. The upload action (`r0adkll/upload-google-play`)
  cannot move an existing versionCode without uploading a file; google-auth would add a dependency
  tree to those jobs; fastlane a Ruby toolchain.
- The production key is in two environments, both limited to `main`, and nowhere else:
  `play-production` (required reviewer: the owner) for the promote job and `promote.yml`, and
  `play-rollout` (no reviewer) for the guard alone. It belongs to a service account of its own;
  the scripts refuse the testing account's key (repository variable `PLAY_TESTING_ACCOUNT`).
- **What `play-rollout` means:** a job on `main` that names that environment gets the key and
  nobody is asked. So whoever can put a commit on `main` could use it: the owner's merges, any
  token that can merge as him, and anything in the `main` ruleset's bypass list. That is the
  price of a guard that needs no tap, accepted for now by the owner. Two things keep it small:
  nothing but a merged pull request may reach `main` (the data workflows must keep publishing through the
  branch `data` and the bypass list must stay empty, docs/DEPLOY.md "Data branch"), and few things
  may hold write access to the repository. Putting the reviewer on `play-rollout` as well closes
  it, at the cost of a tap for every step.
- One writer to production at a time: the promote job, the guard and `promote.yml` share the
  concurrency group `play-promote`. A second run waits; a third replaces the waiting one. If two
  edits ever commit at the same moment, Google Play refuses the later one and that run fails with
  nothing changed.
  A run that waits for the owner's approval can hold the group (certain for `promote.yml`, whose
  group is on the workflow; expected, not yet seen, for the promote job of `app.yml`): the
  guard's daily run and a manual `halt` then only queue behind it, and a later queued run cancels
  the earlier one. So approve or reject a waiting promote first; do not leave it.

## What CI enforces before production

There is no human checklist. A version reaches production only through these, in order:

| Gate | Where | Blocks |
| --- | --- | --- |
| Pull request with the nine required checks green (app, emulator, backend, web, docs, CodeQL actions and python, osv-scanner, zizmor) | `main` ruleset | the merge |
| Analyze, unit, screen-matrix, golden and contract tests on the release commit | `app` job `analyze` | the build |
| Signature made with the upload key, certificate fingerprint checked | `app` job `sign` | everything after |
| On-device tests on that commit: flows on API 29/35/36, upgrade from the last release tag, R8 release build, Maestro on the very AAB that ships | `app` job `e2e` | the upload |
| Upload to closed testing, release tag | `app` jobs `play`, `release-tag` | the promote |
| The owner's approval; completed on `alpha`, not older than production, not already there, the versionCode this run built | `app` job `promote` | production |
| Staged rollout: 20%, then 50%, then 100%, each after the hold, halted when vitals are worse | `rollout-guard` | the next step |

- Security scans are a merge gate, not a release step: CodeQL, osv-scanner and zizmor run on
  every pull request and are required checks, so a release commit on `main` has passed them.
  The Monday run catches advisories published later; its findings are fixed in a new PR.
- The full scan in a Claude Code session ("/vuln-scan on main", the owner's security toolkit)
  is no longer part of the release gate. Run it when wanted; its details stay in the owner's
  private notes.
- A real phone is no longer a gate either: the owner's approval of the first 20% and the staged
  rollout with the guard take that place.
  The checks below are optional.

## Real-device checks (optional, only for the areas a release changes)

Emulators cannot cover these: they have no vendor battery saver or Doze schedule of a real
phone, no Samsung or foldable launcher, and no real bus ride. Do the ones that match what the
release changed, on the closed-testing or production build; none of them blocks a release.

- [ ] Lock a real phone for an hour with the app set up; at least one alert or widget update arrives (Doze, vendor battery savers).
- [ ] Widget on a Samsung phone: add it, resize it through 2x1, 4x1, 2x2, 4x2 and 4x3+; each size shows a full layout with nothing cut off, also at the largest font size and in dark mode.
- [ ] Widget on a foldable (Galaxy Z Fold): fold and unfold; the widget switches layout on each screen. On a Galaxy Z Flip, add it under Settings > Cover screen > Widgets.
- [ ] Widget buttons Today / Nearby / Home open the app on that tab, also when the app was closed.
- [ ] Wake me on a locked screen on a real bus ride.
- [ ] Need a toilet? (once `toilets.json` is published): start Wake me on a real bus two or more stops before your stop, tap Need a toilet?; the sheet lists the stops ahead with a toilet ("Get off at … (in about N min)"), soonest first, and Walking directions opens Google Maps at the toilet. On the train, the sheet lists the next stations ("Stations usually have a toilet" where the data has none). Nearby > Toilets shows the three best toilets near the place.
- [ ] Look at Today and Home once on a small real phone at the largest font size.
- [ ] Public holiday: set the phone's date to a public holiday on a workday (e.g. Fri 25 Dec 2026) before the usual leave time. Today shows the holiday banner and no trip; the background check sends one "Happy Christmas Day · no commute today" notification and no "Time to go".
- [ ] Plan a trip, To: "Lau Pa Sat" finds it at 18 Raffles Quay with the Geoapify line under the results; "560201" finds Blk 201 Ang Mo Kio (OneMap, no Geoapify line); "Jewel Changi" finds Jewel. ("Putra Minang" is not in OpenStreetMap and finds nothing: share it from Google Maps.)

## Run locally

```bash
cd app
flutter test                                    # logic, screens, alerts, upgrade formats
flutter test integration_test/app_test.dart -d <device>   # needs an emulator or phone
```
