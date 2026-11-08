# Rencana: "Where to live?" di dailylah.sg (7 Nov 2026)

Alat web interaktif: pengguna pilih area kantor + tipe flat + sewa/beli + budget → peta dan daftar town HDB diurutkan berdasar waktu tempuh angkutan umum dan harga median. Tujuan: pemancing trafik/SEO dan jalan masuk ke app DailyLah di Play Store. Rilis bareng DailyLah naik production (sekitar 9 Nov 2026).

## Keputusan
- Ide yang dipilih: "Where to live?" (commute + harga HDB). Ide cadangan: "Singapore right now" (peta live), tanpa carpark karena sudah ada wheretopark.sg.
- Bukan Flutter web. Halaman ringan dan statis di situs dailylah.sg (Vercel), data JSON statis.
- Tidak ada API call langsung dari browser: semua data dihitung oleh job terjadwal dan disajikan statis. Render tidak dipakai.
- Teks UI dalam bahasa Inggris, netral agama (sama dengan app).
- Aturan kerja tetap mengikuti docs/HANDOFF.md: satu fase satu PR, rencana dulu dan tunggu persetujuan, tanpa atribusi AI, semua bisa dari HP.

## Sumber data
- Median rent by town & flat type (HDB, per kuartal): data.gov.sg `d_23000a00c52996c55106084ed0339566`. Nilai `na`/kosong = kurang dari 20 transaksi, tampilkan sebagai "not enough data".
- Median resale price by town & flat type (HDB, per kuartal): data.gov.sg `d_b51323a474ba789fb4cc3db58a3116d4`.
- Waktu tempuh: OneMap routing `https://www.onemap.gov.sg/api/public/routingsvc/route`, `routeType=pt`, `mode=TRANSIT`, token Bearer (akun OneMap email/password, token berlaku sekitar 3 hari). Hari kerja, berangkat 08:30. Matriks sekitar 26 town × 6 area kantor ≈ 156 panggilan per refresh.
- Titik town: daftar koordinat pusat town (stasiun MRT/interchange utama) disimpan di JSON di repo dan dicek manual sekali.
- Area kantor v1: CBD (Raffles Place), one-north, Jurong East, Changi Business Park, Woodlands, Paya Lebar. Kode pos bebas ditunda ke v2.
- Lisensi: Singapore Open Data Licence (cantumkan atribusi HDB/data.gov.sg) + atribusi OneMap/SLA di peta.

