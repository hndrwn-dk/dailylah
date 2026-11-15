# Rich notifications: the alerts look like the landing page

Date: 2026-11-15. Status: approved by the owner on 2026-11-15.

## Why

The landing page section "A day with DailyLah" (`web/index.html`, `web/shared/day.js`) shows eight
notifications in the sticker style: a title, one or two lines, and coloured pills with a small
picture (a PSI bar, a thermometer, a week of bars). The app sends every one of those alerts today,
but as a plain Android title and body. The owner wants the app's notifications to look like the
mockup.

## Goals

- The eight alerts of the landing page show, on Android, a custom layout with pills and the small
  picture, in the sticker colours of the app and the home screen widget.
- The pills carry real values (PSI number, UV index, bus number, "Usually 38 min"), never
  placeholders. A pill whose value is not known is left out.
- Rules, wording and what goes in each pill stay in pure Dart (`logic.dart`, `l10n.dart`), tested
  there. Kotlin only draws.
- Nothing about when an alert fires changes: same triggers, same notification IDs, same channel
  (`dailylah_alerts`), same once-per-event log (`AlertLog`), same quiet hours.

## Non-goals

- A morning warning about rain on the evening trip ("Rain from 6 pm" at 7:00). The app has only
  NEA's 2-hour forecast; this needs the 24-hour forecast as a new backend dataset. Follow-up PR.
  The rain pill here says what the 2-hour forecast supports.
- Animation in a notification (falling drops, buzzing phone). Android does not allow it.
- Custom layouts for the other alerts (dengue, lightning, parking time, resale, holiday, the MRT
  ride). They stay plain. The template makes adding them later a Dart-only change.
- iOS. The app is Android only today; on any other platform the plain notification is used.
- Any change to the landing page.

## Anti-goals

- An alert that is lost because the custom layout failed. A plain notification must always be the
  fallback.
- Text drawn as pixels. Every word is a real `TextView`: it follows the system font size and
  TalkBack reads it. Only the small pictures are bitmaps, and they are decorative.
- A new permission, SDK, endpoint or log field (privacy policy stays as it is).

## Constraints found in the code

- `flutter_local_notifications` cannot show custom `RemoteViews`. A native poster is needed.
- Most alerts are posted from the WorkManager isolate (`runChecks` in `app/lib/background.dart`).
  That isolate runs in its own `FlutterEngine`, which registers only plugins from
  `GeneratedPluginRegistrant`. The channels in `MainActivity` (`dailylah/apps`, `dailylah/share`)
  do not exist there. So the poster must be a real Flutter plugin.
- Wake me at my stop (`lib/wake_session.dart`, ID 10) posts from the main isolate with `notifyNow`.
- Android: `minSdk = 29`, target 36. Android 12+ wraps a custom view in the system's own header
  (icon, app name, time) and shows the custom content collapsed in one short row and expanded up to
  256 dp. R8 is on for release builds.
- No Flutter or Android SDK in the authoring session by default: Kotlin and XML are compile-checked
  by the `emulator` workflow on the PR.

## Approaches considered

- **A. Custom Android layouts, drawn natively (picked by the owner).** A small in-repo plugin posts
  the notification with `DecoratedCustomViewStyle` and hand-written XML, like the home screen
  widget. Closest to the mockup, text stays real text. Most work: Kotlin, XML, emulator tests.
- **B. Pills painted into a picture (BigPicture).** No Kotlin, but the pill text is pixels: no font
  scaling, no TalkBack, only visible expanded as a wide banner. Dropped.
- **C. Standard Android styling** (accent colour, large icon, sub text). Small and consistent on
  every phone, but no pills: it only looks a little like the mockup. Dropped.

## Design

### 1. The note (pure Dart)

New in `app/lib/models.dart` (or `logic.dart`), no Flutter imports:

```dart
enum PillTone { amber, red, teal, mint, sky, board, line }
enum NoteArt { none, rain, psi, heat, week, phone }

class NotePill { final String text; final PillTone tone; final String? lineColor; } // lineColor: MRT line hex, tone line only
class RichNote {
  final int id;            // the existing notification id
  final String title, body;
  final List<NotePill> pills;   // 0 to 3, in order
  final NoteArt art;
  final double? artValue;       // psi: marker 0..1 on the bar; heat: fill 0..1
  final List<double> bars;      // week: 7 heights 0..1
  final String? link;           // dailylah://today | nearby | home, what a tap opens
}
```

