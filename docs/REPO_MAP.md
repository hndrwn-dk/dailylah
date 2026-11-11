# Repo map

Made by `scripts/repo_map.py`; do not edit by hand. Run `python3 scripts/repo_map.py`
after adding, moving, renaming or removing a file, a public class or function, a provider
or an endpoint. CI (`docs` workflow) fails when this file is out of date. What each
feature does and why: `app/CLAUDE.md` (Feature map) and `backend/CLAUDE.md`.

## App: `app/lib` (35 files)

### `lib/api.dart`
- Types: `DailyLahApi`, `OneMapApi`, `PlacesApi`, `BundleRepository`, `BusStopRepository`, `MapsLinks`

### `lib/background.dart`
- Functions: `initNotifications`, `notifyNow`, `requestNotificationPermission`, `registerBackgroundWork`, `callbackDispatcher`, `runChecks`, `updateWidget`, `resetWidgetCache`, `widgetTabTaps`

### `lib/data.dart`
- Types: `Closure`, `Hawker`, `DengueCluster`, `Poi`, `PoiKind (enum)`, `PoiSet`, `Carpark`, `HdbBlock`, `ResaleStat`, `ResaleData`, `RentData`, `PrayerTimes`, `EPoint`, `EvPlug`, `EvSite`, `EvLive`, `EmergencyKind (enum)`, `EmergencySet`, `MrtStation`, `Project`, `AroundSet`, `PrivateProject`, `PublicEvent`, `QuarterMedian`, `TownCommute`, `WtlArea`, `WtlTown`, `WhereToLive`, `ToiletKind (enum)`, `Toilet`
- Functions: `expandPlaceName`, `capitalizeWord`, `cleanPlaceName`, `cleanDetail`, `isTemporarilyClosed`

### `lib/l10n.dart`
- Types: `AirLevel (enum)`, `OrderInReason (enum)`, `ParkTime (enum)`, `TripAdvice (enum)`, `S`
- Functions: `noOrphan`

