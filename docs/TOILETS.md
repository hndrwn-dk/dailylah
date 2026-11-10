# Rencana: "Need a toilet?" di perjalanan dan di Nearby (9 Nov 2026)

Masalah: orang kebelet di bus atau MRT perlu tahu turun di mana dan berapa lama lagi untuk sampai ke toilet terdekat. Tidak ada dataset toilet umum resmi di data.gov.sg; data digabung dari Geoapify (OpenStreetMap), NParks dan hawker centre.

## Keputusan
- Opsi C: saat ride aktif ("Wake me at my stop" atau "I'm on the train") pakai sisa rute; tanpa ride pakai lokasi sekarang.
- Semua dihitung di HP dari bundle statis; lokasi tidak dikirim ke mana pun. Key Geoapify hanya di CI (secret `GEOAPIFY_API_KEY`), tidak di APK, tidak di Render untuk fitur ini.
- Urutan: waktu tercepat dulu; seri → mal, hawker, stasiun/interchange lebih dulu (lebih banyak bilik, cocok untuk "besar").
- MRT tanpa data toilet di dekatnya: tetap tampilkan stasiun dengan teks "Stations usually have a toilet", tanpa klaim lebih.
- Teks UI bahasa Inggris. Atribusi "© OpenStreetMap contributors" di layar toilet dan di halaman legal.

## Data: bundle `toilets.json` (backend/app/bundles.py, data.yml)
- `build_toilets(client, hawkers, poi)`:
  - Geoapify Places `GET https://api.geoapify.com/v2/places?categories=amenity.toilet&filter=rect:103.59,1.15,104.10,1.48&limit=500&offset=N` sampai halaman kosong (maks 20 halaman). Ambil `name`, `lat`, `lon`, dan kategori/datasource untuk jenis.
  - Tambah toilet taman dari data fasilitas NParks yang sudah ada (`PARK_FACILITIES`, label "Toilet") dan semua hawker centre dari `build_hawkers` (hampir semua punya toilet).
  - Jenis `k`: `mall` | `station` (MRT/LRT/bus interchange) | `hawker` | `park` | `other`, dari kategori Geoapify dan nama (mis. "Interchange", "MRT", "Mall", "Plaza", "City").
  - Dedupe: titik berjarak < 30 m dianggap sama; simpan yang namanya paling jelas.
  - Format ringkas: `[{"n": "Jurong Point", "la": 1.3399, "lo": 103.7065, "k": "mall"}]`, koordinat 5 desimal.
- `build_static.py`: `attempt("toilets", ...)`; data lama dipakai kalau Geoapify gagal (pola `attempt` yang ada).
- `.github/workflows/data.yml`: env `GEOAPIFY_API_KEY: ${{ secrets.GEOAPIFY_API_KEY }}` di job build. Kalau job memakai allowlist egress, tambah `api.geoapify.com`. Key tidak boleh tercetak di log (jangan print URL).
- Tes backend: parsing halaman Geoapify (mock), paginasi berhenti di halaman kosong, dedupe 30 m, jenis dari nama, hawker/taman ikut masuk, kegagalan Geoapify tidak menghapus bundle lama, key tidak ada di output.

## App
- `data.dart`: `class Toilet { name, lat, lng, kind }` + `fromBundle`. `providers.dart`: `toiletsProvider` dari bundle `toilets`.
- `logic.dart`:
  - `List<ToiletStop> toiletsAheadBus(BusRoutes routes, String service, BusStop from, BusStop alight, List<BusStop> stops, List<Toilet> toilets, {double radius = 250, int limit = 3})`: halte di antara posisi sekarang dan halte turun (urutan dari `bus_routes`), untuk tiap halte toilet terdekat dalam `radius` m. Menit ke halte ≈ 2 menit per halte, ditambah jalan kaki (`walkMinutesTo`). Halte tanpa toilet dilewati.
  - `List<ToiletStop> toiletsAheadMrt(MrtRide ride, int? fixIndex, List<MrtExit> exits, List<Toilet> toilets, {double radius = 150, int limit = 3})`: stasiun berikutnya; toilet dalam 150 m dari salah satu pintu keluar; kalau tidak ada, entri stasiun dengan `assumed: true`. Menit memakai perkiraan waktu antar stasiun yang sudah dipakai `mrt_ride.dart`.
  - `List<(Toilet, double)> toiletsNear(List<Toilet> all, double lat, double lng, {int limit = 3})`.
  - Urutan pakai fungsi bersama `toiletRank` (menit, lalu jenis mal/hawker/station, lalu jarak).
