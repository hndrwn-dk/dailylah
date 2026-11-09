# Rencana: libur nasional mematikan perjalanan kantor/sekolah (9 Nov 2026)

Bug: Senin 9 Nov 2026 (Deepavali, observed) app tetap mengirim "Time to go" untuk perjalanan ke kantor. Libur nasional MOM harus mematikan semua perjalanan kantor dan sekolah, dan diganti satu notif libur yang berguna.

## Keputusan
- Libur nasional (MOM): kantor dan sekolah libur. Libur sekolah (MOE): hanya sekolah libur, kantor jalan (perilaku sekarang dipertahankan).
- Pengganti leave-by di libur nasional: satu notif pagi (opsi B) berisi nama libur, cuaca 2 jam dekat rumah, dan maksimal 2 event terdekat dari rumah yang berlangsung hari itu.
- Libur sekolah tidak dapat notif libur (bisa 6 minggu, terlalu sering); cukup banner di Today seperti sekarang.
- Tempat custom (jemput anak, dll.), gangguan MRT, parkir, dengue/heat di rumah tidak berubah.
- Teks UI bahasa Inggris, netral (sama dengan app). Tanpa sumber data baru.

## Sumber data (sudah ada, tidak ada yang baru)
- Libur nasional: bundle `holidays` (`web/data/holidays.json`), dibangun `backend/app/bundles.py` `build_holidays` dari data.gov.sg `d_8ef23381f9417e4d4254ee8b4dcdb176` (MOM, consolidated). Sudah memuat hari pengganti, mis. `{"d":"2026-11-09","n":"Deepavali (Observed)"}`. Model: `Holiday` (`logic.dart` ~2272).
- Libur sekolah: bundle `school_holidays`, `SchoolHoliday`, `schoolHolidayOn`, `isSchoolDay`, `schoolHolidaysProvider`.
- Event: bundle `events` (Eventfinda), `PublicEvent`, `eventsProvider`, `eventsNear()` (`logic.dart` ~2460).
- Cuaca: `forecastNear()` yang sudah dipakai blok hujan di `background.dart`.

## Penyebab
`commutePlace(fav, now)` (`logic.dart` ~243) hanya melihat hari dalam minggu (`Place.days`). Pengecekan libur sekolah ditambal terpisah di 4 tempat (background.dart 170-171, today.dart 34-36, `widgetTrip` 2569, `isSchoolDay`), sedangkan libur nasional tidak dicek di mana pun kecuali weekly digest.

## Desain

### 1. Satu aturan pusat: `DaysOff` (logic.dart, dekat `SchoolHoliday`)
```dart
/// Public (MOM) and school (MOE) holidays, to tell which trips are off today.
class DaysOff {
  const DaysOff({this.holidays = const [], this.school = const []});
  final List<Holiday> holidays;
  final List<SchoolHoliday> school;

  /// The public holiday on [now]'s date, or null.
  Holiday? publicOn(DateTime now);

  /// True when [p] has no trip on [now]: a public holiday (work and school), or a school
  /// holiday (school only).
  bool isOff(Place p, DateTime now);
}
```
- `commutePlace(fav, now, [DaysOff off = const DaysOff()])`: lewati tempat yang `off.isOff(p, now)`. Default kosong supaya pemanggil/tes lama tetap sama.
- Teruskan parameter opsional yang sama ke `isCommuteDay`, `originFor`, `destinationFor`, `widgetTrip`/`widgetData` (ganti parameter `schoolHolidays` dengan `DaysOff`), dan `isSchoolDay` (sekolah juga libur di libur nasional).
- `commuteTimes` tetap jalan: fallback ke tempat kantor/sekolah supaya `cardFor` pagi/sore tidak berubah.
- Hapus tambalan libur sekolah yang jadi berlebih (background.dart 170-171, today.dart 34-36, widgetTrip 2569) dan pakai `commutePlace(..., off)`.

### 2. Notif libur (background.dart, blok leave-by)
- Fungsi murni di logic.dart:
  ```dart
  /// The holiday notification: (title, body), or null when [now] is not a public holiday
  /// that replaces a trip.
  (String, String)? holidayNote(S s, Favorites fav, DateTime now, DaysOff off,
      {AreaForecast? homeWeather, List<PublicEvent> events = const []});
  ```
  - Null kalau bukan libur nasional, atau kalau tanpa libur pun tidak ada perjalanan hari ini (`commutePlace(fav, now) == null`, mis. Minggu atau hari kerja tidak terdaftar).
  - Judul: `s.holidayTitle(name)` → "Happy Deepavali (Observed) · no commute today". Pakai nama dari bundle apa adanya.
  - Isi: cuaca dekat rumah (`homeWeather.forecast`, mis. "Ang Mo Kio: Partly Cloudy") lalu maksimal 2 event dari `eventsNear(events, home.lat, home.lng, now, days: 1, limit: 2)`, format "Name · 2.1 km". Tanpa event: cuaca saja. Tanpa cuaca dan tanpa event: "Enjoy the day off."
