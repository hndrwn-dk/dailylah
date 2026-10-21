/// User-facing strings (English). Pure Dart (no Flutter) so the background isolate
/// can word notifications too. Keep all copy here rather than in widgets.
library;

import 'models.dart';

/// NEA health advisory bands for haze (24-hour PSI and 1-hour PM2.5).
enum AirLevel { good, moderate, unhealthy, veryUnhealthy, hazardous }

class S {
  const S();

  // ---------------------------------------------------------------- general
  String get appName => 'DailyLah';
  String get retry => 'Try again';
  String get loading => 'Loading…';
  String get notAvailable => 'Not available yet';
  String get serverWaking =>
      'The server may be waking up. Pull down to try again.';
  String get save => 'Save';
  String get done => 'Done';
  String get cancel => 'Cancel';
  String get remove => 'Remove';
  String get add => 'Add';
  String get search => 'Search';
  String get seeAll => 'See all';
  String get dataSource => 'Data: NEA and HDB via data.gov.sg, and LTA DataMall.';
  String minutesAway(int m) => m == 0 ? 'Arr' : '$m';
  String get min => 'min';
  String metres(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
  String walkMinutes(double m) => '${(m / 80).ceil()} min walk';

  // ---------------------------------------------------------------- navigation
  String get tabToday => 'Today';
  String get tabNearby => 'Nearby';
  String get tabHomes => 'Home';
  String get tabMore => 'More';

  // ---------------------------------------------------------------- places
  String placeLabel(String kind) => switch (kind) {
        'home' => 'Home',
        'work' => 'Work',
        'school' => 'School',
        _ => 'Place',
      };
  String busFrom(String place) => 'Buses from $place';

  // ---------------------------------------------------------------- today
  String greeting(int hour) {
    if (hour < 11) return 'Good morning';
    if (hour < 15) return 'Good afternoon';
    if (hour < 19) return 'Good evening';
    return 'Good night';
  }

  String get morningCard => 'Morning card';
  String get eveningCard => 'Evening card';
  String get weather2h => 'Next 2 hours';
  String get bringUmbrella => 'Bring an umbrella';
  String get noRain => 'No rain expected';
  String validUntil(String text) => 'Valid $text';
  String get mrtLinesAll => 'MRT & LRT';
  String get allLinesNormal => 'All lines running normally';
  String get starLine => 'Star this line';
  String get maxStarredLines => 'You can star up to 3 lines.';
  String get starHint => 'Starred lines get alerts and evening crowd levels. Tap a line to star it.';
  String get starHintNone => 'You get alerts for any line. Tap a line to star up to 3 and keep alerts to those.';
  String get days => 'Days';
  String get goAt => 'Leave home';
  String get backAt => 'Leave here';
  String get halalCheck => 'Check halal status (MUIS)';
  String get halalNote => 'Opens the official MUIS halal directory. DailyLah does not have halal data.';
  String get showHalal => 'Halal check';
  String get showHalalSub => 'Link to the MUIS halal directory on food places';
  String get mrtLines => 'Your MRT lines';
  String get mrtNormal => 'Running normally';
  String get mrtDisrupted => 'Disrupted';
  String get noBusesNow => 'No buses right now';
  String get busesUnavailable => 'Bus times not available';
  String get crowdLow => 'Quiet';
  String get crowdMid => 'Busy';
  String get crowdHigh => 'Packed';
  String loadLabel(String code) => switch (code) {
        'SEA' => 'Seats',
        'SDA' => 'Standing',
        'LSD' => 'Full',
        _ => '',
      };
  String get taxisNearby => 'Taxis nearby';
  String taxisWithin(int n) => '$n available within 500 m';
  String get parkingAt => 'Parking';
  String get freeLots => 'free';
  String lotsFree(int n) => '$n lots free';
  String get pullToRefresh => 'Pull down to refresh.';

  // alerts strip
  String hawkerClosedToday(String name) => '$name is closed today';
  String hawkerClosedTomorrow(String name) => '$name is closed tomorrow';
  String dengueNear(String place, int n) => '$n dengue cluster(s) near $place';
  String heatAt(String place, String level) => 'Heat stress $level near $place';
  String get lightningNear => 'Lightning nearby. Stay indoors.';
  String mrtAlert(String lines) => 'Disruption on $lines';
  String rainAt(String place) => 'Rain expected near $place';

  String tryInstead(String name, String dist) => 'Try $name ($dist)';
  String get rainNow => 'Rain now';
  String rainMm(double mm) => mm == 0 ? 'Dry' : '${mm.toStringAsFixed(1)} mm';
  String get uvLabel => 'UV';
  String uvLevel(int v) => v >= 11
      ? 'Extreme'
      : v >= 8
          ? 'Very high'
          : v >= 6
              ? 'High'
              : v >= 3
                  ? 'Moderate'
                  : 'Low';
  String get heatLabel => 'Heat stress';
  String heatLevel(String c) => switch (c.toLowerCase()) {
        'low' => 'Low',
        'moderate' => 'Moderate',
        'high' => 'High',
        _ => c,
      };
  String get weatherNow => 'Weather now';
  String nearestStation(String name) => 'Nearest station: $name';

  // air quality
  String get airLabel => 'Air (PSI)';
  String airLevel(AirLevel l) => switch (l) {
        AirLevel.good => 'Good',
        AirLevel.moderate => 'Moderate',
        AirLevel.unhealthy => 'Unhealthy',
        AirLevel.veryUnhealthy => 'Very unhealthy',
        AirLevel.hazardous => 'Hazardous',
      };
  String airAdviceShort(AirLevel level) => switch (level) {
        AirLevel.unhealthy => 'Haze: reduce strenuous outdoor activity. Elderly, children and people with heart or lung conditions should limit time outside.',
        AirLevel.veryUnhealthy => 'Haze very unhealthy: avoid strenuous outdoor activity. Wear an N95 mask if you must be outside for long.',
        AirLevel.hazardous => 'Haze hazardous: stay indoors where possible. Wear an N95 mask if you go out.',
        AirLevel.good || AirLevel.moderate => 'Air quality is fine. No mask needed.',
      };
  String get maskNeeded => 'Mask advised';
  String get noMask => 'No mask needed';
  String get hazeTitle => 'Haze';
  String get hazeSource => 'PSI and PM2.5: NEA. Health advice follows NEA guidelines; see haze.gov.sg.';

  String taxisNear(String place) => 'Taxis near $place';
  String get within200 => 'within 200 m';
  String get within500 => 'within 500 m';
  String get taxiWithin1km => 'within 1 km';
  String get taxiStands => 'Nearest taxi stands';
  String get taxiLive => 'Free taxis right now, from LTA. Updated every few minutes.';
  String get taxiMapLegend => 'Dots are free taxis, squares are taxi stands. Rings at 250 m, 500 m and 1 km.';
  String get bookTaxi => 'Book a ride';
  String get bookTaxiNote => 'Opens the app if installed, otherwise its Play Store page.';
  String get callCdg => 'Call ComfortDelGro 6552 1111';
  String airDetail(String region, int? psi, int? pm) => 'Region: $region${psi == null ? '' : ' · PSI (24h) $psi'}${pm == null ? '' : ' · PM2.5 (1h) $pm µg/m³'}';
  String get moreAtHaze => 'More at haze.gov.sg';
  String get seeHawkers => 'See hawkers nearby';

  // trips and routines
  String modeLabel(String mode) => switch (mode) {
        'transit' => 'Bus/MRT',
        'car' => 'Car',
        'motorcycle' => 'Motorbike',
        'bicycle' => 'Bicycle',
        _ => 'Taxi',
      };
  String get usuallyBy => 'Usually by';
  String get usuallyByHint => 'Pick one or more. The first is used on the Today card.';
  String get whenLabel => 'When';
  String whenName(String w) => switch (w) {
        'weekdays' => 'Weekdays',
        'weekends' => 'Weekends',
        _ => 'Anytime',
      };
  String get workDaysTitle => 'Work or school days';
  List<String> get dayShort => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String tripTitle(String from, String to) => '$from → $to';
  String busesTo(String place) => 'Buses to $place';
  String rideInfo(int stops, double km, String alight) =>
      '$stops stops · ${km.toStringAsFixed(1)} km · get off at $alight';
  String get noDirectBus => 'No direct bus from this stop. Check the full route in Google Maps.';
  String get routeInMaps => 'Route in Google Maps';
  String get otherBuses => 'Other buses at this stop';
  String get changeStop => 'Change stop';
  String get goSomewhere => 'Go somewhere';
  String get goSomewhereHint => 'Pick a place to see how to get there now.';
  String get fromHome => 'From Home';
  String get fromHere => 'From here';
  String parkingNearPlace(String place) => 'Parking near $place';
  String get carLots => 'car lots';
  String get bikeLots => 'motorbike lots';
  String get noParkingData => 'No live parking data near this place.';
  String get trafficOnWay => 'Traffic on the way';
  String get noIncidents => 'No reported incidents near your route.';
  String get driveInMaps => 'Drive with Google Maps';
  String get rideInMaps => 'Ride with Google Maps';
  String get bicycleParking => 'Bicycle parking near';
  String get noRacks => 'No LTA bicycle racks within 800 m.';
  String get cycleWeatherTip => 'Check rain, haze and heat above before you ride.';
  String get taxiFromHere => 'Taxi from';
  String get addPlacesHint => 'Add places like your favourite food spot in Setup to see them here.';

  String get mrtOption => 'By MRT';
  String lineName(String code) {
    final n = trainLines[code] ?? code;
    return n.endsWith('LRT') ? n : '$n Line';
  }

  String changeAt(String station) => 'Change trains at $station';
  String walkIsQuicker(String minutes, String dist) => '$minutes · $dist';
  String get walkingRoute => 'Walking route';
  String suggestedStop(String dist, String place) => 'Has a direct bus · $dist from $place';
  String get useThisStop => 'Use this stop';
  String stopSaved(String name) => '$name saved as your stop';
  String thenIn(int m) => m == 0 ? 'then Arr' : 'then $m min';
  String get nearestHawker => 'Nearest hawker';
  String headingTo(String place) => 'Heading to $place';
  String get headingHome => 'Heading home';
  String get todayLabel => 'Today';
  String walkTo(String station, String dist) => 'Walk $dist to $station';
  String rideLine(String line, int? stops) => stops == null ? 'Ride $line' : 'Ride $line · ~$stops stops';
  String get changeTrains => 'Change trains on the way';
  String alightAt(String station, String dist) => 'Get off at $station · $dist walk';
  String get mrtRouteInMaps => 'MRT route in Google Maps';
  String get noMrtNearby => 'No MRT station within a 15-minute walk of both ends.';
  String mrtLineDisrupted(String line) => '$line is disrupted right now';
  String get from => 'From';
  String get to => 'To';
  String get anyAddress => 'Search';

  // emergency
  String get emergency => 'Emergency';
  String get call995 => '995 Ambulance & fire';
  String get call999 => '999 Police';
  String get call1777 => '1777 Non-emergency ambulance';
  String get aeHospitals => 'Hospital A&E (24 hours)';
  String get aeds => 'Nearest AEDs';
  String get fireStations => 'Fire stations';
  String get chasClinics => 'CHAS clinics';
  String get shelters => 'Civil Defence shelters';
  String get emergencyNote => 'In a life-threatening emergency, call 995 first. Locations are from SCDF, MOH and OneMap and may be out of date.';
  String get callLabel => 'Call';
  String fromYou(String d) => '$d from you';
  String away(String d) => '$d away';
  String busNo(String service) => 'Bus $service';
  String get wayWalk => 'Walk';
  String get wayTransit => 'Bus/MRT';
  String get wayBike => 'Bike';
  String get wayCar => 'Car';
  String get seeInMaps => 'in Maps';
  String get estimateNote => 'Rough times from distance. Google Maps has the live route and traffic.';
  String get getDirections => 'Get directions';
  String get openInMaps => 'Open in Maps';
  String get mapUnavailable => 'Map preview not available. Directions still work.';
  String get mapNote => 'Map: OneMap, Singapore Land Authority. Directions open in Google Maps from where you are.';
  String get saveCarpark => 'Save car park';
  String get savedCarpark => 'Saved';
  String get directions => 'Directions';

  // ---------------------------------------------------------------- nearby
  String get hawkers => 'Hawker';
  String get parking => 'Parking';
  String get dengue => 'Dengue';
  String get weekend => 'Weekend';
  String get mosques => 'Mosques';
  String get around => 'Around';
  String get openNow => 'Open';
  String get closedNow => 'Closed today';
  String closedRange(String from, String to, String reason) =>
      'Closed $from–$to ($reason)';
  String closureReason(String code) => switch (code) {
        'cleaning' => 'cleaning',
        'works' => 'repairs',
        _ => code,
      };
  String get favourite => 'Favourite';
  String get noUpcomingClosure => 'No closure scheduled';
  String get dengueNone => 'No active dengue cluster within 2 km.';
  String dengueCases(int n) => '$n cases';
  String get dengueTips => 'Check for stagnant water at home once a week: flower pots, pails, roof gutters.';
  String get parkingHint => 'HDB car parks near this place. Tap a car park to save it.';
  String get freeParking => 'Free parking';
  String get nightParking => 'Night parking';
  String get weekendSunny => 'Dry weather: good time to head outdoors.';
  String get weekendRainy => 'Rain expected: indoor ideas nearby.';
  String get schools => 'Schools';
  String get primarySchools => 'Primary schools';
  String get secondarySchools => 'Secondary schools';
  String get preschools => 'Preschools';
  String get within1km => 'Within 1 km';
  String get between1and2km => '1 to 2 km';
  String get p1Note => 'Straight-line distance from your saved address. MOE uses its own home-to-school measurement for P1 priority, so confirm on SchoolFinder.';
  String get openSchoolFinder => 'Open MOE SchoolFinder';
  String get setAddressForSchools => 'Set your home address for accurate school distances.';
  String get parkingElsewhere => 'Check parking at another address';
  String parkingNear(String place) => 'Parking near $place';
  String get parks => 'Parks';
  String get libraries => 'Libraries';
  String get communityClubs => 'Community clubs';
  String get sports => 'Sports & pools';
  String get prayerTimes => 'Prayer times today';
  String get nextPrayer => 'Next';
  List<String> get prayerNames => const ['Subuh', 'Syuruk', 'Zohor', 'Asar', 'Maghrib', 'Isyak'];
  String get fridayNote => 'Friday: Zohor is replaced by Friday prayer.';
  String get findMosque => 'Find a mosque (MUIS directory)';
  String get prayerTab => 'Prayer';
  String get prayerSource => 'Prayer times: MUIS via data.gov.sg.';

  // ---------------------------------------------------------------- homes (HDB)
  String get homesTitle => 'Find an HDB block';
  String get homeTitle => 'Home';
  String blockLabel(String b) => 'Blk $b';
  String get setHomeFirst => 'Set your home to see everything around it.';
  String get setHome => 'Set home';
  String get notHdb => 'Not an HDB block, so there are no resale or lease details. Everything around your home is below.';
  String get blockDetails => 'Prices, rent and score';
  String get watchBlock => 'Watch for new sales';
  String get watchingBlock => 'Watching';
  String medianFor(String flatType) => 'median ${flatType.toLowerCase()}';
  String rentMedian(String flatType, String amount) => 'Rent around $amount a month for a ${flatType.toLowerCase().replaceAll('-', ' ')} in this town';
  String get propertyAgents => 'Property agents';
  String get worksTitle => 'Upgrading and works';
  String get worksNone => 'No upgrading or construction listed within 1 km.';
  String atYourBlock(String what) => 'At your block: $what';
  String projectKind(String k) => switch (k) {
        'lup' => 'Lift Upgrading',
        'nrp' => 'Neighbourhood Renewal',
        'eup' => 'Estate Upgrading',
        'hdb' => 'New HDB flats',
        'hdbroad' => 'HDB road works',
        'cycling' => 'Cycling path works',
        'road' => 'LTA road works',
        'rail' => 'MRT works',
        'drain' => 'Drainage works',
        'sewer' => 'Sewer works',
        'water' => 'Water pipe works',
        'abc' => 'Waterway works',
        'park' => 'New park',
        'pc' => 'Park connector works',
        'parkfac' => 'Park facility works',
        'ura' => 'URA project',
        _ => 'Works',
      };
  String projectWhen(String from, String to) => [
        if (from.isNotEmpty) 'from $from',
        if (to.isNotEmpty) 'until $to',
      ].join(' ');
  String get hipNote => 'HIP (Home Improvement Programme) status is not published as open data. Check your block on the HDB website.';
  String get checkHip => 'Check HIP on HDB';
  String get dengueHeading => 'Dengue';
  String get schoolsTitle => 'Schools';
  String get healthTitle => 'Health and safety';
  String get pharmacies => 'Pharmacies';
  String get police => 'Police posts and centres';
  String get communityTitle => 'Community';
  String get residentsCommittees => 'Residents\' Committees';
  String get mpOffices => 'MP offices (Meet-the-People)';
  String get hdbBranch => 'HDB branch';
  String get eldercare => 'Eldercare';
  String get studentCare => 'Student care';
  String get familyServices => 'Family services';
  String get recyclingTitle => 'Recycling';
  String get ewastePoints => 'E-waste drop-off';
  String get reuseChannels => 'Donate, resell or repair';
  String get recyclingNote => 'Blue recycling bins are at every HDB block and collected by your public waste collector; collection days are not published as open data.';
  String get weekendTitle => 'Weekend near home';
  String get attractions => 'Attractions';
  String get museums => 'Museums';
  String get bbqPits => 'BBQ pits';
  String get pcnAccess => 'Park connector access';
  String get parkingFoodTitle => 'Parking and food';
  String get hdbCarparks => 'HDB car parks';
  String get hawkerClosures => 'Hawker closures in the next 30 days';
  String hawkerClosed(String name, String from, String to) => '$name · $from to $to';
  String showAll(int n) => 'Show all ($n)';
  String get showLess => 'Show less';
  String get findBlock => 'Find another HDB block';
  String get homeDataNote => 'Works, services and places: OneMap (SLA) and agencies via data.gov.sg. Computed on your phone.';
  String get homesIntro => 'Search a block to see resale prices, rent and daily life around it.';
  String get blockSearchHint => 'Block and street, e.g. 123 Bedok North';
  String get watched => 'Watched blocks';
  String get compare => 'Compare';
  String compareCount(int n) => 'Compare ($n)';
  String get addToCompare => 'Add to compare';
  String get inCompare => 'In comparison';
  String get watch => 'Watch';
  String get watching => 'Watching';
  String builtIn(int y) => 'Built $y';
  String leaseLeft(int years) => '$years years lease left';
  String storeys(int n) => '$n storeys';
  String get resalePrices => 'Resale prices, last 24 months';
  String get noResale => 'No resale transactions in this block in the last 24 months.';
  String medianOf(int n) => 'median of $n sales';
  String latestSale(String month, String price) => 'Latest $month: $price';
  String townMedian(String town) => '$town median';
  String get rentTitle => 'Typical rent in this town';
  String get rentNote => 'Median monthly rent of approved HDB rentals.';
  String get perMonth => '/month';
  String get dailyLifeScore => 'Daily life around this block';
  String get nearestMrt => 'Nearest MRT';
  String get busStops400 => 'Bus stops within 400 m';
  String get hawkers1km => 'Hawker centres within 1 km';
  String get primary1km => 'Primary schools within 1 km';
  String get primary2km => 'Primary schools within 2 km';
  String get parks1km => 'Parks within 1 km';
  String get dengue1km => 'Dengue clusters within 1 km';
  String get builtLabel => 'Year built';
  String get leaseLabel => 'Lease left (years)';
  String get ceaSource => 'Data: Council for Estate Agencies (CEA) via data.gov.sg.';
  String get checkAgent => 'Check a property agent';
  String get agentHint => 'CEA registration number, e.g. R012345A';
  String get agentNotFound => 'No agent with this number in the CEA register.';
  String get agentRegistered => 'Registered with CEA';
  String get homesDisclaimer => 'Past transactions from public data, not current listings. Not financial advice. Check eligibility on hdb.gov.sg.';
  String get emptyWatch => 'Watch a block to get notified about new resale transactions.';
  String newSales(String block, int n) => '$n new resale transaction(s) at $block';

  // ---------------------------------------------------------------- settings / more
  String get settings => 'Settings';
  String get welcome => 'Welcome to DailyLah';
  String get welcomeIntro => 'Set it up once and DailyLah tells you what matters: buses, MRT, rain and more. Everything stays on this phone.';
  String get places => 'Places';
  String get optional => 'optional';
  String pickStopNear(String place) => 'Pick the bus stop nearest to $place';
  String get pickStop => 'Pick a stop';
  String get addAnotherStop => 'Add another stop';
  String get yourLines => 'MRT/LRT lines you use';
  String get departureTimesSub => 'The Today card switches from the morning to the evening trip halfway between these times.';
  String get departureTimes => 'Usual departure times';
  String get leaveHome => 'Leave home';
  String get leaveWork => 'Leave work';
  String get notifications => 'Notifications';
  String get alertMrt => 'MRT disruption on my lines';
  String get alertRain => 'Rain before I leave';
  String get alertRainSub => 'At most 3 a day, none 10 pm–6 am';
  String get alertHawker => 'Favourite hawker closed tomorrow';
  String get alertDengue => 'New dengue cluster near home or school';
  String get alertHeat => 'Heat, lightning or haze';
  String get alertHomes => 'New resale transactions at watched blocks';
  String get extras => 'Extras';
  String get showPrayer => 'Show prayer times';
  String get showPrayerSub => 'MUIS daily prayer times in Nearby';
  String get pickHomeFirst => 'Set your home address first.';
  String get familyShare => 'Share with family';
  String get familyShareSub => 'Copy your places and lines to another phone';
  String get familyShareIntro => 'Scan or send this code to another phone. It holds your saved stops, lines and times, nothing else. No account or server involved.';
  String get copyCode => 'Copy code';
  String get shareCode => 'Share code';
  String get codeCopied => 'Code copied';
  String get importCode => 'Import from a family member';
  String get pasteCode => 'Paste the code here';
  String get importDone => 'Places and lines imported';
  String get importInvalid => 'This code is not a DailyLah share code.';
  String get about => 'About DailyLah';
  String get aboutSub => 'Privacy, terms and data sources';

  // about
  String version(String v) => 'Version $v · Tursina Labs';
  String get aboutIntro => 'A daily companion for life in Singapore. No account, no ads. Your places and settings stay on this phone.';
  String get privacyPolicy => 'Privacy policy';
  String get termsOfService => 'Terms of service';
  String get contactUs => 'Contact us';
  String get dataSources => 'Data sources';
  String get dataAttribution => 'Contains information from LTA DataMall and from datasets by NEA, HDB, CEA, MUIS, NParks, NLB, SportSG, PA and MOE accessed through data.gov.sg, made available under the Singapore Open Data Licence. Bus times, crowd levels, forecasts and prices are estimates.';
  String get independent => 'DailyLah is an independent app and is not affiliated with LTA, NEA, HDB or the Singapore government.';
  String get openSourceLicences => 'Open-source licences';
  String cannotOpen(String url) => 'Cannot open $url';
  String get yourSetup => 'Your setup';
  String get editSetup => 'Places, lines and times';
  String get alertsTitle => 'Alerts';
  String get systemLanguage => 'Phone default';

  // address
  String get address => 'Address';
  String get setAddress => 'Set address';
  String get changeAddress => 'Change address';
  String addressFor(String place) => 'Address of $place';
  String get addressHint => 'Postal code, block and street, or building';
  String get useMyLocation => 'Use my current location';
  String get myLocation => 'My location';
  String get noAddressFound => 'No address found. Try a postal code.';
  String get addressPrivacy => 'Search uses OneMap (Singapore Land Authority). Your saved address stays on this phone.';
  String get busStopsHere => 'Bus stops';
  String get stopsAutoPicked => 'Nearest stops picked for you. Change them any time.';
  String get pickAddressFirst => 'Set your home address first.';
  String get bundlesLoading => 'Downloading local data. Pull down or reopen the app in a moment.';
  String get blockNotInData => 'This address is not in the HDB block data yet.';

  // custom places and "anywhere"
  String get otherPlaces => 'Other places';
  String get otherPlacesHint => "Save places you visit often, like your parents' home, the gym or your mosque.";
  String get addPlace => 'Add a place';
  String get placeName => 'Name';
  String get placeNameHint => "e.g. Mum's house, Gym";
  String get rename => 'Rename';
  String get hereNow => 'Here';
  String get searchPlace => 'Search';
  String maxPlaces(int n) => 'You can save up to $n places.';

  // stop picker
  String get stopSearchHint => 'Stop name, road or 5-digit code';
  String get nearestStops => 'Nearest stops to my location';
  String get locationDenied => 'Location permission denied. Search by name instead.';
  String get locationUnavailable => 'Location not available. Search by name instead.';
  String get stopsUnavailable => 'Stop list not available yet. Try again later.';
  String get checkBuses => 'Check buses';
  String stopCode(String code) => 'Stop $code';

  // notifications (background)
  String get channelName => 'DailyLah alerts';
  String get channelDesc => 'MRT disruptions, rain, hawker closures, dengue and heat';
  String get checkAlternatives => 'Check alternative routes.';
  String get hawkerTomorrowTitle => 'Hawker closed tomorrow';
  String get dengueTitle => 'Dengue cluster nearby';
  String get heatTitle => 'Heat and lightning';
}
