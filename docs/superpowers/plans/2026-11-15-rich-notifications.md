# Rich Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The eight alerts of the landing page's "A day with DailyLah" show on Android with sticker pills and a small picture instead of plain text.

**Architecture:** Pure Dart builds a `RichNote` per alert (title, body, up to 3 pills, art). A small Android-only plugin inside the repo (`app/packages/dailylah_notify`) posts it with `DecoratedCustomViewStyle` and one hand-written `RemoteViews` layout. `background.dart` sends the note to the plugin and falls back to the plain `flutter_local_notifications` notification when the plugin answers false.

**Tech Stack:** Flutter 3.47.9 (pinned in the workflows), Dart, Kotlin, Android `RemoteViews`, `flutter_local_notifications` 22, `workmanager` 0.10.

**Spec:** `docs/superpowers/specs/2026-11-15-rich-notifications-design.md`

## Global Constraints

- Triggers, notification IDs (rain 2, haze 8, leave 9 and 13+i, MRT 1, wake 10, hawker 3, heat 5, digest 12), channel `dailylah_alerts`, `AlertLog` keys and quiet hours do not change.
- `lib/models.dart`, `lib/logic.dart`, `lib/l10n.dart` stay pure Dart (no Flutter import). Every user-facing string goes through `S`.
- A pill whose value is unknown is left out. No text in bitmaps. Layout uses only `LinearLayout`, `TextView`, `ImageView`.
- No new permission, SDK, endpoint or log field. App id and namespace of `app/android/app` untouched.
- Commits: author Hendrawan, no AI attribution, English imperative. One branch (`claude/sweet-pascal-sm6tvk`), no PR unless the owner asks.
- Toolchain in the session: install Flutter 3.47.9 (`https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz`) outside the repo and run `flutter pub get --enforce-lockfile` (without the flag only in Task 2, which changes the lockfile), `flutter analyze`, `flutter test`. Kotlin and XML are compile-checked by the `emulator` workflow, not locally, unless an Android SDK turns out to be available; say which in the final report.
- App commands run from `app/`.

## Review Focus

1. Plugin missing or throwing (tests, a stripped class under R8): the plain notification must still show, once. Test in Task 3.
2. Body far longer than the layout (digest with many lines, long LTA text): notification still posts; body capped at 5 lines, pills kept. `maxLines`/`ellipsize` in Task 2's layout; sample with a long body in Task 4's integration test.
3. Values that would make a nonsense pill: UV 0 or missing, no direct bus, disruption on a line not on today's trip, habits off, PSI above 300. Tests in Task 1.
4. 200% system text on a narrow shade: pills wrap to a second row, whole words. Row split rule in Task 2 (pills 1-2 on row one, pill 3 on row two) so nothing depends on measuring.
5. "Show me an example" with notifications not allowed: asks for the permission, posts nothing and says so when refused; never writes `AlertLog`. Test in Task 4.

---

### Task 1: The note and its eight builders (pure Dart)

**Files:**
- Modify: `app/lib/models.dart` (note classes), `app/lib/logic.dart` (builders, line colours), `app/lib/l10n.dart` (strings), `app/lib/ui/theme.dart` (`DL.lineColors` reads the pure map)
- Test: `app/test/logic_test.dart`

**Interfaces — Produces:**

```dart
// models.dart
enum PillTone { amber, red, teal, mint, sky, board, line }
enum NoteArt { none, rain, psi, heat, week, phone }
class NotePill { const NotePill(this.text, this.tone, {this.lineColor}); final String text; final PillTone tone; final int? lineColor; } // 0xRRGGBB
class RichNote {
  const RichNote({required this.id, required this.title, required this.body, this.pills = const [],
      this.art = NoteArt.none, this.artValue, this.bars = const [], this.link});
  Map<String, Object?> toMap(); // id, title, body, pills:[{text,tone,lineColor}], art (name), artValue, bars, link
}

// logic.dart
const mrtLineColors = <String, int>{...}; // moved from DL.lineColors, same codes and colours
RichNote rainNote(S s, {required String placeKind, required AreaForecast f});
RichNote hazeNote(S s, AirQuality air);
RichNote leaveNote(S s, LeaveBy lb, {int id = 9, String? placeName, int? usualMinutes});
RichNote mrtNote(S s, List<LineStatus> bad, {String? planBBus});
RichNote wakeNote(S s, WakeEvent ev, String stop);
RichNote hawkerNote(S s, String name, {String? altName, double? altMetres});
RichNote heatNote(S s, {required String place, required String level, int? uv});
RichNote digestNote(S s, List<String> lines, {int? weekCents, List<int> tripsPerDay = const []});
/// First direct bus for today's trip when a disrupted line is on it; null otherwise.
String? planBBus({required MrtPlan? plan, required Map<String, dynamic>? alerts, required Iterable<String> directServices});
List<RichNote> sampleNotes(S s); // the eight, landing page values, real ids
```

