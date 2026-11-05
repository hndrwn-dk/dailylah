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
| Upgrade on device `scripts/emulator_upgrade.sh` | GitHub Actions `emulator` | every PR, or by hand with a `base_ref` | 5: previous build installed, data seeded, new build installed with `adb install -r` |
| Release build (R8) `scripts/emulator_release.sh` | GitHub Actions `emulator` (API 35) | every PR touching `app/` | release build with R8 starts with saved data, runs the WorkManager job and widget; fails on missing classes/plugins in logcat |
| Maestro flows `app/maestro/` (`scripts/emulator_maestro.sh`) | GitHub Actions `emulator` job `maestro` (API 35) | every PR touching `app/`, and every release before the upload | 1, 3A, 3C as a person uses the release build: onboarding, Setup saved over a restart, Today bus arrivals, Nearby sections, Home block, location denied then allowed, Appearance; see "Maestro" below |
| Contract tests `contracts/v1/` | GitHub Actions `backend` (`tests/test_contracts.py`) and `app` (`test/contract_test.dart`) | every push touching `backend/`, `app/` or `contracts/` | the app and the server agree on every `/v1/*` response; see "Contract tests" below |
| Golden tests `app/test/golden_test.dart` | GitHub Actions `app` (Linux only, `GOLDENS=1`) | every push touching `app/` | Today, Nearby, Home and More in light and dark, pixel by pixel against `app/test/goldens/`; see "Golden tests" below |
| AI review (advisory) `.claude/skills/review-pr` | Claude Code cloud, scheduled task "DailyLah PR review" | every 8 hours (02:17, 10:17, 18:17 Singapore time), or on request in a session | bugs, CLAUDE.md rules and security on open PRs; one comment per PR, never blocks; see "AI review" below |
| Feature tests `app/test/features_test.dart` | GitHub Actions `app` (flutter test) | every PR | each feature through the real widgets: Ate here at halal places, meal time in History, live bus position |
| Release gate | GitHub Actions `app` jobs `e2e` + `play` | every push to `main` and manual releases | the whole `emulator` workflow must pass on the commit before the AAB goes to Google Play (closed testing by default) |
| Real phones `testlab.yml` (Robo) | Firebase Test Lab | by hand before a release | 6: crashes on a Samsung, a Xiaomi/Oppo and a Google phone |
| Security scans `security.yml` | GitHub Actions `security` | every PR, push to `main`, Mondays | CodeQL (actions, python, java-kotlin), osv-scanner (dependencies), zizmor (workflows); see below |
| Backend security `backend.yml` | GitHub Actions `backend` | every push touching `backend/` | ruff bandit rules (`S`), `pip-audit` on the installed dependency tree |
| Agent docs `docs.yml` | GitHub Actions `docs` | every PR and push to `main` | `docs/REPO_MAP.md` and every `AGENTS.md` match the code and CLAUDE.md (`scripts/repo_map.py --check`) |

The screen matrix uses the bundles committed in `web/data/`, so screens render with real data.
The API, location and storage are faked. A test fails on any exception or layout overflow.

## Security scans

Layer order: deterministic scans (this section) → AI review (planned) → a person decides.
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
  (infos are fatal) in the `app` workflow and, from Phase 6, by the AI review.
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
- On a failure the log shows the texts on screen ("Screen when the flows stopped") and the artifact
  `maestro-results` keeps the videos, screenshots and error logcat for 14 days. The job summary
  lists each flow as passed or failed.

Writing flows:
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

- Scheduled task "DailyLah PR review" (claude.ai > Claude Code > scheduled tasks) fires every 8 hours
  and starts a fresh session that runs the `review-pr` skill (`.claude/skills/review-pr/SKILL.md`)
  on open PRs that have no review for their current head commit (only its own marker comments count;
  a marker written by anyone else is ignored). Forks, drafts and bot PRs
  (dailylah-bot, Dependabot) are skipped.
- On request: in any Claude Code session on this repo, ask "review PR #N".
- What it checks and how it writes is in `.github/prompts/review.md` (change the prompt there, no
  workflow change needed). It reads `.claude/security-profile.md` for the threat model.
- Security uses the owner's claude-toolkit in the private `hndrwn-dk/security-memory`
  (`claude-toolkit/global/`): a fresh `security-reviewer` subagent per PR, the memory format of
  `/vuln-scan`, and after the PR reviews a `/find-critical-bugs` pass over the last 7 days. The
  toolkit is read from the clone, not installed into the session.
- Security gate before a merge: ask the session for "security gate for PR #N"; it follows the
  toolkit's `/security-gate` and posts `Security gate: pass at <sha>.` on the PR.
- Output: one comment per PR, updated on each new commit: `SETUJUI` or `PERLU PERUBAHAN`, then
  findings by severity (Kritis, Tinggi, Sedang) with `file:line`.
- The repository is public, so a security finding shows only as a count in the PR. Its details go
  to the private repository `hndrwn-dk/security-memory` (`dailylah/reports/` and
  `dailylah/dailylah---flagged-vulnerabilities.json`).
- Advisory only: it never approves, blocks, merges or pushes. A review can be wrong; a person
  decides. It does not replace any gate above.
- Stop or change the schedule in the scheduled task settings.

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

## Still manual (about 5 minutes before a release)

- [ ] Lock a real phone for an hour with the app set up; at least one alert or widget update arrives (Doze, vendor battery savers).
- [ ] Widget on a Samsung phone: add it, resize it through 2x1, 4x1, 2x2, 4x2 and 4x3+; each size shows a full layout with nothing cut off, also at the largest font size and in dark mode.
- [ ] Widget on a foldable (Galaxy Z Fold): fold and unfold; the widget switches layout on each screen. On a Galaxy Z Flip, add it under Settings > Cover screen > Widgets.
- [ ] Widget buttons Today / Nearby / Home open the app on that tab, also when the app was closed.
- [ ] Wake me on a locked screen on a real bus ride.
- [ ] Look at Today and Home once on a small real phone at the largest font size.

## Firebase Test Lab (one-time setup)

1. In the Google Cloud console for your Firebase project, enable the **Cloud Testing API** and **Cloud Tool Results API**.
2. IAM > Service accounts > create `github-testlab` with roles **Firebase Test Lab Admin** and **Storage Object Admin**, then create a JSON key.
3. GitHub > Settings > Secrets and variables > Actions:
   - secret `FIREBASE_SA_KEY` = the JSON key contents (paste it there, never in chat or a commit)
   - variable `FIREBASE_PROJECT_ID` = your Firebase project id
4. Run it: Actions > testlab > Run workflow. Results link is in the run summary.

Free Spark plan: 5 physical-device runs a day. Test Lab is deprecated and shuts down on
30 Sep 2027 (Firebase docs); move the Robo job elsewhere before then.

## Run locally

```bash
cd app
flutter test                                    # logic, screens, alerts, upgrade formats
flutter test integration_test/app_test.dart -d <device>   # needs an emulator or phone
```