- Di `background.dart`: muat `DaysOff` sekali di awal pass (`holidays` + `school_holidays`) dan pakai di semua blok yang sekarang memuat `school_holidays` sendiri-sendiri.
- Blok leave-by: kalau `holidayNote(...)` tidak null dan sedang `inLeaveWindow(now, goAt)` (goAt dari `commuteTimes`), `fav.leaveAlerts`, tidak `quiet`, dan belum `log.alreadySent('holiday:$day')` → `notify(20, title, body)`, `markSent('holiday:$day')`, return (tanpa leave-by). ID 20 belum dipakai (sekarang 1-13+i).
- Blok hujan: karena `destinationFor` sekarang null di hari libur, payung untuk perjalanan otomatis berhenti; pastikan tetap tidak error saat `dest == null`.

### 3. Today (ui/today.dart) dan providers
- `providers.dart`: `holidaysProvider` (FutureProvider dari bundle `holidays`, pola sama dengan `schoolHolidaysProvider`) dan `daysOffProvider` yang menggabungkan keduanya. `widgetDataProvider` pakai `daysOffProvider`.
- Today: `commute = isCommuteDay(fav, now, off)`. Banner info:
  - libur nasional pada hari yang sebenarnya hari perjalanan → `s.publicHolidayToday(name)` ("Deepavali (Observed): public holiday, no work or school trip today."), ikon `Icons.celebration_outlined`, `AlertTone.info`.
  - libur sekolah (tanpa libur nasional) → banner `schoolHolidayToday` yang sudah ada.
- Kartu event di Today sudah ada; tidak diubah.

### 4. Teks (l10n.dart)
`holidayTitle(String name)`, `publicHolidayToday(String name)`, `holidayEnjoy` ("Enjoy the day off."), `eventNearby(String name, String km)`. Bahasa Inggris, tanpa emoji di teks notif.

## Uji (app/test/logic_test.dart)
1. `DaysOff.isOff`: 9 Nov 2026 kantor dan sekolah off; 23 Nov 2026 (libur sekolah) sekolah off, kantor tidak; 10 Nov 2026 keduanya on.
2. `commutePlace` dengan `DaysOff`: 9 Nov → null; 23 Nov dengan kantor + sekolah → kantor; tanpa `DaysOff` → perilaku lama (tes yang ada tetap lolos).
3. `holidayNote`: 9 Nov, kantor Sen-Jum → judul memuat "Deepavali (Observed)", isi memuat cuaca dan tepat 2 event terdekat (3 event di input, satu > 10 km); Minggu 8 Nov → null; 23 Nov (hanya libur sekolah) → null; tanpa event → cuaca saja.
4. `widgetTrip` 9 Nov → ''; `destinationFor` 9 Nov → null; `isSchoolDay` 9 Nov → false.
5. Widget test Today (harness yang ada): 9 Nov tidak menampilkan TripSection dan menampilkan banner libur nasional.

## Rencana kerja (satu PR, branch `fix/public-holiday-commute`)
1. `DaysOff` + `publicOn`/`isOff` + tes 1. (~15 mnt)
2. `commutePlace` & turunannya terima `DaysOff`; hapus tambalan libur sekolah; tes 2 & 4 + tes lama hijau. (~30 mnt)
3. `holidayNote` + teks l10n + tes 3. (~20 mnt)
4. background.dart: muat `DaysOff` sekali, notif ID 20, leave-by dilewati. (~20 mnt)
5. providers + Today banner + widget test 5. (~20 mnt)
6. Docs: `docs/QA.md` (cek manual: ubah tanggal perangkat ke 25 Des → notif libur, tanpa "Time to go"), `app/CLAUDE.md` feature map, `python3 scripts/repo_map.py`. Draf commit + PR ke Hendrawan sebelum commit/PR.

## Di luar cakupan
Notif libur untuk libur sekolah, event di luar 10 km, jadwal bus hari Minggu/libur (LTA tidak memberi data yang bisa diandalkan), Children's Day per jenjang sekolah (sudah diurus bundle `school_holidays`).
