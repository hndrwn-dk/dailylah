# Rencana: cari nama tempat di Plan a trip dengan Geoapify (9 Nov 2026)

Masalah: OneMap (`/v1/search`) bagus untuk kode pos, blok HDB, gedung, sekolah dan stasiun, tapi tidak menemukan nama restoran/toko/mal kecil (contoh: "Putra Minang"). Orang tidak hafal kode pos tempat seperti itu. Plan a trip adalah tempat risikonya paling tinggi (kolom tujuan dipakai berulang).

## Keputusan
- Hanya Plan a trip (kolom From dan To, `_search` di `app/lib/ui/trip.dart`). Onboarding Home/Work/School tetap OneMap saja.
- Routing (opsi B): ketikan yang diawali angka ("560201", "201 Ang Mo Kio") atau "Blk"/"Block" + angka → OneMap seperti sekarang. Selain itu → Geoapify. Geoapify kosong → OneMap sekali sebagai jaring pengaman. Keduanya kosong → pesan kosong yang sudah direncanakan (Share from Google Maps, Pick on map).
- Geoapify berlangganan berbayar (Hendrawan), jadi batas "limited commercial use" free plan tidak berlaku. Pilihan ini menggantikan rencana v1.1 Google Places di `docs/tester-feedback-plan.md`.
- Key hanya di server (env `GEOAPIFY_API_KEY`), tidak pernah di APK. Lokasi pengguna tidak dikirim sebagai bias; cukup `filter=countrycode:sg`.
- Debounce 400 ms + minimal 3 karakter sudah ada di `AddressPickerPage`; tidak ditambah.

## Backend: `GET /v1/places?q=`
- Modul baru `backend/app/geoapify.py` (pola sama dengan `onemap.py`): klien httpx async, `autocomplete(text)` → `GET https://api.geoapify.com/v1/geocode/autocomplete` dengan `text`, `filter=countrycode:sg`, `limit=6`, `lang=en`, `format=json`, `apiKey`. Timeout 10 detik.
- `config.py`: `geoapify_api_key: str | None = None`, `places_ttl: int = 86400`.
- `main.py`: endpoint `/v1/places` meniru `/v1/search`: normalisasi spasi, panjang 2–80 (422), cache memory saja (`c.set_memory_only`, kunci `geoapify:places:{QUERY}`), query tidak di-log.
  - Tanpa key → 503 "place search not configured". Error/timeout/429 Geoapify → 502 "upstream Geoapify error".
  - Respons diringkas di server (jangan teruskan body mentah): `{"fetched_at": ..., "data": [{"name", "address", "postal", "lat", "lng", "type"}]}` dari `results[]` (`name` atau `address_line1`, `address_line2`, `postcode`, `lat`, `lon`, `result_type`). Hasil tanpa lat/lon dibuang. Key tidak boleh muncul di respons, log atau pesan error (URL httpx bisa memuat key: tangkap dan buang).
- `contracts/v1/places.json` (contoh respons) + tes kontrak, mengikuti `contracts/v1/search.json`.
- `backend/CLAUDE.md`: Geoapify di bagian upstream keys; `.env.example`: `GEOAPIFY_API_KEY=`.
- Tes (`backend/tests`): query valid (httpx dimock), terlalu pendek → 422, cache hit tanpa panggilan kedua, upstream error → 502, tanpa key → 503, key tidak ada di respons/teks error, hasil tanpa koordinat dibuang.

## App
- `api.dart`: `PlacesApi.search(q)` → `$apiUrl/v1/places`. Tidak ada fallback langsung ke Geoapify (key hanya di server); gagal → lempar, provider pindah ke OneMap.
- `logic.dart`:
  - `bool looksLikeAddress(String q)`: diawali angka, atau `^(blk|block)\s*\d` (tanpa beda huruf besar/kecil).
  - `List<AddressHit> parsePlaces(Map<String, dynamic> body)`: `label` = `name` (+ ", " + `address` kalau beda), `building` = `name`, `road` = `address`, `postal`, `lat`, `lng`, `block` = ''.
- `providers.dart`: `placeSearchProvider` (FutureProvider.autoDispose.family): `looksLikeAddress` → `addressSearchProvider`; selain itu `PlacesApi` → kalau kosong atau error → OneMap.
- `ui/address_picker.dart`: parameter `places` (default false). Kalau true pakai `placeSearchProvider` dan tampilkan baris atribusi kecil di bawah hasil yang berasal dari Geoapify: "Powered by Geoapify · © OpenStreetMap contributors" (string di `l10n.dart`).
- `ui/trip.dart` `_search`: `AddressPickerPage(title: s.searchPlace, places: true)`.
- Tes (`app/test`): `looksLikeAddress` ("560201", "201 Ang Mo Kio", "Blk 201", "blk201" → true; "Putra Minang", "Jewel" → false); `parsePlaces` dari contoh kontrak; provider: nama → Places, angka → OneMap, Places kosong → OneMap, Places error → OneMap; widget test: onboarding picker tidak memanggil Places.

## Privacy dan docs
- `docs/legal/privacy.md` bagian 4a: di Plan a trip, teks nama tempat yang diketik dikirim ke server kami lalu ke **Geoapify** (berbasis OpenStreetMap) dengan key kami; tidak di-log, disimpan di memory maksimal sehari, Geoapify tidak tahu siapa yang mencari. Atribusi OpenStreetMap (ODbL) di halaman legal.
- `app/CLAUDE.md` feature map, `python3 scripts/repo_map.py`, `docs/QA.md` (cek manual: Plan a trip → "Putra Minang", "560201", "Jewel Changi").
- `docs/tester-feedback-plan.md` bagian Address search v1.1: Google Places diganti Geoapify (rencana ini).

## Langkah untuk Hendrawan
1. Buat API key khusus DailyLah di dashboard Geoapify; batasi ke IP/domain Render kalau tersedia.
2. Render → service API → Environment: `GEOAPIFY_API_KEY`. Redeploy.
3. Coba 10 nama tempat yang sering dicari setelah deploy; catat yang tidak ketemu di PR.

## Rencana kerja (satu PR, branch `feat/place-search`)
1. Backend `geoapify.py` + config + tes klien. (~20 mnt)
2. Endpoint `/v1/places` + kontrak + tes. (~25 mnt)
3. App `PlacesApi`, `looksLikeAddress`, `parsePlaces` + tes. (~20 mnt)
4. `placeSearchProvider` + picker `places` + atribusi + trip `_search` + tes provider/widget. (~30 mnt)
5. Privacy, `backend/CLAUDE.md`, `.env.example`, feature map, repo map, QA. (~15 mnt)
6. Draf commit + PR ke Hendrawan sebelum commit/PR; setelah PR: review-pr + security gate.

## Di luar cakupan
Onboarding pakai Geoapify, bias lokasi, Place Details/jam buka, toilet (`docs/TOILETS.md`, terpisah).
