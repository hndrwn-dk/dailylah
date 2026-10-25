# DailyLah Privacy Policy

**Last updated: 24 October 2026**
App: DailyLah (Android, package `com.tursinalabs.dailylah`)
Published at: https://www.tursinalabs.com/dailylah/privacy

[English](#english) · [Bahasa Indonesia](#bahasa-indonesia)

---

## English

### 1. Scope
This policy covers only the DailyLah app by Tursina Labs. Other Tursina Labs products are covered by the studio privacy policy. Use of the app is also governed by the [DailyLah Terms of Service](https://www.tursinalabs.com/dailylah/terms).

### 2. What DailyLah is
DailyLah is a free daily companion for people in Singapore. It shows bus arrivals at your saved stops, MRT/LRT service status, platform crowd levels and the 2-hour weather forecast, using public data from LTA DataMall and data.gov.sg. There is no DailyLah account and no sign-in.

### 3. Data stored only on your phone
- Your saved places (Home, Work, School): the address you chose (label, postal code and coordinates) and the bus stops you picked for it
- The MRT/LRT lines you selected, your usual departure times, your alert settings, the days and times you go to work or school, starred MRT lines, and how you usually travel to each place (bus/MRT, car, motorbike, bicycle or taxi), and optional extras
- Favourite hawker centres, saved car parks, and HDB blocks you watch or compare
- A short log of alerts already shown, so the same alert is not sent twice
- What you choose to log with **Learn my habits**: trips you start and end with "I'm leaving" and "Arrived" (route, start time, minutes, whether it was raining, travel mode and straight-line distance), hawker centres you mark with "Ate here", and the car park, level and lot you save with "I parked here" (and, once you pick the car up, how long you parked there and whether it was an HDB car park, for a cost estimate), and any costs you enter for trips or parking. These are shown on the History tab, where you can remove single entries. You can turn this off and delete it all any time in More > Extras. It is not part of the family share code.
- Copies of public data bundles (bus stops, hawker centres, dengue clusters, schools, parks and their facilities, supermarkets, car parks, HDB blocks, resale and rent statistics, prayer times, public and MOE school holidays, and public events listed on Eventfinda), and the text shown on the home screen widget

This data never leaves your phone. It is not backed up to Tursina Labs.

**Share with family** creates a QR code or text code on your phone containing your saved bus stops, MRT lines and departure times. It is not sent to Tursina Labs; it only leaves your phone if you show it or send it yourself (for example through a chat app). Importing a code works by pasting it, without the camera.

### 4. Location
DailyLah asks for location permission only when you tap **"Nearest stops to my location"**, **"Use my current location"** or **"Here"** in the Nearby tab. Once you have allowed it, the Nearby tab also reads your position when you open it, so it can show what is around you. Your position is used on the phone to find the nearest bus stops, food, car parks, taxis and help, and is then discarded. It is not stored and is not sent to Tursina Labs or anyone else; for live bus arrivals the app sends only the bus stop codes. DailyLah does not otherwise use your location in the background. The one exception is **"Wake me at my stop"**: when you start it during a bus ride, the app follows your position until you are near your stop (shown as an ongoing notification, so it keeps working with the screen off), then stops. Your position is compared with the stop on the phone and is never stored or sent. You can deny the permission and still pick a saved place or search an address.

### 4a. Address search
When you set an address or search a postal code, the text you type is sent to our server, which passes it on to **OneMap**, the map service of the Singapore Land Authority, with our OneMap account token (OneMap requires one). Our server does not log the search text; it keeps the answer in memory for up to a day so the same search is not repeated, and it never knows who searched. If our server is unavailable, the phone asks OneMap directly. The address you pick is saved only on your phone. You can also choose **"Use my current location"**, which reads your position once and saves it as the address.

### 5. What our server receives
To show live information, the app sends requests to the DailyLah API operated by Tursina Labs:
- The 5-digit **bus stop code** you are viewing, to get bus arrival times
- The **MRT/LRT line code** (for example `NSL`), to get platform crowd levels
- A **CEA registration number** you type into "Check a property agent", to look it up in the public CEA register. This number identifies the agent, not you
- Requests for the weather forecast, haze (PSI and PM2.5), heat stress, lightning, train service alerts, HDB car park availability, car park availability for LTA, URA and HDB car parks, traffic incidents and taxi availability, which contain no personal data

Which buses go to your destination, parking near it and incidents on the way are worked out on your phone; the server only sends the full public lists. Searching HDB blocks, comparing blocks, nearby hawker centres, dengue clusters and weekend ideas are all computed on your phone from the public data bundles, so the server does not learn which places you look at.

The app also downloads these public data bundles from our website. Like any web service, our hosting providers record technical request logs (IP address, time, requested path and app version) for operations and security, and keep them for a limited period. We do not combine these logs with any other data and we do not use them to identify you. The server never receives your saved places, home or work location, or GPS coordinates.

The **Home** tab shows your block (or, for a private home, URA sale and rent figures for the project at your address), upgrading and construction work, schools, health and community services, recycling points, parks and parking around your saved home. All of it comes from public data bundles (OneMap, URA and data.gov.sg) downloaded to your phone, and the distances are computed on your phone; your home address is not sent anywhere for this.

If you turn on **Halal food nearby** (More > Extras), the app shows halal places listed on Muslim.sg from a bundle downloaded to your phone; searching and distances are done on your phone. DailyLah is not affiliated with MUIS.

The **Emergency** tab lists AEDs, A&E hospitals, CHAS clinics, fire stations and Civil Defence shelters near the place you pick, computed on your phone. Tapping a phone number opens your dialer; tapping directions opens Google Maps with the destination only. The "MRT route in Google Maps" button on a trip is the one exception: it opens Google Maps with both ends of that trip (for example your home and your office), and only when you tap it. The taxi view shows free taxis and LTA taxi stands around your place, also computed on your phone. The ride and food delivery buttons (Grab, Gojek, CDG Zig, TADA, GrabFood, foodpanda) only open that app on your phone, or its Play Store page; DailyLah sends nothing to them and takes no orders. Tapping an event opens its page on Eventfinda in your browser; the event list itself is downloaded by our daily build, so Eventfinda never sees who uses DailyLah. When you open a place (a hawker centre, car park, school and so on), the app loads a small map picture of that place from OneMap (Singapore Land Authority); only the place's coordinates are sent, not your location.

### 6. Notifications
Alerts for MRT disruptions, rain before your usual departure, favourite hawker centres closing tomorrow, dengue clusters near home or school, high heat stress or lightning, new resale transactions at blocks you watch, when to leave for your bus (to work or school, or to a saved place you gave a usual time), the Sunday "This week around you" summary and your parking time are decided **on your phone**. Every 15 minutes or so, the app checks the latest public alerts and forecast and, if they match your settings, shows a local notification. No push token or device identifier is sent to Tursina Labs. You can turn alerts off in the app settings or in Android settings.

### 7. What we do not do
- No DailyLah account and no sign-in
- No analytics, tracking or advertising SDKs, and no ads
- No sale or sharing of personal information
- No access to your contacts, photos, microphone or camera

### 8. Service providers
- **Render** (Singapore region) hosts the DailyLah API
- **Upstash** caches public weather and transport data (no personal data)
- **Vercel** hosts the public bus stop list and our web pages
- **Google Play** distributes the app and may process install, update and crash data under Google's own policies

Public data comes from **LTA DataMall** and **data.gov.sg**. The app does not send your data to these government sources; our server requests public data on behalf of all users.

### 9. Retention and deletion
Data on your phone stays until you clear the app's storage or uninstall DailyLah. Because there is no account, there is nothing to delete on our side and no account-deletion page. Server request logs expire automatically.

### 10. Your rights
Under Singapore's Personal Data Protection Act (PDPA) you may ask about personal data we hold. Because DailyLah has no accounts and does not link logs to people, we generally cannot identify any request as yours, but you can still contact us with questions.

### 11. Children
DailyLah is not directed at children under 13.

### 12. Changes
We may update this policy. When we do, we change the "Last updated" date above. The current version is always at https://www.tursinalabs.com/dailylah/privacy.

### 13. Contact
support@tursinalabs.com

---

## Bahasa Indonesia

### 1. Cakupan
Kebijakan ini hanya berlaku untuk aplikasi DailyLah dari Tursina Labs. Produk Tursina Labs lainnya diatur oleh kebijakan privasi studio. Penggunaan aplikasi juga diatur oleh [Ketentuan Layanan DailyLah](https://www.tursinalabs.com/dailylah/terms).

### 2. Tentang DailyLah
DailyLah adalah teman harian gratis untuk warga Singapura. Aplikasi ini menampilkan kedatangan bus di halte favorit, status layanan MRT/LRT, tingkat kepadatan peron, dan prakiraan cuaca 2 jam, memakai data publik dari LTA DataMall dan data.gov.sg. Tidak ada akun DailyLah dan tidak perlu login.

### 3. Data yang hanya tersimpan di HP Anda
- Tempat yang Anda simpan (Rumah, Kantor, Sekolah): alamat yang Anda pilih (label, kode pos, dan koordinat) serta halte bus yang Anda pilih
- Jalur MRT/LRT pilihan, jam berangkat biasa, pengaturan notifikasi, hari dan jam ke kantor atau sekolah, jalur MRT berbintang, dan cara Anda biasanya bepergian ke setiap tempat (bus/MRT, mobil, motor, sepeda, atau taksi), serta fitur tambahan opsional
- Hawker favorit, parkir yang disimpan, serta blok HDB yang Anda pantau atau bandingkan
- Catatan singkat notifikasi yang sudah tampil, supaya notifikasi yang sama tidak dikirim dua kali
- Yang Anda catat sendiri lewat **Learn my habits**: perjalanan yang Anda mulai dan akhiri dengan "I'm leaving" dan "Arrived" (rute, jam mulai, durasi, apakah sedang hujan, moda perjalanan, dan jarak garis lurus), hawker yang Anda tandai dengan "Ate here", serta lokasi parkir, level, dan nomor lot yang Anda simpan dengan "I parked here" (dan, setelah mobil diambil, berapa lama parkirnya serta apakah itu tempat parkir HDB, untuk perkiraan biaya), serta biaya perjalanan atau parkir yang Anda isi sendiri. Semua ini tampil di tab History, tempat Anda bisa menghapus entri satu per satu. Fitur ini bisa dimatikan dan seluruh datanya dihapus kapan saja di More > Extras. Data ini tidak ikut dalam kode berbagi keluarga.
- Salinan bundel data publik (halte bus, hawker, cluster dengue, sekolah, taman beserta fasilitasnya, supermarket, parkir, blok HDB, statistik harga resale dan sewa, jadwal sholat, hari libur nasional dan libur sekolah MOE, serta event publik dari Eventfinda), dan teks yang tampil di widget layar utama

Data ini tidak pernah keluar dari HP Anda dan tidak dicadangkan ke Tursina Labs.

**Bagikan ke keluarga** membuat kode QR atau kode teks di HP Anda yang berisi halte bus, jalur MRT, dan jam berangkat yang Anda simpan. Kode ini tidak dikirim ke Tursina Labs; kode hanya keluar dari HP jika Anda sendiri menunjukkan atau mengirimkannya (misalnya lewat aplikasi chat). Impor kode dilakukan dengan menempelkan teks, tanpa kamera.

### 4. Lokasi
DailyLah hanya meminta izin lokasi saat Anda menekan **"Halte terdekat dari lokasi saya"**, **"Gunakan lokasi saya saat ini"**, atau **"Here"** di tab Nearby. Setelah Anda mengizinkan, tab Nearby juga membaca posisi Anda saat dibuka agar bisa menampilkan apa yang ada di sekitar Anda. Posisi Anda dipakai di HP untuk mencari halte, makanan, parkir, taksi, dan bantuan terdekat, lalu dibuang. Posisi tidak disimpan dan tidak dikirim ke Tursina Labs atau pihak lain; untuk jadwal bus, aplikasi hanya mengirim kode halte. Selain itu DailyLah tidak memakai lokasi di latar belakang. Satu-satunya pengecualian adalah **"Wake me at my stop"**: saat Anda menyalakannya di dalam bus, aplikasi mengikuti posisi Anda sampai dekat halte tujuan (tampil sebagai notifikasi yang berjalan, supaya tetap bekerja saat layar mati), lalu berhenti. Posisi dibandingkan dengan halte di HP dan tidak pernah disimpan atau dikirim. Anda boleh menolak izin ini dan tetap bisa memilih tempat tersimpan atau mencari alamat.

### 4a. Pencarian alamat
Saat Anda mengatur alamat atau mencari kode pos, teks yang Anda ketik dikirim ke server kami, yang meneruskannya ke **OneMap**, layanan peta Singapore Land Authority, dengan token akun OneMap kami (OneMap mewajibkannya). Server kami tidak mencatat teks pencarian; jawabannya disimpan di memori paling lama sehari agar pencarian yang sama tidak diulang, dan server tidak tahu siapa yang mencari. Jika server kami tidak tersedia, HP bertanya langsung ke OneMap. Alamat yang Anda pilih hanya disimpan di HP. Anda juga bisa memilih **"Pakai lokasi saya sekarang"**, yang membaca posisi Anda sekali lalu menyimpannya sebagai alamat.

### 5. Data yang diterima server kami
Untuk menampilkan informasi real-time, aplikasi mengirim permintaan ke API DailyLah yang dioperasikan Tursina Labs:
- **Kode halte bus** 5 digit yang sedang Anda lihat, untuk mendapatkan jadwal kedatangan bus
- **Kode jalur MRT/LRT** (misalnya `NSL`), untuk mendapatkan tingkat kepadatan peron
- **Nomor registrasi CEA** yang Anda ketik di "Cek agen properti", untuk dicocokkan dengan register CEA publik. Nomor ini mengidentifikasi agen, bukan Anda
- Permintaan prakiraan cuaca, kabut asap (PSI dan PM2.5), tingkat panas, petir, status layanan kereta, ketersediaan parkir HDB, ketersediaan parkir LTA, URA, dan HDB, insiden lalu lintas, dan ketersediaan taksi, yang tidak berisi data pribadi

Bus mana yang menuju tujuan Anda, parkir di dekatnya, dan insiden di jalan dihitung di HP Anda; server hanya mengirim daftar publik lengkap. Pencarian blok HDB, perbandingan blok, hawker terdekat, cluster dengue, dan ide akhir pekan dihitung di HP Anda dari bundel data publik, sehingga server tidak tahu tempat mana yang Anda lihat.

Aplikasi juga mengunduh bundel data publik tersebut dari situs kami. Seperti layanan web pada umumnya, penyedia hosting kami mencatat log teknis (alamat IP, waktu, path yang diminta, dan versi aplikasi) untuk operasional dan keamanan, dan menyimpannya untuk jangka waktu terbatas. Kami tidak menggabungkan log ini dengan data lain dan tidak memakainya untuk mengidentifikasi Anda. Server tidak pernah menerima tempat yang Anda simpan, lokasi rumah atau kantor, maupun koordinat GPS.

Tab **Home** menampilkan blok Anda (atau, untuk rumah swasta, data jual dan sewa URA untuk proyek di alamat Anda), pekerjaan upgrading dan konstruksi, sekolah, layanan kesehatan dan komunitas, titik daur ulang, taman, dan parkir di sekitar rumah yang Anda simpan. Semuanya berasal dari bundle data publik (OneMap, URA, dan data.gov.sg) yang diunduh ke HP, dan jaraknya dihitung di HP; alamat rumah Anda tidak dikirim ke mana pun untuk fitur ini.

Jika Anda menyalakan **Halal food nearby** (More > Extras), app menampilkan tempat halal yang terdaftar di Muslim.sg dari bundle yang diunduh ke HP; pencarian dan jarak dihitung di HP. DailyLah tidak berafiliasi dengan MUIS.

Tab **Darurat** menampilkan AED, IGD rumah sakit, klinik CHAS, pos pemadam kebakaran, dan shelter Civil Defence di sekitar tempat yang Anda pilih, dihitung di HP Anda. Menekan nomor telepon membuka aplikasi telepon; menekan rute membuka Google Maps dengan tujuan saja. Satu-satunya pengecualian adalah tombol "MRT route in Google Maps" pada perjalanan: tombol itu membuka Google Maps dengan kedua ujung perjalanan (misalnya rumah dan kantor Anda), dan hanya saat Anda menekannya. Tampilan taksi menunjukkan taksi kosong dan pangkalan taksi LTA di sekitar tempat Anda, juga dihitung di HP Anda. Saat Anda membuka sebuah tempat (hawker, parkir, sekolah, dan lain-lain), app memuat gambar peta kecil tempat itu dari OneMap (Singapore Land Authority); yang dikirim hanya koordinat tempat tersebut, bukan lokasi Anda. Tombol ride dan pesan antar makanan (Grab, Gojek, CDG Zig, TADA, GrabFood, foodpanda) hanya membuka aplikasi tersebut di HP Anda, atau halaman Play Store-nya; DailyLah tidak mengirim apa pun ke aplikasi itu dan tidak menerima pesanan. Menekan sebuah event membuka halamannya di Eventfinda di browser; daftar event diunduh oleh proses harian kami, jadi Eventfinda tidak tahu siapa yang memakai DailyLah.

### 6. Notifikasi
Notifikasi gangguan MRT, hujan sebelum jam berangkat, hawker favorit yang tutup besok, cluster dengue dekat rumah atau sekolah, panas tinggi atau petir, transaksi resale baru di blok yang Anda pantau, kapan berangkat untuk mengejar bus (ke kantor, sekolah, atau tempat tersimpan yang Anda beri jam biasa), ringkasan Minggu "This week around you", dan waktu parkir Anda diputuskan **di HP Anda**. Kira-kira setiap 15 menit, aplikasi mengecek status dan prakiraan publik terbaru, lalu menampilkan notifikasi lokal jika sesuai dengan pengaturan Anda. Tidak ada token push atau pengenal perangkat yang dikirim ke Tursina Labs. Notifikasi bisa dimatikan di pengaturan aplikasi atau pengaturan Android.

### 7. Yang tidak kami lakukan
- Tidak ada akun DailyLah dan tidak ada login
- Tidak ada SDK analitik, pelacakan, atau iklan, dan tidak ada iklan
- Tidak menjual atau membagikan informasi pribadi
- Tidak mengakses kontak, foto, mikrofon, atau kamera

### 8. Penyedia layanan
- **Render** (region Singapura) menjalankan API DailyLah
- **Upstash** menyimpan cache data cuaca dan transportasi publik (tanpa data pribadi)
- **Vercel** menyajikan daftar halte bus publik dan halaman web kami
- **Google Play** mendistribusikan aplikasi dan dapat memproses data instalasi, pembaruan, dan crash sesuai kebijakan Google

Data publik berasal dari **LTA DataMall** dan **data.gov.sg**. Aplikasi tidak mengirim data Anda ke sumber pemerintah tersebut; server kami yang meminta data publik atas nama semua pengguna.

### 9. Penyimpanan dan penghapusan
Data di HP Anda tersimpan sampai Anda menghapus penyimpanan aplikasi atau meng-uninstall DailyLah. Karena tidak ada akun, tidak ada data yang perlu dihapus di sisi kami dan tidak ada halaman penghapusan akun. Log permintaan di server terhapus otomatis.

### 10. Hak Anda
Berdasarkan Personal Data Protection Act (PDPA) Singapura, Anda dapat menanyakan data pribadi yang kami simpan. Karena DailyLah tidak memiliki akun dan tidak mengaitkan log dengan orang tertentu, umumnya kami tidak dapat mengenali permintaan mana yang berasal dari Anda, tetapi Anda tetap dapat menghubungi kami.

### 11. Anak-anak
DailyLah tidak ditujukan untuk anak di bawah 13 tahun.

### 12. Perubahan
Kami dapat memperbarui kebijakan ini. Jika diperbarui, tanggal "Last updated" di atas akan berubah. Versi terbaru selalu ada di https://www.tursinalabs.com/dailylah/privacy.

### 13. Kontak
support@tursinalabs.com