- UI `lib/ui/toilets.dart` (`ToiletSheet`): daftar maks 3: "Get off at <stop> (in ±6 min) · <toilet>, 2 min walk" atau "<toilet> · 300 m". Tombol arah jalan kaki membuka Google Maps dengan tujuan saja (seperti Emergency). Baris atribusi OSM.
- Pintu masuk:
  - `ui/wake.dart` dan `ui/mrt_ride.dart`: tombol "Need a toilet?" (ikon `Icons.wc`) → `ToiletSheet` mode ride.
  - Notifikasi ongoing Wake me / I'm on the train: action "Need a toilet?" yang membuka app langsung ke sheet (kalau pola action notifikasi sudah ada; kalau belum, tombol di layar saja dan catat di PR).
  - Nearby: chip "Toilets" → `ToiletSheet` mode lokasi (izin lokasi seperti fitur Nearby lain).
- Tes app: bus (urutan halte benar, halte tanpa toilet dilewati, hanya halte sebelum/sampai halte turun, limit 3); MRT (toilet dekat exit, fallback `assumed`); `toiletsNear`; ranking seri memilih mal; widget test sheet mode ride dan mode lokasi; dark mode dan text scale 2.0.

## Privacy dan docs
- `docs/legal/privacy.md`: daftar toilet adalah bundle publik yang diunduh ke HP; posisi dan rute dihitung di HP dan tidak dikirim. Atribusi OpenStreetMap (ODbL) dan Geoapify.
- `app/CLAUDE.md` feature map, `backend/CLAUDE.md` (bundle baru + secret CI), `python3 scripts/repo_map.py`, `docs/QA.md` (cek manual: Wake me di bus 2 halte → sheet menampilkan halte; Nearby → 3 toilet).

## Langkah untuk Hendrawan
1. GitHub → Settings → Secrets and variables → Actions: `GEOAPIFY_API_KEY` (boleh key yang sama dengan Render, atau key kedua khusus CI).
2. Jalankan `data.yml` manual sekali setelah merge; cek `web/data/toilets.json` terisi.

## Rencana kerja (satu PR, branch `feat/toilets`)
1. Backend `build_toilets` + tes + `build_static`. (~30 mnt)
2. `data.yml` secret/allowlist + docs backend. (~10 mnt)
3. App `Toilet`, provider, `toiletsNear`, `toiletRank` + tes. (~20 mnt)
4. `toiletsAheadBus` dan `toiletsAheadMrt` + tes. (~35 mnt)
5. `ToiletSheet` + tombol di wake/mrt_ride + chip Nearby (+ action notifikasi kalau ada polanya) + widget test. (~35 mnt)
6. Privacy, feature map, repo map, QA. Draf commit + PR ke Hendrawan sebelum commit/PR; setelah PR: review-pr + security gate.

## Di luar cakupan
Jam buka dan rating toilet, toilet di dalam/luar gantry MRT (tidak ada data), filter kecil/besar terpisah, toilet aksesibel/bayi (bisa v2 dari tag OSM `wheelchair`/`changing_table`).

## Catatan implementasi (beda dari rencana, mengikuti kode)
- Tidak ada data pintu keluar MRT di app: `mrt_stations.json` memberi satu titik per stasiun (rata-rata exit). `toiletsAheadMrt(ride, here, toilets)` memakai radius 250 m dari titik stasiun (≈ 150 m dari exit), bukan `List<MrtExit>`/`fixIndex`; `here` = posisi perkiraan ride (`RideState.indexAt`).
- `toiletsAheadBus` menerima `Map<String, BusStop>` (`busStopsByCodeProvider`) dan posisi GPS terakhir (`lat`, `lng`) dari `WakeState`, yang kini juga menyimpan halte naik (`from`, diisi dari kartu trip). Menit per halte = `feederMinutesPerStop` (2).
- Menit antar stasiun = `rideMinutesTo` (`rideMinutesPerStop` 2, `rideTransferMinutes` 5).
- Belum ada pola action di notifikasi ongoing (notifikasi lokasi dibuat geolocator, `notifyNow` tanpa action): "Need a toilet?" hanya tombol di layar Wake me dan On the train.
- Nearby: "Toilets" adalah chip section seperti chip lain (`ToiletsNearby` untuk tempat yang dipilih, termasuk Here), bukan bottom sheet.
- Toilet taman: titik toilet NParks dari Park Facilities yang sudah diunduh `build_poi` (`park_toilet_points`), dinamai taman terdekat ≤ 400 m.
