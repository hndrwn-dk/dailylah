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
| Feature tests `app/test/features_test.dart` | GitHub Actions `app` (flutter test) | every PR | each feature through the real widgets: Ate here at halal places, meal time in History, live bus position |
| Release gate | GitHub Actions `app` jobs `e2e` + `play` | every push to `main` and manual releases | the whole `emulator` workflow must pass on the commit before the AAB goes to Google Play (closed testing by default) |
| Real phones `testlab.yml` (Robo) | Firebase Test Lab | by hand before a release | 6: crashes on a Samsung, a Xiaomi/Oppo and a Google phone |
| Security scans `security.yml` | GitHub Actions `security` | every PR, push to `main`, Mondays | CodeQL (actions, python, java-kotlin), osv-scanner (dependencies), zizmor (workflows); see below |
| Backend security `backend.yml` | GitHub Actions `backend` | every push touching `backend/` | ruff bandit rules (`S`), `pip-audit` on the installed dependency tree |

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
| pip-audit | backend runtime dependencies | any known vulnerability | `--ignore-vuln ID` in `backend.yml`, with a comment |
| Dependabot | pub, gradle, pip, github-actions | opens update PRs weekly (Monday), minor/patch grouped | — |

- **Dart is not supported by CodeQL.** The app's Dart code is covered by `dart analyze`
  (infos are fatal) in the `app` workflow and, from Phase 6, by the AI review.
- The java-kotlin build takes about 10 minutes, so on PRs it only runs when `app/android/`
  or `security.yml` changes; the Monday run and manual runs always include it.
- A baseline takes **Low findings only**, each with a reason (and for osv a date to look
  again). Anything higher is fixed or the dependency is replaced.
- Lockfiles: `app/pubspec.lock` is committed and CI uses `flutter pub get --enforce-lockfile`;
  backend dependencies are pinned with `==`.
- GitHub settings that are not in the repo (one-time, by hand): secret scanning, push
  protection, Dependabot alerts and security updates. See docs/HANDOFF.md.

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
