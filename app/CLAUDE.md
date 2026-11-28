# DailyLah app (Flutter) — guide for AI coding agents

Read the root `CLAUDE.md` first (identity, privacy, CI security, Git workflow). Paths below are
relative to `app/` unless they start with a top-level folder. File and symbol index:
`docs/REPO_MAP.md`.

## Code layout and UI rules
- `lib/models.dart`, `lib/data.dart` (bundle models), `lib/logic.dart` and `lib/l10n.dart`
  (strings, class `S`) are pure Dart (no Flutter, no I/O) so the WorkManager isolate
  can use them. Put parsing and decision rules there, with tests in `test/logic_test.dart`.
  The app is English only; every user-facing string still goes through `S`.
- Religion-neutral by default: no onboarding question about religion. Faith-specific
  features (MUIS prayer times, halal food from the `halal.json` bundle built from Muslim.sg
  listings) are opt-in under More > Extras. Halal places can be starred (`Favorites.halalPlaces`, by `mealPlaceId`) and
  come first in `halalNear`, like favourite hawkers. Every screen that lists halal places (the Nearby card, the
  See all list, Home > Food) and the sheet of a halal place (`S.halalSheetSubtitle`, `NearItem.sheetNote`) says
  `S.halalDisclaimer`, word for word: "Not affiliated with MUIS. Always verify halal status directly: look for
  the MUIS halal certificate at the premises." Never shorten it.
- Sources are credited once, in About > Data sources. A card, tab or sheet has no "Data: ..." footnote and
  names no source or agency in its notes. What stays on a screen: a short disclaimer where the decision is
  made (halal, past sales / not financial advice, estimates, emergency, toilets), with the full wording in
  the Terms of Service (`docs/legal/terms.md` section 3, linked from About); a privacy line where the user types something that is sent (address and place
  search); and the credit a provider asks for next to its data (the OneMap logo and credit on the map,
  `S.placesAttribution` with Geoapify results and toilets, the Eventfinda line with events). What is computed on
  the phone is said in the privacy policy (`docs/legal/privacy.md`), not on a screen. Tests: `test/source_notes_test.dart`.
- `lib/providers.dart` holds all Riverpod providers (Riverpod 3); widgets in `lib/ui/` only render.
  Every `ProviderScope` and `ProviderContainer` (app and tests) passes `retry: noRetry`: Riverpod 3
  would otherwise retry failed providers up to 10 times on its own, on top of `_live`'s rules.
  `StateProvider` comes from `package:flutter_riverpod/legacy.dart`; read async values with `.value`.
