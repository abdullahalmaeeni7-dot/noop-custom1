# Live editing, colored history and preserved health details

This revision uses the supplied APK's actual Live/calendar XML, resource strings, navigation declarations and motion assets. The [APK coverage ledger](../design/apk/COVERAGE.md) inventories all 24 packaged graphs and 209 declared destinations, with the remaining gaps. It is not a claim that all WHOOP features or services have been recreated.

## Live

Open Home → + → Live, or More → Live camera & photo overlays. Choose Recovery, Strain, Sleep, Overview or Live. Open the overlay/settings control and use **Size** or **Zoom and drag to adjust**. Each stat has an independent position, scale and visibility for the selected mode. Save Changes persists the layout. Reset Layout resets only that mode. VoiceOver adjustable actions also resize the selected stat.

Live mode supports HR, Strain, calories, timer and an actual HR graph. The graph uses only received readings, separates gaps and never substitutes a decorative signal. Calories remain recorded day calories, not an invented workout burn. Imported activity Strain can be selected separately from Day Strain. Local estimates remain opt-in and labeled.

Choose a saved photo to compose recorded stats. Adjust Photo supports the APK's 0.6–8× zoom and unrestricted translation; Reset Photo restores framing. Full is 9:16 and Condensed is 4:5, matching the APK letterbox ratio of height = 1.25 × width. The same normalized stat layout is applied to preview, photo capture, selected photos, transparent PNGs and recorded video. Video output is cropped to the selected aspect ratio before compositing. Photo dates are local to Live and do not modify Home's selected date or any measurement timestamp.

Camera and Photos permissions are still required on a physical phone. Simulator editing does not demonstrate an actual camera recording or hardware sensor transfer.

## Dates and calendar

Opening the app, finishing setup, importing files/account/Health measurements and restoring a backup returns the dashboard to **today**. A file with records from November 9 still contains November 9 records; no health measurement or sample timestamp is relabeled as today. Export metadata retains the current export time and the actual recorded range. Background tracker-history merges preserve deliberate date browsing.

Today follows the calendar date on the iPhone, including while travelling. At local midnight or on returning to the app, Home advances when you were viewing Today. A deliberately selected older date stays selected.

Tap the date strip on Home or score details to open the Recovery Calendar. It shows real reported Recovery: red 0–33, yellow 34–66, green 67–100. Missing scores stay uncolored. Month/year navigation, percentage labels, selection outlines, future-date disabling, Today and accessible touch targets are shared with Live's independent recorded-date picker. The archive stores day labels as UTC keys. Selecting Today maps the current local calendar date to its matching key. Individual readings retain their original timestamps.

## Sleep, Health and trends

Supported account payloads and CSV headers now retain Awake, Light, Deep (SWS), REM, time in bed, sleep consistency, sleep efficiency, sleep debt, SpO₂ and absolute skin temperature. Sleep displays the reported stage breakdown and additional metrics; Health Monitor displays the additional health measurements. Missing values remain absent. Skin temperature is absolute Celsius; a proprietary personal-baseline delta is not guessed.

JSON, full backups and the daily CSV preserve these fields. Daily CSV keeps its original first 13 columns and appends ten health/sleep columns. Old JSON/backups remain readable. Stage durations, percentages and health ranges are validated before saving.

Sleep, Recovery and Strain details offer 7/30/90-day chart windows, Recovery colors, chart selection and averages over the actual recorded days. Missing dates are not counted as zero scores.

## Startup motion

The provided APK's original loading animation is 132 frames at 60 FPS (2.2 seconds). It was rendered from its Lottie JSON to a local movie; the original intro video was copied byte-for-byte. These run locally in AVFoundation. The loading animation runs once per app launch while storage prepares, with a bounded failure fallback. Reduce Motion skips playback. The welcome intro pauses when inactive and stops when leaving the page. [Provenance and hashes](../App/Resources/apk-motion-provenance.json) distinguish original assets from the converted loading movie.

## Verification boundaries

Portable tests cover date preservation/rollover, calendar alignment and color boundaries, layout bounds and persistence, preview/export scale invariance, historical HR provenance, local-estimate labeling, richer provider fields and backup/import validation. Native interaction tests separately exercise the new calendar, rich-data screens and Live controls. Physical camera recording, band compatibility and WHOOP private services are not established by simulator results. See [validation](../VALIDATION.json) for the actual outcomes.
