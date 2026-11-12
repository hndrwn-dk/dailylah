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
  come first in `halalNear`, like favourite hawkers. Halal screens always say "Not affiliated with MUIS.
  Always verify halal status directly" (`S.halalDisclaimer`).
- `lib/providers.dart` holds all Riverpod providers (Riverpod 3); widgets in `lib/ui/` only render.
  Every `ProviderScope` and `ProviderContainer` (app and tests) passes `retry: noRetry`: Riverpod 3
  would otherwise retry failed providers up to 10 times on its own, on top of `_live`'s rules.
  `StateProvider` comes from `package:flutter_riverpod/legacy.dart`; read async values with `.value`.
- `AppFrame` (`ui/app_frame.dart`, MaterialApp.builder) keeps every route above the system navigation
  bar (Android draws edge to edge; the 3-button bar hid Setup's Save), so pages need no bottom inset.
- Keyboard: `KeyboardNavigatorObserver` closes it whenever a page, sheet or dialog opens or closes, and
  `KeyboardRepaint` forces a fresh frame once it is gone (some phones left a blank area where it was);
  pickers pop with `popAfterKeyboard`. Both are wired in `main.dart` (`ui/keyboard.dart`).
- Tabs keep their scroll position (`IndexedStack`, one `ScrollController` per tab in `ui/shell.dart`);
  tapping the selected tab scrolls it to the top, and Today goes back to the top after 30 min away
  or when the card switches while another tab is open (`todayBackToTop`).
- UI: `ui/shell.dart` (tabs Today / Nearby / Home / History / More), `ui/theme.dart` (design tokens
  in `DL`, fonts Plus Jakarta Sans + Barlow Condensed in `assets/fonts/`), `ui/widgets.dart`
  (Panel, HeroHeader, BusPlate, PillRow, BentoTile...). Keep the sticker style: ink outlines
  and hard offset shadows (`Panel`), not soft Material cards. Signature elements (see `DL`):
  bus plates and the LED `BusBoard` for live arrivals, MRT `StationChip`/`LineChip` in official
  colours, `PaintedBlockNumber` as the Home hero, amber = look now / teal = go and nothing else.
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
  `commuteTimes` in logic.dart). MRT: all lines show on Today; `Favorites.lines` are the
  starred ones (max 3), and alerts cover every line when none is starred (`watchedLines`). Today shows the commute trip
  (`TripSection` in `ui/trip.dart`) and a "Go somewhere" picker. "Buses to X" uses the
  `bus_routes.json` bundle (`directRides` in logic.dart; trip start stops are filtered to the
  side of the road with a direct bus, or nearby stops with one are suggested, `tripStops`;
  loop services that go the long way are dropped, `tripRides`). Bus/MRT also shows the nearest MRT
  station at each end from the `mrt_stations.json` bundle (`mrtPlan`). "Plan a trip" (`TripPlannerPage`,
  `GoSomewhere`) is one route card: From on top, To below, both with the same choices (Here, Home, Work,
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
  an explicit button; no chip opens another app by itself. Under that card `_LiveExtras` shows LTA DataMall
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
  "My car is electric" with plug chips, or "Electric car? Show EV chargers" in Nearby > Park): `EvChargers`
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
  Muslim.sg, OpenStreetMap via Geoapify, OneMap, URA; a tap opens the source's page, URLs are constants in
  about.dart), the full Singapore Open Data Licence statement under it (`S.dataAttribution`), the estimates
  note as an info `AlertBanner`, a licences card (open data licence, in-app open-source licences) and the
  independence line as the footer. A new data source gets a row there. Tests: `test/about_test.dart`.
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
- Nearby (`ui/nearby.dart`) is "I am here now": starts on Here, chips for one section at a time
  (`nearbySectionProvider`: bus, eat, green = parks, park = car parking, taxi, prayer, help). The taxi sheet
  (`TaxiSheet` in `ui/today.dart`) answers first (`TaxiEaseCard`, `taxiEase`), then the nearest stand with
  Walk there (`taxisAround`), then `TaxiRadar` on the dark board (tap a taxi: distance and `compass8`
  direction; stands are 48 dp `TaxiStandPin`s that open the stand; for TalkBack the radar has a label
  and its tap picks the nearest taxi), then booking apps. Eat offers GrabFood/foodpanda only
  when it rains, the air is unhealthy or the nearest hawker is closed (`orderInReason`).