## Status
- Fase 0: selesai. Secret `ONEMAP_EMAIL`/`ONEMAP_PASSWORD` sudah ada (dipakai `data.yml`); situs dailylah.sg adalah folder `web/` di repo ini (Vercel).
- Fase 1: selesai (PR #116, 7 Nov 2026); run pertama di `main` commit datanya, run kedua "No data changes".
- Fase 2: branch `feat/where-to-live-page` (lihat "Fase 2: yang dibangun").

## Fase 0: langkah untuk Hendrawan (selesai)
1. Daftar akun OneMap API, lalu tambahkan secret `ONEMAP_EMAIL` dan `ONEMAP_PASSWORD` di repo.
2. Pastikan di mana kode situs dailylah.sg berada (folder di repo dailylah atau repo/proyek Vercel lain). Cek dulu sebelum merencanakan Fase 2.

## Fase 1: pipeline data (1 PR)
- `scripts/where_to_live/build.py` (Python, di bawah ruff S + pip-audit yang sudah ada): ambil dua dataset HDB, ambil kuartal terbaru yang tersedia per town/flat type, hitung matriks OneMap, lalu keluarkan `where-to-live.json` (berisi `generated_at`, kuartal sumber, per town: rent/resale per flat type, menit + jumlah transfer per area kantor).
- Retry + backoff untuk OneMap, cache hasil rute (rute jarang berubah; hitung ulang bulanan, harga dicek mingguan).
- Workflow terjadwal mingguan (pin SHA, permissions minimal, lolos zizmor) yang membuka PR atau commit hanya kalau JSON berubah. Repo public, jadi menit runner standar aman, tapi tetap ukur durasinya.
- Unit test untuk parser (`na`, kuartal hilang, town tanpa data).

### Fase 1: yang dibangun (beda dari rencana awal)
- Kode di `backend/app/where_to_live.py` (bukan `scripts/`), supaya kena ruff `S`, pip-audit dan
  `pytest` backend, dan memakai `DataGov` (`app/bundles.py`) serta `OneMap` (`app/onemap.py`).
  Tes: `backend/tests/test_where_to_live.py`.
- Hanya dataset median kuartal; tidak ada fallback ke `hdb_rent.json`.
- Titik town dan area kantor: `backend/data/where_to_live_points.json` (26 town, 6 area), koordinat
  stasiun dari `web/data/mrt_stations.json` (dicek oleh tes). Town "CENTRAL" di data HDB = Central
  Area (titik Tanjong Pagar).
- Per town dan tipe flat: median dari kuartal terbaru yang punya angka, paling jauh 4 kuartal ke
  belakang (`QUARTERS_KEPT`), disimpan sebagai `{"median", "quarter"}`; `null` = "not enough data".
  Tipe flat yang ada di dataset tapi tidak di town itu juga `null`.
- Rute: OneMap `routeType=pt`, `mode=TRANSIT`, hari kerja berikutnya (lewati libur dari
  `web/data/holidays.json`) jam 08:30, itinerary tercepat. Retry 3x dengan backoff untuk 429/5xx/
  error jaringan. Cache `backend/data/where_to_live_routes.json`, dihitung ulang setelah 30 hari
  atau kalau titiknya pindah; rute yang gagal memakai nilai lama. Town yang sama dengan area kantor
  (Jurong East, Woodlands) tidak ditanya ke OneMap dan dicatat
  `{"min": null, "transfers": null, "same_area": true}`; halaman menampilkannya sebagai "In this area".
- Keluaran `web/data/where-to-live.json` (compact): `generated_at`, `rent_quarter`,
  `resale_quarter`, `commute_depart`, `areas[]`, `towns[]` (`id`, `name`, `station`, `lat`, `lng`,
  `rent`, `resale`, `commute: {area id: {"min", "transfers"} | {"same_area": true, ...} | null}`),
  `attribution`. Tipe flat dari kedua dataset (`4-RM`, `4-room`) dinormalisasi ke `4-ROOM`. Tidak masuk
  `manifest.json` app (`NOT_IN_MANIFEST` di `build_static.py`).
- `generated_at` hanya diperbarui kalau datanya berubah, jadi minggu tanpa perubahan tidak membuat
  commit. Cache rute juga hanya ditulis kalau berubah.
- Run dianggap rusak dan tidak menulis apa pun kalau kurang dari 20 town punya harga atau kurang
  dari 75% waktu tempuh diketahui.
- Workflow `.github/workflows/where-to-live.yml`: Senin 03:41 SGT + `workflow_dispatch`, job `build`
  hanya di `main`, commit langsung ke `main` seperti `data.yml` (pull --rebase lalu push, 3 kali).
  Saat ruleset `main` aktif, workflow ini butuh bypass yang sama dengan `data.yml` (HANDOFF,
  "Rulesets").
- Uji di branch: trigger sementara `push` dengan job `dry-run` (`--dry-run`) jalan sekali pada
  7 Nov 2026 (154 rute OK, sekitar 3,6 menit; kolom asli: sewa `quarter`/`town`/`flat_type` `4-RM`/
  `median_rent`, resale `quarter`/`town` huruf campur/`flat_type` `4-room`/`price`, nilai `na` dan
  `-`). Trigger itu sudah dihapus sebelum merge.
- Lokal: `cd backend && python -m app.where_to_live ../web/data --dry-run` (butuh `.env` dengan
  akun OneMap).

## Fase 2: halaman web (1 PR)
- Rute `/where-to-live` di dailylah.sg, mobile-first, dark mode, aksesibel (kontras, label, keyboard).
- Input: area kantor, sewa/beli, tipe flat, budget, maks waktu tempuh. Hasil: daftar urut + peta (MapLibre atau Leaflet dengan tile OneMap, marker/bubble di pusat town; poligon ditunda karena batas town HDB ≠ planning area).
- Kartu town: "38 min to CBD, 1 transfer, 4-room median rent $X (Q3 2026)".
- State di URL query supaya hasil bisa dibagikan. CTA "Get DailyLah" ke Play Store.
- Disclaimer: angka indikatif dari data HDB yang dideklarasikan sendiri; tidak berafiliasi dengan HDB/SLA.
- **Wajib saat merender `where-to-live.json`:**
  - Semua teks dari JSON (`name`, `station`, `attribution`, id area, dan teks lain yang datang dari
    file itu) di-escape: pakai `textContent` / `createTextNode` atau escape HTML; jangan pernah
    `innerHTML` dengan string dari JSON. Berlaku juga untuk popup/tooltip peta dan atribut
    (`title`, `aria-label`). Nilai dari URL query (area, tipe flat, budget) divalidasi terhadap
    daftar yang ada di JSON sebelum dipakai.
  - Label harga memakai `quarter` per angka (`rent["4-ROOM"].quarter`), bukan `rent_quarter`/
    `resale_quarter` di level atas: satu town bisa memakai kuartal yang lebih lama karena kuartal
    terbarunya `na`. `null` ditampilkan sebagai "Not enough data".
  - Commute `{"same_area": true}` ditampilkan sebagai "In this area"; commute `null` sebagai
    "No route data".

### Fase 2: yang dibangun
- Halaman `web/where-to-live/index.html` (dilayani di `/where-to-live`), `app.css`, `app.js` (DOM dan
  peta), `logic.js` (fungsi murni: baca/tulis URL, `rank`, label). Tanpa build step, tanpa CDN.
- Daftar ranking bergaya papan LED (seperti papan bus di landing page): satu baris per town
  (nama, menit, harga tebal: `$3,400/mo` atau `$559,400`). Baris adalah tombol (`aria-expanded`);
  saat dibuka tampil stasiun, jumlah transfer, kuartal angka itu, dan alasan kalau di luar pilihan.
  Tiga kelompok: "Fits your choices" (8 teratas, lalu tombol "Show all N"), "No <flat> price data"
  (hanya kalau budget diisi), "Outside your choices" (dilipat dalam `<details>` selama ada town yang
  cocok). Urutan: waktu tempuh (same area paling atas), lalu harga.
- Peta Leaflet 1.9.4 (`web/vendor/leaflet-1.9.4/`, dari npm, checksum di README-nya), tile OneMap
  Default/Night mengikuti `prefers-color-scheme`, atribusi OneMap (logo
  `https://www.onemap.gov.sg/web-assets/images/logo/om_logo.png`, OneMap, SLA; logo yang gagal dimuat
  disembunyikan). Penanda: pil berisi menit (`22′`) lewat `L.divIcon` dengan elemen DOM, warna per
  waktu tempuh (≤20, 21–35, 36–50, >50; "Here" untuk town = area kantor), garis putus-putus kalau
  tanpa harga, abu dan kecil kalau di luar pilihan; kantor memakai pin. Ketuk pil membuka barisnya di
  daftar (menampilkan semua / membuka lipatan kalau perlu); ketuk baris menyorot pil dan membuka
  popup-nya. Desktop: peta `position: sticky` di kolom kanan. HP: peta di atas daftar (320 px).
- Form: Rent / Buy resale sebagai segmented control; semua kontrol 46 px supaya baris desktop rata.
- Kartu ringkasan di atas daftar (`highlights` di `logic.js`): "Fastest" (waktu tempuh terpendek,
  harga lebih murah kalau seri) dan "Best value" (termurah di antara town dengan waktu tempuh ≤ median
  kandidat), hanya dari town yang cocok dan punya harga serta rute; disembunyikan kalau tidak ada.
- Tombol Share: `navigator.share` dengan URL saat ini; kalau tidak ada, "Copy link" lalu "Link
  copied" (clipboard). Tanpa script pihak ketiga, CSP tidak berubah.
- Footer pendek: satu baris "Indicative figures from HDB via data.gov.sg (Singapore Open Data Licence).
  Updated <tanggal dari generated_at>.", lalu `<details>` "About the data" (kuartal, 08:30 dari stasiun
  MRT utama, perjalanan terjadwal, arti "not enough data", tidak berafiliasi dengan HDB/SLA), lalu
  DailyLah · Privacy · Terms. OneMap/SLA hanya di atribusi peta. Daftar sumber lengkap dan catatan
  halal ada di `docs/legal/terms.md` bagian 5.
