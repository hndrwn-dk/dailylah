# DailyLah — QA and regression tests

The full release test plan lives in the Claude doc "DailyLah — Rencana Uji Regresi Rilis".
This file maps that plan to the automated tests in this repo and lists what is still manual.

## What runs where

| Layer | Where | When | Covers (plan section) |
| --- | --- | --- | --- |
| Logic tests `app/test/logic_test.dart` | GitHub Actions `app` | every push | parsing and rules |
| Screen matrix `app/test/screens_matrix_test.dart` | GitHub Actions `app` | every push | 2 (every tab, section and page) × 4 (normal, offline with cache, offline first install, location denied, 200% text, dark mode, 320 dp screen) |
| Alert rules `app/test/background_rules_test.dart` | GitHub Actions `app` | every push | 2 Notifications, 3B: runs the real `runChecks` pass |
| Upgrade formats `app/test/upgrade_test.dart` | GitHub Actions `app` | every push | 5: old stored data still loads |
| On-device flows `app/integration_test/app_test.dart` | GitHub Actions `emulator` (API 29 = minSdk / Android 10, API 35, API 36 = Play's required target) | every PR touching `app/` | 1, 3A, 3B, 3C: real SharedPreferences, notification read back from Android's active notifications, widget provider in the package, location revoked |
| Upgrade on device `scripts/emulator_upgrade.sh` | GitHub Actions `emulator` | every PR (from `origin/main`), every release (from the last release tag `v*`), or by hand with a `base_ref` | 5: previous build installed (with its own `pubspec.lock`), data seeded, new build installed with `adb install -r`; see "Release tags" below |
| Release build (R8) `scripts/emulator_release.sh` | GitHub Actions `emulator` (API 35) | every PR touching `app/` | release build with R8 starts with saved data, runs the WorkManager job and widget; fails on missing classes/plugins in logcat |
| Maestro flows `app/maestro/` (`scripts/emulator_maestro.sh`) | GitHub Actions `emulator` job `maestro` (API 35) | every PR touching `app/`, and every release before the upload | 1, 3A, 3C as a person uses the release build: onboarding, Setup saved over a restart, Today bus arrivals, Nearby sections, Home block, location denied then allowed, Appearance; see "Maestro" below |
| Contract tests `contracts/v1/` | GitHub Actions `backend` (`tests/test_contracts.py`) and `app` (`test/contract_test.dart`) | every push touching `backend/`, `app/` or `contracts/` | the app and the server agree on every `/v1/*` response; see "Contract tests" below |
| Golden tests `app/test/golden_test.dart` | GitHub Actions `app` (Linux only, `GOLDENS=1`) | every push touching `app/` | Today, Nearby, Home and More in light and dark, pixel by pixel against `app/test/goldens/`; see "Golden tests" below |
| AI review (advisory) `.claude/skills/review-pr` | a Claude Code session, on request | "review PR #N" or "security gate for PR #N" before a merge | bugs, CLAUDE.md rules and security on a PR; one comment, never blocks; see "AI review" below |
| Web check `scripts/web_check.sh` | GitHub Actions `web-check` | daily 07:23 Singapore time, and by hand | dailylah.sg opens, /privacy and /terms redirect to the policy pages, `data/manifest.json` valid on all three hosts, one bundle matches its sha256; see "Web check" below |
| Feature tests `app/test/features_test.dart` | GitHub Actions `app` (flutter test) | every PR | each feature through the real widgets: Ate here at halal places, meal time in History, live bus position |
| Release gate | GitHub Actions `app` jobs `e2e` + `play` + `release-tag` | every push to `main` and manual releases | the whole `emulator` workflow must pass on the commit before the AAB goes to Google Play (closed testing by default); one upload at a time; the uploaded commit is tagged `v<versionName>` |
| Security scans `security.yml` | GitHub Actions `security` | every PR, push to `main`, Mondays | CodeQL (actions, python, java-kotlin), osv-scanner (dependencies), zizmor (workflows); see below |
| Backend security `backend.yml` | GitHub Actions `backend` | every push touching `backend/` | ruff bandit rules (`S`), `pip-audit` on the installed dependency tree |
| Agent docs `docs.yml` | GitHub Actions `docs` | every PR and push to `main` | `docs/REPO_MAP.md` and every `AGENTS.md` match the code and CLAUDE.md (`scripts/repo_map.py --check`) |

The screen matrix uses the bundles committed in `web/data/`, so screens render with real data.
The API, location and storage are faked. A test fails on any exception or layout overflow.

## Release tags

Every upload to Google Play tags its commit `v<versionName>` (`app` job `release-tag`, after
`play`). The tags mark what users really run:
- A release tests the upgrade from the nearest tag below its commit (`git describe` on `HEAD^`),
  not from the commit before it, which may never have shipped. With no tag yet, it falls back to
  that commit with a `No release tag` warning.
- Pull requests still test the upgrade from `origin/main`: that catches a broken format before
  it reaches a release.
- The tag is the last upload to any track, closed testing included. Users on production can be a
  version behind until it is promoted.
- The old version is built with its own `pubspec.lock` (`--enforce-lockfile`); a tag from before
  the lockfile was committed (v1.9.1 and older) resolves its dependencies fresh, with a warning.
- A tag is never moved. Uploading again without a new `version:` (a manual run on another track)
  keeps the tag on the first commit and says so in a warning.
- A production upload also keeps the AAB and `dailylah-mapping.txt` in a draft GitHub Release of
  that tag, since run artifacts expire after 30 days. Drafts are visible only to the owner; publish
  it by hand if wanted.

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
- `play` (environment `play`, or `play-production` with the owner's approval) and `release-tag`
  (draft Release for production) only ever take `dailylah-aab`, so nothing unsigned is uploaded or
  archived.
- This protects the keys. It does not prove what is inside the AAB: Gradle plugins and pub packages
  still build it; the tests, R8 checks and Maestro are what catch a bad build.
- `jarsigner -verify -strict` is not used: an upload certificate is self-signed, which `-strict`
  always rejects. The signature check plus the certificate fingerprint cover it.

## Required checks

The `main` ruleset (set up by hand, docs/HANDOFF.md "Rulesets") requires these checks on every
pull request, by the names GitHub shows:

| Check | Workflow | What it stands for |
| --- | --- | --- |
| `app result` | `app.yml` | `analyze` (analyze, tests, unsigned AAB) when `app/`, `contracts/` or `app.yml` change |
| `emulator result` | `emulator.yml` | `flows (API 29/35/36)`, `upgrade (previous version → this build)`, `release build (R8) starts and runs`, `Maestro flows (release APK)` when `app/`, `scripts/emulator_*.sh` or `emulator.yml` change |
| `backend result` | `backend.yml` | `test` (ruff, pytest, pip-audit) when `backend/`, `contracts/` or `backend.yml` change |
| `web result` | `web.yml` | `page logic (node --test)` when `web/` (not `web/data/`) or `web.yml` change |
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
  `sign the App Bundle`, `upload to Google Play (…)` and `tag the release`.
- A new workflow whose result should be required follows the same pattern and is added to the
  ruleset by hand.

## Security scans

Layer order: deterministic scans (this section) → AI review (see "AI review") → a person decides.
None of these block the Google Play upload; a red `security` run is fixed before merging.

| Tool | Scans | Fails the run on | Baseline |
| --- | --- | --- | --- |
| CodeQL `actions`, `python` | workflows, `backend/`, `scripts/` | results show in Security > Code scanning (PR check) | dismiss in the Security tab with a reason |
| CodeQL `java-kotlin` | `app/android` (MainActivity, home screen widget), built with `flutter build apk --debug` | same | same |
| osv-scanner v2.7.0 | `app/pubspec.lock`, `backend/requirements*.txt`, `.github/tools/requirements.txt` | High/Critical (CVSS ≥ 7.0); Medium/Low are warnings | `osv-scanner.toml` |
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
  protection, Dependabot alerts and security updates. See docs/HANDOFF.md.

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
- Security uses the owner's claude-toolkit in the private `hndrwn-dk/security-memory`
  (`claude-toolkit/global/`): a fresh `security-reviewer` subagent per PR, the memory format of
  `/vuln-scan`. The toolkit is read from the clone, not installed into the session (auto mode
  blocks writing hooks into `~/.claude`).
- Security gate before a merge: ask the session for "security gate for PR #N"; it follows the
  toolkit's `/security-gate` and posts `Security gate: pass at <sha>.` on the PR.
- Output: one comment per PR, updated on each new commit: `SETUJUI` or `PERLU PERUBAHAN`, then
  findings by severity (Kritis, Tinggi, Sedang) with `file:line`.
- The repository is public, so a security finding shows only as a count in the PR. Its details go
  to the private repository `hndrwn-dk/security-memory` (`dailylah/reports/` and
  `dailylah/dailylah---flagged-vulnerabilities.json`).
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

## Known PRD gaps (tests marked `skip`)

Remove the `skip` when the gap is fixed (or change the PRD and delete the test).

1. Notifications have no "don't show this type again" action. `background_rules_test.dart`
2. No "last updated" label on real-time data when offline. `screens_matrix_test.dart`
3. MRT alerts are not sent during quiet hours, but the PRD exempts morning MRT disruptions. `background_rules_test.dart`
4. The PRD caps all non-MRT alerts at 3 a day; the app caps only rain. Not tested yet.
5. Heat-stress alerts default to on; the PRD says off. `background_rules_test.dart`

## Before promoting a release to production

Uploads to closed testing are already gated (`app` > `e2e`: emulator flows, upgrade, R8 release and
Maestro on the AAB that is uploaded). Production is promoted by hand in Play Console; before that,
for the release's commit on `main`:
- [ ] `security` workflow green on that commit (CodeQL, osv-scanner, zizmor).
- [ ] The closed-testing build ran on at least one real phone (yours or a tester's) for a few days
      with no crash in Play Console > Android vitals.
- [ ] Full security scan: in a Claude Code session ask for "/vuln-scan on main" (the owner's
      claude-toolkit, details only in the private `hndrwn-dk/security-memory`); no new medium+ issue.
- [ ] The manual checks below.
No promote to production while any of these is open.

## Still manual (about 5 minutes before a release)

- [ ] Lock a real phone for an hour with the app set up; at least one alert or widget update arrives (Doze, vendor battery savers).
- [ ] Widget on a Samsung phone: add it, resize it through 2x1, 4x1, 2x2, 4x2 and 4x3+; each size shows a full layout with nothing cut off, also at the largest font size and in dark mode.
- [ ] Widget on a foldable (Galaxy Z Fold): fold and unfold; the widget switches layout on each screen. On a Galaxy Z Flip, add it under Settings > Cover screen > Widgets.
- [ ] Widget buttons Today / Nearby / Home open the app on that tab, also when the app was closed.
- [ ] Wake me on a locked screen on a real bus ride.
- [ ] Look at Today and Home once on a small real phone at the largest font size.

## Run locally

```bash
cd app
flutter test                                    # logic, screens, alerts, upgrade formats
flutter test integration_test/app_test.dart -d <device>   # needs an emulator or phone
```
