# UI revamp: handoff for the next session

Updated 21 Nov 2026, after release 2.16.1 (PR #212, commit `af7f12d` on `main`). The revamp of the
four tabs the owner asked for is **done and merged**. This file now says what was built, what is
left, and how the work went, for whoever picks it up next. It is on a session branch only (not on
`main`); delete it, or keep it out of the PR, when nothing here is left.

## What was done

| Tab | PR | Release | Commit on `main` |
|---|---|---|---|
| Today (before this handoff) | #206 | 2.12.0 | `461e9ed` |
| Nearby | #207 | 2.13.0 | `26943c0` |
| Home | #208 | 2.14.0 | `1a54b46` |
| History | #209 | 2.15.0 | `058042a` |
| More | #210 | 2.16.0 | `67b0660` |
| More: plug inside the EV tile | #212 | 2.16.1 | `af7f12d` |

What each one changed is in its PR description and in the feature map of `app/CLAUDE.md`. The
building blocks they share, all in `app/lib/ui/widgets.dart`:

- **`SectionTiles`**: the sections of a tab as even tiles (icon over name), four a row, fewer when the
  longest name would not fit; a name a little too wide is drawn smaller (`labelShrink`) before a row
  gives up a tile. Nearby and Home use it.
- **`PlaceRow`**: a row that opens something: name, a line under it, a large figure (`BigNumber`: the
  distance, or the row's own number, or a cost) and a chevron; `action` puts a few words where the
  figure would be ("Add price"). At large text on a small phone it drops its icon so words stay whole.
  Nearby, Home (`NearGroup`), toilets and History use it.
- **`BigNumber`**: one line always; a figure too wide for its room is drawn smaller.
- **`SectionTitle(trailingAtEnd:)`**, **`PageTitle`** with `WordWrapTitle` (a title never breaks inside
  a word).

The rules the owner picked, tab after tab, now hold on all five tabs:

1. A shadow means "this opens something". What only tells lies flat (Today's reading strip, Home's
   facts strip, History's spending card, More's switch tiles).
2. A row that opens something shows a chevron, and the useful number large.
3. Say a thing once on a screen.
4. Even rows of tiles, not pills that wrap unevenly.
5. A warning colours a small part, not a whole cell.

After the four tabs, the owner sent a screenshot of More > Extras: "My plug" sat alone under the
grid and did not read as part of "My car is electric". He picked option C of three from a mockup:
the tile is full width and holds the row "Charger plug · Type 2" (`SettingTile.below`, `holdsRow`,
`_PlugRow`); Learn my habits is full width too. Review found one real thing: a tile whose root
widget changes type when a row comes or goes is rebuilt on every tap (no ripple, a new TalkBack
node), hence `holdsRow`.

## What is left

Nothing here is started. Each is small; ask the owner before doing any of it.

**For the owner, outside the repo**
- Republish the privacy policy at tursinalabs.com/dailylah/privacy from `docs/legal/privacy.md`
  (changed in #210: the delete is at the end of the History tab; dated 21 Nov 2026).
- Releases 2.15.0 and 2.16.0 wait for approval in the `play-production` environment unless already
  promoted (2.13.0 and 2.14.0 were promoted).
- Nobody has tried 2.12.0 to 2.16.0 on a real phone from these sessions. Everything was rendered in
  tests and run on CI emulators.
- Seven mockup pages are still published privately on the owner's account: three from the Today
  session (tiles, whole Today screen, mode picker) and four options pages from this one (Nearby,
  Home, History, More). The whole-Today one shows a raised/flat rule that was not shipped as drawn.

**Decisions the owner has not made**
- "Delete all my history" (History) has no Undo, on purpose: it is the delete the privacy policy
  promises, and the question says it cannot be undone. Adding Undo is a few lines
  (`showActionSnackBar` with `restore`, as the two removals above it do).

**Left untouched because the owner did not pick them**
- Home: the private-home card (`_PrivateCard`) still has mint chips that look tappable; watched-block
  tiles (`BlockTile`) on Blocks and agents open a page with no chevron; the hero (block number and
  street) takes half the first screen at 200% text.
- Plan a trip (`ui/trip.dart`) still uses `PillRow` for From and To, and still shows its own rain
  banner (it has no weather card).
- EV charger rows on a car trip (`_DriveBlock`) have no chevron yet (`EvChargers(chevron:)` is off
  there; it is on in Nearby and Home).
- `AlertBanner` (shared) still has a shadow and no tap; left alone on purpose since the Today session.
- History: the "n of m priced" line went with the old tiles. An unpriced meal says "Add price" on its
  row instead. Bring the count back only if the owner misses it.

**A security note, not fixed**
- Found in review of #208, in code that PR did not touch. It is described in a suggested task queued
  for the owner ("Check event links are https before opening them"), not here: the repo is public.
  The owner's private security notes repo is not named anywhere a cloud session can read, so nothing
  was saved there for any of the five PRs. Tell the owner this each time.

**Dependabot pull requests closed without merging** (21 Nov, at the owner's choice; all four had
green CI on a base from 16 Nov). Dependabot opens new ones when newer versions come out. What the
check found, for when they come back:
- #184 Gradle wrapper 9.8.2 to 9.9.1: the checksum in the PR was the `-all.zip` one, as the rule asks.
- #185 playwright-core 1.64.1 to 1.65.0 (`web/tests/e2e`): the lockfile only.
- #186 flutter_riverpod 3.4.3 to 3.5.0: adds four transitive packages to `pubspec.lock`
  (`cupertino_ui`, `material_ui`, `intl`, `flutter_localizations`). Worth its own look.
- #187 fastapi 0.162.0 to 0.162.5, pytest-asyncio, ruff: Dependabot wrote the lockfile line as
  `uvicorn[standard]==0.54.0` where `uv pip compile` writes `uvicorn==0.54.0`. Regenerate the
  lockfile with the command in `backend/requirements.in` rather than taking Dependabot's.

## How the owner likes to work

- Shows a screenshot or asks for "the mockup", names the problem, asks "can we change?".
- Wants **options side by side** (current plus two or three) on a published page, then picks by
  name ("1B, 2C, 3B, 4A, Yes"). Give a recommendation; build nothing before the pick. Say "anything
  you leave out I take as the recommended one".
- Picks are sometimes not the recommended ones, and sometimes come with a change ("ensure Delete my
  history is on History, not in More"). Build exactly that.
- Prefers **real renders from the app code** once something is built; sends "Try again" when a turn
  ends without a summary.
- Asks for "PR, review, gate and merge" in one go, and is happy for the next tab's audit and mockup
  to start while the previous PR waits on CI.
- Answers short. Ask one thing at a time, or state the default you will take.

## Tooling that worked

- **Flutter is not preinstalled in cloud sessions.** Install the pinned SDK (the version is
  `flutter-version:` in `.github/workflows/app.yml`, 3.47.9 at the time of writing):
  `curl -sSfL -o f.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_<version>-stable.tar.xz`,
  unpack to `/opt/fl`, `git config --global --add safe.directory /opt/fl/flutter`, then
  `flutter pub get --enforce-lockfile` in `app/`. About 5 minutes. Full `flutter test` takes about
  4.5 minutes (1,346 tests at 2.16.0).
- **Real renders:** a throwaway test in `app/test/` (never committed; the session's stop hook
  complains about untracked files, so move it out of the repo after each run) that pumps
  `DailyLahApp` with the harness fakes, loads the fonts as `test/golden_test.dart` does, sets a tall
  view (`Size(412, 1500)` or taller, `devicePixelRatio = 2`), and ends with
  `await expectLater(find.byType(MaterialApp), matchesGoldenFile('<absolute path>.png'))`, run with
  `--update-goldens`. Pick a tab with `containerOf(tester).read(shellTabProvider.notifier).state = n`
  (Today 0, Nearby 1, Home 2, History 3, More 4) and a section with `nearbySectionProvider` /
  `homeSectionProvider`. Render light, dark (`Condition(dark: true)`) and
  `Condition(textScale: 2.0, size: Size(320, …))`. History needs entries: restore a `Habits` with
  `habitsProvider.notifier.restore(...)`. Nearby needs a place: `nearbyKeyProvider = 'extra:0'`.
  The 200% render on 320 dp found a real bug on every tab.
- **Goldens:** `GOLDENS=1 flutter test test/golden_test.dart` compares locally and tells which
  images a change touches. Do not commit local images: run the `goldens` workflow on the branch
  (`workflow_dispatch`); it commits them in about two minutes. Fetch and fast-forward before the PR.
- **Tests to expect to touch:** `test/features_test.dart`, `test/persona_test.dart` (one case per
  feature PR), `test/screens_matrix_test.dart` (a new sheet or page gets a case), and any test that
  finds a control by type (`ListTile` became `PlaceRow`, `PillRow` and `BentoTile` are gone from the
  tabs). Text widths differ in tests without the fonts loaded: do not assert on which row a tile
  lands; assert on `SectionTiles.columns(...)`. A row scrolled to by `ensureVisible` can sit under
  the floating tab bar, so a tap misses: call the widget's `onTap` or scroll it to the middle.
- **Maestro** (`app/maestro/`): flows match visible text and accessibility text with regexes. Flows
  04, 05, 06 and 12 were updated for the new controls and passed first time. Grep the flows for any
  label a change renames.
- **Review and gate:** fresh subagents with no history, one for bugs and rules
  (`.github/prompts/review.md`) and one for security (`.claude/security-profile.md`), then one more
  on the final head. They found real things every time (a flow waiting for a removed pill, a web
  address printed in a row, a number breaking between digits, the privacy policy pointing at the old
  place). Ask them to look for every text that mentions what moved.
- **Building the next tab while a PR waits:** commit it on a local branch on top of the open PR's
  head and do not push. After the squash merge, `git checkout -B <session branch> origin/main` and
  cherry-pick: the tree is identical, so it applies cleanly. GitHub deletes the session branch on
  merge; push it again afterwards (the stop hook asks for it).

## PR, review, gate, release

- Root `CLAUDE.md`, `app/CLAUDE.md` and `.claude/skills/review-pr/SKILL.md` are the rules. A feature
  PR is a release: bump `version:` in `app/pubspec.yaml`, replace `docs/store/whatsnew/whatsnew-en-US`
  and `S.whatsNewNotes` (same lines, 500 characters at most). Update `app/CLAUDE.md` and run
  `python3 scripts/repo_map.py`.
- A change to where data is deleted or what is stored also changes `docs/legal/privacy.md` (and its
  "Last updated" date) and the landing page FAQ in `web/index.html`.
- **Attribution:** the GitHub tool appends "Generated by Claude Code" to every PR description and
  comment it writes (seen on #212). In a description it goes away with one more
  `update_pull_request`; in a comment it comes back on every edit, so the review and gate comments
  of #212 carry it. Squash commit messages carry none. Tell the owner each time.
- **This file and the PR:** it is on the session branch, so take it out in a commit before the PR is
  opened and put it back after the merge. Its old commits stay readable through the PR; keep
  anything about a security note out of it (title only, as below, is already too much: the reviewer
  of #212 flagged it as low).
- **CI noise:** every push to an open PR ends the emulator run of the previous commit, which reports
  as an "emulator result" failure for the old commit. Check the head sha before acting. Nothing
  failed on a final head in these four PRs. Earlier flakes seen: Maven Central 403/429 on the
  runners, and "Failed to start Dart Development Service"; one re-run fixed each.
- Merging a release PR starts the release run on `main`; its `promote` job waits for the owner's
  approval in the `play-production` environment.
