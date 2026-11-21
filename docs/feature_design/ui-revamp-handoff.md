# UI revamp: handoff for the next session

Written 21 Nov 2026, after release 2.12.0 (PR #206, commit `461e9ed` on `main`). The owner wants the
same kind of revamp for the other four tabs, one phase at a time: **Nearby, Home, History, More**.
None of that has been started. This file is on branch `ccr-ee4081d9-wky5gt` only (not on `main`);
delete it, or keep it out of the PR, when the work is done.

## What 2.12.0 changed on Today (the pattern to carry over)

- **Mode picker:** `ModeRail` in `app/lib/ui/widgets.dart`. One row of icons with a rough time each,
  an amber thumb that is tapped or dragged (critically damped spring, velocity carried into the
  settle, jump when animations are off), names as tooltips, a grid of named tiles when a segment
  would be under 48 dp times the text scale (`ModeRail.fits`).
- **Readings:** `_AirRow` (the one reading that opens a sheet: a raised card with a chevron) and
  `_ReadingStrip` (UV, heat stress: one flat outlined card, no shadow; a warning turns only the icon
  chip amber) in `app/lib/ui/today.dart`.
- **Rain once:** `_HeroWeather` says the forecast, "Raining now · 0.4 mm" and the mode's tip
  (`S.rainTip`). Today hides the rain alert banner; `TripSection(weatherAbove: true)` drops the
  trip's rain advice. Plan a trip keeps its banner.

The design ideas behind them, in the owner's words and choices:

1. Things that look the same must behave the same. A card that opens something is raised (hard
   shadow) and has a chevron; something that only tells is flat.
2. Say a thing once. No fact repeated in two cards or banners on one screen.
3. A warning colours a small part (a chip), not a whole cell, and every cell of a group has the same
   edge.
4. Compare before tapping: show the useful number on the control itself.
5. Fewer, even rows instead of pills that wrap unevenly.

## What the owner did not want

- A **global** raised/flat rule applied to every card at once. It was built, then reverted at the
  owner's request ("I just want to iterate"). Do not re-apply it wholesale. Change one element at a
  time, and only the ones the owner picks.
- Full amber fills for a warning inside a strip.
- The same information in several places.

`AlertBanner` (shared by all tabs) still has a shadow and no tap; it was left alone on purpose.

## How the owner likes to work

- Shows a screenshot, names the problem, asks "can we change?".
- Wants **options side by side** (current plus two or three), then picks one by name. Give a
  recommendation, but build nothing before the pick.
- Prefers **real renders from the app code** over HTML mockups once something is built. HTML
  mockups (published as private artifacts) are fine for the options stage.
- Says "Yes" to short questions; when you ask two things at once, the second may go unanswered. Ask
  one thing at a time, or state the default you will take.
- Asks for PR, review, gate and merge in one go at the end.

## Proposed phases (one PR each; ask before starting each)

For every phase: (a) render the tab as it is, light, dark and 200% text on 320 dp; (b) list what
looks tappable but is not, what is tappable with no cue, what is said twice, what wraps unevenly;
(c) show two or three options per problem as a mockup; (d) build only what the owner picks;
(e) real renders; (f) PR.

1. **Nearby** (`app/lib/ui/nearby.dart`, 1,536 lines, 23 `Panel`s). Section chips are a `PillRow`
   (wraps into rows, like the old mode pills). Known from the Today audit: EV charger rows
   (`app/lib/ui/ev.dart`) and car park rows open a sheet with no chevron. `BentoTile` is used at
   `nearby.dart:866`.
2. **Home** (`app/lib/ui/home.dart`, 1,113 lines). Section chips are a `PillRow` under the hero.
   `BentoTile`s at `home.dart:199` are all tappable (`onTap: () => go(key)`) but show no chevron.
   Weekend place rows open a sheet with no chevron (same widget as Today's `_WeekendCard`).
3. **History** (`app/lib/ui/history.dart`, 686 lines). Two `PillRow`s (period and kind filter).
   The summary `BentoTile`s at `history.dart:114` are not tappable but look raised. Rows are tapped
   to enter a cost and swiped to remove.
4. **More** (`app/lib/ui/more.dart`, 738 lines). Already follows a raised/flat rule: a `SettingTile`
   that is on is mint and raised, off is dashed and flat, link tiles have a chevron. Probably the
   smallest phase; check it against the others for consistency rather than redesigning it.

These notes come from reading the code for Today, not from an audit of the four tabs. Do the audit
first; the line numbers will have moved.

## Tooling that worked

- **Flutter is not preinstalled in cloud sessions.** Install the pinned SDK (the version is
  `flutter-version:` in `.github/workflows/app.yml`, 3.47.9 at the time of writing):
  `curl -sSfL -o f.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_<version>-stable.tar.xz`,
  unpack to `/opt/fl`, `git config --global --add safe.directory /opt/fl/flutter`, then
  `flutter pub get --enforce-lockfile` in `app/`. About 5 minutes. Full `flutter test` takes about
  4.5 minutes.
- **Real renders:** a throwaway test in `app/test/` (never committed) that pumps `DailyLahApp` with
  the harness fakes, loads the fonts as `test/golden_test.dart` does, sets a tall view
  (`Size(412, 1100)`, `devicePixelRatio = 2`), and ends with
  `await expectLater(find.byType(MaterialApp), matchesGoldenFile('<absolute path>.png'))`, run with
  `--update-goldens`. Pick a tab with `containerOf(tester).read(shellTabProvider.notifier).state = n`
  (Today 0, Nearby 1, Home 2, History 3, More 4) and a section with `nearbySectionProvider` /
  `homeSectionProvider`. `FakeApi.weather()` returns nothing: to see readings, subclass it and
  return `contracts/v1/weather_<kind>.json`'s `response` (skip `lightning`, which adds a banner).
- **Goldens:** `GOLDENS=1 flutter test test/golden_test.dart` compares locally. When a tab's look
  changes, do not commit local images: run the `goldens` workflow on the branch
  (`workflow_dispatch`), which commits them. It covers Today, Nearby, Home, More in light and dark
  and all five tabs on a foldable.
- **Tests to expect to touch:** `test/features_test.dart` (one case per change),
  `test/persona_test.dart` (one case per feature PR, the reviewer checks), `test/screens_matrix_test.dart`
  (48 dp targets and screen-reader labels: a `GestureDetector` with its own semantics children needs
  `excludeFromSemantics: true`), `test/contrast_test.dart`, and any test that finds a control by
  type or label (`PillRow` is asserted in several).
- **Maestro** (`app/maestro/`): flows match visible text and accessibility text with regexes.
  `04_nearby.yaml` taps the Nearby pills by name (`"(?s)Bus"`, `"(?s)Taxi"`), so a change to those
  pills must keep the names reachable (a `Tooltip` gives an accessibility text) or update the flow.

## PR, review, gate, release

- Root `CLAUDE.md`, `app/CLAUDE.md` and `.claude/skills/review-pr/SKILL.md` are the rules. A feature
  PR is a release: bump `version:` in `app/pubspec.yaml`, replace `docs/store/whatsnew/whatsnew-en-US`
  and `S.whatsNewNotes` (same lines, 500 characters at most). Update `app/CLAUDE.md` and run
  `python3 scripts/repo_map.py`.
- `main` moves while a session runs (2.11.3 landed mid-session last time). Fetch and merge `main`
  before opening the PR; resolve only the version, whatsnew and `whatsNewNotes` hunks by hand
  (`git checkout --ours <file>` on `l10n.dart` drops main's other strings: use `git checkout -m`).
- **Security gate:** the owner's private security notes repo is not named anywhere a cloud session
  can read. Last time the review and gate used only `.claude/security-profile.md` and nothing was
  saved to private notes. Tell the owner this each time.
- **Attribution:** the GitHub tool appends a "Generated by Claude Code" line to PR descriptions and
  comments, against the owner's rule. It cannot be switched off from the session; the squash commit
  message is under your control and must carry none. Tell the owner.
- **CI flakes seen:** Maven Central answering 403 / 429 to Gradle on the runners, and "Failed to
  start Dart Development Service" in an emulator flow job. One re-run of the failed jobs fixed each.
  Maestro flow 03 failed for a real reason (a card state the flow did not accept); read the log
  before re-running anything.
- Merging a release PR starts the release run on `main`; its `promote` job waits for the owner's
  approval in the `play-production` environment.

## Still open from this session

- 2.12.0 has not been tried on a real device by anyone.
- Three mockup pages are still published privately on the owner's account (tiles, whole Today
  screen, mode picker). The whole-screen one shows the raised/flat rule that was not shipped.
- Plan a trip still shows its own rain banner (it has no weather card).