### `lib/logic.dart`
- Types: `AreaForecast`, `WakeEvent (enum)`, `LineStatus`, `CardKind (enum)`, `BlockScore`, `ShareChoice`, `ShareImport`, `AlertKind (enum)`, `TodayAlert`, `AirQuality`, `BusRoutes`, `DirectRide`, `BusStrip`, `ParkingLot`, `TripStops`, `MrtPlan`, `MrtRide`, `ToiletStop`, `FeederBus`, `MrtChoice`, `LeaveBy`, `TripBoardRow (typedef)`, `HistoryKind (enum)`, `HistoryEntry`, `HistoryPeriod (enum)`, `HistorySummary`, `MealNudge`, `Holiday`, `SchoolHoliday`, `DaysOff`, `SharedPlace`, `WtlMode (enum)`, `WtlChoice`, `WtlGroup (enum)`, `WtlReason (enum)`, `WtlRow`, `WtlLineKey (enum)`, `WtlCellKind (enum)`, `WtlCell`, `WtlLine`, `TownRent (typedef)`, `WtlSort (enum)`
- Functions: `distanceMeters`, `nearestStops`, `searchStops`, `forecastNear`, `isRainyForecast`, `liveStaleSince`, `wakeEvent`, `parseBusArrival`, `lineStatuses`, `highCrowdShare`, `commutePlace`, `cardFor`, `todayBackToTop`, `isCommuteDay`, `watchedLines`, `extrasForToday`, `originFor`, `destinationFor`, `isQuietHour`, `inRainWindow`, `dayKey`, `dateOnly`, `shortDate`, `sgd`, `monthLabel`, `taxisWithin`, `heatStressNear`, `isHighHeat`, `lightningNear`, `preferIndoor`, `nextPrayerIndex`, `scoreBlock`, `searchBlocks`, `encodeShareCode`, `readShareCode`, `shareConflicts`, `applyShare`, `decodeShareCode`, `todayAlerts`, `parseOneMap`, `looksLikeAddress`, `parsePlaces`, `blockForAddress`, `isPostalCode`, `uvIndex`, `psiLevel`, `pm25Level`, `airNear`, `taxiEase`, `taxisAround`, `compass8`, `directRides`, `busWhere`, `busStrip`, `tripRides`, `usableStops`, `destinationStops`, `parseParking`, `distanceToSegment`, `tripStops`, `shortPlaceName`, `lineOfCode`, `mrtPlan`, `mrtPlanBetween`, `mrtLeg`, `mrtRide`, `toiletRank`, `toiletsAheadBus`, `toiletsAheadMrt`, `stationOnLine`, `feederBus`, `usualMrtChoice`, `lineMrtChoice`, `mrtChoices`, `stationCrowd`, `rideMinutesTo`, `rideIndexAt`, `rideEta`, `rideFixIndex`, `rideLineAt`, `rideAlertDue`, `homeBlock`, `projectEnded`, `distanceToProject`, `upgradingAtHome`, `titleCase`, `privateProjectFor`, `orderInReason`, `isParkNight`, `parkTime`, `transitResting`, `mrtPlanLines`, `walkMinutesTo`, `leaveBy`, `tripBoard`, `inLeaveWindow`, `stopBefore`, `wakeRadius`, `tripRouteKey`, `tripMinutes`, `mealPlaceId`, `halalPlaceId`, `mealTimeOn`, `addMeal`, `mealPriceToOffer`, `parseMealCents`, `lastMealPrice`, `parkMinutes`, `adultCardFare`, `tripFareEstimate`, `hdbParkingCost`, `parkingEstimate`, `historyOfKinds`, `parseCents`, `historySince`, `historyEntries`, `historySummary`, `mealNudge`, `parkReminderDue`, `weeklyDigest`, `inDigestWindow`, `tripAdvice`, `clockLabel`, `sinceLabel`, `servicesToPlaces`, `schoolHolidayOn`, `isSchoolDay`, `extrasDueNow`, `shortAddress`, `daysToWeekendEnd`, `whatsNewDue`, `evPlugMatches`, `evLiveFor`, `shortForecast`, `weatherKind`, `widgetTrip`, `widgetData`, `tabForWidgetUri`, `mapsLinkIn`, `isMapsLinkHost`, `parseSharedPlace`, `mapsLinkPlace`, `wtlFlatTypes`, `wtlBudgetLimit`, `wtlChecked`, `wtlChangeMode`, `wtlAnchorPlace`, `wtlRank`, `wtlCompareIds`, `wtlToggleCompare`, `wtlTownFor`, `townRents`, `wtlSorted`, `wtlBlockLines`, `withRecentBlock`, `compareCandidates`

### `lib/main.dart`
- Types: `DailyLahApp`
- Functions: `main`

### `lib/models.dart`
- Types: `PlaceKind (enum)`, `PlaceKindLabel (extension)`, `BusStop`, `TravelMode (enum)`, `PlaceWhen (enum)`, `AddressHit`, `PlaceHits`, `Place`, `TimeOfDayHM`, `Favorites`, `BusEta`, `BusWhere`, `ParkedCar`, `TripLog`, `ParkLog`, `MealLog`, `Habits`
- Functions: `travelModeFrom`

### `lib/mrt_ride.dart`
- Types: `RideState`, `RideNotifier`
- Providers: 2 (listed below)

### `lib/providers.dart`
- Types: `FavoritesNotifier`, `HabitsNotifier`
- Functions: `noRetry`, `nowOf`
- Providers: 75 (listed below)

### `lib/share_intake.dart`
- Functions: `sharedPlaces`

### `lib/store.dart`
- Types: `FavoritesStore`, `HabitsStore`, `AlertLog`, `LiveCache`

### `lib/ui/about.dart`
- Types: `DataSource`, `AboutDailyLahPage`
- Functions: `openPlayListing`, `appVersionLabel`, `openExternal`

### `lib/ui/address_picker.dart`
- Types: `AddressPickerPage`

### `lib/ui/app_frame.dart`
- Types: `AppFrame`