Spec values to pin: links `dailylah://today` for all but hawker (`dailylah://nearby`) and wake (null). Haze `artValue = min(psi24 / 300, 1)`; pill "PSI 128 Unhealthy" red, or "PM2.5 62 Unhealthy" when `pm25Level(pm25).index > psiLevel(psi24).index` or psi is null. Leave pills in order: board service, teal "Leave in 6 min" / "Leave now" at 0, sky "Usually 38 min" only when `usualMinutes != null`. MRT pills: line (first disrupted line, its colour), red "Disrupted", board bus when `planBBus != null`. Heat: red "Heat stress High", amber "UV 11" only when `uv != null && uv > 0`; title "Heat stress high.", body "Near School. Bring water and take the sheltered way."; art heat, `artValue` 1. Rain: title "Rain before you leave.", body "Rain near your office (Bishan): Showers. Bring an umbrella." built from `placeLabel`, area and forecast; pills amber "☂ Rain near Work", sky "Forecast 12 pm to 2 pm" when `validText` is non-empty. Digest: sky "≈ $24.60 this week" only when `weekCents != null && weekCents > 0`; art week with `bars` = trips per day scaled to the max, empty (art none) when all zero. Wake: amber "Your stop is next" / red "May have passed", art phone. Hawker: red "Closed tomorrow", mint "Open: Name, 400 m" when alt given.

- [ ] **Step 1:** Write failing tests in `logic_test.dart`, group `rich notes`: one test per builder asserting title, body, pill texts/tones in order, art, link with the values above; plus `uv 0 and null leave the UV pill out`, `no usual time leaves the sky pill out`, `PSI 420 caps the marker at 1`, `PM2.5 62 with PSI 80 shows the PM2.5 pill`, `planBBus is null when the disrupted line is not on the plan`, `planBBus is null with no direct service`, `digest with no trips has no art`, `sampleNotes has the eight ids 2, 8, 9, 1, 10, 3, 5, 12`, `toMap round-trips through StandardMessageCodec` (encode with `const StandardMessageCodec()`).
- [ ] **Step 2:** `flutter test test/logic_test.dart --plain-name "rich notes"` → fails (undefined names).
- [ ] **Step 3:** Implement the classes, builders, strings in `S`, and move the line colours (`DL.lineColors` becomes `{for (e in mrtLineColors.entries) e.key: Color(0xFF000000 | e.value)}`).
- [ ] **Step 4:** `flutter test test/logic_test.dart` and `flutter analyze` → pass, no issues.
- [ ] **Step 5:** Commit "Add rich note model and builders for the eight alerts".

### Task 2: The `dailylah_notify` plugin

**Files:**
- Create: `app/packages/dailylah_notify/pubspec.yaml` (plugin, `platforms: android: {package: com.tursinalabs.dailylah.notify, pluginClass: DailylahNotifyPlugin}`), `lib/dailylah_notify.dart`, `android/build.gradle.kts` (namespace `com.tursinalabs.dailylah.notify`, minSdk 29, same Kotlin/AGP style as the app), `android/src/main/AndroidManifest.xml`, `android/src/main/kotlin/com/tursinalabs/dailylah/notify/DailylahNotifyPlugin.kt`, `NoteArt.kt`, `android/src/main/res/layout/dl_note.xml`, `res/drawable/dl_note_pill_{amber,red,teal,mint,sky,board,line}.xml`, `res/values/dl_note_colors.xml`
- Modify: `app/pubspec.yaml` (`dailylah_notify: {path: packages/dailylah_notify}`), `app/pubspec.lock`, `.github/dependabot.yml` only if the pub entry needs the path ignored
- Test: `app/packages/dailylah_notify/test/dailylah_notify_test.dart`