- Teks ringan bergaya landing page (subjudul, hasil kosong, judul CTA "Know before you go lah.");
  disclaimer, atribusi dan label data tetap bahasa Inggris standar.
- State di URL (`?area=&mode=&flat=&budget=&max=`), nilai di-validasi terhadap JSON; default tidak
  ditulis.
- CTA dari `web/shared/cta.js` (satu konstanta untuk landing page dan halaman ini): sekarang alur
  tester (Google Group lalu opt-in). Ganti ke listing publik saat production live (HANDOFF).
- CSP khusus `/where-to-live` di `web/vercel.json`: hanya `'self'` untuk script, style, font dan
  fetch; gambar dari `'self'`, `data:` dan `www.onemap.gov.sg`. Atribusi OneMap memakai kelas
  `om-logo`, bukan style inline.
- Tes: `web/tests/logic.test.mjs` (`node --test`, workflow `web.yml`, check `web result`): URL dan
  nilai liar, label kuartal per angka, `same_area`, budget/waktu, alasan, file JSON asli, tidak ada
  `innerHTML` di skrip halaman, CTA hanya di `cta.js`, aset hanya lokal. Escaping dicek dengan
  Playwright memakai JSON berisi HTML/JS: tampil sebagai teks, tidak ada script yang jalan.
