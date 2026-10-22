# DailyLah: handoff for the next chat

Start here, then read `CLAUDE.md` and `docs/PRD.md`.

## Status (21 Oct 2026)
- PR #24 is merged into `main`. It contains:
  - Release start-up fix: R8 is off.
  - "Leave work" / "Leave school" labels.
  - "Upgrading" chip.
  - Red Emergency and Meeting points chips.
  - New logo and Welcome wordmark.
  - Play Store icon (`app/assets/store/play-icon-512.png`) and feature graphic (`docs/feature_design/`).
  - Home: Food and Parking split, with a Halal chip.
  - ActiveSG "Book on ActiveSG".
  - Today: taxis shown once when Taxi is the trip mode.
- The last two commits (ActiveSG, taxi dedupe) were merged without CI. Run analyze and test locally first.
- Still to confirm on a phone: onboarding stays saved after the app is closed and reopened.

## Latest batch (22 Oct 2026, branch feat/daily-companion)
Nearby section chips, clearer Watch/Compare, Plan B for MRT disruptions, leave-by, wake me at my
stop, I parked here, weekly digest (+ holidays.json bundle), weather tips per mode, know-me
(trip times, meal suggestions). ERP on the route is not possible: LTA removed the ERP rates API
from DataMall in Sep 2024. Return Right machine locations: website terms forbid reuse; ask BCRS.

## Domains
- `dailylah.sg` is the website and the first host for data bundles; `dailylah.tursinalabs.com`
  and `dailylah-web.vercel.app` are fallbacks (same Vercel deployment, `webUrls` in `api.dart`).
- Privacy and terms stay at `tursinalabs.com/dailylah/privacy` and `/terms`;
  `dailylah.sg/privacy` and `/terms` redirect there (`web/vercel.json`).

## Build locally: GitHub Actions minutes are used up
These workflows do not run until the quota resets: app.yml (APK), data.yml (daily bundles), and the persona and probe workflows.

App:
```
cd app
flutter pub get
flutter analyze
flutter test
```

Signed release APK. Set these env vars, never commit them, then build:
- `ANDROID_KEYSTORE_PATH` = `C:\Users\hendr\Deployment\signed\dailylah\dailylah-upload.jks`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Run `flutter build apk --release`. The output is `app/build/app/outputs/flutter-apk/app-release.apk`.

Backend:
```
cd backend
pip install -r requirements-dev.txt
pytest
ruff check .
```

Data bundles:
- Build with `cd backend && python -m app.build_static`. It needs the secrets in `.env`: LTA, OneMap, URA.
- Copy the output into `web/data/` and push. Vercel serves it.
- Until this runs, `around.json` has no ActiveSG points.

## How Hendrawan works
- Chats in Indonesian. The app is English only.
- "diskusi dulu" = discuss only, do not build.
- One PR and one APK per batch. Ask before merging.
- Never ask for secrets in chat. Keep the app religion-neutral: halal and prayer times are opt-in.
- Keep the sticker theme.
