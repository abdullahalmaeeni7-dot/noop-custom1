# APK feature and screen coverage

Source: user-supplied WHOOP Android **5.444.1 / 431134**. All **24 packaged XML navigation graphs**, **209 declared destinations** and **92 navigation actions** are inventoried in [feature-inventory.json](feature-inventory.json). These are declarations, not 209 working features or a complete list of server-fed/Compose screens. The original APK SHA-256 is recorded in that inventory.

## Implemented in this revision

- Live: independent per-stat pinch/drag/size, visibility controls, restore/reset, saved layouts, photo positioning/zoom, Full and Condensed framing, day/activity Strain selection, actual HR graph, and consistent geometry across preview, photos, transparent PNG and video. The recorded-date picker is independent of Home.
- Calendar: seven Monday-first columns, 36-point visible day shapes, real Recovery percentages/colors, month/year navigation, unavailable-day state and Today action; shared by Home, metric details and Live.
- Dates: opening the app, importing files/accounts/Health and restoring backups opens today. Historical record/sample dates remain intact. Background device history preserves deliberate browsing. Midnight follows today only when the user was already viewing today.
- Sleep/Health: preserve and display provider stages, consistency, efficiency, debt, SpO₂ and absolute skin temperature. Keep these values through JSON, CSV and full backup. No proprietary baseline or stage score is invented.
- Details: 7/30/90-day windows, calendar date selection, Recovery-colored bars, chart selection and averages from recorded days.
- Startup: the APK’s 132-frame, 60 FPS loading animation is rendered as a local 2.2-second movie, and its 4.053-second intro video is copied byte-for-byte. Reduce Motion skips playback. See [asset provenance](../../App/Resources/apk-motion-provenance.json).

## APK evidence used

- [Live layout](evidence/activity_selfie.xml): CameraView, recordable/playback surfaces, overlay container, zoomable/translatable photo, aspect letterbox, footer pager and controls. The photo zoom XML specifies 0.6–8× and unrestricted translation.
- [Aspect implementation](evidence/aspect-letterbox-bytecode.txt): `onLayout` multiplies width by the configured ratio. The XML supplies **1.25**, corresponding to the condensed **4:5 width/height** crop.
- [Calendar layout](evidence/calendar_layout.xml) and [day layout](evidence/custom_calendar_day.xml): seven columns and a 36×36 dp visible day. The resolved string IDs are Monday through Sunday. iOS touch targets remain at least 44 points.
- [Navigation declarations](navigation-declarations.json) and [decoded-resource hashes](evidence/manifest.json). Android dp/XML geometry is not proof of pixel equality with the user’s iOS screenshots.

## Complete packaged graph ledger