- `AppFrame` (`ui/app_frame.dart`, MaterialApp.builder) keeps every route above the system navigation
  bar (Android draws edge to edge; the 3-button bar hid Setup's Save), so pages need no bottom inset.
  On a wider window it keeps the app in a centred column with the page colour beside it and gives
  that column a `MediaQuery` whose width is the column's (`frameWidth`): up to `kMaxContentWidth`
  (600 dp) the whole window; then 600 dp (a foldable opened upright, a phone on its side); from
  `kTwoColumnMinWidth` (840 dp: a foldable opened flat on its side, a tablet) up to `kMaxWideWidth`
  (1040 dp), unless large text would make each column of cards narrower than a 320 dp phone at
  100% text (then 600 dp). Only the tabs use the wide column: `isWide(context)` is true there, and
  the cards of each tab are a `CardColumns` (widgets.dart) instead of a `Column`: stacked on a
  phone, two columns when wide, in reading order (left column, then right; split where the heights
  are closest, `splitColumns`; a run that would leave the right column empty, one card or a heading and its
  card, takes the whole width). A child wrapped in `FullWidth` spans both columns (banners, a row of
  tiles, a section's heading, notes; also a section widget that has its own `CardColumns`); a
  `SectionTitle`, a child wrapped in `KeepWithNext` (any other heading) or an empty `SizedBox` stays with
  the card after it; where a run splits, the column whose top heading (a `SectionTitle`, or a card that
  `OpensWithHeading` such as Today's weekend card) has more space above it is lifted by the difference, so
  both columns start level (a heading beside a card, or two headings); a section whose two lists each have a
  heading keeps each heading with its list when wide (Nearby > Eat puts its notes above both; Nearby > Help
  puts 995 and 999 side by side above Help nearby and the meeting points); a section that is one child of the
  page's list splits its own cards when wrapped in `FullWidth` (`CardColumns.splitsAt`): Today's commute
  `TripSection` has its heading across the page, the mode picker and I'm leaving starting the left column,
  and the bus and MRT cards (`_TransitBlock.withLead`) beside each other; when such a section ends with its two
  columns uneven, the cards after it carry on under them (`splitColumnsFrom`: the shorter column is filled first,
  reading order kept; a `FullWidth` child closes the columns), so a short bus card no longer leaves an empty
  block beside By MRT; a
  `CardColumns` inside one of
  the two columns just stacks. One and two columns are the same widgets, so fold, unfold and
  rotation keep scroll position and card state. A new tab section puts its cards in a `CardColumns`.
  When the layout turns into two columns (a foldable opened flat, a tablet turned; `FoldFlap.twoColumns`) `FoldFlap` opens the
  app like paper: the left half is the new layout at once and the right half swings open from the fold line in
  the middle (a snapshot of the new layout, `toImageSync`, over the live app, with a hard shadow and shaded while
  it turns), after `kFoldFlapSettle` (a foldable switches screens and plays its own animation while the app
  already draws at the new width) and while the hinge reports half open (at most `kFoldFlapHold` in all), in
  `kFoldFlapOpen`; folding, a wider window that stays one column (large text) or was two columns already (a
  tablet, a window being resized) and animations off have no flap. Scrolled down from the top, the tabs blur and fade under the status bar (`StatusBarFade` in the shell, a
  `BackdropFilter`; it follows the open tab's `ScrollController`) as they fade above the tab bar.
  Every pushed page is laid out for a phone: `ColumnPageTransitionsBuilder` (the theme's page
  transition) puts each `MaterialPageRoute` except the first in a `PhoneColumn` (600 dp, centred,
  its own `MediaQuery`), first-run Setup gets one in `main.dart`, and sheets are limited to 600 dp
  by the theme. So read the width from `MediaQuery` or `LayoutBuilder`, never from the view, push
  pages with `MaterialPageRoute`, and do not add a width limit per page. Dimming of a sheet or
  dialog covers the app's column (the whole window up to 1040 dp). Orientation is not locked. The
  frame is the one entry of a full-window `Overlay`, which is therefore the root overlay: Flutter
  puts the Cut/Copy/Paste toolbar of a text field there and places it by window coordinates, so
  anything else put in the root overlay must do the same. Tests: `test/app_frame_test.dart`,
  `test/card_columns_test.dart`, the "foldable landscape" and "tablet" rows of the screen matrix
  and the five `*-fold-landscape` goldens.
- Keyboard: `KeyboardNavigatorObserver` closes it whenever a page, sheet or dialog opens or closes, and
  `KeyboardRepaint` forces a fresh frame once it is gone (some phones left a blank area where it was) and drops the keyboard's height from `MediaQuery` while no text field has focus (back from the background Android can report a keyboard that is no longer up, and every Scaffold cut its body by that much);
  pickers pop with `popAfterKeyboard`. Both are wired in `main.dart` (`ui/keyboard.dart`).
- Tabs keep their scroll position (`IndexedStack`, one `ScrollController` per tab in `ui/shell.dart`);
  tapping the selected tab scrolls it to the top, and Today goes back to the top after 30 min away
  or when the card switches while another tab is open (`todayBackToTop`).
- UI: `ui/shell.dart` (tabs Today / Nearby / Home / History / More), `ui/theme.dart` (design tokens
  in `DL`, fonts Plus Jakarta Sans + Barlow Condensed in `assets/fonts/`), `ui/widgets.dart`
  (Panel, HeroHeader, BusPlate, PillRow, ModeRail, SectionTiles, PlaceRow, BentoTile...). Keep the sticker style: ink outlines
  and hard offset shadows (`Panel`), not soft Material cards. Signature elements (see `DL`):
  bus plates and the LED `BusBoard` for live arrivals, MRT `StationChip`/`LineChip` in official
  colours, `PaintedBlockNumber` as the Home hero, amber = look now / teal = go and nothing else. A raised card (hard shadow) is one that opens something; a reading that
  opens nothing lies flat (Today's UV and heat strip, `_ReadingStrip`, an outlined card with no shadow where a reading to
  look at turns only its icon chip amber, beside the Air card that opens its sheet).
  Layouts must hold at 200% system
  text, also on a 320 dp phone (wrap, never fixed widths for text); secondary text keeps 4.5:1 contrast
  (`DL.mist`). Tap targets are at least 48 dp (`kMinInteractiveDimension`), also custom ones
  (`PillRow`, `PlaceSelector`, `StickerIconButton`, `AlertBanner`); a pill tells TalkBack it is
  selected, and an icon-only tap target has a tooltip or `Semantics` label.

## Feature map
Each feature with its screens, rules (logic.dart) and providers. Update it in the same PR when a
feature, screen, provider or rule moves, appears or goes away.
- Routines: each place has travel modes (`Place.modes`, first = default) and custom places a
  `when`; work/school places carry their own `days` and `go`/`back` times (`commutePlace`,
  `commuteTimes` in logic.dart). MRT: the Today card (`_MrtCard` in `ui/today.dart`) leads with
  one status pill (all running, lines disrupted, or closed at night), a red box per disrupted
  line, the starred lines as tiles with their crowd level (`crowdLevel` in logic.dart) and the
  other lines as plates to star; `Favorites.lines` are the starred ones (max 3), and alerts cover every line when none is starred (`watchedLines`). Today shows the commute trip
  (`TripSection` in `ui/trip.dart`) and a "Go somewhere" picker. "Buses to X" uses the
  `bus_routes.json` bundle (`directRides` in logic.dart; trip start stops are filtered to the
  side of the road with a direct bus, or nearby stops with one are suggested, `tripStops`;
  loop services that go the long way are dropped, `tripRides`). Options with changes (`lib/transit.dart`, pure Dart): `TransitNet` is
  built from the bus stops, bus routes and MRT stations bundles (MRT extensions and LRT loops joined to their trunk
  station, walks up to `transferWalkMetres`), and `transitOptions` finds up to 3 door-to-door options (bus, MRT and
  walks, at most 3 rides) on estimated minutes: three searches (all, buses only, starting by train), options that
  board the same first ride or go the long way round (`_roundabout`) dropped, peak-only and night services left
  out (`peakOnlyService`). `transitNetProvider` builds the net once per run, `transitOptionsProvider` (family on
  the two ends) runs the search; `TransitOptionsCard` (ui/trip.dart: one 48 dp row per option, walk minutes, bus plates
  and line chips, "~N min"; the open one draws its legs as a route line like By MRT, `_LegStep`: walks dotted, a bus teal, a train in its line's colour, a dot at the start, each change and the end; "Times after the first bus or train are estimates") replaces
  the "No direct bus" stop cards when no stop has a direct bus, followed by a live `TripBusCard` for the first bus
  of the best way (`_firstBusCard`: buses from its stop to the stop of the first change, `TripBusCard.legService`:
  "No times for bus 966 at this stop right now" instead of "No direct bus") and By MRT; ways over a disrupted MRT line
  are left out (`tripWaysProvider`, the list the card and I'm leaving share); which way is open is kept per trip
  ends (`openWayProvider`); I'm leaving on such a trip keeps no stop or bus (`_TripTimer._leave`), so Bus arriving
  does not start, but keeps the open way's steps on the running trip (`TripStep` in models.dart, `stepsOf` in
  transit.dart; `Habits.tripSteps` JSON `st`, `tripStepIndex` `si`, cleared with the trip; rules `stepAfter`,
  `remainingMinutes`, `nextRideIndex`; tests `test/trip_nav_test.dart`) for trip navigation
  (docs/superpowers/specs/2026-11-26-trip-navigation-design.md; phases 1-4). While walking to the next ride or
  waiting for it, the navigator's `checkBetter` (every tick) runs `transitOptions` from that stop to `Habits.tripTo`
  and `betterWay` (transit.dart: at least `betterWayMinutes` sooner than the rest of the plan, other rides) puts a
  faster way in `betterWayProvider`; `BetterWayCard` on the trip page offers Switch (`switchToBetter`, the rest of
  the trip becomes its steps, `replaceTripSteps`; Undo `undoSwitch`) and Keep my way (`keepMine`, not offered again
  on that step); with the app in the background one `betterWayNote` (ID 25) a step. Never switches by itself. The ways
  from that stop are worked out once a step, drop disrupted MRT lines like the planner (`withoutDisrupted`, shared
  with `tripWaysProvider`), and are compared like with like (`rideWaitMinutes`: the plan's wait at a change against
  an option's first wait, `betterWay(extraMinutes:)`); Switch and Undo start the new first step's tool and clear the
  per-step memories (`_replanned`), and Undo (an 8 s snackbar) works only on the same trip's first step of the way
  switched to. The trip bar says the step
  ("Step 2 of 4 · 966 in 4 min", `S.stepOf`, `stepLabel`) and opens `RunningTripPage`, which for a trip with steps
  shows `TripStepsCard` (every step: done ones dimmed, the active one amber with a critically damped spring,
  `_Settle`, none with animations off; the step button from `stepAction`: I'm on 966 / I'm on the train / Got off,
  haptic on Got off) and the live card of the bus being walked to (`_waitedBusCard`); the open way is kept by
  signature (`openWayProvider`, `openWayIndex`). The navigator (`lib/trip_nav.dart`, `tripNavProvider`, kept
  alive by the shell; `tripNavigationOnProvider`, on; `test/trip_nav_session_test.dart` sets it per case, every other
  test runs with it on; Arrived on the train bar of a trip with changes moves to the step after the ride,
  `finishRide`, and Wake me started by hand from the bus card of a walk step moves the trip past that bus)
  runs each step's tool once (`navToolFor`: Bus arriving while walking to a bus, Wake me on a bus with
  `start(ask: false)`, the train ride over an MRT run, `mrtRunEnd`), moves on when Bus arriving ends with the
  rider over `busLeftStopMetres` from the stop, when Wake me fires, or when a run is over by time
  (`navRideOver`), posts the get-off note by estimate without location (`navGetOffDue`), keeps when the step began
  (`Habits.tripStepAt`, JSON `sa`; `setTripStep`) and stops each tool as its step ends (`next()` for taps); tests
  `test/trip_nav_session_test.dart`; with direct
  buses it shows after them on the planner page only, so Today stays short. Tests: `test/transit_test.dart`,
  "ways with changes" in `test/features_test.dart` and the screens matrix. Bus/MRT also shows the nearest MRT
  station at each end from the `mrt_stations.json` bundle (`mrtPlan`). "Plan a trip" (`TripPlannerPage`,
  `GoSomewhere`) is one route card: From on top, To below, both with the same choices (Current location = `S.hereNow`, called Here below, Home, Work,
  School, saved places, and a search field, `goAdhocFromProvider`/`goAdhocDestProvider`) and a
  swap button between. That search (`AddressPickerPage(places: true)`, `placeSearchProvider`) also finds
  shops and restaurants by name: a query that starts with a number or "Blk"/"Block" and a number goes to
  OneMap (`looksLikeAddress`), anything else to Geoapify through `/v1/places` (`PlacesApi`, `parsePlaces`;
  the key stays on the server), and to OneMap when that finds nothing or fails. Geoapify results carry
  "Powered by Geoapify · © OpenStreetMap contributors" (`S.placesAttribution`), and the end takes the
  place's own name (`AddressHit.name`). Other address pickers (setup, Nearby) stay OneMap only;
  picking on one end what the other has swaps them (`pickTripEnd`); the location
  arriving late never undoes a pick (`goPicksProvider`). The tip about
  saving places sits small at the end, only while none beyond Home/Work/School is saved. On each bus card
  ("From stop: <name>") the bus to leave for is a mint card on top ("Leave in 7 min to catch 36"), then
  the board (`tripBoard`): that bus first, buses that come before the walk is done dimmed with "Too
  soon" at the end (`BoardRow.dim`/`tag`). Strings that wrap keep their last words together with
  no-break spaces (`noOrphan`, `busWhereLine`). The I'm leaving how-to is small under the button and
  gone once the trip is learned. From and To within `samePlaceMetres` say "You're already there" (no walk, buses or
  timer). Short trips (rules in logic.dart, tests in `test/short_trip_test.dart`): Walk is the first mode chip
  (`TravelMode.walk`, `tripModes`; Setup offers the other five, `savedTravelModes`) and is picked by itself when
  the walking route is at most `walkDefaultMaxMetres` or `walkDefaultMaxMinutes` (`walkIsDefault`,
  `defaultTripMode`; never on the daily commute); a mode picked by hand wins (`modeOverrideProvider`), in the planner for that
  trip's two ends only (`plannedModeKey`), so it neither follows the next trip nor changes the commute. A bus is
  compared with walking door to door (`busDoorToDoor`: walk to the stop and wait, `feederMinutesPerStop` a stop,
  walk from the alighting stop); when it is no quicker, or rides one stop on a trip under `walkInsteadMetres`
  (`busNotFaster`), there is no "Leave now" card and the buses fold into one line ("Bus 196 · 1 stop · not faster
  than walking", tap to open) under the walking card (`_WalkCard`). Car, Motorbike, Bicycle and Taxi start with
  `_ModeCard`: a rough time and distance (`modeMinutes`, `cycleKmh`, `driveKmh`, `routeMetres`) and Google Maps as
  an explicit button; no chip opens another app by itself. The modes are picked in `ModeRail` (widgets.dart): one row of icons, each
  with a rough time (`modeMinutes`, `S.shortMinutes`; none for Bus/MRT), an amber thumb on the pick that can be tapped or
  dragged (it springs to the mode the drag was heading for), names as tooltips and the pick named after the trip's
  title (`S.tripBy`); when a segment would be under 48 dp times the text scale (`ModeRail.fits`) it is a grid of
  named tiles instead. Under that card `_LiveExtras` shows LTA DataMall
  details from `/v1/trip-extras` (`tripExtrasProvider`, asked only while that mode is picked; `parseTripExtras`,
  `TripExtras`, `ExtraSpot`): Car and Motorbike the nearest car parks to the destination with free lots (C/Y),
  distance, agency and "Lots as of HH:mm" (Motorbike hides the section when none has motorbike lots); Bicycle the
  nearest bicycle parking (rack type, racks, sheltered); Taxi the free taxis within 500 m of the start. The point
  is sent rounded to 4 decimals (`extrasCoord`); the phone's own position ("Here", `startsHere`/`endsHere`) is
  never sent: the phone then filters `/v1/parking`, `/v1/taxi` and the bicycle racks bundle itself
  (`localTripExtras`). On an error the card stays and one line says "Live info unavailable"; Bicycle falls
  back to the racks bundle instead. "Use my current location" in the planner's search is Here too (`AddressHit.here`). Board rows put their details (load, wheelchair, stops) under the number at full width when the column
  beside it is too narrow for whole words (`_BoardRowLayout`, large text, small screens). Maestro: `maestro/09_plan_trip.yaml`. Driving uses `/v1/trip-extras`
  (parking) and `/v1/traffic-incidents`.
- EV charging (opt-in, `Favorites.evPlug`: '' none, 'any', 'Type 2', 'CCS2', 'CHAdeMO'; More > Extras
  "My car is electric", a full-width tile that holds its "Charger plug" row, which opens the plug list, or "Electric car? Show EV chargers" in Nearby > Park): `EvChargers`
  (`ui/ev.dart`) in Nearby > Park, Home > Parking and car trips (`_DriveBlock`). Locations, plugs, kW and
  price come from the daily `ev.json` bundle (LTA `EVCBatch`, `compact_ev_sites`; `evSitesProvider`,
  `evNear`, `evPlugMatches`); free chargers live from `/v1/ev/{postal}` (LTA `EVChargingPoints`,
  `compact_ev_live`, memory-cached `ev_ttl`; `evLiveProvider`, `evFree`), asked only for rows on screen.
  The two LTA feeds differ (batch: `longtitude`, `postalCode`, no `locationId`, `current`/`powerRating`=kW;
  live: `powerRating`=AC/DC, `chargingSpeed`; numbers as strings; empty connector status falls back to the
  charger's), so live rows are matched to a site by id, else name, else the only one (`evLiveFor`).
- Favourites, custom places, watched/compared blocks and extras are stored with SharedPreferences
  (`lib/store.dart`). Family share is a `DL1:` code built on-device: the sender picks home/school/work, lines+times
  and hawkers (`ShareChoice`, `encodeShareCode`); the receiver ticks what to take (`readShareCode`,
  `shareConflicts`, `applyShare`), and a saved place is only replaced when ticked. About has Share
  DailyLah and Rate (Play Store, `openPlayListing`).
- About > Data sources (`AboutDailyLahPage` in `ui/about.dart`): one card with a row per credited source
  (`dataSources`, `DataSource`: LTA DataMall, data.gov.sg with the agencies as chips from `S.dataAgencies`,
  Muslim.sg, OpenStreetMap via Geoapify, OneMap (SLA), URA, Eventfinda; a tap opens the source's page, URLs are
  constants in about.dart), the
  estimates note as an info `AlertBanner`, a licences card (open data licence, in-app open-source licences) and the
  independence line as the footer. It is the only place that credits sources: a new data source gets a row
  there (and its agency a chip, and a place in the Singapore Open Data Licence statement of
  `docs/legal/terms.md` section 5, which is not repeated on the page). About has no list of disclaimers: a new
  disclaimer gets a short line on its screen and its full wording in `docs/legal/terms.md` section 3 (About
  links to the Terms of Service).
  Tests: `test/about_test.dart`, `test/source_notes_test.dart`.
- More (`ui/more.dart`) is sticker tiles in a `TileGrid` (two columns; one when a tile would be narrower than `tileMinWidth` times the text scale, `tileColumns`): a
  `SettingTile` with a `value` is a switch (mint with a solid outline when on, dashed when off, flat either way, "On"/"Off" in words,
  `toggled` for TalkBack), without one it opens something (raised, a chevron, a button for TalkBack): on More too a shadow
  means the tile opens something. Your setup and The app are link tiles, Alerts
  and Extras switch tiles; Alerts shows "9 of 10 on" beside its title (`alertsOn`, `alertKinds`). Lunch is the ninth
  alert tile, and while it is on the tile beside it is the link "Lunch time: 12.00" (the time picker); Bus arriving
  (`Favorites.busAlerts`, on by default) is the tenth and last, so Lunch keeps its time beside it. Extras is two tiles
  side by side, then Learn my habits and My car is electric at full width (three would leave a hole); while the car
  is electric that tile holds its plug as a row of its own under a line (`SettingTile.below`, with `holdsRow` so the tile is the same widgets on and off, `_PlugRow`: "Charger
  plug · Type 2" and a chevron, its own button for TalkBack, 48 dp), which opens `showEvPlugPicker`. "Show me an example" is a text link under the alerts. "Delete all my history"
  is not on More: it is at the end of the History tab (`S.deleteHistory`, shown while anything is logged or a car is parked).
- Appearance: More > Appearance picks follow the phone / light / dark (`Favorites.theme`: '', 'light',
  'dark'; `themeModeFor` in theme.dart). Dark mode keeps sticker surfaces (mint, sky, amber) with ink text.
- What's new: after an update, Today shows `WhatsNewCard` with `S.whatsNewNotes` until closed
  (`whatsNewDue`, `Favorites.seenVersion`). The version comes from `releaseVersionProvider` (the
  APP_VERSION dart-define, '' in tests and `flutter run`, so the card only shows in release builds);
  first-run setup marks the current version as seen, so new installs never get it.
- Home screen widget (`DailyLahWidgetProvider.kt`, layouts `res/layout/dl_widget_*.xml`): the app (Today,
  `widgetDataProvider`) and the background pass save string keys from `widgetData` in logic.dart (weather +
  icon key, MRT, today's trip, the bus to leave for as a clock time, the top alert); only known parts are
  written, and `updateWidget` skips repeats. Five layouts by size (small 2x1, wide 4x1, medium, large, XL with
  Today/Nearby/Home buttons, `dailylah://` links read by `tabForWidgetUri`). Android 12+ gets them as a sized
  `RemoteViews` map, so resizing and foldables switch layout without waking the app; Android 10/11 pick in
  `onAppWidgetOptionsChanged`. Colours are resources (values-night for dark), never set from code, so a
  dark-mode switch stays right. `DailyLahCoverWidgetProvider` is the same widget for the Galaxy Z Flip cover
  screen (keyguard category + Samsung `sub_screen` meta-data). Layouts are written by hand-kept XML: keep view
  ids in sync with the Kotlin.
- Live readings (forecast, train alerts, weather) are cache first (`_live` in providers.dart,
  `LiveCache` in store.dart): the last good answer shows at once (forecast up to 2 h old, train
  alerts 30 min, weather 1 h), then the server's answer. A failed call is retried once (it wakes
  Render) and then every `liveRetryEvery`; coming back to the app after `liveRefreshAfter`
  refetches all `liveProviders`. The background check also writes forecast and train alerts to the
  cache. An old reading shows "Updated HH:MM" (`liveStaleSince`).
- Alerts run on-device: WorkManager every 15 min (`lib/background.dart`) calls the API and
  reads the cached bundles, then shows local notifications. Keep the alert rules (quiet
  hours, one per event, max 3 rain alerts a day) in `logic.dart` / `AlertLog`.
  Every alert shows with pills and a small picture. The first eight are the landing page's "A day with DailyLah": rain (ID 2),
  haze (8), leave by (9, 13+i for custom places), MRT disruption (1), Wake me at my stop (10), hawker closed
  tomorrow (3), heat stress (5) and the Sunday digest (12). What each shows is a `RichNote` (models.dart: title,
  body, up to 3 `NotePill`s with a `PillTone`, a `NoteArt`, the tab a tap opens) built in logic.dart by
  `rainNote`, `hazeNote`, `leaveNote`, `mrtNote`, `wakeNote`, `hawkerNote`, `heatNote`, `digestNote`; a pill
  whose value is not known is left out (UV from `/v1/weather/uv` only when the heat alert shows; the plan B bus
  only when the disrupted line is on today's trip, `planBBus`; "Usually 38 min" and the digest's week,
  `weekHabits`, only with `learnHabits`). `showNote` (background.dart) sends the note to the in-repo plugin
  `packages/dailylah_notify` (Android only, channel `dailylah/notify`; a real plugin because the WorkManager
  isolate has no `MainActivity` channels) and shows the plain notification with the same title and body when
  the plugin answers false, so an alert is never lost. The plugin (`NotePoster.kt`, `NoteArt.kt`,
  `res/layout/dl_note.xml`, kept by hand like the widget) posts on the same channel `dailylah_alerts` and IDs
  with `DecoratedCustomViewStyle`: real text only (pills are `TextView`s, pictures are decorative bitmaps; the title is bold; the PSI bar is
  green to 50, amber to 100 and red above, so the marker agrees with the pill),
  only `LinearLayout`/`TextView`/`ImageView`, pills filled row by row by a character budget that shrinks with
  larger text, colours as resources (values-night). The other alerts have the layout too: `parkNote` (ID 11), `dengueNote` (4), `lightningNote` (6),
  `homesNote` (7), `holidayRichNote` (20), Bus arriving's `busNearNote` and `busArrivingNote` (24), trip navigation's faster way `betterWayNote` (25) and, for "I'm on the train", `rideNextNote` (21) and `rideDisruptedNote`
  (22; the ride used 11 and 12 before, which replaced the parking reminder and the digest). The ongoing
  "Watching for your stop" / "Riding to" notification belongs to geolocator's foreground service, which takes
  only a title and a text: the app replaces its content with the pill layout (`wakeWatchNote`: the bus and
  metres to go; `rideWatchNote`: the line and stops to go) through `showOngoingNote` and the plugin's
  `showOngoing`, which posts under that notification's own ID and channel and only while it is on screen
  (never a stray one). The ID and channel (`locationServiceNoteId`, `locationServiceChannel`) are private
  constants of geolocator_android: a test fails when its version in `pubspec.lock` differs from
  `locationServicePluginVersion`, so a geolocator upgrade re-reads them in `GeolocatorLocationService.java`.
  Lunch (`lunchNote`, ID 23; `Favorites.lunchAlerts`, off until switched on in More > Alerts, with its time
  `Favorites.lunchAt`, 12:00 by default): on a work or school day (`lunchPlace`: `commutePlace`, so never on a
  public or school holiday) the background pass sends one note in the 45 min from the time set (`inLunchWindow`,
  once a day `lunch:<day>`) with an open hawker centre within `lunchMaxMetres` of that place, a starred one first
  (`lunchPick`, `LunchPick`), and "Rain expected" when the forecast there says so. It goes by the calendar, never
  by where the phone is (no position in the background), names the place ("Near Work: ...") and opens Nearby on
  Eat (`dailylah://nearby/eat`, `nearbySectionForUri`; `widgetTabTaps` now yields the tab and the section). On
  Today, from 30 min before to 2 h after that time (`lunchCardDue`): at the office the same pick sits inside
  `AtPlaceCard` with "Where to eat"; elsewhere (not at home) `LunchCard` opens Nearby > Eat (`openNearbyEat`).
  Halal places are not suggested in the note (no room for `S.halalDisclaimer`); Nearby > Eat lists them.
  The note always has its picture (`NoteArt.lunch`, a bowl) and a pill: with no hawker centre to name, "Where to eat".
  A new alert is a new `...Note` builder; no two alerts share an ID (a test checks the samples). More > Alerts > "Show me an
  example" (`showExampleAlerts`, `sampleNotes`) posts every alert (18) with sample values, titled "Example: ..." and
  under their own IDs (the alert's + 100), so a sample never replaces a real alert, and never touches
  `AlertLog`. The MRT note's line pill is the trip's line the plan B bus goes around (`planBBus`), not just the
  first disrupted one. The body gives way to the pills: 9 lines with none (a long digest), two fewer per row. Tests: "rich notes" in `test/logic_test.dart`, "alerts with pills" in
  `test/background_rules_test.dart`, `test/dailylah_notify_test.dart`, and on emulators "every sample alert
  posts with the custom layout" in `integration_test/app_test.dart`. How the layout looks on a real shade is
  checked by eye with Show me an example.
- Nearby (`ui/nearby.dart`) is "I am here now": starts on Here. The place is said once, on the button that
  changes it (`_PlaceButton`: "Gym · TAMPINES HUB" with a down arrow, amber once a place is picked; `_pickPlace`
  opens the list "Nearby where?": Current location, the saved places, Search for a place), with the
  Use my current location button beside it. The sections are `SectionTiles` (widgets.dart: even tiles, icon over
  name, four a row or fewer when the longest name would not fit, `SectionTiles.columns`; a short last row is
  filled by its last tile; a name a little too wide is drawn smaller, down to `SectionTiles.labelShrink`,
  before a row gives up a tile), one section at a time
  (`nearbySectionProvider`: bus, eat, green = parks, park = car parking, taxi, toilet, prayer, help). A row that
  opens something is a `PlaceRow` (widgets.dart): name, a line under it, a large figure and a chevron. The
  figure is the distance (`S.metresParts`), or the row's own number (free lots, free chargers, the prayer time),
  in which case the distance stays in the line under the name; a car park without a live count has no figure.
  Every such row opens that place's own sheet (an HDB car park: `_showCarpark`; a toilet: the place sheet with
  walking directions). The bus hint ("Tap a bus to see where it is") is said once beside the heading, See all
  sits at the end of its heading (`SectionTitle.trailingAtEnd`), and the Taxi card says the answer
  (`taxiEase`, `S.taxiEaseTitle`) over "2 free taxis within 500 m · stand 88 m" (`S.taxiNearLine`). The trip
  planner keeps `PillRow`; EV rows on a car trip have no chevron yet (`EvChargers(chevron:)`). The taxi sheet
  (`TaxiSheet` in `ui/today.dart`) answers first (`TaxiEaseCard`, `taxiEase`), then the nearest stand with
  Walk there (`taxisAround`), then `TaxiRadar` on the dark board (tap a taxi: distance and `compass8`
  direction; stands are 48 dp `TaxiStandPin`s that open the stand; for TalkBack the radar has a label
  and its tap picks the nearest taxi), then booking apps. Eat offers GrabFood/foodpanda only
  when it rains, the air is unhealthy or the nearest hawker is closed (`orderInReason`).
- Trip extras (`ui/trip.dart`, rules in logic.dart): Plan B when the trip's MRT line is disrupted
  (`planDisruption`), "Leave in N min" (`leaveBy`, plus one background reminder), weather tips per
  mode (`tripAdvice`; on Today rain is said once, in the weather card `_HeroWeather`: the forecast at both ends,
  "Raining now · 0.4 mm" from the gauge and the mode's tip `S.rainTip`, so Today shows no "Rain expected" banner and
  its trip (`TripSection(weatherAbove: true)`) no rain banner; the planner keeps its banner), "Wake me at my stop" (`ui/wake.dart`, session in `lib/wake_session.dart` /
  `wakeProvider` so it survives leaving the page, `WakeBanner` above the tabs, rider picks the bus,
  `wakeRadius` / `wakeEvent` incl. "may have passed"; foreground location only while it runs, never
  stored, auto-stops after 2 h). Live arrivals refetch every 30 s while shown (`busRefreshEvery`).
  Each arrival shows where the bus is now (`busWhere`: nearest route stop within 400 m of LTA's bus GPS,
  up to 40 stops back, else straight-line distance; `S.busLive`; on a route that passes the same street twice,
  stops within `busPassTieMetres` of the nearest are settled by which fits the arrival time, `_busOnRoute`,
  shared with `busStrip`), or "Timetable estimate" when LTA's
  `Monitored` is 0. No map SDK. Tapping an arrival (`BusBoard` rows, `BusRow`) opens "Where's my bus?"
  (`ui/bus_sheet.dart`, `showWhereBus`): the stops left to the rider's stop with the bus on them
  (`busStrip`), Next/Then bus, load as `LoadBars` (Seats free / Standing / Packed) and "Open in Maps"
  (a Google Maps link with the bus position, no SDK). The sheet opens on the arrival that was tapped
  (`busPick`, by its minutes). A bus at no stop on a long stretch (an expressway) is drawn between the two
  stops it is in line with (`BusStrip.between`: the straight distances to both add up to no more than the
  road between them plus 400 m), as a row "On the way · 1.5 km from your stop" (`S.busOnTheWay`).
  From "Here" within `arrivedMetres` of the destination the trip shows "You're here".
  Already there (Today): when the app opens or comes back to the front and location is already allowed
  (it never asks), the shell reads the position once (`_locate` in `ui/shell.dart`) and keeps only which
  saved Home, Work or School the phone is at (`savedPlaceAt`, within `arrivedMetres` of the address;
  `phoneAtProvider`, memory only). Today then shows `AtPlaceCard` (`ui/today.dart`: "Have a good day at
  work", "You're home. Take a rest.") instead of the commute `TripSection` and the MRT card (`restingAt`: at
  the trip's destination, or still at work or school on the evening card until `leaveSoonMinutes` before the
  usual time to leave); "Show my trip anyway" (`showTripAnywayProvider`) brings the trip back until the app
  is next opened. A trip being timed to that place ends (`HabitsNotifier.arrivedAt`), and so does one found at
  its own destination (`Habits.tripTo`, kept for every trip but a "Here" destination; `arrivedNear`,
  `atTripEnd`, within `arrivedMetres`), so a planned trip ends at the mall when Arrived was forgotten. It is
  logged with its time only when that is at most 15 min over the trip's usual time (`arrivalLogMinutes`);
  with no usual time yet the way back of the same trip counts, else a rough time from its distance and mode
  (`arrivalUsualMinutes`, `transitKmh`, `transitStartMinutes`). Otherwise the app was opened long after
  arriving: the trip is kept without a time (`TripLog.timed` false, JSON `nt`; `finishTrip(timed: false)`),
  as is one where Arrived comes over 3 h late; under 3 min it is not kept. `finishTrip` says what became of
  it (`TripEnd`), and Arrived's snackbar is `tripEndNote`. Only a bus trip has bells on its board (`tripMode`), never one started with I'm on the train (`Habits.tripTrain`, JSON `tn`, kept after the ride stops or the app is reopened) nor while a ride runs (`rideProvider`); the ride (`RideNotifier`) stops when its trip ends, also by itself at the destination. Without location nothing changes.
  MRT: the trip's By MRT card (`_MrtOption` in ui/trip.dart) leads with the same status pill and red disruption box
  as Today's MRT & LRT card (`MrtStatusPill`, `MrtDisruptionBox` in widgets.dart), then the minutes door to door
  (`mrtDoorMinutes`) and the route drawn as a line (`_RouteStep`: start, the walk or feeder bus dotted, the boarding
  station with its crowd, the ride in the line's colour, one leg per line with `mrtRideLegs`, striped red when that
  line is disrupted, the last station, the walk, the end), then "I'm on the train" with Change line and the Maps
  route as links (`mrtRide`/`mrtLeg`: every station from
  board to alight, change station included). The ride (`lib/mrt_ride.dart`, `rideProvider`, like the wake
  session) estimates the position from the time (`rideMinutesPerStop`, `rideTransferMinutes`,
  `rideIndexAt`; GPS fixes near a station correct it, `rideFixIndex`), checks LTA train alerts every
  `rideCheckEvery` and notifies once on a disruption, and alerts one stop before (`rideAlertDue`).
  `MrtRidePage` / `RideBanner` in `ui/mrt_ride.dart`; Arrived ends the ride and the timed trip.
  "Change line" on the MRT card opens `MrtLineSheet` (ui/trip.dart): the usual nearest-station route plus one
  option per line (`mrtChoices`, `lineMrtChoice`): that line's nearest station within `lineChoiceMaxMetres`, boarded
  on that line only (`stationOnLine`), walked or, beyond `feederWalkMetres`, reached by a direct bus from the
  bus_routes bundle (`feederBus`); options that ride the same stations as the usual one are dropped. The pick is
  saved per trip key (`Favorites.mrtLines`, `mrtRouteKey`, max 20) and the card shows "Today: Green line" with
  Change. The card also shows the boarding station's crowd now (`stationCrowd`, `stationCrowdProvider` on
  `/v1/crowd/{line}`, `CrowdPeople`). No live train positions: LTA does not publish them.
- Need a toilet?: `ToiletSheet` / `showToiletSheet` (`ui/toilets.dart`) from a button on
  `WakeMePage` (`ToiletRide.bus`) and `MrtRidePage` (`ToiletRide.train`), and Nearby's Toilets chip
  (`ToiletsNearby`, a section like the others, for the place picked). Data: the `toilets` bundle (`Toilet`,
  `ToiletKind` in data.dart, `toiletsProvider`; built daily by `build_toilets`, backend/CLAUDE.md). Rules in logic.dart,
  all on the phone: `toiletsAheadBus` (the stops after the boarding stop, or after the route stop nearest the last
  GPS fix, or the stop before it when the bus has not reached it, up to the alight stop on the `bus_routes` route; best toilet within 250 m of each stop; stops without
  one are skipped; `feederMinutesPerStop` a stop plus `walkMinutesTo`; `busToiletsProvider` in wake_session.dart,
  which now keeps the boarding stop `WakeState.from` and the last fix in memory), `toiletsAheadMrt` (the stations
  after the ride's estimated position, best toilet within 250 m of the station point, else `assumed`: "Stations
  usually have a toilet"; `rideMinutesTo`; `trainToiletsProvider` in mrt_ride.dart), `toiletsNear`
  (`toiletsNearProvider`) and one order, `toiletRank` (minutes, then mall/hawker/station, then metres); max 3 each.
  Walking directions open Google Maps with the toilet as destination only (`openDirections`). Every list ends with
  the estimate note and "Powered by Geoapify · © OpenStreetMap contributors". Tests use `harnessToilets`.
- History tab (`ui/history.dart`): logged trips, finished parkings (`ParkLog`, written by
  `clearParked`) and meals by day for this week/month/all (`historyEntries`, `historySummary`,
  `historyByDay`). The period is one rail (`_PeriodRail`: This week, This month, All time; the three names
  shrink together at large text) and the totals of the period are the filter (`_KindTiles`: All with what was
  spent, Trips, Parking and Meals, each a tile with its figure; four in a row, two at large text; they count the
  whole period whatever kind is shown, and are hidden with nothing logged, when only the note shows). A row is
  a `PlaceRow` in a `Dismissible`: the time and duration under the name ("time not known" for a trip that was
  not timed, `S.tripNotTimed`; such trips count in History but not in `tripStats`), the cost large with "estimate" under
  an estimated one, or "Add price" / "Add cost" (`PlaceRow.action`) where there is none; swipe to remove with
  Undo. Under the list: the swipe hint once, "Remove these N entries" in red, "Delete all my history" (everything
  logged in any period and the parked car, after a question), then the cost note. Costs: an
  entered `costCents` wins, else an estimate — bus/MRT `adultCardFare` (PTC table, incl.
  the 26 Dec 2026 change) on straight-line km × 1.3 (`tripFareEstimate`), and HDB EPS rates for
  parkings at HDB car parks (`hdbParkingCost`, Central Area list `hdbCentralCarparks`). Tap a trip
  or parking to enter what it cost. "Ate here" is on the hawker and halal place sheets (not the list
  row), with Undo; taps within 30 min count as one meal (`addMeal`). Halal places have no id, so their
  meals use `mealPlaceId` (position) and keep the name in `MealLog.name`; `mealNudge` counts hawkers only.
  Meals have an optional price (`MealLog.priceCents`, JSON key `c`, absent on older meals): "Ate here"
  and the History meal sheet (`_MealSheet`: price, day (`mealOnDay`, up to `mealBackDays` back via
  `mealFirstDay`) and `mealTimeOn` time, never in the future, saved with `editMeal`) share `MealPricePicker` in widgets.dart (chips `mealPriceChips` $4/$6/$8, Other
  through `askMealPrice`/`parseMealCents`, max `mealPriceMaxCents` $200); "Ate here" preselects the price
  of a meal it corrects (logged in the last 30 min) or else the last price at that place, by name
  for halal places (`mealPriceToOffer`, `lastMealPrice`), and still logs with one tap. `historySummary` adds priced meals
  to `costCents` and counts them (`mealsPriced`, `mealCents`); the Meals tile says what the priced meals cost,
  and each meal row shows its price.
  "Ate here" can log a meal eaten earlier: "Another day" asks for the day and then the time (`_AteHereButton`);
  such a meal is only added (`ateAt(backdated: true)`), never merged with one within 30 min.
  Spending card (`_SpendChart`, shown when the period has any cost; flat, since only its bars can be tapped):
  the total first with "spent this week" and the average per day so far (`S.spentIn`), then stacked bars drawn
  with plain widgets (no chart package), meals / transport / parking, one bar per day for week and month and per
  month for "all" (`historySpendBars`, last 12 months; a bar is at most 56 dp wide); tap a bar to read it. Under
  it the totals per kind and the lines from `historySpendInsight` (the day that cost most) and
  `historyPreviousCents` (last week or month up to the same point; none when a full log no longer reaches back that far). It follows the kind filter.
  Every trip card (commute and "Go somewhere") has I'm leaving; the running trip shows in `TripBanner`
  above the tabs (inline on the planner page, which hides the tabs) with Arrived / Stop timing; its buttons
  go under the text when they would not fit beside it (large text, 320 dp); every tab leaves room under its
  list for that bar too (`navClearance` in widgets.dart: the bar's height from the shell's Scaffold, at least
  `kNavClearance`), so it never covers the end of a tab.
  Bus arriving (`lib/bus_watch.dart`, `busWatchProvider`, like the wake session; `Favorites.busAlerts`): on a
  bus trip I'm leaving (`_TripTimer._leave`) remembers on the phone where the trip goes (on every trip), the stop of its first
  stop card and the bus to leave for (`tripLeave`, from `stopPlan`, the rule `TripBusCard` also uses;
  `Habits.tripTo`, `tripStop`, `tripBus`, cleared with the trip; never a "Here" destination) and watches that
  bus without asking for any permission: with location already allowed on geolocator's foreground service,
  else only while the app is open. It polls the stop every `busRefreshEvery` and follows one arrival by its
  expected time (`busWatchStep`, `BusTrack`, `busTrackToleranceMinutes`: an earlier bus of the same service is
  ignored, and `BusTrack.ahead`, the bus just ahead, keeps the two apart when both times move), alerts once at `busNearMinutes` and once on arriving (`busNearNote`, `busArrivingNote`, both ID 24),
  keeps the ongoing notification as pills (`busWatchNote`: bus, minutes or "Updated HH:mm" once the reading is
  older than `busStaleAfter`, stops away or metres to the stop), and ends when the bus is gone (missing from two readings in a row after it was near, or well past its time), the rider has
  left the stop after it was near (`busLeftStopMetres`; the position is only compared with the stop, in
  memory), the trip ends, Wake me or I'm on the train starts, or after `busWatchLimit`. While the trip runs,
  each direct row of its board has a bell in place of the chevron (`BoardRow.bell`, `BoardBell`; "Alerting" on
  the watched one): a tap picks that bus (and may ask for location and notifications), a tap on the filled one
  stops and says so with Undo (`S.busAlertsOff`); a bus watched in the app only (no location yet) first asks on that tap (`BusWatchState.asked`). The bar's second line is the watched bus ("197 in 5 min · 4 stops away"), a tap on its text opens
  `RunningTripPage` (the bar, the `TripBusCard` of the remembered stop and "Change this trip"), and once the
  bus has gone the bar offers Wake me before its stop. Today (`todayTripSlot`): the same card sits right under
  the weather tiles while such a trip runs and is not the commute card already shown; `PlanTripCard` at the end
  of Today (one card, so on a wide window it fills the shorter column) is a "Where to?" field that opens the planner on its place search
  (`TripPlannerPage(searchTo:)`, `GoSomewhere.searchDestination`) and the saved places as chips that open it with
  that destination (`planChipKeys`, not the place the phone is at; `pickDestination`), its heading opening the
  planner as it is; a destination picked in
  the planner but not left for (`plannerPlace`) moves `PlanTripCard` up there as "To <place> · See buses and
  leave", until I'm leaving is tapped for it (`goLeftForProvider`; a new pick offers it again). Tests: `test/bus_watch_test.dart`, `test/bus_watch_session_test.dart`, `test/bus_watch_ui_test.dart`. Commute
  keys stay "home>work"; planned trips keep the names shown (`tripRouteKey`, `S.routeEnd`), and an end at the phone's position is named on the phone (`hereName`: the saved place it is at, else "Near <station> station" or "Near <bus stop>" within `hereNameMetres`, else "Current location"; the position is not kept).
- Habits (`Habits` in models.dart, `HabitsStore` in store.dart, `habitsProvider`): parked car, trips
  logged with I'm leaving/Arrived (`tripStats`), "Ate here" meals (`mealNudge`). On the phone only,
  behind `Favorites.learnHabits`, never in the share code. Weekly Sunday digest (`weeklyDigest`)
  uses the `holidays.json` bundle (MOM public holidays). Days off are one rule, `DaysOff` (logic.dart;
  `holidaysProvider` + `schoolHolidaysProvider` = `daysOffProvider`, loaded once per background pass):
  a public holiday (observed days included) turns off the work and school trips, `school_holidays.json`
  (MOE, kept by hand, see web/data/README.md) only the school trip (`commutePlace`, `isCommuteDay`,
  `originFor`, `destinationFor`, `isSchoolDay`, `widgetTrip` take it). On a public holiday that would be a
  trip day, Today shows a banner (`S.publicHolidayToday`) and the morning leave-by reminder becomes one
  holiday notification (ID 20, once a day `holiday:<day>`; `holidayNote`: the holiday's name, weather near
  home, up to 2 events near home today from `eventsNear`). School holidays get only the banner. Custom
  places can carry a usual time (`Place.go`) for a leave-by reminder (`extrasDueNow`).
- Weekend card on Today (days without a work/school trip) and Home > Weekend: places (`weekendPicks`)
  and events (`eventsNear`) from `events.json`, built daily by `backend/app/events.py` from
  Eventfinda (secrets `EVENTFINDA_USER`/`EVENTFINDA_PASSWORD`; key stays in CI). Each event links
  to its Eventfinda page with attribution. Eventbrite was left out: it has no public event search.
- Parks: names spelled out on the phone (`expandPlaceName`: Pk, Pg, Jln...), facility chips from NParks
  Park Facilities attached per park in `poi.json` (`attach_facilities`, key `f`; unmapped CLASS values are
  logged in the data build and listed in `backend/data/build_report.json` as `park_facility_unknown`), shown as icons in lists (`FacilityIcons`, `facilityIcon` in widgets.dart) and
  as chips on the place sheet, and a "good time to go?" line (`parkTime`, `parkTimeProvider`) from
  lightning, rain, haze, heat stress, UV and the forecast. After dark (`isParkNight`, 7.30 pm to 7 am)
  the warnings still show, heat stress is skipped, and a clear night says so (`ParkTime.goodNight`).
- Prayer times (`prayer.json`): this year's and next year's MUIS timetables, found by name in data.gov.sg
  collection 2312 (`build_prayer`); next year appears once MUIS publishes it.
- School alerts (heat, lightning, dengue at school) only fire on school days (`isSchoolDay`: the school's
  days and not a school or public holiday); otherwise the heat/lightning checks use home.
- Where to live? (rules in logic.dart, ported from web/where-to-live/logic.js with the same cases in
  `test/where_to_live_test.dart`): the `where-to-live` bundle (`whereToLiveProvider`, `WhereToLive` in
  data.dart; HDB medians each with its own quarter, weekday 08:30 trips to six office areas, the same
  file as dailylah.sg/where-to-live). `wtlAnchorPlace` (work, else school) and `wtlNearestArea` (within
  `wtlNearestAreaMaxMeters`) pick the office area on the phone; the address is never sent.
  `wtlChecked` / `wtlChangeMode` (choices checked against the data; switching rent/buy drops the
  budget), `wtlRank` (match / noPrice / other), `wtlMonthly` (fares and hours on `wtlWorkdays`, all-in for rent),
  `wtlHighlights`, `wtlCompareIds` / `wtlToggleCompare` (max `wtlMaxCompare`) and `wtlCompareTable`
  (best per line; the office area's own town is "in this area" and takes no part, and all-in/hours
  mark no best while it is compared). No page of its own: it lives on the block page "Prices, rent and
  commute" (`BlockPage` in `ui/homes.dart`), built from `ui/block_commute.dart`. A block takes its town's
  numbers from the town's MRT station (`wtlTownFor`, HDB town name to bundle town). `BlockCommute`: office
  area, rent/buy and flat type (kept in `Favorites` `wtlArea`, `wtlMode`, `wtlFlat`; `wtlChoiceFor`), then
  a 2×2 grid (minutes | transfers, fare a trip | hours a month) and the all-in month as the main figure with
  "S$<rent> rent + S$<fares> fares" under it (fares a month when buying), labelled estimate.
  `TownsBoard`: budget, time limit and sort (`WtlSort`, `wtlSorted`; per visit), Fastest / Best value, the
  LED board (top 8 + Show all, the block's own town always shown) with "More about" to
  `dailylah.sg/where-to-live/<id>` (`wtlTownUrl`). Town rent on the block page and the Home block card is one
  source per town (`townRents`, `townRentFor`): the quarterly where-to-live medians with their quarter, or
  `hdb_rent`'s six-month medians (with the period) only for a town the bundle lacks. `ComparePage` adds
  time, transfers, fare, all-in (or fares) and hours per block (`wtlBlockLines`, `wtlCompareLinesFor`,
  `WtlCellText`; the office area's own town shows its rent with a small "rent only"), same "in this area" and
  "Best" rules as the website, with the area, flat type and rent/buy as chips above the table, section titles
  "Resale median" and "Rent in town", and short labels ("Hawkers ≤ 1 km"); the daily life lines (nearest MRT,
  bus stops, hawkers, schools, parks, dengue; `scoreBlock`) are only here, not on the block page. While fewer than
  `maxCompareBlocks` (3) blocks are compared, Compare has an "Add block" column (and "Add another block to compare"
  with one block) that opens `BlockSearchPage(onPick:)` (`pickBlockToCompare`, `addCompare`): the usual search plus
  watched and recently viewed blocks (`Favorites.recentBlocks`, max 6, set when a block page opens, `sawBlock`;
  `withRecentBlock`, `compareCandidates`). Compare on the block page shows "Added. Add another block to compare"
  with Add (pick the next block, then the comparison). Flat types read one way everywhere (`S.wtlFlatName`: "3-room",
  "Executive", from "3 ROOM" or "3-ROOM"). Block page UI:
  Watch and Compare are one size with one-line labels, stacked when they would not fit (`_ActionButtons`);
  the street in the header wraps between words and shrinks only when one word is too wide (`WordWrapTitle`);
  lease left is a bar of the 99 years with the year it ends (`LeaseBar`, also in Compare); resale prices show
  the short figure (S$1.07M) over the full one; town rents are a list of `FlatChip` + price + quarter. Both pages
  end in one disclaimer line, "Indicative only, not advice. Updated <date>." (`DataFooter`), whose "About this
  data" opens `showAboutData` (the 08:30 / 22-day method, transactions not listings, the hdb.gov.sg
  eligibility link, and "See data sources", which opens About). Maestro: `maestro/08_where_to_live.yaml`, `maestro/10_compare_blocks.yaml`.
- Names put in title case (streets, OneMap addresses, CHAS clinics) keep short forms in capitals
  (`capitalizeWord` in data.dart: MRT, LRT, HDB, NTUC...), so "Tampines MRT Station" reads the same everywhere.
- Home tab (`ui/home.dart`) is about the saved home, one section at a time (`SectionTiles` under the hero, eight
  in two rows, `homeSectionProvider`, `HomePage.sections`: home, safety, schools, health, community, weekend,
  food, parking): its HDB block (`homeBlock`) or private project (`private_homes.json` from
  URA, `privateProjectFor`; backend `app/ura.py`, secret `URA_ACCESS_KEY`). My home is the block card
  (`_MyBlock`: built, lease left and storeys in a flat strip `_FactStrip`, one fact a line at large text; the
  raised price card with a chevron opens `BlockPage`, where Notify me lives; the strip's dividers are the
  outline's colour and width) and "Around
  your home" (`_Glance`): `PlaceRow`s for the nearest primary school, hawker and AED, each opening its section,
  then Upgrading and works (`around.json` bundle from OneMap themes, `projectsNear`), Recycling and Blocks and
  agents, each on a page of its own (`HomeTopicPage`, `HomePage.topics`, `S.homeTopic`). Safety (`_Safety`) is
  the call buttons (995 red, 999 amber, as on Nearby), AEDs, A&E, police and fire stations, then the emergency
  meeting points. Every list (`NearGroup`) is `PlaceRow`s like Nearby: the distance large, or the row's own
  number with the distance under the name (`NearItem.big`; an empty `big` means no figure, a car park without
  a live count), then a chevron; phone numbers and links are on the sheet, and a row never shows a web
  address (`withoutWebAddress` in logic.dart). Block search is `BlockSearchPage`. HDB data is computed on the
  phone from bundles; only CEA lookups hit the API.
- Share to DailyLah: OneMap search finds addresses and buildings, not shop names, so a place found in Google Maps
  is shared in (Android `SEND` text/plain filter on MainActivity, channel `dailylah/share`: `take` hands over the
  launching share once, `shared` pushes later ones; `sharedPlaces()` in `lib/share_intake.dart`). `parseSharedPlace`
  (logic.dart) takes the name, the postal code (never digits in links or unit numbers) or a dropped pin's point;
  a share with only a Google Maps link ("Shared route" + maps.app.goo.gl) is opened on the phone (`MapsLinks` in
  api.dart: short-link redirects only, incl. share.google from Chrome's Google Search; Google hosts only, `isMapsLinkHost`) and read by `mapsLinkPlace` (directions:
  last stop and its `!3d!4d` pin; place pages: name, postal code, pin). Generic titles (`_sharedTitles`) are not names;
  the shell opens `TripPlannerPage(shared:)`, which searches only the postal code and sets the ad hoc destination
  under the shared name, else opens `AddressPickerPage(note:)`. The picker's empty state explains what search finds
  (`S.noAddressTips`).
- Static bundles (where they are fetched from, how the phone saves them) and the OneMap token:
  `backend/CLAUDE.md` "Data pipeline". The app reaches bundles only through `webUrls` in
  `lib/api.dart`, searches OneMap only through `/v1/search` and place names only through `/v1/places`.

## Build, CI and release
- The `app` workflow runs analyze and tests on every push and pull request; failures are emitted as
  annotations on the commit. It builds no APK: only a release builds the App Bundle, unsigned
  (`DAILYLAH_UNSIGNED_RELEASE=1`), and the `sign` job signs it with the upload key (secrets
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
  and variable `UPLOAD_CERT_SHA256` in environment `signing`; `scripts/sign_aab.sh`, docs/QA.md
  "Release signing"). Locally the release still signs from `ANDROID_KEYSTORE_PATH` or the debug key. Native changes (manifest, Kotlin widget, `dailylah/apps` channel) are
  compile-checked by the `emulator` workflow, which builds and runs the debug and release APKs on every
  pull request; its `release` job also checks targetSdk 36+ for Google Play and that Android backup stays off
  (`allowBackup="false"`, privacy). Testers get builds from
  Play (closed testing), not from CI artifacts.
- Release builds use R8 (minify + resource shrinking). Plugins reached by reflection/JNI are kept in
  `android/app/proguard-rules.pro`, resources used by name in `res/raw/keep.xml`. The AAB artifact
  carries `dailylah-mapping.txt`, which the Play upload below sends with each release, and native debug
  symbols inside the bundle (`ndk.debugSymbolLevel = "FULL"`, checked by `scripts/emulator_release.sh`). A release is a
  PR with a new feature or bug fix: it bumps `version:` (patch for fixes, minor for features) and
  replaces `docs/store/whatsnew/whatsnew-en-US` with what is new in that version only (never the
  notes of earlier releases; max 500 characters, plain text, one file per store language), and puts the
  same lines in `S.whatsNewNotes` for the What's new card (a test checks they match). Other PRs
  (docs, tests, CI, data) leave both alone. On a push to `main` the `app` workflow builds the AAB and
  releases only when `version:` changed (otherwise it runs analyze and tests only), and fails if it
  changed without new release notes. A release runs: build (`analyze`), then the whole `emulator` workflow on that commit
  (`e2e`, a reusable call: flows on API 29/35/36; upgrade test from the last release tag `v*`; Maestro
  flows on a universal APK made from the very AAB that is uploaded), and only if all of it passes it
  is released to the track in the repository variable `PLAY_PUSH_TRACK`: unset or `manual` uploads
  nothing (the owner uploads by hand, docs/QA.md "Manual releases"); `alpha` makes the `play` job
  upload to closed testing. `release-tag` then tags the commit `v<versionName>` and keeps the AAB, mapping and
  `whatsnew-en-US` in a draft GitHub Release (docs/QA.md "Release tags").
  Production is "merge, one tap, shipped" (docs/QA.md "Production release (automatic)"): after
  `release-tag`, the `promote` job of `app.yml` (push to `main` only, track `alpha`, repository
  variable `AUTO_PROMOTE` = `on`) waits for the owner's approval in environment `play-production`
  (main only, required reviewer), then runs `scripts/play_promote.py --auto` and puts
  the versionCode that run built on production as a staged rollout at 20%, with no rebuild and no
  upload. The
  `rollout-guard` workflow (every six hours) (`.github/workflows/rollout-guard.yml`, `scripts/rollout_guard.py`;
  environment `play-rollout`, no reviewer; repository variable `AUTO_ROLLOUT` = `on`)
  raises it 20 → 50 → 100% after `ROLLOUT_HOLD_HOURS` (6: 100% within a day) at a fraction when Android vitals
  (Play Developer Reporting API: user-perceived crash and ANR rate, new versionCode against the
  previous one) are OK or have no data, and halts it and opens an issue `release-halted` when
  they are worse; it never resumes or raises a halted release and never raises on an API error.
  Its clock is a GitHub issue per versionCode (label `release-rollout`, markers by
  `github-actions[bot]`). The `promote` workflow (`.github/workflows/promote.yml`; inputs `action`
  promote/rollout/halt/resume, `version`, `rollout` 10/20/50/100, `dry_run`) is the manual
  override. Tests: `backend/tests/test_play_promote.py` and `test_rollout_guard.py`. There is no
  human checklist before production (docs/QA.md "What CI enforces before production"); the
  real-device checks there are optional. A manual run of `app` on `main` can pick
  another `play_track` (manual, internal, beta; never production, which is reached only by promoting the alpha release); it runs the same tests first. A flaky emulator
  job blocks the upload: re-run failed jobs and `play` follows. The upload sends the AAB, mapping file
  and release notes with the service account in secret `PLAY_SERVICE_ACCOUNT_JSON` (environment `play`,
  testing tracks only; upload action pinned by commit). The emulator `release` job (`scripts/emulator_release.sh`)
  starts the release build with saved data, runs the WorkManager job and widget, and fails on
  missing classes or plugins. A new plugin with native code may need a keep rule.

## Store assets (Google Play)
- Version: bump `version:` in `app/pubspec.yaml` only (e.g. `2.0.1+23`). CI takes the versionName from
  there and uses the run number as versionCode, so every CI build can be uploaded. First public release: 2.0.0 (after the 1.9.x test builds; versions never go back).
- Icon `app/assets/store/play-icon-512.png` and feature graphic `docs/feature_design/feature-graphic-1024x500.png`
  come from `scripts/make_feature_graphic.py`.
- Phone screenshots (8, 1080x1920) in `docs/store/screenshots`: real screens rendered by `app/test_store`
  (demo data, app fonts) and captioned by `scripts/frame_screenshots.py`. The `screenshots` workflow
  runs both on a branch and commits the result; change scenes or captions there, not by hand.

## Testing a feature
- Every feature or bug fix PR adds tests for what it changes: the rules in `test/logic_test.dart`, and
  the user's path through the real widgets in `test/features_test.dart` (tap, sheet, button, what ends up
  stored or shown), with the fakes in `test/support/harness.dart` (`FakeApi`, `FileBundles` reading
  `web/data`, `FakeGeolocator`). Anything that needs a real plugin (notifications, widget, location,
  storage across restarts) goes in `integration_test/app_test.dart`, run on emulators.
- `test/contrast_test.dart` runs Flutter's text contrast check (4.5:1, large text 3:1) on every tab
  and section in light and dark. Text on the page or a card uses `DL.goText`, `DL.muted`, `DL.stopText`
  (theme-aware), never the light-only `DL.tealText`/`DL.mist`/`DL.stop`; those stay for sticker surfaces.
- `maestro/` drives the release build through the screen like a person (onboarding, Setup over a restart,
  Today buses, Nearby, Home, location, Appearance, Where to live, Plan a trip, Compare blocks, the greeting at home or at work, a school found by name, Share with family, the sample alerts in the notification shade, and in `maestro/large_text/` the tabs, Plan a trip and About at the largest font size), run by the emulator `maestro` job. A change to a
  string, tab or screen those flows tap on updates the flow in the same PR; how to write and run them
  is in docs/QA.md "Maestro". Every `launchApp` denies notifications, except flow 14, which needs them to post the sample alerts. A failed run prints why and runs all
  flows once more; a pass on that retry is a "Maestro flaky" warning to read, not to ignore.
- `test/contract_test.dart` runs the parsers on the shared API examples in `contracts/v1/`; a parser
  that reads a new field or endpoint gets an example and a check there (docs/QA.md "Contract tests").
- `test/golden_test.dart` compares Today, Nearby, Home and More (light and dark), and all five
  tabs on a foldable held on its side (880×600 dp, two columns), with the images in
  `test/goldens/`, on Linux CI only. A PR that changes how those tabs look on purpose updates the
  images with the `goldens` workflow on its branch and says so in the description (docs/QA.md
  "Golden tests").
- `test/screens_matrix_test.dart` renders every screen under every condition in docs/QA.md (offline,
  denied location, 130% and 200% text, dark, small screen, a phone on its side, foldable on its side, tablet) and checks each for
  48 dp tap targets and screen reader labels (`expectAccessible`). Rule: a new screen, sheet or tab section must be added
  there in the same PR, and a tap target under 48 dp is fixed, not added to `knownSmallTargets`
  (that list and `_knownIssues` are empty; they hold only what docs/QA.md "Open findings" lists).
- `test/persona_test.dart` follows five kinds of users (office worker, student, university student, homemaker,
  senior) through the journeys no other test covers; a feature PR adds one case to the persona it matters to
  (docs/QA.md "Persona journeys").