### `lib/ui/block_commute.dart`
- Types: `BlockCommute`, `TownsBoard`, `WtlCellText`, `DataFooter`
- Functions: `wtlTownUrl`, `wtlSessionChoice`, `dataDay`, `showAboutData`

### `lib/ui/bus_sheet.dart`
- Types: `WhereBusSheet`
- Functions: `showWhereBus`

### `lib/ui/ev.dart`
- Types: `EvChargers`

### `lib/ui/history.dart`
- Types: `HistoryPage`
- Providers: 2 (listed below)

### `lib/ui/home.dart`
- Types: `HomePage`, `NearItem`, `NearGroup`

### `lib/ui/homes.dart`
- Types: `BlockSearchPage`, `BlockTile`, `BlockPage`, `LeaseBar`, `FlatChip`, `ComparePage`, `AgentCheckPage`, `WordWrapTitle`
- Functions: `pickBlockToCompare`

### `lib/ui/keyboard.dart`
- Types: `KeyboardNavigatorObserver`, `KeyboardRepaint`

### `lib/ui/more.dart`
- Types: `MorePage`, `FamilySharePage`
- Functions: `showEvPlugPicker`, `showAppearancePicker`

### `lib/ui/mrt_ride.dart`
- Types: `MrtRidePage`, `RideStatusCard`, `RideBanner`
- Functions: `finishRide`

### `lib/ui/nearby.dart`
- Types: `NearbyPage`

### `lib/ui/place_sheet.dart`
- Functions: `oneMapStatic`, `openDirections`, `openRoute`, `openInMaps`, `mercatorOffset`, `showPlaceSheet`

### `lib/ui/setup.dart`
- Types: `SetupPage`, `ModeChips`

### `lib/ui/shell.dart`
- Types: `AppShell`

### `lib/ui/stop_picker.dart`
- Types: `StopPickerPage`

### `lib/ui/theme.dart`
- Types: `DL`
- Functions: `themeModeFor`, `buildTheme`

### `lib/ui/today.dart`
- Types: `TodayPage`, `BusStopCard`, `BusRow`, `StopArrivalsPage`, `TaxiSheet`, `TaxiEaseCard`, `TaxiRadar`, `TaxiStandPin`, `WhatsNewCard`
- Functions: `openApp`

### `lib/ui/toilets.dart`
- Types: `ToiletRide (enum)`, `ToiletSheet`, `ToiletsNearby`, `ToiletRows`, `ToiletFooter`
- Functions: `showToiletSheet`

### `lib/ui/trip.dart`
- Types: `TripSection`, `MrtLineSheet`, `TripBusCard`, `GoSomewhere`, `TripPlannerPage`, `PlanTripCard`, `TripBanner`
- Functions: `modeIcon`, `mrtRouteKey`, `showMrtLineSheet`

### `lib/ui/wake.dart`
- Types: `WakeMePage`, `WakeBanner`

### `lib/ui/widgets.dart`
- Types: `BusPlate`, `LoadMeter`, `LineChip`, `Panel`, `SectionTitle`, `AlertTone (enum)`, `AlertBanner`, `EmptyNote`, `Stat`, `PlaceSelector`, `HeroHeader`, `StickerIconButton`, `PageTitle`, `BentoTile`, `PillRow`, `Pulse`, `PillNav`, `StationChip`, `PaintedBlockNumber`, `BoardRow`, `LoadBars`, `BusBoard`, `ParkTimeBanner`, `InfoChips`, `FacilityIcons`, `DialogButtons`, `BigNumber`, `CrowdPeople`, `MealPricePicker`
- Functions: `placeTitle`, `facilityIcon`, `showActionSnackBar`, `popAfterKeyboard`, `askMealPrice`

### `lib/wake_session.dart`
- Types: `WakeState`, `WakeNotifier`
- Providers: 2 (listed below)

## Riverpod providers (81)