- Trip extras (`ui/trip.dart`, rules in logic.dart): Plan B when the trip's MRT line is disrupted
  (`planDisruption`), "Leave in N min" (`leaveBy`, plus one background reminder), weather tips per
  mode (`tripAdvice`), "Wake me at my stop" (`ui/wake.dart`, session in `lib/wake_session.dart` /
  `wakeProvider` so it survives leaving the page, `WakeBanner` above the tabs, rider picks the bus,
  `wakeRadius` / `wakeEvent` incl. "may have passed"; foreground location only while it runs, never
  stored, auto-stops after 2 h). Live arrivals refetch every 30 s while shown (`busRefreshEvery`).
  Each arrival shows where the bus is now (`busWhere`: nearest route stop within 400 m of LTA's bus GPS,
  up to 40 stops back, else straight-line distance; `S.busLive`), or "Timetable estimate" when LTA's
  `Monitored` is 0. No map SDK. Tapping an arrival (`BusBoard` rows, `BusRow`) opens "Where's my bus?"
  (`ui/bus_sheet.dart`, `showWhereBus`): the stops left to the rider's stop with the bus on them
  (`busStrip`), Next/Then bus, load as `LoadBars` (Seats free / Standing / Packed) and "Open in Maps"
  (a Google Maps link with the bus position, no SDK).
  From "Here" within `arrivedMetres` of the destination the trip shows "You're here".
  MRT: the MRT card shows the line status and "I'm on the train" (`mrtRide`/`mrtLeg`: every station from
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
  `historyByDay`); filter by kind, swipe to remove with Undo, or remove all shown. Costs: an
  entered `costCents` wins, else an estimate shown with ≈ — bus/MRT `adultCardFare` (PTC table, incl.
  the 26 Dec 2026 change) on straight-line km × 1.3 (`tripFareEstimate`), and HDB EPS rates for
  parkings at HDB car parks (`hdbParkingCost`, Central Area list `hdbCentralCarparks`). Tap a trip
  or parking to enter what it cost. "Ate here" is on the hawker and halal place sheets (not the list
  row), with Undo; taps within 30 min count as one meal (`addMeal`). Halal places have no id, so their
  meals use `mealPlaceId` (position) and keep the name in `MealLog.name`; `mealNudge` counts hawkers only.
  Meals have an optional price (`MealLog.priceCents`, JSON key `c`, absent on older meals): "Ate here"
  and the History meal sheet (`_MealSheet`: price and `mealTimeOn` time, same day, not in the future,
  saved with `editMeal`) share `MealPricePicker` in widgets.dart (chips `mealPriceChips` $4/$6/$8, Other
  through `askMealPrice`/`parseMealCents`, max `mealPriceMaxCents` $200); "Ate here" preselects the price
  of a meal it corrects (logged in the last 30 min) or else the last price at that place, by name
  for halal places (`mealPriceToOffer`, `lastMealPrice`), and still logs with one tap. `historySummary` adds priced meals
  to `costCents` and counts them (`mealsPriced`, `mealCents`); the Meals tile says "$x · n of m meals
  priced" and each meal row shows its price.
  Every trip card (commute and "Go somewhere") has I'm leaving; the running trip shows in `TripBanner`
  above the tabs (inline on the planner page, which hides the tabs) with Arrived / Stop timing. Commute
  keys stay "home>work"; planned trips keep the names shown (`tripRouteKey`, `S.routeEnd`).
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
  data" opens `showAboutData` (sources, licence, the 08:30 / 22-day method, transactions not listings, the
  hdb.gov.sg eligibility link). Maestro: `maestro/08_where_to_live.yaml`, `maestro/10_compare_blocks.yaml`.
- Names put in title case (streets, OneMap addresses, CHAS clinics) keep short forms in capitals
  (`capitalizeWord` in data.dart: MRT, LRT, HDB, NTUC...), so "Tampines MRT Station" reads the same everywhere.
- Home tab (`ui/home.dart`) is about the saved home, one section at a time (chips under the hero,
  `homeSectionProvider`): its HDB block (`homeBlock`) or private project (`private_homes.json` from
  URA, `privateProjectFor`; backend `app/ura.py`, secret `URA_ACCESS_KEY`), upgrading and
  works (`around.json` bundle from OneMap themes, `projectsNear`), schools, health, community,
  recycling, weekend, parking; block search is `BlockSearchPage`. HDB data is computed on the
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
  upload. The daily
  `rollout-guard` workflow (`.github/workflows/rollout-guard.yml`, `scripts/rollout_guard.py`;
  environment `play-rollout`, no reviewer; repository variable `AUTO_ROLLOUT` = `on`)
  raises it 20 → 50 → 100% after `ROLLOUT_HOLD_HOURS` (48) at a fraction when Android vitals
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
  Today buses, Nearby, Home, location, Appearance, Where to live, Plan a trip, Compare blocks), run by the emulator `maestro` job. A change to a
  string, tab or screen those flows tap on updates the flow in the same PR; how to write and run them
  is in docs/QA.md "Maestro". Every `launchApp` denies notifications. A failed run prints why and runs all
  flows once more; a pass on that retry is a "Maestro flaky" warning to read, not to ignore.
- `test/contract_test.dart` runs the parsers on the shared API examples in `contracts/v1/`; a parser
  that reads a new field or endpoint gets an example and a check there (docs/QA.md "Contract tests").
- `test/golden_test.dart` compares Today, Nearby, Home and More (light and dark) with the images in
  `test/goldens/`, on Linux CI only. A PR that changes how those tabs look on purpose updates the
  images with the `goldens` workflow on its branch and says so in the description (docs/QA.md
  "Golden tests").
- `test/screens_matrix_test.dart` renders every screen under every condition in docs/QA.md (offline,
  denied location, 200% text, dark, small screen); a new screen or tab section is added there.