- `scripts/web_check.sh` langkah 5: `/where-to-live` 200 dengan CSP, `where-to-live.json` valid.
- Privasi: `docs/legal/privacy.md` bagian 5a (situs, OneMap tiles, tanpa cookie/analytics).

## Fase 3: SEO, ongkos, halaman town (dibangun 8 Nov 2026)
- **Ongkos:** tiap rute OneMap menyimpan `fare` (tarif kartu dewasa, sen; `null` kalau OneMap tidak
  memberi) di cache dan di `commute.<area>.fare`. Entri cache lama tanpa `fare` diambil ulang sekali
  (run pertama setelah merge: sekitar 154 panggilan, 4 menit). Laporan run mencatat `no_fare`.
- **Biaya sebenarnya per bulan** (`monthlyCost`, `allInText` di `logic.js`): sewa + ongkos
  pergi-pulang 22 hari kerja, plus jam di jalan (menit x 2 x 22 / 60). Tampil di baris yang dibuka
  dan di kartu ringkasan, berlabel "estimate". Mode beli: ongkos dan jam saja. Town = area kantor:
  tanpa ongkos dan jam.
- **Halaman town:** `backend/app/where_to_live_pages.py` menulis `web/where-to-live-towns/<id>.html`
  (26) dan `index.html`, disajikan di `/where-to-live/<id>` dan `/where-to-live/towns` lewat rewrite
  di `web/vercel.json`; CSP yang sama juga dipasang untuk `/where-to-live-towns/*`, dan
  `robots.txt` melarang path folder itu (canonical menunjuk ke `/where-to-live/<id>`). Isi: dua
  paragraf dari data town itu (peringkat ke CBD, area kantor terdekat, jam per bulan, sewa
  terendah, perbandingan dengan town terdekat, median vs median 26 town), tabel 6 area kantor
  (waktu, transfer, ongkos, jam dan ongkos per bulan), tabel harga per tipe flat dengan kuartalnya,
  3 town terdekat, dan tautan ke tool (`?compare=<id>`: town itu langsung terpilih untuk dibandingkan). Semua nilai lewat
  `html.escape`; tidak ada script selain `cta.js`. Jaccard 5-kata antar halaman maksimal sekitar 0,31
  (tes: < 0,5).
- **SEO:** `web/sitemap.xml` (dibuat generator, `lastmod` dari `generated_at`), `web/robots.txt`
  (tetap), canonical, meta description dan OG per town. Tool dan Home menautkan
  ke `/where-to-live/towns`.
- **Workflow:** patch dari job build `where-to-live.yml` hanya boleh mengubah JSON-nya dan cache
  rute (allowlist `push_data.sh`, yang mendukung `dir/*.ext`; `data.yml` dibatasi ke `*.json`), dan
  setiap `*.json` harus berupa objek atau array JSON yang valid. Halaman town dan `web/sitemap.xml`
  dibuat di job push oleh generator milik `main` sendiri (`push_data.sh --generate`, `python3`
  runner, stdlib, tanpa pip) setelah patch diterapkan; hanya `web/where-to-live-towns/*.html` dan
  sitemap yang di-commit dari hasilnya. Jadi job build tidak bisa menambah script atau halaman yang
  disajikan situs. `web/vercel.json` memasang `X-Content-Type-Options: nosniff` untuk `/data/*`,
  jadi bundle JSON tidak bisa dijalankan sebagai script.