**Interfaces — Produces:**

```dart
class DailylahNotify {
  /// Posts the note with the custom layout. False on any error or when no plugin answers.
  static Future<bool> show(Map<String, Object?> note, {required String channelName, required String channelDescription});
}
```

Channel `dailylah/notify`, method `show`. Kotlin: `NotificationCompat.Builder(ctx, "dailylah_alerts")`, create the channel (IMPORTANCE_HIGH) if absent, small icon the app's `ic_launcher` mipmap looked up by name on the application package (as today), `setContentTitle`, `setContentText`, `setStyle(DecoratedCustomViewStyle())`, `setCustomBigContentView` and `setCustomHeadsUpContentView` with `dl_note`, priority high, auto-cancel, content intent = launch intent of the app package with `data = Uri.parse(link)` when present (`FLAG_IMMUTABLE | FLAG_UPDATE_CURRENT`, request code = id). Returns `false` (never throws) on any exception, and when `areNotificationsEnabled()` is false.

Layout `dl_note.xml`: vertical `LinearLayout`; body `TextView` (`maxLines=5`, `ellipsize=end`, notification text appearance); row one: art `ImageView` (decorative) + pill 1 + pill 2; row two: pill 3. Unused views `GONE`. Pills: sp text, bold, single line, fill by tone with 2 dp ink outline (`#0F1618`); ink text on amber/mint/sky/teal, white on red/board/line; `line` fill set with `setColorStateList`/`setInt("setBackgroundColor")` from `lineColor`. Colours from the landing page tokens and the widget's `res/values/colors`. `NoteArt.kt`: `fun draw(ctx, art: String, value: Double?, bars: List<Double>): Bitmap?` with `Canvas` (PSI bar green/amber/red thirds with an ink marker at `value`; thermometer filled to `value`; seven bars; umbrella; phone).

- [ ] **Step 1:** Write the Dart test: a mock handler on `dailylah/notify` returning `true` → `show` is true and received the map and channel names; handler throwing `PlatformException` → false; no handler (`MissingPluginException`) → false.
- [ ] **Step 2:** `cd app/packages/dailylah_notify && flutter test` → fails.
- [ ] **Step 3:** Implement the Dart side, then Kotlin, layout, drawables. `cd app && flutter pub get` (updates `pubspec.lock`).
- [ ] **Step 4:** Plugin test passes; `cd app && flutter analyze && flutter test` still pass. If an Android SDK is present, `flutter build apk --debug`; otherwise note that CI compiles it.
- [ ] **Step 5:** Commit "Add dailylah_notify plugin: custom notification layout".

### Task 3: Send the eight alerts as rich notes

**Files:**
- Modify: `app/lib/background.dart`, `app/lib/wake_session.dart`
- Test: `app/test/background_rules_test.dart`

**Interfaces:**
- Consumes: Task 1 builders, `DailylahNotify.show`.
- Produces: `Future<void> showNote(RichNote n, {S s = const S()})` in `background.dart`: rich first; on false, `notifications.show(id, title, body)` on the usual channel with `BigTextStyleInformation(body)`.

Changes in `runChecks` (rules unchanged, only what is shown): rain → `rainNote`; haze → `hazeNote(air)`; leave (ID 9) → `leaveNote` with `usualMinutes` from `tripStats((await HabitsStore().load()).trips, tripRouteKey(origin kind, dest kind)).usual` when `fav.learnHabits`; custom places (13+i) → `leaveNote(id: 13 + i, placeName:)`; MRT → `mrtNote(bad, planBBus:)` where the plan is `mrtPlan(stations from the mrt_stations bundle, origin, destination)` and `directServices` come from `tripRides` over `usableStops(origin)` (bundles only; null when there is no destination today); hawker → `hawkerNote`; heat → `heatNote` with `uvIndex(await api.weather('uv'))` fetched inside a try only when the heat alert is about to show; digest → `digestNote` with this week's `historySummary` cents and trips per day when `fav.learnHabits`. `wake_session.dart` calls `showNote(wakeNote(...))`; `notifyNow` stays for the MRT ride.

