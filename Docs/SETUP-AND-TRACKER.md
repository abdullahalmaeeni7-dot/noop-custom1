# First launch, tracker status and data

First launch has one **Get Started** button. The sequence is Profile → Tracker → Sync your data → Home. Pairing does not exclude importing or exporting. The data step retains the Bluetooth connection and offers direct tracker-history sync, WHOOP ZIP/CSV/JSON import, the existing account bridge, Apple Health and measurement export. Incomplete setup resumes at the last step; completing or reopening the guide does not erase saved measurements.

Device Settings opens on **Status**. Setup and settings share the same pairing and sync components. Nearby sensors show their names; signal levels and implementation details do not occupy the main screen. **Advanced** retains received-reading diagnostics, optional local Strain settings, transport limitations, permissions and disconnect. A stalled connection exposes its actual error through **Having trouble?**.

**Receiving data** requires a connected sensor and a valid heart-rate sample received within the previous ten seconds. The check runs every second, so a stopped stream cannot stay green simply because no further Bluetooth callback occurred. The screen also shows actual readings saved today and archived history. Neither a Bluetooth link nor a command acknowledgement proves that a band is producing usable measurements.

**Sync Tracker** uses the existing read-transfer implementation. Complete raw batches must be saved durably before the app acknowledges their receipt to the band. Raw ZIP export is available after at least one complete batch is stored; measurement/profile export remains available independently. Raw archives and restorable measurement JSON are distinct formats.

Official Recovery, Sleep and Strain require WHOOP account/export records. Raw heart rate and beat intervals do not contain those finished scores. Optional local Strain remains explicitly labeled and disabled by default. No demo measurements, invented battery percentage, imitation vibration, or simulated successful connection are introduced.

Home and detail score rings share `PulseRingTrack`: rounded strokes, a twelve-o'clock start, clockwise progress, 0.7-second ease-out and Reduce Motion support. The visible stroke stays inside the requested diameter. Missing scores have no colored arc. Comparison ticks appear only when real comparison data is supplied. Home's 81-point diameter and 5.8-point stroke are retained from the documented screenshot proportions. Official animation timing and pixel equality cannot be measured from static conversation images.

The native system launch screen now uses the same centered wordmark and background as saved-data loading. Loading waits only for actual storage work; no artificial delay is added.

For wrist-removal status, optional stored-reading sync, sleep sources and the threshold for activity detection, see [Using the tracker overnight](OVERNIGHT-TRACKING.md).

## Verification

`TrackerConnectionEvidenceTests` covers freshness expiry, future timestamps, invalid values and link-only states. The existing suite covers captured protocol frames, handshake gating, history batches, storage-before-acknowledgement, ZIP/JSON import and export, recording and provider-score preservation. `UITests/SetupFlowTests.swift` exercises the real simulator UI through first launch, app restart during setup, searching with no physical hardware, import/export access, Home and Device Settings. It also captures Arabic first launch. Simulator screenshots and test outcomes are published by the native-layout workflow.

A physical WHOOP band is not available in this environment. Bluetooth radio behavior, individual firmware compatibility, background collection over a full day and end-to-end transfer from that band remain unverified. Confirm them on the phone by observing fresh BPM, a rising saved-reading count, and a completed history sync and export. The app must report failures, rather than manufacture Recovery or Sleep scores to appear functional.