- **Tes:** `backend/tests/test_where_to_live.py` (fare), `test_where_to_live_pages.py` (generator,
  escaping, sitemap, halaman lama dihapus, tidak ada duplikat, file yang di-commit = hasil generator),
  `test_push_data.py` (pola `*.ext`, halaman di patch ditolak, JSON tidak valid ditolak, halaman
  dibuat saat push, `nosniff` untuk `/data/`), `web/tests/logic.test.mjs` (biaya, `?town=`, compare).
- **Gambar OG per town** (8 Nov): PNG statis 1200×630 di `web/og/where-to-live/<id>.png`, tanpa
  angka: nama town, "Commute & HDB prices", papan LED dan wordmark. Dibuat dengan script dev
  `scripts/build_og_images.py` (Pillow, font OFL Barlow Condensed dan Plus Jakarta Sans dari
  google/fonts; TTF tidak di-commit, lisensinya ada di `web/fonts/*-OFL.txt`) lalu di-commit. Tidak
  ada build step di Vercel, dan job push serta `push_data.sh` tidak menyentuh gambar. Halaman town
  memakai `og:image` (+ ukuran, `twitter:card` `summary_large_image`); town yang belum punya gambar
  memakai `/brand/og.jpg`. **Town baru di data:** jalankan script itu dan commit PNG-nya; tes
  `test_every_town_has_a_share_image` gagal sampai itu dilakukan.
- Town tanpa sewa maupun harga jual mendapat satu kalimat "no median rent or resale price".

## Compare (8 Nov)
- Tiap baris papan punya tombol "+ Compare" (maksimal 3 town; tombol lain nonaktif kalau penuh). Di
  HP tombolnya di baris kecil di bawah nama town, supaya nama tidak terpotong; di layar lebar di
  sampingnya. Bar yang menempel di bawah menampilkan town terpilih (ketuk untuk menghapus) dan
  tombol "Compare"; dengan satu town tertulis "Add a town to compare".
- Tabel perbandingan di atas papan: kolom per town, baris waktu tempuh ke area kantor terpilih,
  transfer, tarif per perjalanan, harga tipe flat terpilih dengan kuartalnya, all-in per bulan
  (sewa + tarif; mode beli: tarif per bulan) dan jam di jalan per bulan. Nilai terendah di tiap
  baris diberi "Best" (seri: semua), hanya kalau minimal dua town punya nilai. Town = area kantor
  (`same_area`) bertuliskan "In this area" di baris waktu, transfer, tarif, all-in/tarif per bulan
  dan jam, dan tidak ikut penentuan "Best" di baris itu (sama seperti di daftar dan halaman town);
  harganya tetap dibandingkan. Di HP tabelnya digeser ke samping, kolom label tetap.
  Tabel ikut pilihan area kantor, mode dan tipe flat.
- URL: `?compare=punggol,bedok,sengkang` (id dari JSON saja, tiap town sekali, maksimal 3, sisanya
  dibuang), jadi bisa di-Share; dengan dua town atau lebih tabelnya langsung terbuka. Halaman town
  menautkan `?compare=<id>`; `?town=` lama tetap membuka baris town itu.
- Logika di `logic.js` (`compareIds`, `toggleCompare`, `compareTable`, `compareBarText`), tes di
  `web/tests/logic.test.mjs`. Semua teks lewat `textContent`; CSP tidak berubah.

## Fase 4: launch
- Live bersamaan dengan production DailyLah. Post LinkedIn: app + alat web.

## Risiko / catatan
- Tabel sewa HDB per town sudah banyak (smartcalculator.sg, propertynet.sg, themoneybees.co). Pembeda kita adalah gabungan waktu tempuh dan harga dalam satu peta, jadi itu yang harus ditonjolkan di UI dan SEO.
- API key data.gov.sg DailyLah hanya berlaku sampai Des 2026, perlu key baru untuk 2027 (job ini ikut terdampak).
- Ide v2: data per blok dari "Renting Out of Flats from Jan 2021" (`d_c9f57187485a850908655db0e8cfe651`) untuk tingkat detail yang belum ada di situs lain; input kode pos bebas.
- Simpan rencana ini ke repo sebagai `docs/WHERE_TO_LIVE.md` di PR Fase 1 supaya sesi berikutnya bisa membacanya.