- [ ] **Step 1:** Extend the test `setUp` with a mock handler for `dailylah/notify` that records calls in `rich` and returns a settable `richOk` (default true). Add tests: `rain alert goes out as a rich note with the umbrella pill` (rich has id 2, `shown` has no rain); `when the plugin answers false the plain rain alert shows once` (`richOk = false`: one `shown` with title "Rain before you leave."); `MRT note carries a bus pill only when the line is on the trip`; `heat note has the UV pill when /v1/weather/uv has a reading and none when it fails`; `rich notes still fire once per event` (two passes → one rich call). Add `uv` to `FakeApi.weather` if it has none. Update existing assertions that read titles from `shown` to read from both lists through one helper `titles`.
- [ ] **Step 2:** `flutter test test/background_rules_test.dart` → new tests fail.
- [ ] **Step 3:** Implement `showNote` and the changes above.
- [ ] **Step 4:** `flutter analyze && flutter test` → all pass.
- [ ] **Step 5:** Commit "Show the eight alerts with pills, plain as fallback".

### Task 4: "Show me an example" and the emulator check

**Files:**
- Modify: `app/lib/ui/more.dart` (row under the alert toggles), `app/lib/l10n.dart` (`alertExample` "Show me an example", `alertExampleSub` "Posts sample alerts so you can see how they look", `alertExampleOff` "Allow notifications to see the examples"), `app/integration_test/app_test.dart`
- Test: `app/test/features_test.dart`; golden of More changes (see Task 5)

**Interfaces — Consumes:** `sampleNotes(s)`, `showNote`, `requestNotificationPermission`.

Behaviour: tap → request permission; if the rich channel reports false for the first note and the plain one cannot show either (permission refused), show a SnackBar with `alertExampleOff`; else post all eight. Never touches `AlertLog`. Row is a 48 dp tap target in the sticker style used by neighbouring rows.

- [ ] **Step 1:** `features_test.dart`: `More > Alerts > Show me an example posts the eight sample notes` (mock `dailylah/notify`, expect ids {2, 8, 9, 1, 10, 3, 5, 12} and `alerts.sent` unchanged in SharedPreferences). `integration_test/app_test.dart`: `every sample note posts on the real system` (call `showNote` for each sample plus one with a 40-line body, then `getActiveNotifications()` contains all ids).
- [ ] **Step 2:** `flutter test test/features_test.dart` → fails.
- [ ] **Step 3:** Implement the row.
- [ ] **Step 4:** `flutter analyze && flutter test` → pass except the More goldens, which Task 5 regenerates; `test/screens_matrix_test.dart` and `test/contrast_test.dart` pass.
- [ ] **Step 5:** Commit "Add Show me an example to More > Alerts".

### Task 5: Docs, release and CI

**Files:**
- Modify: `app/CLAUDE.md` (Alerts entry of the feature map: rich notes, builders, plugin, fallback, example row), `app/pubspec.yaml` (`version: 2.6.0+33`), `docs/store/whatsnew/whatsnew-en-US` and `S.whatsNewNotes` (same line: "Alerts have a new look: rain, haze, heat, your bus and MRT disruptions now show the key facts as coloured tags. See them under More > Alerts > Show me an example."), `docs/QA.md` (one line under the notification checks: how to view the layouts), `app/android/app/proguard-rules.pro` only if the release emulator job fails without a keep rule, `app/maestro/*` only if a flow taps the Alerts section
- Generated: `docs/REPO_MAP.md`, every `AGENTS.md` via `python3 scripts/repo_map.py`

- [ ] **Step 1:** Make the edits; run `python3 scripts/repo_map.py` then `python3 scripts/repo_map.py --check` → OK.
- [ ] **Step 2:** `cd app && flutter analyze && flutter test` (the what's-new match test passes); `./scripts/check-app-id.sh` → OK.
- [ ] **Step 3:** Commit "Release 2.6.0: rich alerts", push the branch.
- [ ] **Step 4:** With the owner's go-ahead (it commits to the branch): run the `goldens` workflow on the branch for the More tab images. Then watch `app`, `emulator`, `security` and `docs` on the branch; fix what fails (Kotlin compile errors, a keep rule, lockfile).
- [ ] **Step 5:** Report: what CI verified, what only the owner's phone can verify (the look, via Show me an example on the alpha build), and the follow-up (24-hour forecast for "Rain from 6 pm").