| Provider | Kind | File |
| --- | --- | --- |
| `rideProvider` | `NotifierProvider` | `lib/mrt_ride.dart` |
| `trainToiletsProvider` | `Provider.autoDispose` | `lib/mrt_ride.dart` |
| `apiProvider` | `Provider` | `lib/providers.dart` |
| `oneMapProvider` | `Provider` | `lib/providers.dart` |
| `placesProvider` | `Provider` | `lib/providers.dart` |
| `mapsLinksProvider` | `Provider` | `lib/providers.dart` |
| `bundleRepoProvider` | `Provider` | `lib/providers.dart` |
| `busStopRepoProvider` | `Provider` | `lib/providers.dart` |
| `favoritesStoreProvider` | `Provider` | `lib/providers.dart` |
| `initialFavoritesProvider` | `Provider` | `lib/providers.dart` |
| `favoritesProvider` | `NotifierProvider` | `lib/providers.dart` |
| `habitsProvider` | `NotifierProvider` | `lib/providers.dart` |
| `eventsProvider` | `FutureProvider` | `lib/providers.dart` |
| `schoolHolidaysProvider` | `FutureProvider` | `lib/providers.dart` |
| `holidaysProvider` | `FutureProvider` | `lib/providers.dart` |
| `daysOffProvider` | `Provider` | `lib/providers.dart` |
| `stringsProvider` | `Provider` | `lib/providers.dart` |
| `releaseVersionProvider` | `Provider` | `lib/providers.dart` |
| `busStopsProvider` | `FutureProvider` | `lib/providers.dart` |
| `busStopsByCodeProvider` | `Provider` | `lib/providers.dart` |
| `hawkersProvider` | `FutureProvider` | `lib/providers.dart` |
| `dengueProvider` | `FutureProvider` | `lib/providers.dart` |
| `poisProvider` | `FutureProvider` | `lib/providers.dart` |
| `carparkInfoProvider` | `FutureProvider` | `lib/providers.dart` |
| `hdbBlocksProvider` | `FutureProvider` | `lib/providers.dart` |
| `resaleProvider` | `FutureProvider` | `lib/providers.dart` |
| `rentProvider` | `FutureProvider` | `lib/providers.dart` |
| `whereToLiveProvider` | `FutureProvider` | `lib/providers.dart` |
| `busRoutesProvider` | `FutureProvider` | `lib/providers.dart` |
| `privateHomesProvider` | `FutureProvider` | `lib/providers.dart` |
| `homeSectionProvider` | `StateProvider` | `lib/providers.dart` |
| `nearbySectionProvider` | `StateProvider` | `lib/providers.dart` |
| `halalProvider` | `FutureProvider` | `lib/providers.dart` |
| `toiletsProvider` | `FutureProvider` | `lib/providers.dart` |
| `toiletsNearProvider` | `Provider.autoDispose.family` | `lib/providers.dart` |
| `evSitesProvider` | `FutureProvider` | `lib/providers.dart` |
| `evLiveProvider` | `FutureProvider.autoDispose.family` | `lib/providers.dart` |
| `aroundProvider` | `FutureProvider` | `lib/providers.dart` |
| `mrtStationsProvider` | `FutureProvider` | `lib/providers.dart` |
| `goAdhocDestProvider` | `StateProvider` | `lib/providers.dart` |
| `goAdhocFromProvider` | `StateProvider` | `lib/providers.dart` |
| `goFromKeyProvider` | `StateProvider` | `lib/providers.dart` |
| `bicycleRacksProvider` | `FutureProvider` | `lib/providers.dart` |
| `parkingLiveProvider` | `FutureProvider.autoDispose` | `lib/providers.dart` |
| `incidentsProvider` | `FutureProvider.autoDispose` | `lib/providers.dart` |
| `modeOverrideProvider` | `StateProvider` | `lib/providers.dart` |
| `goKeyProvider` | `StateProvider` | `lib/providers.dart` |
| `goPicksProvider` | `StateProvider` | `lib/providers.dart` |
| `goFromHereProvider` | `StateProvider` | `lib/providers.dart` |
| `taxiStandsProvider` | `FutureProvider` | `lib/providers.dart` |
| `emergencyProvider` | `FutureProvider` | `lib/providers.dart` |
| `prayerProvider` | `FutureProvider` | `lib/providers.dart` |
| `clockProvider` | `StreamProvider` | `lib/providers.dart` |
| `cardKindProvider` | `Provider` | `lib/providers.dart` |
| `liveCacheProvider` | `Provider` | `lib/providers.dart` |
| `forecastProvider` | `StreamProvider.autoDispose` | `lib/providers.dart` |
| `trainAlertsProvider` | `StreamProvider.autoDispose` | `lib/providers.dart` |
| `wbgtProvider` | `?` | `lib/providers.dart` |
| `rainfallProvider` | `?` | `lib/providers.dart` |
| `psiProvider` | `?` | `lib/providers.dart` |
| `pm25Provider` | `?` | `lib/providers.dart` |
| `uvProvider` | `?` | `lib/providers.dart` |
| `lightningProvider` | `?` | `lib/providers.dart` |
| `parkTimeProvider` | `Provider.autoDispose.family` | `lib/providers.dart` |
| `carparkLiveProvider` | `FutureProvider.autoDispose` | `lib/providers.dart` |
| `taxiProvider` | `FutureProvider.autoDispose` | `lib/providers.dart` |
| `busArrivalProvider` | `FutureProvider.autoDispose.family` | `lib/providers.dart` |
| `stationCrowdProvider` | `FutureProvider.autoDispose.family` | `lib/providers.dart` |
| `crowdShareProvider` | `FutureProvider.autoDispose.family` | `lib/providers.dart` |
| `agentProvider` | `FutureProvider.autoDispose.family` | `lib/providers.dart` |
| `nearbyKeyProvider` | `StateProvider` | `lib/providers.dart` |
| `adhocPlaceProvider` | `StateProvider` | `lib/providers.dart` |
| `todayAlertsProvider` | `Provider.autoDispose` | `lib/providers.dart` |
| `widgetDataProvider` | `Provider.autoDispose` | `lib/providers.dart` |
| `addressSearchProvider` | `FutureProvider.autoDispose.family` | `lib/providers.dart` |
| `placeSearchProvider` | `FutureProvider.autoDispose.family` | `lib/providers.dart` |
| `shellTabProvider` | `StateProvider` | `lib/providers.dart` |
| `historyPeriodProvider` | `StateProvider` | `lib/ui/history.dart` |
| `historyKindProvider` | `StateProvider` | `lib/ui/history.dart` |
| `wakeProvider` | `NotifierProvider` | `lib/wake_session.dart` |
| `busToiletsProvider` | `Provider.autoDispose` | `lib/wake_session.dart` |

