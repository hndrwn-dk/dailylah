# DailyLah: handoff for the next chat

Start here, then read `CLAUDE.md` (the feature map is kept current there) and `docs/PRD.md`.

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
    `GIT_SHA` so About shows the version and commit, e.g. `0.2.0 (a8d2bba)`.
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
