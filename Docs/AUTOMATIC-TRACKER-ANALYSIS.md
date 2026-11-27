# Tracker data on Home

Pair a supported tracker once. Stored-history sync defaults to enabled after the supported handshake. New live readings and supported stored readings feed dashboard estimates automatically. Apple Health remains an additional data source.

On reopening, recent raw history already archived on the phone is decoded again, including records saved by earlier versions. Receipt acknowledgements require a durable raw save. Unsupported records remain in the raw archive.

Strain integrates adjacent recorded intervals with a maximum 90-second gap and a minimum minute of coverage. It groups observations by local calendar day, deduplicates timestamps and gives provider scores priority. Resting and maximum heart rates use existing settings, defaulting to 55 and 190 BPM. Adjust these assumptions in Advanced device settings.

Sleep uses the existing overnight detector. Without a measured resting baseline, it requires four continuous hours of lower heart rate, including two hours between midnight and 6 a.m. It waits for subsequent readings and a 30-minute delay before displaying estimated sleep. Heart rate alone can misclassify quiet wakefulness and miss interrupted sleep. Reported sleep and manually corrected sleep take priority. Sleep remains editable. No local sleep stage or Recovery score is generated.

Projections are recalculated from saved measurements after launch. Original timestamps and provider scores are preserved in exports. Local projections are displayed separately from provider measurements.

## NOOP inspection

The archived NOOP source on backup/noop-before-whoop-5e7f970 was inspected, including HistoricalStreams.swift, SleepStager.swift, StrainScorer.swift and AnalyticsEngine.swift. NOOP decodes sensor history and performs its own analytics. Its sleep implementation documents approximate staging and a lower-confidence heart-rate-only path. Its calculations do not establish equivalence to WHOOP proprietary scores.

This revision uses the existing decoder, overnight detector and strain helpers. Screen design continues to use the existing components.

## Verification

217 portable tests passed, covering replay deduplication, sparse data, untagged imports, local-day assignment, sleep completion evidence and provider precedence. Physical overnight operation requires device verification. Native build results are recorded in VALIDATION.json.
