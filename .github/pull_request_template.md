## What

## Why

## How it was tested

## Not testable before the next release
<!-- Workflow or release changes only: what runs only on main or on a release, and what to watch on the first one. Otherwise "n/a". -->

## Settings to do by hand
<!-- Rulesets, environments, secrets, variables: the steps, also in docs/DEPLOY.md. Otherwise "none". -->

## Checklist
<!-- Tick what is done; write "n/a" after an item that does not apply. -->
- [ ] AI review ("review PR #N") ran on the current head commit (its comment marker has the head sha).
- [ ] Security gate comment by `hndrwn-dk`, `Security gate: pass at <short sha>.`, for the head commit (needed when `app/`, `backend/`, `.github/` or `.claude/` change).
- [ ] `docs/legal/privacy.md` updated if data handling changed (permission, SDK, endpoint, log field).
- [ ] Release only: `version:` bumped, `docs/store/whatsnew/whatsnew-en-US` and `S.whatsNewNotes` updated; other PRs leave all three alone.
- [ ] Structure changed: feature map (`app/CLAUDE.md` / `backend/CLAUDE.md`) and `docs/REPO_MAP.md` updated.
- [ ] No security finding details (public repo) and no AI attribution in this PR.