## Backend endpoints (14)

| Method | Path | Handler | File |
| --- | --- | --- | --- |
| GET | `/health` | `health` | `backend/app/main.py` |
| POST | `/internal/poll` | `poll` | `backend/app/main.py` |
| GET | `/v1/agent/{reg_no}` | `agent` | `backend/app/main.py` |
| GET | `/v1/bus-arrival/{stop_code}` | `bus_arrival` | `backend/app/main.py` |
| GET | `/v1/carpark` | `carpark` | `backend/app/main.py` |
| GET | `/v1/crowd/{line}` | `crowd` | `backend/app/main.py` |
| GET | `/v1/ev/{postal}` | `ev_chargers` | `backend/app/main.py` |
| GET | `/v1/parking` | `parking` | `backend/app/main.py` |
| GET | `/v1/places` | `places` | `backend/app/main.py` |
| GET | `/v1/search` | `search` | `backend/app/main.py` |
| GET | `/v1/taxi` | `taxi` | `backend/app/main.py` |
| GET | `/v1/traffic-incidents` | `traffic_incidents` | `backend/app/main.py` |
| GET | `/v1/train-alerts` | `train_alerts` | `backend/app/main.py` |
| GET | `/v1/weather/{kind}` | `weather` | `backend/app/main.py` |
