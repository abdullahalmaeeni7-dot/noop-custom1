# Tracker updates

[Download the unsigned iPhone IPA](https://github.com/abdullahalmaeeni7-dot/noop-custom1/raw/refs/heads/device-download/18f1ce5df80ffccdfd93e5993b566d909169b9fe/WHOOP-unsigned.ipa). The build from `18f1ce5` passed the Apple device build and package checks. Its verified SHA-256 is `d7827764bc4cb70c29f9aa38dd8223a09ad8b4c0db811f168c5ce04b20612608`. Sign the IPA with Sideloadly. Apple Health sleep access requires a signing profile that supports HealthKit.

Home shows supported wrist-removal events and sustained activity from live readings. For overnight sleep, enable Apple Health sleep sync, refresh a linked WHOOP account, or review a resting interval recorded by your band. [Overnight setup and activity detection](Docs/OVERNIGHT-TRACKING.md)

Previous interface revision: [Live resizing, colored Recovery history and preserved sleep/health details](Docs/LIVE-CALENDAR-AND-DATA.md). Live supports independently sized/positioned overlays, full/condensed output, photo adjustment and an actual heart-rate graph. Importing older data opens Home on Today and preserves the original measurement dates. The date picker shows reported red/yellow/green Recovery scores. The supplied APK's loading and welcome motion assets are bundled locally; [provenance](App/Resources/apk-motion-provenance.json) distinguishes the original intro from the converted loading movie.

Feature scope: the [APK coverage ledger](design/apk/COVERAGE.md) audits 24 packaged navigation graphs and 209 declared destinations. It records implemented controls, partial areas and missing services. These counts do not mean 209 features are complete. Full official-app parity, physical camera behavior and tracker compatibility remain unverified.

Latest setup revision: [one welcome flow and simpler tracker status](Docs/SETUP-AND-TRACKER.md), with [actual native screenshots and passing interaction checks](design/home/native-review-07/REVIEW.md). Get Started leads through profile, pairing, sync/import and export before Home. Device Settings shares this pairing flow and keeps technical details under Advanced. Only fresh received readings verify a live stream.

Latest tracker revision: [direct stored-data download](Docs/DEVICE-HISTORY-TRANSFER.md). Tracker → Download from tracker requests real stored packets, saves full batches before acknowledging them, and provides a raw ZIP plus decoded HR/R-R CSV. Home and Live show supplied WHOOP scores by default; local Strain estimates are opt-in. The current device build passed; physical-band transfer remains unverified.

Latest tracker change: [automatic recording and local daily Strain](Docs/ReleaseNotes/2026-11-17-automatic-tracking.md). Incoming BLE readings now save without starting a workout. The updated iPhone build passed Apple SDK compilation and device packaging; its direct download is below. Official Recovery still requires supported WHOOP data.

Earlier interface build: [download its unsigned IPA directly](https://github.com/abdullahalmaeeni7-dot/noop-custom1/raw/refs/heads/device-download/f55d7e837ad0c08cbc8efe5ed2f5c8270913720b/WHOOP-unsigned.ipa), built from `f55d7e8` with the iOS device SDK (5,376,997 bytes). Sign it with Sideloadly using the same account/app identifier to retain your data. The Mac tests, Apple SDK build and device package checks passed. The published checksum, new code markers and bundled motion files were independently verified. SHA-256: `23e041f63c9b71057d9878881166802220bb70fa1d2a6875aec8cef3014c6afb`.

Reference-screen status: [screen-by-screen audit and shared visual corrections](design/reviews/2026-11-16-reference-audit.md).

Current runtime corrections: [Live, cycle imports, startup and tracker fixes](Docs/ReleaseNotes/2026-11-16-runtime-fixes.md).

Arabic is available from the globe on first launch or **More → Language → العربية**. The app remembers the choice and mirrors the interface. Nutrition AI can use a separate Gemini service without WHOOP OAuth: follow [the deployment and pairing guide](Server/NUTRITION-SETUP.md). No provider key is bundled in the app. Shared point measurements now drive Home rings, cards, the day selector and navigation; reference geometry is documented in [design tokens](design/tokens/home.json).

# WHOOP iPhone app

First launch opens Welcome → Get Started → Profile → Find your tracker → Sync/import/export → Home. Later launches use your saved profile and measurements. Import the official WHOOP web-export ZIP directly; no account bridge is needed for ZIP imports.

Home now follows the supplied reference hierarchy, with three animated score rings, paired monitor cards, My Day, sleep, activities, journal, plan and dashboard. Navigation includes Home, Health, Community and More; Nutrition is available under More. The floating day actions, compact rings on scroll and profile/export controls use the existing functional flows. The membership-expiry banner stays removed. Standard cards use opaque surfaces; the floating navigation retains native iOS 26 Liquid Glass, system material on older iOS, and accessibility fallbacks. Exact official-app appearance and feature parity are not established.

Nutrition includes a real Take Photo capture flow, photo-library selection, preview and editable AI estimates. Capture works independently of the server. **AI photo/text analysis requires a configured HTTPS account bridge with server-only `AI_API_KEY`, `AI_API_URL` and a vision-capable `AI_MODEL`.** No credentials or production service are bundled. Connection settings and manual-entry recovery are available directly from the food form.

See [layout and camera details](Docs/LAYOUT-AND-MEAL-CAMERA.md), [ZIP and glass implementation](Docs/ZIP-AND-GLASS.md), [profile and export behavior](Docs/PROFILE-PERSONALIZATION.md), and [current verification](VALIDATION.json). The [overnight tracking iPhone build passed](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/45670044997). Use the direct IPA link at the top of this file, then sign/install with Sideloadly. This binary includes direct historical tracker reads, synchronized raw storage, CSV/ZIP export, opt-in local Strain, and the existing Home/camera/import fixes. See the [native interface captures from the f55d7e8 build](design/home/native-review-08/REVIEW.md). Physical camera capture and a production AI provider remain untested.

---

# WHOOP — iPhone reconstruction

A standalone iOS 17+ SwiftUI project named **WHOOP**, with the original supplied wordmark, icon and typefaces. It combines local functionality with client behavior recovered using REA. Exact official-app appearance and feature parity are not established.

## Run on your Mac

**Windows:** GitHub Actions builds the unsigned iPhone IPA automatically after relevant pushes to `main`. Open the latest successful [Build iPhone IPA run](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/workflows/ios-ipa.yml), download `WHOOP-unsigned-iphone-ipa`, extract the ZIP, then sign and install the IPA with Sideloadly. Codemagic is optional; see [its separate instructions](README-CODEMAGIC.md) if you prefer it.

For an IPA, double-click **Build IPA.command** after extracting the project on a Mac with full Xcode. The detailed [iPhone installation guide](Docs/INSTALL-IPHONE.md) covers Sideloadly, signed Xcode export and the included manual GitHub Mac-runner workflow. No IPA has been built in this Linux executor.

1. Extract `WHOOP-iOS-source.zip` and open **WHOOP.xcodeproj** in Xcode 26 or newer.
2. Select the **WHOOP** scheme and an iPhone simulator, then Run.
3. For your iPhone, select the device and your development team under **Signing & Capabilities**. The signing profile must support the included HealthKit entitlement. The display name stays WHOOP; its separate bundle identifier is `local.whoop.reconstruction`.

The iOS project uses bundled resources, system frameworks and the pinned ZIPFoundation package. The server’s shared Nutrition routes require `npm ci` at the project root. The `WHOOPCore` package is local. Apple SDKs, code signing and device installation require a Mac with Xcode; this Linux workspace has not built an iPhone binary.

```bash
./Scripts/build-on-mac.sh
```

That command tests the core and builds an unsigned simulator application. To attempt a real arm64 device build and create an **unsigned** IPA on your Mac:

```bash
./Scripts/package-ipa-on-mac.sh
```

The latter packages the actual device build. Installation requires device signing, including compatible HealthKit entitlements. The unsigned package linked above is built and validated on the Mac CI runner; it is not signed for your phone.

## Functionality

[Nutrition](Docs/NUTRITION.md) adds offline food/exercise/weight logging, Mifflin targets, macro dials, 7/30-day charts, favorites, photo/text AI estimates and day reviews through the existing server. Its section uses Inter and its own unbranded dark palette. [Live media](Docs/LIVE-MEDIA.md) adds camera/photo overlays, transparent PNG exports and the WorkoutLive extension source. Native media and widget runtime behavior remain unverified.

- **Screenshot-guided interface:** compact overview with three rings, Health/Stress shortcuts, activities, sleep, journal and customizable dashboard rows; Home/Health/Community/More tabs, secondary Sleep/Recovery/Strain/Nutrition/Profile destinations, and full-screen Sleep/Recovery/Strain gauges. See [visual-reference notes](Docs/REFERENCE-UI.md). Day history, charts, UTC dates and example/imported/empty states remain connected.
- **WHOOP account:** browser OAuth through the included personal HTTPS bridge; imports account-supplied cycle, Recovery, sleep and workout records over selected 14/30-day UTC windows. Setup is required; no live account exchange has been tested.
- **Apple Health:** explicit read-only import of steps, active energy, resting heart rate, respiratory rate, heart rate and time asleep. Sleep is grouped by local wake date. Optional automatic sleep sync checks the past seven days. It does not write to Health. SDNN is not substituted for WHOOP's RMSSD HRV.
- **Local records:** journal creation/edit/deletion, manual activity logs, activity editing/deletion, foreground workout recording with actual received heart rate and separately labelled local strain estimates.
- **Files:** validated CSV/JSON day import, day export with millisecond timestamps, and full versioned backups that include journal notes and activities. Restore validates the whole backup before replacement.
- **Devices:** standard heart-rate broadcasts; recovered GEN4/MAVERICK/GOOSE frame decoding with CRC checks; opt-in experimental Hello → matched success → live-HR request handling, with pending/error/timeout states.
- **Tracker history:** user-initiated download of supported stored batches, durable raw storage before acknowledgement, selected measured HR/R-R layouts and raw ZIP/CSV export. Unknown payloads remain raw; official Recovery, Sleep and Strain are not inferred from them. See [transfer limitations](Docs/DEVICE-HISTORY-TRANSFER.md).
- **Calculations:** all 211 recovered strain thresholds, selected helper equations, a controlled reference calculator, and a conservative bounded live smoother/interval accumulator. Local estimates do not overwrite supplied daily scores.

First launch displays setup with no seeded measurements. **More → WHOOP account** opens account setup. **Import from Apple Health**, **Import day data**, or **Record a workout** adds actual measurements. **Save full backup** includes your day data, journal and activity records; **Export day data** deliberately exports only the days. Example provenance survives backup and import.

## Important boundaries

| Area | State |
| --- | --- |
| Original name, wordmark and typefaces | Included with source provenance |
| Local features and portable helpers | Implemented; see source and tests |
| Standard/custom Bluetooth and HealthKit adapters | Implemented but untested on an iPhone/strap |
| Hello/live-HR commands | Narrow experimental opt-in; not full clock/identity/history initialization |
| Public WHOOP account sync | Native OAuth adapter + Node bridge source implemented; requires registered client and trusted HTTPS service |
| Personalized Home, online teams/coaching/payments | Private services unresolved |
| Daily Recovery/sleep scoring and native MSK formulas | Unrecovered; not replaced with fake measurements |
| Full history sync, exact visuals and official-app parity | Not established |
| Xcode device build and signed IPA | Unsigned arm64 build passed on Mac CI; personal signing and device installation remain required |

The app explains its local-reconstruction status in **Menu → About this edition**. It does not collect WHOOP passwords or claim affiliation. No private WHOOP service, firmware operation or physical sensor was used during development.

## Connect your WHOOP account

Follow [account setup](Docs/ACCOUNT-SYNC.md) and [server setup](Docs/AccountAPI/README.md). Register your own WHOOP OAuth client, configure the server-only credentials, and expose the bridge over trusted HTTPS on port 443. Enter that origin in the Account screen, Connect, then Sync. No password or client secret goes into this app. API compatibility was corroborated against a pinned third-party SDK because the official specification host was inaccessible; live validation remains required.

## Verification

**The overnight tracking revision passes 213 Swift core tests and 13 packaging tests.** The previously recorded server suite passes 33 Node tests using local HTTP handlers and synthetic upstream records, without contacting WHOOP; this client-focused revision does not change the server.

The portable Swift suite covers imports, provenance, timestamp roundtrips, complete backups, sleep-interval union, standard BLE bytes, recovered frame/command golden fixtures, malformed/fragmented streams, bounded live strain and reply-state handling. Exact results are in [VALIDATION.json](VALIDATION.json) and [the tracker revision test log](Validation/overnight-tracker-core-tests.log).

Application Swift files pass frontend parsing and the Xcode project passes structural checks. The current revision also passed an Apple SDK build and unsigned arm64 IPA validation on the Mac CI runner. These checks do not establish physical camera or tracker behavior. Native interaction outcomes are recorded separately in VALIDATION.json.

See [STATUS.md](STATUS.md), [CORE-NOTES.md](CORE-NOTES.md), [Apple Health](Docs/APPLE-HEALTH.md), [backups](Docs/BACKUP-FORMAT.md), [live strain](Docs/LIVE-STRAIN.md), [device stream](Docs/DEVICE-STREAM.md), [packet decoding](Docs/WHOOP-PROTOCOL.md), [device history](Docs/DEVICE-HISTORY.md), [device time](Docs/DEVICE-TIME.md) and [reconstruction evidence](Docs/RECONSTRUCTION.md). [Examples](Examples) contains sample import files. The full REA records are delivered separately as `WHOOP-analysis-report.zip`.

The [parity ledger](Docs/PARITY.md) separates the current implementation from the requested exact WHOOP experience and identifies the missing evidence and behavior.

## Repository migration

The previous NOOP application is preserved on [the recovery branch](https://github.com/abdullahalmaeeni7-dot/noop-custom1/tree/backup/noop-before-whoop-5e7f970). Its app targets, packages, tools and workflows have been removed from this branch. The root LICENSE, NOTICE, ATTRIBUTION.md and DISCLAIMER.md are retained as historical copyright and attribution records for that prior source; their descriptions of NOOP do not describe the current application.