| Graph | Coverage | Existing native implementation / boundary |
| --- | --- | --- |
| `advanced_labs_graph` (18 destinations) | service_gap | No matching native implementation. Lab ordering, clinician review and provider biomarker integration require the vendor service. |
| `change_password_graph` (2 destinations) | service_gap | [App/Views/AccountView.swift](../../App/Views/AccountView.swift). An account bridge does not implement WHOOP password changes. |
| `community_graph` (10 destinations) | service_gap | [App/Views/SecondaryViews.swift](../../App/Views/SecondaryViews.swift). Local activity history exists. WHOOP teams, leaderboards, friends, referrals and family billing are not connected. |
| `core_details_graph` (1 destinations) | partial_native | [App/Views/DetailViews.swift](../../App/Views/DetailViews.swift). Sleep/Recovery/Strain details, stages, reported efficiency/consistency/debt, chart selection and trends; not every proprietary insight is available. |
| `core_details_weightlifting_activity_details_graph` (1 destinations) | partial_native | [App/Views/DetailViews.swift](../../App/Views/DetailViews.swift). Recorded activities are available; vendor muscular-load details are absent. |
| `design_showcase_graph` (4 destinations) | developer_only | No matching native implementation. Packaged design-system demonstration; not treated as a member feature. |
| `download_graph` (1 destinations) | partial_native | [App/DeviceModel.swift](../../App/DeviceModel.swift). Supported history transfer, storage-before-acknowledgement, raw export and HR/R-R projection; physical device compatibility is not verified. |
| `health_graph` (1 destinations) | partial_native | [App/Views/DashboardViews.swift](../../App/Views/DashboardViews.swift). Recorded health measurements and personalized age display; proprietary aging, pace and clinical services are unavailable. |
| `home_graph` (107 destinations) | partial_native | [App/Views/DashboardViews.swift](../../App/Views/DashboardViews.swift). Home, score details, day navigation, recovery calendar, activities and trend windows; original Home content is server-fed. |
| `memberdataexport_nav_graph` (3 destinations) | native_local | [App/Views/MeasurementExportView.swift](../../App/Views/MeasurementExportView.swift). Saved-data JSON/CSV, full backups and raw tracker archives; requesting a vendor account archive is a separate service. |
| `new_journal_nav_graph` (1 destinations) | partial_native | [App/Views/DetailViews.swift](../../App/Views/DetailViews.swift). Local caffeine/alcohol/late-meal journal and notes; the remote behavior catalog and vendor impact model are absent. |
| `onboarding_stories_graph` (1 destinations) | partial_native | [App/WHOOPApp.swift](../../App/WHOOPApp.swift). Single local setup, packaged loading motion and original intro video; vendor login/activation flows are not reproduced. |
| `profile_graph` (1 destinations) | partial_native | [App/Pulse/PulseHomePanels.swift](../../App/Pulse/PulseHomePanels.swift). Local profile, chosen age/streak, recorded highlights and exports; vendor achievement/ranking services are absent. |
| `profile_levels_graph` (1 destinations) | partial_native | [App/Pulse/PulseHomePanels.swift](../../App/Pulse/PulseHomePanels.swift). Existing local presentation does not reproduce WHOOP level entitlements. |
| `proper_fit_nav_graph` (1 destinations) | not_implemented | No matching native implementation. The original fit-education flow has not been rebuilt. |
| `sage_graph` (2 destinations) | service_gap | [App/Views/ReferenceComponents.swift](../../App/Views/ReferenceComponents.swift). Recorded-day review is not WHOOP’s proprietary Coach chat service. |
| `settings_graph_redesign` (39 destinations) | partial_native | [App/Views/SecondaryViews.swift](../../App/Views/SecondaryViews.swift). Local preferences, language, device, data and account-bridge settings; billing and account administration remain provider services. |
| `sleep_coach_graph` (1 destinations) | partial_native | [App/Views/DetailViews.swift](../../App/Views/DetailViews.swift). Reported sleep need/debt and history are displayed; band alarm scheduling and vendor coaching are not implemented. |
| `strength_trainer_graph` (1 destinations) | partial_native | [App/WorkoutRecorder.swift](../../App/WorkoutRecorder.swift). Real HR workout recording and optional labeled local estimates; muscular load, set recognition and native MSK model are not implemented. |
| `stress_monitor_graph` (1 destinations) | service_gap | [App/Views/ReferenceComponents.swift](../../App/Views/ReferenceComponents.swift). Presentation exists; proprietary stress scores/time series are not inferred from HR. |
| `stress_session_graph` (1 destinations) | not_implemented | No matching native implementation. Guided stress sessions and vendor stress scoring are not implemented. |
| `training_activity_settings_graph` (3 destinations) | partial_native | [App/Views/DetailViews.swift](../../App/Views/DetailViews.swift). Local activity names/durations and HR limits; not all sport-specific device settings. |
| `user_journey_graph` (2 destinations) | partial_native | [App/WHOOPApp.swift](../../App/WHOOPApp.swift). Local setup and optional public-account bridge; remote activation/membership routing remains unavailable. |
| `weightlifting_nav_graph` (6 destinations) | partial_native | [App/WorkoutRecorder.swift](../../App/WorkoutRecorder.swift). Same strength boundary; no invented rep/set metrics. |

## Boundaries

The APK contains a client. Its Home feed is decoded as a typed server response containing pillars, headers and menu definitions. Member state, entitlements, backend responses, newer iOS screens and runtime feature flags affect what is rendered. Static resources and class names cannot establish every exact screen, interaction, animation or service. Original iOS reference image bytes are also absent, so pixel equality remains unverified.

WHOOP teams/friends/leaderboards, billing/referrals/family plans, proprietary Coach, Advanced Labs, WHOOP Age/pace algorithms, certified ECG/BP behavior, full strength/muscular-load scoring, band alarms and full device administration are **not completed by this change**. The ledger marks those gaps explicitly. They are not replaced by fake server responses, invented measurements or inert success screens. Physical tracker/camera tests and live account-service compatibility still require the actual device and configured service.

Regenerate the inventory with `python3 Scripts/audit-apk-features.py --apk /path/to/original.apk`. The script uses the included decoded declarations and can verify the supplied APK identity; it does not execute APK code or contact WHOOP services.