One builder per alert in `logic.dart`, each returning a `RichNote` from values the background pass
already has, with strings from `S`. `toMap()` gives the plain map sent over the channel.

### 2. The eight alerts

Titles and bodies follow the landing page wording where the data supports it. IDs do not change.

| # | Alert (ID) | Title / body | Art | Pills |
|---|---|---|---|---|
| 1 | Rain (2) | "Rain before you leave." / "Rain near your office (Bishan): Showers. Bring an umbrella." (place label and area from the forecast, as today) | rain | amber "☂ Rain near Work"; sky "Forecast 12 pm to 2 pm" when the forecast has a valid period (`AreaForecast.validText`: NEA's forecast window, not when the rain stops, so never "until") |
| 2 | Haze (8) | "Haze: unhealthy" / `airAdviceShort(level)` | psi, marker at PSI/300 capped at 1 | red "PSI 128 Unhealthy" (amber for a level below unhealthy never fires). When PM2.5 drove the level and PSI did not: red "PM2.5 62 Unhealthy" |
| 3 | Leave by (9, and 13+i for custom places) | "Time to go" / `leaveIn(...)` as today | none | board "36" (the bus), teal "Leave in 6 min" ("Leave now" at 0), sky "Usually 38 min" only when `tripStats` has a usual time for this route and `learnHabits` is on |
| 4 | MRT disruption (1) | "Disruption on EWL" / LTA's text, as today | none | line "EWL" in the line's official colour (first disrupted line), red "Disrupted", board "858" = first direct bus for today's trip from `tripRides` on the bundles (no extra API call), only when a disrupted line is on today's trip (`planDisruption` with `mrtPlan` from the `mrt_stations` bundle), as the landing page says ("on your way"); left out when there is no trip today, the trip is not affected or there is no direct bus |
| 5 | Wake me (10) | as today | phone | amber "Your stop is next"; red "May have passed" for the passed event |
| 6 | Hawker closed tomorrow (3) | as today | none | red "Closed tomorrow", mint "Open: <name>, 400 m" when `openAlternatives` has one |
| 7 | Heat stress (5) | "Heat stress high." / "Near School. Bring water and take the sheltered way." | heat, fill by level | red "Heat stress High", amber "UV 11" from `/v1/weather/uv` (`uvIndex`), fetched only when this alert is about to be shown; left out when the call fails or UV is 0 |
| 8 | Weekly digest (12) | "This week around you" / the digest lines, as today | week: trips per day of the last 7 days | sky "≈ $24.60 this week" from `historySummary` (this week), only when `learnHabits` is on and the sum is above 0; no art when there are no trips |

The leave-by alert stands in for the mockup's "I'm leaving" card: a tap opens Today, where the
I'm leaving button is. No action button in the notification (author's call: starting a timed trip
from the shade needs the app open anyway).

Every pill text is one short line and comes from `S`.

A tap opens (author's call): Nearby for the hawker alert; the app as it is for Wake me (the ride
is running there); Today for the other six.

