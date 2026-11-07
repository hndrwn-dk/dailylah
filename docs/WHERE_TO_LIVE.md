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
- Fase 1: branch `feat/where-to-live-data` (lihat "Fase 1: yang dibangun").

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
  atau kalau titiknya pindah; rute yang gagal memakai nilai lama. Town = area kantor (Jurong East,
  Woodlands) dicatat 0 menit.
- Keluaran `web/data/where-to-live.json` (compact): `generated_at`, `rent_quarter`,
  `resale_quarter`, `commute_depart`, `areas[]`, `towns[]` (`id`, `name`, `station`, `lat`, `lng`,
  `rent`, `resale`, `commute: {area id: {"min", "transfers"} | null}`), `attribution`. Tidak masuk
  `manifest.json` app (`NOT_IN_MANIFEST` di `build_static.py`).
- `generated_at` hanya diperbarui kalau datanya berubah, jadi minggu tanpa perubahan tidak membuat
  commit. Cache rute juga hanya ditulis kalau berubah.
- Run dianggap rusak dan tidak menulis apa pun kalau kurang dari 20 town punya harga atau kurang
  dari 75% waktu tempuh diketahui.
- Workflow `.github/workflows/where-to-live.yml`: Senin 03:41 SGT + `workflow_dispatch`, job `build`
  hanya di `main`, commit langsung ke `main` seperti `data.yml` (pull --rebase lalu push, 3 kali).
  Saat ruleset `main` aktif, workflow ini butuh bypass yang sama dengan `data.yml` (HANDOFF,
  "Rulesets").
- Selama PR terbuka ada trigger sementara `push` ke `feat/where-to-live-data` dengan job `dry-run`
  (`--dry-run`: cetak laporan, contoh baris dataset, contoh jawaban OneMap dan potongan JSON; tidak
  menulis atau push). Dihapus sebelum merge.
- Lokal: `cd backend && python -m app.where_to_live ../web/data --dry-run` (butuh `.env` dengan
  akun OneMap).

## Fase 2: halaman web (1 PR)
- Rute `/where-to-live` di dailylah.sg, mobile-first, dark mode, aksesibel (kontras, label, keyboard).
- Input: area kantor, sewa/beli, tipe flat, budget, maks waktu tempuh. Hasil: daftar urut + peta (MapLibre atau Leaflet dengan tile OneMap, marker/bubble di pusat town; poligon ditunda karena batas town HDB ≠ planning area).
- Kartu town: "38 min to CBD, 1 transfer, 4-room median rent $X (Q3 2026)".
- State di URL query supaya hasil bisa dibagikan. CTA "Get DailyLah" ke Play Store.
- Disclaimer: angka indikatif dari data HDB yang dideklarasikan sendiri; tidak berafiliasi dengan HDB/SLA.

## Fase 3: SEO + bagikan (1 PR)
- Halaman statis per town (sekitar 26), misalnya "Living in Punggol: commute and HDB prices", dibuat dari JSON yang sama saat build. Sitemap, meta, gambar OG.

## Fase 4: launch
- Live bersamaan dengan production DailyLah. Post LinkedIn: app + alat web.

## Risiko / catatan
- Tabel sewa HDB per town sudah banyak (smartcalculator.sg, propertynet.sg, themoneybees.co). Pembeda kita adalah gabungan waktu tempuh dan harga dalam satu peta, jadi itu yang harus ditonjolkan di UI dan SEO.
- API key data.gov.sg DailyLah hanya berlaku sampai Des 2026, perlu key baru untuk 2027 (job ini ikut terdampak).
- Ide v2: data per blok dari "Renting Out of Flats from Jan 2021" (`d_c9f57187485a850908655db0e8cfe651`) untuk tingkat detail yang belum ada di situs lain; input kode pos bebas.
- Simpan rencana ini ke repo sebagai `docs/WHERE_TO_LIVE.md` di PR Fase 1 supaya sesi berikutnya bisa membacanya.
