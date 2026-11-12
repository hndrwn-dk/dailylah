# DailyLah: deploy and secrets

How the hosted parts of DailyLah and the GitHub side of CI are set up. The app ships through
GitHub Actions to Google Play ([QA.md](QA.md)); this page covers the backend, the website, the data
workflow, the release environments and the rulesets.

## Services

1. **Render**: New > Blueprint > pick this repo (uses `render.yaml`). Set the secret env vars.
2. **Upstash**: create a Redis database (Singapore region if available) and set `REDIS_URL`.
   In QStash, copy the signing keys into `QSTASH_CURRENT_SIGNING_KEY` and `QSTASH_NEXT_SIGNING_KEY`.
3. **Schedule the poller** once Render is live:
   `QSTASH_TOKEN=... API_URL=https://<your-service>.onrender.com ./scripts/create-qstash-schedule.sh`
4. **Neon**: create a project, enable PostGIS (`CREATE EXTENSION postgis;`) and set `DATABASE_URL`.
5. **Vercel**: import the repo, set Root Directory to `web`, Framework Preset "Other". The build
   command and output folder come from `web/vercel.json` (`bash build.sh`: with the data
   published from the branch `data` it lays that branch over the site, see
   [Data branch](#data-branch)); leave the dashboard's build and output settings empty. The app tries
   `https://dailylah.sg`, then `https://dailylah.tursinalabs.com`, then
   `https://dailylah-web.vercel.app`. To use a single other host, build with
   `--dart-define=WEB_URL=https://<host>`.
6. **Data bundles**: add the repo secrets `LTA_ACCOUNT_KEY`, `ONEMAP_EMAIL` and `ONEMAP_PASSWORD`
   (`DATAGOV_API_KEY` and `GEOAPIFY_API_KEY` are optional; see the header of `data.yml`). The push
   job also needs the `data-push` environment with its deploy key `DATA_PUSH_SSH_KEY` and the
   Vercel deploy hook, set up as in [Data branch](#data-branch) below. Then run the `data` workflow once (Actions > data > Run
   workflow). After that it runs daily.

## Secrets

Backend env vars (see [`backend/.env.example`](../backend/.env.example)):

| Env var | Where to get it |
| --- | --- |
| `DATAGOV_API_KEY` | data.gov.sg developer portal |
| `LTA_ACCOUNT_KEY` | LTA DataMall account |
| `ONEMAP_EMAIL`, `ONEMAP_PASSWORD` | OneMap API registration |
| `URA_ACCESS_KEY` | URA Data Service |
| `GEOAPIFY_API_KEY` | Geoapify dashboard (backend only, never in the app) |
| `PLACES_DAILY_BUDGET` | Optional, default 1,900: place search calls to Geoapify per UTC day. Keep it below the key's daily cap in the Geoapify dashboard (2,000), because the daily data build uses the same key |
| `REDIS_URL` | Upstash Redis console |
| `QSTASH_*_SIGNING_KEY` | Upstash QStash console |
| `DATABASE_URL` | Neon console |
| `PUBLIC_BASE_URL` | Your Render service URL |

Never commit `.env`, API keys or keystores. In CI, the data build keys are repo secrets; the
signing, Play and data-push keys live in their own GitHub environments (`signing`, `play`,
`play-production`, `play-rollout`, `data-push`); none of them is a repository secret. See "CI security" in [`CLAUDE.md`](../CLAUDE.md).

## Release signing environments
Set up by hand under Settings > Environments, each limited to `main` with no admin bypass:
- `signing`: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD`, and the environment variable `UPLOAD_CERT_SHA256` (checked against
  keytool and Play Console). Its source in Play Console: Protected with Play > Play Store
  protection > Manage Play app signing > Upload key certificate > SHA-256. Do not use the
  "App signing key certificate" on the same page: that is Google's key, and every sign would fail.
- `play`: `PLAY_SERVICE_ACCOUNT_JSON`, the key of the testing service account (testing tracks
  only; uploads from `app.yml`).
- `play-production`: `PLAY_SERVICE_ACCOUNT_JSON`, the key of the production service account (a
  different account, see below), required reviewer: the repo owner (prevent self-review off).
  Used by the `promote` job of `app.yml` and by `promote.yml`, never by the upload job (`app.yml`
  offers no production track).
- `play-rollout`: `PLAY_SERVICE_ACCOUNT_JSON`, a key of the same production service account, no
  reviewer. Used by `rollout-guard.yml` only ("Production releases" step 6).

## Production releases
One-time settings for docs/QA.md "Production release (automatic)". All of them work in a phone
browser (github.com, play.google.com/console and console.cloud.google.com; the GitHub mobile app
does not show repository settings).

The owner approves the first step of every release to production (20%); the guard then raises
it without asking. Steps 1 to 5 can be done now. **Steps 6 and 7 come last**: they give the
guard a production key that no person stands in front of, so do them only when nothing but a
merged pull request can put a commit on `main` ([Data branch](#data-branch), all steps: the
`main` ruleset has no bypass).

1. **Version bumps go to closed testing.** GitHub > the repository > Settings > Secrets and
   variables > Actions > Variables tab > New repository variable: Name `PLAY_PUSH_TRACK`, Value
   `alpha`. (See "Release track for a version bump" below to turn it off again.) Keep it `alpha`:
   with any other value nothing is promoted to production.
2. **Production has a service account of its own.** Environment `play` hands its key to the
   third-party upload action on every closed-testing release, so that account must never be able
   to release to production. Two accounts:
   - The existing one (in `play`): Play Console > Users and permissions > the service account
     (its email ends in `.iam.gserviceaccount.com`) > App permissions > DailyLah. Under Releases
     keep only **"Release apps to testing tracks"**; "Release to production, exclude devices, and
     use Play App Signing" stays **off**. Save changes.
   - A new one, for production only: Google Cloud Console > IAM & Admin > Service accounts >
     Create service account (no project role) > Keys > Add key > JSON. Play Console > Users and
     permissions > Invite new users: its email, App permissions > DailyLah: **"Release to
     production, exclude devices, and use Play App Signing"**, "Release apps to testing tracks"
     and "View app information and download bulk reports (read-only)"; nothing else (no financial
     data, no store presence, no admin). Play Console sometimes renames permissions: pick the one
     in the Releases group that names production.
   - GitHub > Settings > Environments > `play-production` > `PLAY_SERVICE_ACCOUNT_JSON`: replace
     it with the new key file (all of it), then delete the downloaded file. Never paste the key
     in a chat. `play` keeps the old key.
   - Settings > Secrets and variables > Actions > Variables > New repository variable: Name
     `PLAY_TESTING_ACCOUNT`, Value the email of the **existing** (testing) service account. It is
     not a secret. The promote job, the guard and `promote` refuse to run when the production key
     belongs to that account; while the variable is missing only a dry run works, with a warning.
     This is a setup check: what keeps the testing account out of production is its Play Console
     permission above.
3. **`play-production` asks the owner.** Settings > Environments > `play-production`: Required
   reviewers lists the owner, "Prevent self-review" is off (the owner's merge starts the run and
   he approves it), Deployment branches and tags = Selected branches, `main` only, "Allow
   administrators to bypass configured protection rules" off, no wait timer, and the secret
   `PLAY_SERVICE_ACCOUNT_JSON` is listed. This stays: it is the one tap of a release.
4. **Android vitals for the guard.** The guard reads crash and ANR rates with the production
   service account:
   - Play Console > Users and permissions > the **production** service account > App permissions
     > DailyLah: **"View app information and download bulk reports (read-only)"** is ticked (step
     2 already asks for it; the Reporting API's reference calls it "View app information
     (read-only)"). No other new permission.
   - Google Cloud Console (console.cloud.google.com) > the project that owns the service account
     > APIs & Services > Library > search **"Google Play Developer Reporting API"** > Enable.
     ("Google Play Android Developer API" is already enabled there; it is a different API.)
5. **Promote after one tap.** Settings > Secrets and variables > Actions > Variables > New
   repository variable: Name `AUTO_PROMOTE`, Value `on`. From the next version bump the `app` run
   ends with the job "promote to production (staged, 20%)" waiting for you: GitHub mobile >
   the notification > Review deployments > Approve. **To stop:** edit the variable to `off` (or
   delete it); Actions > promote still works by hand.
6. **The guard's environment** (only after "Data branch" is done, see above). The key file of
   step 2 was deleted, so make another key for the same account: Google Cloud Console > IAM &
   Admin > Service accounts > the production account > Keys > Add key > JSON. Then GitHub >
   Settings > Environments > New environment `play-rollout` (if one with that name is already
   listed, delete it first and make it new): Deployment branches and tags =
   Selected branches, `main` only; no required reviewers; "Allow administrators to bypass
   configured protection rules" off; save and read the branch rule back; only then Add secret `PLAY_SERVICE_ACCOUNT_JSON` = the new key file
   (all of it); delete the downloaded file. Never paste the key in a chat. Check it: Actions >
   rollout-guard > Run workflow on `main` with `dry_run` on; its summary shows what production
   holds, "no staged rollout" or the hold and health lines, and no warning about
   `PLAY_TESTING_ACCOUNT`. `HTTP 403` naming the Reporting API means step 4 is not done; "Secret
   PLAY_SERVICE_ACCOUNT_JSON is not set" means the environment has no key yet. Do not run it
   before the environment exists: GitHub would make an empty `play-rollout` open to every branch.
7. **Switch the guard on** (only after step 6). Same Variables tab: Name `AUTO_ROLLOUT`, Value
   `on`. From then on the guard raises a staged release every two days and halts it when vitals
   are worse. **To stop:** edit the variable to `off` (or delete it); then nothing raises or
   halts a release until you do it with Actions > promote.
8. Optional, same Variables tab, only to change a default: `ROLLOUT_HOLD_HOURS` (48),
   `ROLLOUT_MIN_USER_DAYS` (500), `ROLLOUT_CRASH_BAD_PERCENT` (1.09), `ROLLOUT_ANR_BAD_PERCENT`
   (0.47), `ROLLOUT_WORSE_FACTOR` (1.5). Their meaning: docs/QA.md "Rollout guard".
9. Optional: Issues > Labels > New label `release-halted` and `release-rollout`, to pick their
   colours (the guard creates both the first time it needs them), and watch the repository's
   issues in the GitHub mobile app so a `release-halted` issue is a push notification.

## Release track for a version bump
Repository variable `PLAY_PUSH_TRACK` (Settings > Secrets and variables > Actions > Variables tab)
decides what a version bump on `main` does (docs/QA.md "Manual releases"):
- Not set, or `manual`: build, test, sign, tag `v<version>` and a draft GitHub Release with the AAB,
  mapping and release notes. No Google Play upload; the owner uploads in Play Console by hand.
- `alpha`: the same, and the `play` job uploads to closed testing. Production then follows after
  one approval while `AUTO_PROMOTE` is `on` ("Production releases" above), else with Actions >
  promote.
- Switch the automatic upload back on: New repository variable (or edit), Name `PLAY_PUSH_TRACK`,
  Value `alpha`, Add variable. Turn it off again: set it to `manual` or delete it.
- Check it on the next release: the `analyze` job says `Release (manual upload)` or
  `Release ... goes to alpha`, and `upload to Google Play (…)` is skipped or runs.

## Rulesets
Set up by hand: Settings > Rules > Rulesets > New.

**`main`** (New branch ruleset; Enforcement: Active; Target: Include default branch):
1. Restrict deletions; Block force pushes.
2. Require a pull request before merging: required approvals **0** (the owner cannot approve their
   own PR); Allowed merge methods: **Squash** only.
3. Require status checks to pass, "Require branches to be up to date" **off**. Add these, source
   GitHub Actions (names exactly as GitHub shows them; docs/QA.md "Required checks"):
   `app result`, `emulator result`, `backend result`, `web result`, `repo map and AGENTS.md up to date`, `CodeQL (actions)`, `CodeQL (python)`,
   `osv-scanner (dependencies)`, `zizmor (workflows)`.
4. Bypass list: **empty**. The data is published from the branch `data`
   ([Data branch](#data-branch), step 6), so nothing pushes to `main`: only a merged pull
   request puts a commit there. (Deploy keys were on this list while `web/data-source.txt` said
   `main`; going back needs them again.) `screenshots.yml` never pushes to `main` and `goldens.yml` skips
   `main`.
5. Do not add yourself as a bypass actor: merges go through PRs like everything else.

**`v*` tags** (New tag ruleset; Enforcement: Active; Target: Include by pattern `v*`):
1. Restrict updates (a release tag never moves); Restrict deletions; Block force pushes.
2. Restrict creations: leave off. `release-tag` creates the tags and GitHub Actions cannot be a
   bypass actor on a personal repository; only the owner and Actions can write to this repository.

After both are on, check: a docs-only PR shows all nine checks green and can be squash-merged;
`git push --force` to `main` and `git push --delete origin v1.9.2` are refused.

## Data branch
Where the daily and weekly data (`data.yml`, `where-to-live.yml`) is published from is one word in
`web/data-source.txt` on `main`, changed only by a pull request:

- **`data`** (today, since 12 Nov 2026): the push job pushes to the branch `data` and never to
  `main`, then calls a Vercel deploy hook; the site's build step (`web/build.sh`) lays the `data`
  branch over `main` in every deployment, previews of pull requests included. The `main` ruleset
  needs no bypass.
- **`main`** (before): the push job pushes the update to `main` with the deploy key, and Vercel
  deploys on that push. The deploy key must then be in the `main` ruleset's bypass list. The
  branch `data` gets a copy of the data files after each update; nothing reads it.

The `data` branch holds only data files: `web/data/*.json`, the generated town pages
`web/where-to-live-towns/*.html`, `web/sitemap.xml`, and the builds' caches
`backend/data/geocode.json`, `where_to_live_routes.json` and `build_report.json`. Each workflow
builds in a read-only job and hands a patch to a `push` job in environment `data-push`, which
runs `scripts/push_data.sh` (GitHub's host key pinned, key file removed after). With source
`data` it starts from the newest `main` for the code, lays the newest `data` branch over it,
checks and applies the patch, runs main's own page generator, and pushes a commit with only
those files to `data`. The copies of these files on `main` are what the tests read: a pull
request that edits one changes neither the site nor its Vercel preview. Refresh
them with an ordinary pull request when a test needs newer data (a new town also needs its
share image, `scripts/build_og_images.py`). Two things on `main` still reach the published data:
`web/data/school_holidays.json` (written by hand; in the push job main's copy always wins, and a
change to it starts the `data` workflow, whose update brings it to the site a few minutes later) and the page generator `backend/app/where_to_live_pages.py` (a
change to it starts `where-to-live`, which makes the published pages again).

**Moving from `main` to `data`** (done on 12 Nov 2026; kept for a new repository or after going
back), all in a phone browser, in this order:

1. **Deploy key and environment** (already there): create a pair (`ssh-keygen -t ed25519 -f
   dailylah-data-push -N ""`, on a laptop or in Termux); Settings > Deploy keys > Add: the `.pub`
   file, title `data-push`, **Allow write access**; Settings > Environments > New `data-push`:
   Deployment branches `main` only, no admin bypass; Add secret `DATA_PUSH_SSH_KEY` = the private
   key file (all lines, including BEGIN and END); then delete both local key files. Never paste
   the private key in a chat. Keep exactly one deploy key on the repository.
2. **Only the deploy key may write the `data` branch.** First delete the branch `data` if it is
   there (the repository's Branches page > the bin next to `data`): what it holds from before the
   ruleset is not to be trusted, and the next data update makes it again from `main`. Then
   Settings > Rules > Rulesets > New branch
   ruleset `data`: Enforcement Active; Target: Include by pattern `data`; tick **Restrict
   creations**, **Restrict updates**, **Restrict deletions** and **Block force pushes**; Bypass
   list: **Deploy keys** (Always), nothing else. This is required, not optional: once the site
   is built from this branch, whoever can push to it can change what the site and the app show,
   and without the ruleset every workflow with write access could. Check it: wait for a `data` run
   whose `push` job says "Pushed to main" with no warning about the copy on the data branch (a run
   that says "No data changes" has not made the branch); the Branches page then shows `data`
   again, updated by dailylah-bot.
3. **Deploy hook.** vercel.com > the project (dailylah-web) > Settings > Git > Deploy Hooks: Name
   `data`, Branch `main`, Create Hook, copy the URL (it starts with
   `https://api.vercel.com/v1/integrations/deploy/`). GitHub > Settings > Environments >
   `data-push` > Add secret: Name `VERCEL_DEPLOY_HOOK`, Value that URL. The URL can only start a
   deployment of `main`; still, never paste it in a chat.
4. **Switch.** Right after a `data` run that ended without a warning about the copy (so the
   `data` branch equals `main`'s data): a pull request that changes `web/data-source.txt` from
   `main` to `data`, and nothing else. Its Vercel
   preview already builds from the `data` branch: the build log must show
   "data: N .json files from the data branch", and the preview's `/data/manifest.json` must be the
   current one. Merge it. Both data workflows start once on that merge.
5. **Check it.** Actions > data > Run workflow: the `push` job says "Pushed to data: ..." and
   "Asked Vercel to deploy the site." (or the build says "No data changes"). In Vercel the new
   deployment's build log shows the same line as in step 4, and
   `https://dailylah.sg/data/manifest.json` shows today's version.
6. **Take the deploy key out of the `main` ruleset.** Only after step 5 worked: Settings > Rules >
   Rulesets > `main` > Bypass list > remove "Deploy keys" > Save. From then on nothing but a
   merged pull request reaches `main`.
7. Optional: Vercel > Settings > Git > Ignored Build Step, the command
   `[ "$VERCEL_GIT_COMMIT_REF" = "data" ]` stops Vercel from building a preview for every push to
   the `data` branch.

Going back takes three steps, in this order, because by then the copies on `main` are old:
put "Deploy keys" back in the `main` ruleset's bypass list; merge a pull request that brings the
current files of the `data` branch onto `main` (the bundles, town pages, sitemap and the three
files in `backend/data/`); only then the pull request that changes `web/data-source.txt` back to
`main`. Reversing the switch alone would make the site serve the old copies until the next
data runs.

What the `data` branch can and cannot do once it is the source: whoever can write it can change
the data the app and the site show and the town pages (served with the site's CSP), as the deploy
key could before. They cannot put a commit on `main`, so no workflow, script or app code.
`web/build.sh` takes only plain `.json` files into `data/`, `.html` files into
`where-to-live-towns/` and a sitemap that is nothing but a list of dailylah.sg URLs;
`push_data.sh` refuses a `data` branch that holds anything else before it runs main's generator,
and reads `main` and `data` by their full branch names. If the branch cannot be downloaded, the
site build fails and the previous deployment stays up. A branch or tag whose name merely ends in
`refs/heads/main` or `refs/heads/data` stops the data update with an error that names it (git
cannot tell such a name from the real branch when it pushes): delete that ref.

## GitHub security settings
Settings > Advanced Security (or Code security):
1. **Secret scanning**: Enable. Then **Push protection**: Enable.
2. **Dependabot alerts**: Enable. **Dependabot security updates**: Enable.
3. **Code scanning**: leave **Default setup** off (or switch it off). `security.yml` is an
   advanced setup, and GitHub rejects its CodeQL uploads while default setup is on.

## Domains
- `dailylah.sg` is the website and the first host for data bundles; `dailylah.tursinalabs.com`
  and `dailylah-web.vercel.app` are fallbacks (same Vercel deployment, `webUrls` in `api.dart`).
- Privacy and terms stay at `tursinalabs.com/dailylah/privacy` and `/terms`;
  `dailylah.sg/privacy` and `/terms` redirect there (`web/vercel.json`).

## Build locally
- App: `cd app && flutter pub get && flutter analyze && flutter test`.
- Release APK:
  - Set `ANDROID_KEYSTORE_PATH` (the path to your local upload keystore file),
    `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` as env vars. Never commit them.
  - Run `scripts/build-apk.ps1` (Windows) or `scripts/build-apk.sh`. They pass `APP_VERSION` and
    `GIT_SHA` so About shows the version and commit, e.g. `2.0.0 (build 294 · a8d2bba)`.
- Backend: `cd backend && pip install -r requirements-dev.txt && pytest && ruff check .`
- Bundles:
  - Run `cd backend && python -m app.build_static`. It needs the secrets in `.env`.
  - Copy the output into `web/data/` and push.