Decisions taken after the builder check (author's calls):

- The plain fallback uses the note's new title and body, with BigText.
- Wake me gets its own entry point; `notifyNow` stays plain for the MRT ride.
- The MRT line colours the pill needs move to pure Dart so the background isolate can use them.
- The digest art is shown only with `learnHabits`, like its pill.
- Too much content: the body shows at most 5 lines and ends in an ellipsis (a long digest or LTA
  text; the app has the rest), pills at most two rows. Art and pills are never dropped for body.
- A layout the phone cannot draw would lose the alert after posting, where no fallback can catch
  it. So the layout uses only the views every launcher and shade supports and the widget already
  uses (`LinearLayout`, `TextView`, `ImageView`), no custom fonts and no nested `RemoteViews`. No
  kill switch.

### 3. The plugin

`app/packages/dailylah_notify/` (author's call on the name), a path dependency of the app, Android
only (`flutter: plugin: platforms: android:`), Kotlin, namespace
`com.tursinalabs.dailylah.notify` (the app id and `scripts/check-app-id.sh` are untouched: they
read only `app/android/app/build.gradle.kts`).

- Dart side: `Future<bool> showRichNote(Map<String, Object?> note)` on the method channel
  `dailylah/notify`. Returns false on any error or a missing plugin.
- Kotlin side: builds the notification with `NotificationCompat` on channel `dailylah_alerts`
  (creates it with the same name, description and high importance if it does not exist yet), the
  same small icon as today, `setContentTitle`/`setContentText` (shade summary, TalkBack, watches),
  `DecoratedCustomViewStyle`, and one `RemoteViews` layout used for the expanded and the heads-up
  view. The collapsed view stays the system's title and text. A tap opens `MainActivity` with the
  note's `link` as data (the widget's `dailylah://` links, read by `tabForWidgetUri`); auto-cancel.
- Layout (`res/layout/dl_note.xml` in the plugin): body text (title is in the system header row on
  12+; on 10/11 the layout shows title and body), an `ImageView` for the art, three pill
  `TextView`s in a wrapping row. Unused slots are `GONE`. Pills: solid sticker fill, 2 dp ink
  outline, ink text (white on red, board and line), drawables per tone in the plugin. Title and
  body use the notification text appearances so light and dark follow the system; pills keep their
  own colours in both.
- Art: drawn in Kotlin with `Canvas` into a small bitmap (`setImageViewBitmap`): PSI bar in
  green/amber/red with an ink marker, thermometer with red fill, seven bars, umbrella, phone. No
  text in bitmaps. `contentDescription` null (decorative).
- Pill text sizes are in sp; the row wraps so 200% text and a narrow shade still show whole words
  (a pill that does not fit moves to the next row; at most two rows).
- R8: a keep rule for the plugin class in `android/app/proguard-rules.pro` if the release emulator
  job needs it; layouts and drawables are referenced from code, so no `keep.xml` entry.

### 4. Posting

In `background.dart`, one function replaces the direct `notifications.show` for the eight alerts:

```dart
Future<void> showNote(RichNote n) async {
  if (!await DailylahNotify.show(n.toMap())) {
    await notifications.show(id: n.id, title: n.title, body: n.body, ...BigText as today);
  }
}
```

`notifyNow` gains the same path for the wake alert. The plain fallback is exactly today's
notification. Other alerts keep calling `notifications.show`.

### 5. Show me an example

In every build (owner's decision): More > Alerts gets a row "Show me an example". It posts the
eight notes with sample values (the landing page's: PSI 128, bus 36, EWL and 858, UV 11), each
under its own alert's ID, so the owner can check every layout on the alpha build before promoting
and a user can see what the alerts look like. It asks for the notification permission first when
it is missing. The samples do not touch `AlertLog`, so a real alert still fires afterwards. The
integration test uses the same samples.

### 6. Tests

- `test/logic_test.dart`: each builder: wording, pill order, a pill left out when its value is
  missing (no UV, no direct bus, habits off), PSI marker capped, PM2.5-driven haze.
- `test/background_rules_test.dart`: the pass sends the rich note on the `dailylah/notify` channel
  with the expected map; when the channel answers false or is missing, the plain notification is
  shown once; once-per-event still holds.
- `integration_test/app_test.dart` (emulators, API 29/35/36): post every sample note through the
  real plugin and find it among the active notifications; no crash on any API level.
- `scripts/emulator_release.sh` already runs the WorkManager job on the R8 build; it must still
  pass (catches a stripped plugin class).
- How it looks on a real shade is checked by the owner on a phone with "Show me an example" on the alpha build; CI
  cannot judge that.

### 7. Docs and release

- `app/CLAUDE.md`: feature map entry "Alerts" gains the rich notes, the plugin and the fallback;
  `python3 scripts/repo_map.py` for `docs/REPO_MAP.md` and `AGENTS.md`.
- Feature release: `version:` 2.5.0 → 2.6.0, `docs/store/whatsnew/whatsnew-en-US` and
  `S.whatsNewNotes` say the alerts got a new look.
- `app/pubspec.lock` updated for the path dependency.
- Privacy policy: no change (one more read of the public UV reading, no user data).
- PR description says the Kotlin and XML were compile-checked by CI, not locally, if that is how
  it went.

## Left to the builder

- Exact dp sizes, paddings, bitmap sizes and the drawing of each art, guided by the landing page
  CSS (`.pill`, `.psi`, `.therm`, `.bars` in `web/index.html`) and the widget's colours
  (`res/values*/` of the app).
- Exact `S` strings where the table gives an example.
- Whether the note classes live in `models.dart` or `logic.dart`.
- Whether the keep rule is needed.
