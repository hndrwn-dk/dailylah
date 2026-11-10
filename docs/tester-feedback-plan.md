# Tester feedback plan (2 Nov 2026)

Source: closed testing report for DailyLah. No crashes or bugs found; three enhancement points plus generic extras.

## Decisions
- Send feedback stays in About (do not move it).
- Onboarding = coach mark spotlight (option B), so every Tursina Labs app can reuse the same tour.
- Skipped: scheduled dark-mode hours, custom themes, community section, separate performance work.
- Mockups: Design canvas "DailyLah Onboarding Tips" (A1/A2 tip card, B1/B2 spotlight with close X).

## 0. Non-code
- Play Console: confirm the 8 annotated screenshots in docs/store/screenshots are on the main store listing (Today, Wake me, Plan B first).
- Optional: add one dark-mode screenshot after Batch A.

## Batch A (one PR, one APK)
1. Appearance: System / Light / Dark in More (shared_preferences -> MaterialApp.themeMode). Visual pass of every tab in dark mode.
2. What's new card on Today, shown once after an update, text from whatsnew-en-US.
3. Accessibility: review TextScaler.noScaling (today.dart:1301, place_sheet.dart:398); Semantics/tooltips on icon-only buttons; widget test at text scale 2.0.

## Batch B (separate PR): spotlight tour
- Steps: 1 I'm leaving (Today), 2 Wake me (Today), 3 Nearby tab, 4 Home tab. Plan B excluded (only shows during disruptions).
- Own widget lib/ui/tour.dart, no package, copyable to other apps.
- GlobalKey + RenderBox for target rect; CustomPainter dim with a hole + amber ring; callout above/below by available space.
- Robustness: Scrollable.ensureVisible before highlighting; skip a step whose target is missing; recompute on resize/text scale; TalkBack announces callout and focuses it.
- Callout has a close X (44px, label "Close tour"), Skip tour, Back/Next.
- Dismiss rule: X, Skip, Android back or finishing step 4 saves tourDone=true immediately. Never shows again after restart; only via "Show tour again" in More.
- If the app is killed mid-tour without a dismiss: show once more from step 1 next launch; if interrupted again, mark done.
- Starts once after first-run setup and Today data has loaded.
- Tests: 4-step flow, skipped step, dark mode, text scale 2.0.

## Address search (added 7 Nov 2026)
Problem: OneMap search finds postal codes, HDB blocks, buildings, schools and MRT stations well, but not shop/restaurant names. Risk is highest in Plan a trip (destination field, used repeatedly); low in onboarding (home/office/school, entered once, users know the postal code).

### v1.0 (before or at production launch, OneMap only)
1. Onboarding fields: hint "Postal code works best".
2. Empty result message (all search fields): "No match. Try a postal code, block or building name, or share a place from Google Maps." with actions: Share from Google Maps (already decided), Pick on map.
3. Pick on map: drop a pin, reverse geocode via OneMap, use as the place.
4. Measurement: backend counts searches and zero-result searches per screen (onboarding / plan_trip). Counts only, never the query text. Note in docs/legal/privacy.md if needed.

### v1.1 (only if Plan a trip zero-result rate is high after 2-3 weeks)
- **Replaced (9 Nov 2026) by Geoapify place search, docs/PLACE_SEARCH.md.** The Google Places notes below are kept for the record only.
- Google Places as fallback only for the Plan a trip destination field. Onboarding stays OneMap.
- Called only through the backend (key never in the APK), and only when OneMap returns nothing or the user taps "Search more places".
- Autocomplete with session tokens + debounce; minimal field masks.
- Cloud Console: daily quota cap + budget alert. Free caps per SKU since Mar 2025 (Essentials 10k, Pro 5k per month); check current pricing before building.
- Check Google Maps Platform ToS on storing Places data before building: trip destinations used once for routing are fine to keep short-lived; do not save Google coordinates into saved places/offline storage unless ToS allows (store place_id only otherwise). Show Google attribution where results appear.
- Tests: OneMap hit (no Google call), OneMap empty -> Google, quota exceeded -> friendly message + Share/Pick on map.
