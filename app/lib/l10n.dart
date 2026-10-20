/// English and Bahasa Indonesia strings. Pure Dart (no Flutter) so the background
/// isolate can word notifications in the user's language too.
library;

enum AppLang { en, id }

/// NEA health advisory bands for haze (24-hour PSI and 1-hour PM2.5).
enum AirLevel { good, moderate, unhealthy, veryUnhealthy, hazardous }

AppLang langFromCode(String? code) => code == 'id' ? AppLang.id : AppLang.en;

class S {
  const S(this.lang);
  final AppLang lang;

  bool get _id => lang == AppLang.id;
  String _t(String en, String id) => _id ? id : en;

  // ---------------------------------------------------------------- general
  String get appName => 'DailyLah';
  String get retry => _t('Try again', 'Coba lagi');
  String get loading => _t('Loading…', 'Memuat…');
  String get notAvailable => _t('Not available yet', 'Belum tersedia');
  String get serverWaking =>
      _t('The server may be waking up. Pull down to try again.', 'Server mungkin sedang bangun. Tarik ke bawah untuk coba lagi.');
  String get save => _t('Save', 'Simpan');
  String get done => _t('Done', 'Selesai');
  String get cancel => _t('Cancel', 'Batal');
  String get remove => _t('Remove', 'Hapus');
  String get add => _t('Add', 'Tambah');
  String get search => _t('Search', 'Cari');
  String get seeAll => _t('See all', 'Lihat semua');
  String get dataSource => _t('Data: NEA and HDB via data.gov.sg, and LTA DataMall.',
      'Data: NEA dan HDB via data.gov.sg, serta LTA DataMall.');
  String minutesAway(int m) => m == 0 ? _t('Arr', 'Tiba') : '$m';
  String get min => _t('min', 'mnt');
  String metres(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
  String walkMinutes(double m) => _t('${(m / 80).ceil()} min walk', '${(m / 80).ceil()} mnt jalan');

  // ---------------------------------------------------------------- navigation
  String get tabToday => _t('Today', 'Hari ini');
  String get tabNearby => _t('Nearby', 'Sekitar');
  String get tabHomes => _t('Homes', 'Rumah');
  String get tabMore => _t('More', 'Lainnya');

  // ---------------------------------------------------------------- places
  String placeLabel(String kind) => switch (kind) {
        'home' => _t('Home', 'Rumah'),
        'work' => _t('Work', 'Kantor'),
        'school' => _t('School', 'Sekolah'),
        _ => _t('Place', 'Tempat'),
      };
  String busFrom(String place) => _t('Buses from $place', 'Bus dari $place');

  // ---------------------------------------------------------------- today
  String greeting(int hour) {
    if (hour < 11) return _t('Good morning', 'Selamat pagi');
    if (hour < 15) return _t('Good afternoon', 'Selamat siang');
    if (hour < 19) return _t('Good evening', 'Selamat sore');
    return _t('Good night', 'Selamat malam');
  }

  String get morningCard => _t('Morning card', 'Kartu pagi');
  String get eveningCard => _t('Evening card', 'Kartu sore');
  String get weather2h => _t('Next 2 hours', '2 jam ke depan');
  String get bringUmbrella => _t('Bring an umbrella', 'Bawa payung');
  String get noRain => _t('No rain expected', 'Tidak ada hujan');
  String validUntil(String text) => _t('Valid $text', 'Berlaku $text');
  String get mrtLines => _t('Your MRT lines', 'Jalur MRT kamu');
  String get mrtNormal => _t('Running normally', 'Berjalan normal');
  String get mrtDisrupted => _t('Disrupted', 'Terganggu');
  String get noBusesNow => _t('No buses right now', 'Tidak ada bus saat ini');
  String get busesUnavailable => _t('Bus times not available', 'Jadwal bus belum tersedia');
  String get crowdLow => _t('Quiet', 'Lengang');
  String get crowdMid => _t('Busy', 'Agak padat');
  String get crowdHigh => _t('Packed', 'Padat');
  String loadLabel(String code) => switch (code) {
        'SEA' => _t('Seats', 'Ada kursi'),
        'SDA' => _t('Standing', 'Berdiri'),
        'LSD' => _t('Full', 'Penuh'),
        _ => '',
      };
  String get taxisNearby => _t('Taxis nearby', 'Taksi di sekitar');
  String taxisWithin(int n) => _t('$n available within 500 m', '$n tersedia dalam 500 m');
  String get parkingAt => _t('Parking', 'Parkir');
  String get freeLots => _t('free', 'kosong');
  String lotsFree(int n) => _t('$n lots free', '$n slot kosong');
  String get pullToRefresh => _t('Pull down to refresh.', 'Tarik ke bawah untuk memperbarui.');

  // alerts strip
  String hawkerClosedToday(String name) => _t('$name is closed today', '$name tutup hari ini');
  String hawkerClosedTomorrow(String name) => _t('$name is closed tomorrow', '$name tutup besok');
  String dengueNear(String place, int n) => _t('$n dengue cluster(s) near $place', '$n cluster dengue dekat $place');
  String heatAt(String place, String level) => _t('Heat stress $level near $place', 'Panas $level di sekitar $place');
  String get lightningNear => _t('Lightning nearby. Stay indoors.', 'Ada petir di sekitar. Tetap di dalam ruangan.');
  String mrtAlert(String lines) => _t('Disruption on $lines', 'Gangguan di $lines');
  String rainAt(String place) => _t('Rain expected near $place', 'Hujan diperkirakan di sekitar $place');

  String tryInstead(String name, String dist) => _t('Try $name ($dist)', 'Coba $name ($dist)');
  String get rainNow => _t('Rain now', 'Hujan sekarang');
  String rainMm(double mm) => mm == 0 ? _t('Dry', 'Kering') : '${mm.toStringAsFixed(1)} mm';
  String get uvLabel => 'UV';
  String uvLevel(int v) => v >= 11
      ? _t('Extreme', 'Ekstrem')
      : v >= 8
          ? _t('Very high', 'Sangat tinggi')
          : v >= 6
              ? _t('High', 'Tinggi')
              : v >= 3
                  ? _t('Moderate', 'Sedang')
                  : _t('Low', 'Rendah');
  String get heatLabel => _t('Heat stress', 'Tingkat panas');
  String heatLevel(String c) => switch (c.toLowerCase()) {
        'low' => _t('Low', 'Rendah'),
        'moderate' => _t('Moderate', 'Sedang'),
        'high' => _t('High', 'Tinggi'),
        _ => c,
      };
  String get weatherNow => _t('Weather now', 'Cuaca sekarang');
  String nearestStation(String name) => _t('Nearest station: $name', 'Stasiun terdekat: $name');

  // air quality
  String get airLabel => _t('Air (PSI)', 'Udara (PSI)');
  String airLevel(AirLevel l) => switch (l) {
        AirLevel.good => _t('Good', 'Baik'),
        AirLevel.moderate => _t('Moderate', 'Sedang'),
        AirLevel.unhealthy => _t('Unhealthy', 'Tidak sehat'),
        AirLevel.veryUnhealthy => _t('Very unhealthy', 'Sangat tidak sehat'),
        AirLevel.hazardous => _t('Hazardous', 'Berbahaya'),
      };
  String airAdviceShort(AirLevel level) => switch (level) {
        AirLevel.unhealthy => _t('Haze: reduce strenuous outdoor activity. Elderly, children and people with heart or lung conditions should limit time outside.',
            'Kabut asap: kurangi aktivitas berat di luar. Lansia, anak, dan penderita penyakit jantung atau paru sebaiknya membatasi waktu di luar.'),
        AirLevel.veryUnhealthy => _t('Haze very unhealthy: avoid strenuous outdoor activity. Wear an N95 mask if you must be outside for long.',
            'Kabut asap sangat tidak sehat: hindari aktivitas berat di luar. Pakai masker N95 kalau harus lama di luar.'),
        AirLevel.hazardous => _t('Haze hazardous: stay indoors where possible. Wear an N95 mask if you go out.',
            'Kabut asap berbahaya: sebisa mungkin di dalam ruangan. Pakai masker N95 kalau keluar.'),
        AirLevel.good || AirLevel.moderate => _t('Air quality is fine. No mask needed.', 'Kualitas udara baik. Tidak perlu masker.'),
      };
  String get maskNeeded => _t('Mask advised', 'Disarankan masker');
  String get noMask => _t('No mask needed', 'Tidak perlu masker');
  String get hazeTitle => _t('Haze', 'Kabut asap');
  String get hazeSource => _t('PSI and PM2.5: NEA. Health advice follows NEA guidelines; see haze.gov.sg.',
      'PSI dan PM2.5: NEA. Saran kesehatan mengikuti panduan NEA; lihat haze.gov.sg.');

  // emergency
  String get emergency => _t('Emergency', 'Darurat');
  String get call995 => _t('995 Ambulance & fire', '995 Ambulans & kebakaran');
  String get call999 => _t('999 Police', '999 Polisi');
  String get call1777 => _t('1777 Non-emergency ambulance', '1777 Ambulans non-darurat');
  String get aeHospitals => _t('Hospital A&E (24 hours)', 'IGD rumah sakit (24 jam)');
  String get aeds => _t('Nearest AEDs', 'AED terdekat');
  String get fireStations => _t('Fire stations', 'Pos pemadam kebakaran');
  String get chasClinics => _t('CHAS clinics', 'Klinik CHAS');
  String get shelters => _t('Civil Defence shelters', 'Shelter Civil Defence');
  String get emergencyNote => _t(
      'In a life-threatening emergency, call 995 first. Locations are from SCDF, MOH and OneMap and may be out of date.',
      'Dalam keadaan darurat yang mengancam nyawa, telepon 995 dulu. Lokasi dari SCDF, MOH, dan OneMap dan bisa saja tidak mutakhir.');
  String get callLabel => _t('Call', 'Telepon');
  String get directions => _t('Directions', 'Rute');

  // ---------------------------------------------------------------- nearby
  String get hawkers => 'Hawker';
  String get parking => _t('Parking', 'Parkir');
  String get dengue => 'Dengue';
  String get weekend => _t('Weekend', 'Akhir pekan');
  String get mosques => _t('Mosques', 'Masjid');
  String get around => _t('Around', 'Sekitar');
  String get openNow => _t('Open', 'Buka');
  String get closedNow => _t('Closed today', 'Tutup hari ini');
  String closedRange(String from, String to, String reason) =>
      _t('Closed $from–$to ($reason)', 'Tutup $from–$to ($reason)');
  String closureReason(String code) => switch (code) {
        'cleaning' => _t('cleaning', 'pembersihan'),
        'works' => _t('repairs', 'perbaikan'),
        _ => code,
      };
  String get favourite => _t('Favourite', 'Favorit');
  String get noUpcomingClosure => _t('No closure scheduled', 'Tidak ada jadwal tutup');
  String get dengueNone => _t('No active dengue cluster within 2 km.', 'Tidak ada cluster dengue aktif dalam 2 km.');
  String dengueCases(int n) => _t('$n cases', '$n kasus');
  String get dengueTips => _t(
      'Check for stagnant water at home once a week: flower pots, pails, roof gutters.',
      'Cek genangan air di rumah seminggu sekali: pot bunga, ember, talang atap.');
  String get parkingHint => _t('HDB car parks near this place. Tap a car park to save it.',
      'Parkir HDB di sekitar tempat ini. Ketuk untuk menyimpan.');
  String get freeParking => _t('Free parking', 'Parkir gratis');
  String get nightParking => _t('Night parking', 'Parkir malam');
  String get weekendSunny => _t('Dry weather: good time to head outdoors.', 'Cuaca kering: waktunya keluar rumah.');
  String get weekendRainy => _t('Rain expected: indoor ideas nearby.', 'Diperkirakan hujan: ide kegiatan di dalam ruangan.');
  String get schools => _t('Schools', 'Sekolah');
  String get primarySchools => _t('Primary schools', 'Sekolah dasar');
  String get secondarySchools => _t('Secondary schools', 'Sekolah menengah');
  String get preschools => _t('Preschools', 'Preschool');
  String get within1km => _t('Within 1 km', 'Dalam 1 km');
  String get between1and2km => _t('1 to 2 km', '1 sampai 2 km');
  String get p1Note => _t(
      'Straight-line distance from your saved address. MOE uses its own home-to-school measurement for P1 priority, so confirm on SchoolFinder.',
      'Jarak garis lurus dari alamat tersimpan. MOE memakai pengukuran sendiri untuk prioritas P1, jadi cek di SchoolFinder.');
  String get openSchoolFinder => _t('Open MOE SchoolFinder', 'Buka MOE SchoolFinder');
  String get setAddressForSchools => _t('Set your home address for accurate school distances.',
      'Atur alamat rumah supaya jarak sekolah akurat.');
  String get parkingElsewhere => _t('Check parking at another address', 'Cek parkir di alamat lain');
  String parkingNear(String place) => _t('Parking near $place', 'Parkir dekat $place');
  String get parks => _t('Parks', 'Taman');
  String get libraries => _t('Libraries', 'Perpustakaan');
  String get communityClubs => _t('Community clubs', 'Community club');
  String get sports => _t('Sports & pools', 'Olahraga & kolam renang');
  String get prayerTimes => _t('Prayer times today', 'Jadwal sholat hari ini');
  String get nextPrayer => _t('Next', 'Berikutnya');
  List<String> get prayerNames => _id
      ? const ['Subuh', 'Syuruk', 'Zohor', 'Asar', 'Maghrib', 'Isyak']
      : const ['Subuh', 'Syuruk', 'Zohor', 'Asar', 'Maghrib', 'Isyak'];
  String get fridayNote => _t('Friday: Zohor is replaced by Friday prayer.', 'Jumat: Zohor diganti sholat Jumat.');
  String get findMosque => _t('Find a mosque (MUIS directory)', 'Cari masjid (direktori MUIS)');
  String get prayerTab => _t('Prayer', 'Sholat');
  String get prayerSource => _t('Prayer times: MUIS via data.gov.sg.', 'Jadwal sholat: MUIS via data.gov.sg.');

  // ---------------------------------------------------------------- homes (HDB)
  String get homesTitle => _t('HDB homes', 'Rumah HDB');
  String get homesIntro => _t('Search a block to see resale prices, rent and daily life around it.',
      'Cari blok untuk melihat harga resale, sewa, dan kehidupan sehari-hari di sekitarnya.');
  String get blockSearchHint => _t('Block and street, e.g. 123 Bedok North', 'Blok dan jalan, misal 123 Bedok North');
  String get watched => _t('Watched blocks', 'Blok dipantau');
  String get compare => _t('Compare', 'Bandingkan');
  String compareCount(int n) => _t('Compare ($n)', 'Bandingkan ($n)');
  String get addToCompare => _t('Add to compare', 'Tambah ke perbandingan');
  String get inCompare => _t('In comparison', 'Sudah dibandingkan');
  String get watch => _t('Watch', 'Pantau');
  String get watching => _t('Watching', 'Dipantau');
  String builtIn(int y) => _t('Built $y', 'Dibangun $y');
  String leaseLeft(int years) => _t('$years years lease left', 'Sisa lease $years tahun');
  String storeys(int n) => _t('$n storeys', '$n lantai');
  String get resalePrices => _t('Resale prices, last 24 months', 'Harga resale, 24 bulan terakhir');
  String get noResale => _t('No resale transactions in this block in the last 24 months.',
      'Tidak ada transaksi resale di blok ini dalam 24 bulan terakhir.');
  String medianOf(int n) => _t('median of $n sales', 'median dari $n transaksi');
  String latestSale(String month, String price) => _t('Latest $month: $price', 'Terakhir $month: $price');
  String townMedian(String town) => _t('$town median', 'Median $town');
  String get rentTitle => _t('Typical rent in this town', 'Sewa umum di town ini');
  String get rentNote => _t('Median monthly rent of approved HDB rentals.', 'Median sewa bulanan dari sewa HDB yang disetujui.');
  String get perMonth => _t('/month', '/bulan');
  String get dailyLifeScore => _t('Daily life around this block', 'Kehidupan sehari-hari di sekitar blok');
  String get nearestMrt => _t('Nearest MRT', 'MRT terdekat');
  String get busStops400 => _t('Bus stops within 400 m', 'Halte dalam 400 m');
  String get hawkers1km => _t('Hawker centres within 1 km', 'Hawker dalam 1 km');
  String get primary1km => _t('Primary schools within 1 km', 'SD dalam 1 km');
  String get primary2km => _t('Primary schools within 2 km', 'SD dalam 2 km');
  String get parks1km => _t('Parks within 1 km', 'Taman dalam 1 km');
  String get dengue1km => _t('Dengue clusters within 1 km', 'Cluster dengue dalam 1 km');
  String get builtLabel => _t('Year built', 'Tahun dibangun');
  String get leaseLabel => _t('Lease left (years)', 'Sisa lease (tahun)');
  String get ceaSource => _t('Data: Council for Estate Agencies (CEA) via data.gov.sg.',
      'Data: Council for Estate Agencies (CEA) via data.gov.sg.');
  String get checkAgent => _t('Check a property agent', 'Cek agen properti');
  String get agentHint => _t('CEA registration number, e.g. R012345A', 'Nomor registrasi CEA, misal R012345A');
  String get agentNotFound => _t('No agent with this number in the CEA register.',
      'Tidak ada agen dengan nomor ini di register CEA.');
  String get agentRegistered => _t('Registered with CEA', 'Terdaftar di CEA');
  String get homesDisclaimer => _t(
      'Past transactions from public data, not current listings. Not financial advice. Check eligibility on hdb.gov.sg.',
      'Transaksi lampau dari data publik, bukan listing aktif. Bukan saran keuangan. Cek kelayakan di hdb.gov.sg.');
  String get emptyWatch => _t('Watch a block to get notified about new resale transactions.',
      'Pantau blok untuk dapat notifikasi transaksi resale baru.');
  String newSales(String block, int n) => _t('$n new resale transaction(s) at $block', '$n transaksi resale baru di $block');

  // ---------------------------------------------------------------- settings / more
  String get settings => _t('Settings', 'Pengaturan');
  String get welcome => _t('Welcome to DailyLah', 'Selamat datang di DailyLah');
  String get welcomeIntro => _t(
      'Set it up once and DailyLah tells you what matters: buses, MRT, rain and more. Everything stays on this phone.',
      'Atur sekali, lalu DailyLah kasih tahu yang penting: bus, MRT, hujan, dan lainnya. Semua tersimpan di HP ini saja.');
  String get places => _t('Places', 'Tempat');
  String get optional => _t('optional', 'opsional');
  String pickStopNear(String place) => _t('Pick the bus stop nearest to $place', 'Pilih halte terdekat dari $place');
  String get pickStop => _t('Pick a stop', 'Pilih halte');
  String get addAnotherStop => _t('Add another stop', 'Tambah halte lain');
  String get yourLines => _t('MRT/LRT lines you use', 'Jalur MRT/LRT yang biasa dipakai');
  String get departureTimes => _t('Usual departure times', 'Jam berangkat biasa');
  String get leaveHome => _t('Leave home', 'Dari rumah');
  String get leaveWork => _t('Leave work', 'Pulang dari kantor');
  String get notifications => _t('Notifications', 'Notifikasi');
  String get alertMrt => _t('MRT disruption on my lines', 'Gangguan MRT di jalur saya');
  String get alertRain => _t('Rain before I leave', 'Hujan sebelum berangkat');
  String get alertRainSub => _t('At most 3 a day, none 10 pm–6 am', 'Maksimal 3 per hari, tidak ada 22.00–06.00');
  String get alertHawker => _t('Favourite hawker closed tomorrow', 'Hawker favorit tutup besok');
  String get alertDengue => _t('New dengue cluster near home or school', 'Cluster dengue baru dekat rumah/sekolah');
  String get alertHeat => _t('Heat, lightning or haze', 'Panas, petir, atau kabut asap');
  String get alertHomes => _t('New resale transactions at watched blocks', 'Transaksi resale baru di blok dipantau');
  String get language => _t('Language', 'Bahasa');
  String get pickHomeFirst => _t('Set your home address first.', 'Atur alamat rumah dulu.');
  String get familyShare => _t('Share with family', 'Bagikan ke keluarga');
  String get familyShareSub => _t('Copy your places and lines to another phone', 'Salin tempat dan jalur ke HP lain');
  String get familyShareIntro => _t(
      'Scan or send this code to another phone. It holds your saved stops, lines and times, nothing else. No account or server involved.',
      'Scan atau kirim kode ini ke HP lain. Isinya hanya halte, jalur, dan jam yang kamu simpan. Tanpa akun dan tanpa server.');
  String get copyCode => _t('Copy code', 'Salin kode');
  String get shareCode => _t('Share code', 'Bagikan kode');
  String get codeCopied => _t('Code copied', 'Kode disalin');
  String get importCode => _t('Import from a family member', 'Impor dari anggota keluarga');
  String get pasteCode => _t('Paste the code here', 'Tempel kode di sini');
  String get importDone => _t('Places and lines imported', 'Tempat dan jalur sudah diimpor');
  String get importInvalid => _t('This code is not a DailyLah share code.', 'Kode ini bukan kode berbagi DailyLah.');
  String get about => _t('About DailyLah', 'Tentang DailyLah');
  String get aboutSub => _t('Privacy, terms and data sources', 'Privasi, ketentuan, dan sumber data');

  // about
  String version(String v) => _t('Version $v · Tursina Labs', 'Versi $v · Tursina Labs');
  String get aboutIntro => _t(
      'A daily companion for life in Singapore. No account, no ads. Your places and settings stay on this phone.',
      'Teman harian untuk hidup di Singapura. Tanpa akun, tanpa iklan. Tempat dan pengaturanmu hanya tersimpan di HP ini.');
  String get privacyPolicy => _t('Privacy policy', 'Kebijakan privasi');
  String get termsOfService => _t('Terms of service', 'Ketentuan layanan');
  String get contactUs => _t('Contact us', 'Hubungi kami');
  String get dataSources => _t('Data sources', 'Sumber data');
  String get dataAttribution => _t(
      'Contains information from LTA DataMall and from datasets by NEA, HDB, CEA, MUIS, NParks, NLB, SportSG, PA and MOE accessed through data.gov.sg, made available under the Singapore Open Data Licence. Bus times, crowd levels, forecasts and prices are estimates.',
      'Berisi informasi dari LTA DataMall dan dataset NEA, HDB, CEA, MUIS, NParks, NLB, SportSG, PA, dan MOE yang diakses melalui data.gov.sg, tersedia berdasarkan Singapore Open Data Licence. Jadwal bus, kepadatan, prakiraan, dan harga adalah perkiraan.');
  String get independent => _t(
      'DailyLah is an independent app and is not affiliated with LTA, NEA, HDB or the Singapore government.',
      'DailyLah adalah aplikasi independen dan tidak berafiliasi dengan LTA, NEA, HDB, atau pemerintah Singapura.');
  String get openSourceLicences => _t('Open-source licences', 'Lisensi open-source');
  String cannotOpen(String url) => _t('Cannot open $url', 'Tidak bisa membuka $url');
  String get yourSetup => _t('Your setup', 'Pengaturan kamu');
  String get editSetup => _t('Places, lines and times', 'Tempat, jalur, dan jam');
  String get alertsTitle => _t('Alerts', 'Peringatan');
  String get systemLanguage => _t('Phone default', 'Ikuti HP');

  // address
  String get address => _t('Address', 'Alamat');
  String get setAddress => _t('Set address', 'Atur alamat');
  String get changeAddress => _t('Change address', 'Ubah alamat');
  String addressFor(String place) => _t('Address of $place', 'Alamat $place');
  String get addressHint => _t('Postal code, block and street, or building', 'Kode pos, blok dan jalan, atau nama gedung');
  String get useMyLocation => _t('Use my current location', 'Pakai lokasi saya sekarang');
  String get myLocation => _t('My location', 'Lokasi saya');
  String get noAddressFound => _t('No address found. Try a postal code.', 'Alamat tidak ditemukan. Coba pakai kode pos.');
  String get addressPrivacy => _t(
      'Search uses OneMap (Singapore Land Authority). Your saved address stays on this phone.',
      'Pencarian memakai OneMap (Singapore Land Authority). Alamat yang disimpan tetap di HP ini.');
  String get busStopsHere => _t('Bus stops', 'Halte bus');
  String get stopsAutoPicked => _t('Nearest stops picked for you. Change them any time.',
      'Halte terdekat sudah dipilih otomatis. Bisa diganti kapan saja.');
  String get pickAddressFirst => _t('Set your home address first.', 'Atur alamat rumah dulu.');
  String get bundlesLoading => _t(
      'Downloading local data. Pull down or reopen the app in a moment.',
      'Sedang mengunduh data lokal. Tarik ke bawah atau buka ulang app sebentar lagi.');
  String get blockNotInData => _t('This address is not in the HDB block data yet.',
      'Alamat ini belum ada di data blok HDB.');

  // custom places and "anywhere"
  String get otherPlaces => _t('Other places', 'Tempat lain');
  String get otherPlacesHint => _t(
      "Save places you visit often, like your parents' home, the gym or your mosque.",
      'Simpan tempat yang sering dikunjungi, misalnya rumah orang tua, gym, atau masjid langganan.');
  String get addPlace => _t('Add a place', 'Tambah tempat');
  String get placeName => _t('Name', 'Nama');
  String get placeNameHint => _t("e.g. Mum's house, Gym", 'misal Rumah Ibu, Gym');
  String get rename => _t('Rename', 'Ganti nama');
  String get hereNow => _t('Here', 'Di sini');
  String get searchPlace => _t('Search', 'Cari');
  String maxPlaces(int n) => _t('You can save up to $n places.', 'Maksimal $n tempat.');

  // stop picker
  String get stopSearchHint => _t('Stop name, road or 5-digit code', 'Nama halte, jalan, atau kode 5 digit');
  String get nearestStops => _t('Nearest stops to my location', 'Halte terdekat dari lokasi saya');
  String get locationDenied => _t('Location permission denied. Search by name instead.',
      'Izin lokasi ditolak. Cari halte lewat nama saja.');
  String get locationUnavailable => _t('Location not available. Search by name instead.',
      'Lokasi tidak tersedia. Cari halte lewat nama saja.');
  String get stopsUnavailable => _t('Stop list not available yet. Try again later.',
      'Daftar halte belum tersedia. Coba lagi nanti.');
  String get checkBuses => _t('Check buses', 'Cek bus');
  String stopCode(String code) => _t('Stop $code', 'Halte $code');

  // notifications (background)
  String get channelName => _t('DailyLah alerts', 'Peringatan DailyLah');
  String get channelDesc => _t('MRT disruptions, rain, hawker closures, dengue and heat',
      'Gangguan MRT, hujan, hawker tutup, dengue, dan panas');
  String get checkAlternatives => _t('Check alternative routes.', 'Cek jalur alternatif.');
  String get hawkerTomorrowTitle => _t('Hawker closed tomorrow', 'Hawker tutup besok');
  String get dengueTitle => _t('Dengue cluster nearby', 'Cluster dengue di sekitar');
  String get heatTitle => _t('Heat and lightning', 'Panas dan petir');
}
