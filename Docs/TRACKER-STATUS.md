# Tracker button and real heart-rate chart

The top-right Home button now uses a narrow, screenless strap outline with a connection dot, following the supplied reference shape. The same vector is shared by the live dashboard, reference Home, and tracker discovery card; no Apple Watch glyph remains in App sources. The status dot is gray when disconnected, green when linked, and yellow when the tracker reports off-body. It is not a battery indicator.

Tapping the header icon consistently opens Device Settings, including during a recorded workout. Previously it redirected to the workout screen while recording. The button keeps a 44-point touch area and a localized accessible label.

Device Settings now includes a heart-rate graph above pairing/sync controls. It combines saved samples tagged as tracker-recorded with incoming Bluetooth readings, displays the most recent actual sample in each minute over the last 24 hours, and does not draw across gaps longer than 150 seconds. Screenshot/example measurements and untagged imported averages are excluded. One received sample appears as a point. No received readings produces an empty state. A stale or disconnected signal does not display a live BPM value. Times follow the phone's display time zone.

The chart refreshes on live readings, saved-data changes and periodically as samples age out. Deleting or replacing stored data clears the live preview state. The existing tracker transport, recorder, history synchronization, and import/export features remain in use.

## Validation

225 portable core tests pass. New tests cover valid tracker-only data, example exclusion, freshness bounds, duplicate-minute selection, gap segmentation and empty states. Swift source parsing and whitespace checks pass. Updated simulator interaction tests assert the chart panel opens from Home and does not fabricate data without a paired tracker. The Apple device build passed for `dbb0a6a1a9dfa1efbeb88de35f3489aeb23eb28c`; its published IPA checksum and arm64 device package were independently verified. Updated simulator interactions have not yet been verified. Build details are recorded in VALIDATION.json. Physical tracker connectivity, overnight recording, and pixel-identical visual parity have not been verified by this change.
