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

## Fase 0: langkah untuk Hendrawan
1. Daftar akun OneMap API, lalu tambahkan secret `ONEMAP_EMAIL` dan `ONEMAP_PASSWORD` di repo.
2. Pastikan di mana kode situs dailylah.sg berada (folder di repo dailylah atau repo/proyek Vercel lain). Cek dulu sebelum merencanakan Fase 2.

## Fase 1: pipeline data (1 PR)
- `scripts/where_to_live/build.py` (Python, di bawah ruff S + pip-audit yang sudah ada): ambil dua dataset HDB, ambil kuartal terbaru yang tersedia per town/flat type, hitung matriks OneMap, lalu keluarkan `where-to-live.json` (berisi `generated_at`, kuartal sumber, per town: rent/resale per flat type, menit + jumlah transfer per area kantor).
- Retry + backoff untuk OneMap, cache hasil rute (rute jarang berubah; hitung ulang bulanan, harga dicek mingguan).
- Workflow terjadwal mingguan (pin SHA, permissions minimal, lolos zizmor) yang membuka PR atau commit hanya kalau JSON berubah. Repo public, jadi menit runner standar aman, tapi tetap ukur durasinya.
- Unit test untuk parser (`na`, kuartal hilang, town tanpa data).

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
