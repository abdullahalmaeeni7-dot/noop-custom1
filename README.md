Current iPhone build: [download the unsigned IPA directly](https://github.com/abdullahalmaeeni7-dot/noop-custom1/raw/refs/heads/device-download/b28fd8cc7eb09537c11543f42085a5f14266aceb/WHOOP-unsigned.ipa), built from `b28fd8c` with the iOS device SDK. Sign the IPA with Sideloadly; this is an unsigned arm64 iPhone package (4.38 MB). The Mac workflow passed its portable tests, Apple SDK build and package validation. The downloaded IPA matches its published SHA-256.

Reference-screen status: [screen-by-screen audit and shared visual corrections](design/reviews/2026-11-16-reference-audit.md).

Current runtime corrections: [Live, cycle imports, startup and tracker fixes](Docs/ReleaseNotes/2026-11-16-runtime-fixes.md).

Arabic is available from the globe on first launch or **More → Language → العربية**. The app remembers the choice and mirrors the interface. Nutrition AI can use a separate Gemini service without WHOOP OAuth: follow [the deployment and pairing guide](Server/NUTRITION-SETUP.md). No provider key is bundled in the app. Shared point measurements now drive Home rings, cards, the day selector and navigation; reference geometry is documented in [design tokens](design/tokens/home.json).

# WHOOP iPhone app

First launch opens Welcome → Profile → Find your tracker → Import data → Home. Later launches use your saved profile and measurements. Import the official WHOOP web-export ZIP directly; no account bridge is needed for ZIP imports.

Home now follows the supplied reference hierarchy, with three animated score rings, paired monitor cards, My Day, sleep, activities, journal, plan and dashboard. Navigation includes Home, Health, Community and More; Nutrition is available under More. The floating day actions, compact rings on scroll and profile/export controls use the existing functional flows. The membership-expiry banner stays removed. Standard cards use opaque surfaces; the floating navigation retains native iOS 26 Liquid Glass, system material on older iOS, and accessibility fallbacks. Exact official-app appearance and feature parity are not established.

Nutrition includes a real Take Photo capture flow, photo-library selection, preview and editable AI estimates. Capture works independently of the server. **AI photo/text analysis requires a configured HTTPS account bridge with server-only `AI_API_KEY`, `AI_API_URL` and a vision-capable `AI_MODEL`.** No credentials or production service are bundled. Connection settings and manual-entry recovery are available directly from the food form.

See [layout and camera details](Docs/LAYOUT-AND-MEAL-CAMERA.md), [ZIP and glass implementation](Docs/ZIP-AND-GLASS.md), [profile and export behavior](Docs/PROFILE-PERSONALIZATION.md), and [current verification](VALIDATION.json). The [current iPhone build passed](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43935305660). Use the direct IPA link at the top of this file, then sign/install with Sideloadly. This binary includes the current Home/shared styling, Arabic navigation and the earlier camera/import fixes. See the [actual native preview and before/after review](design/home/native-review-06/REVIEW.md). Physical camera capture and a production AI provider remain untested.

---

# WHOOP — iPhone reconstruction

A standalone iOS 17+ SwiftUI project named **WHOOP**, with the original supplied wordmark, icon and typefaces. It combines local functionality with client behavior recovered using REA. Exact official-app appearance and feature parity are not established.

## Run on your Mac

**Windows:** GitHub Actions builds the unsigned iPhone IPA automatically after relevant pushes to `main`. Open the latest successful [Build iPhone IPA run](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/workflows/ios-ipa.yml), download `WHOOP-unsigned-iphone-ipa`, extract the ZIP, then sign and install the IPA with Sideloadly. Codemagic is optional; see [its separate instructions](README-CODEMAGIC.md) if you prefer it.

For an IPA, double-click **Build IPA.command** after extracting the project on a Mac with full Xcode. The detailed [iPhone installation guide](Docs/INSTALL-IPHONE.md) covers Sideloadly, signed Xcode export and the included manual GitHub Mac-runner workflow. No IPA has been built in this Linux executor.

1. Extract `WHOOP-iOS-source.zip` and open **WHOOP.xcodeproj** in Xcode 16 or newer.
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

The latter packages the actual device build, never a renamed simulator product. Installation still requires device signing, including compatible HealthKit entitlements. No IPA was generated or signed here.

## Functionality

[Nutrition](Docs/NUTRITION.md) adds offline food/exercise/weight logging, Mifflin targets, macro dials, 7/30-day charts, favorites, photo/text AI estimates and day reviews through the existing server. Its section uses Inter and its own unbranded dark palette. [Live media](Docs/LIVE-MEDIA.md) adds camera/photo overlays, transparent PNG exports and the WorkoutLive extension source. Native media and widget runtime behavior remain unverified.

- **Screenshot-guided interface:** compact overview with three rings, Health/Stress shortcuts, activities, sleep, journal and customizable dashboard rows; Home/Sleep/Recovery/Strain/Nutrition/More tabs, secondary Health/Community/Profile destinations, and full-screen Sleep/Recovery/Strain gauges. See [visual-reference notes](Docs/REFERENCE-UI.md). Day history, charts, UTC dates and example/imported/empty states remain connected.
- **WHOOP account:** browser OAuth through the included personal HTTPS bridge; imports account-supplied cycle, Recovery, sleep and workout records over selected 14/30-day UTC windows. Setup is required; no live account exchange has been tested.
- **Apple Health:** explicit read-only import of steps, active energy, resting heart rate, respiratory rate, heart rate and unioned time asleep over 14 or 30 UTC days. It does not write to Health. SDNN is not substituted for WHOOP's RMSSD HRV.
- **Local records:** journal creation/edit/deletion, manual activity logs, activity editing/deletion, foreground workout recording with actual received heart rate and separately labelled local strain estimates.
- **Files:** validated CSV/JSON day import, day export with millisecond timestamps, and full versioned backups that include journal notes and activities. Restore validates the whole backup before replacement.
- **Devices:** standard heart-rate broadcasts; recovered GEN4/MAVERICK/GOOSE frame decoding with CRC checks; opt-in experimental Hello → matched success → live-HR request handling, with pending/error/timeout states.
- **Passive history:** recovered common history headers, counters, Unix timestamps and revision flags; unknown payloads remain raw. It does not request, acknowledge or erase history, and historical physiological fields remain unresolved.
- **Calculations:** all 211 recovered strain thresholds, selected helper equations, a controlled reference calculator, and a conservative bounded live smoother/interval accumulator. Local estimates do not overwrite supplied daily scores.

First launch displays a labelled example week. **Menu → WHOOP account** opens account setup. **Import from Apple Health**, **Import day data**, or **Record a workout** adds actual measurements. **Save full backup** includes your day data, journal and activity records; **Export day data** deliberately exports only the days. Example provenance survives backup and import.

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
| Xcode device build and signed IPA | Still required on a Mac |

The app explains its local-reconstruction status in **Menu → About this edition**. It does not collect WHOOP passwords or claim affiliation. No private WHOOP service, firmware operation or physical sensor was used during development.

## Connect your WHOOP account

Follow [account setup](Docs/ACCOUNT-SYNC.md) and [server setup](Docs/AccountAPI/README.md). Register your own WHOOP OAuth client, configure the server-only credentials, and expose the bridge over trusted HTTPS on port 443. Enter that origin in the Account screen, Connect, then Sync. No password or client secret goes into this app. API compatibility was corroborated against a pinned third-party SDK because the official specification host was inaccessible; live validation remains required.

## Verification

**104 Swift core tests and 33 Node server tests pass.** Server tests use local HTTP handlers and synthetic upstream records, without contacting WHOOP.

The portable Swift suite covers imports, provenance, timestamp roundtrips, complete backups, sleep-interval union, standard BLE bytes, recovered frame/command golden fixtures, malformed/fragmented streams, bounded live strain and reply-state handling. Exact results are in [VALIDATION.json](VALIDATION.json) and [Validation/core-tests.log](Validation/core-tests.log).

Application Swift files pass frontend parsing and the Xcode project passes structural checks. **Those checks are not an Apple SDK typecheck, an Xcode build, a simulator run or a device test.**

See [STATUS.md](STATUS.md), [CORE-NOTES.md](CORE-NOTES.md), [Apple Health](Docs/APPLE-HEALTH.md), [backups](Docs/BACKUP-FORMAT.md), [live strain](Docs/LIVE-STRAIN.md), [device stream](Docs/DEVICE-STREAM.md), [packet decoding](Docs/WHOOP-PROTOCOL.md), [device history](Docs/DEVICE-HISTORY.md), [device time](Docs/DEVICE-TIME.md) and [reconstruction evidence](Docs/RECONSTRUCTION.md). [Examples](Examples) contains sample import files. The full REA records are delivered separately as `WHOOP-analysis-report.zip`.

The [parity ledger](Docs/PARITY.md) separates the current implementation from the requested exact WHOOP experience and identifies the missing evidence and behavior.

## Repository migration

The previous NOOP application is preserved on [the recovery branch](https://github.com/abdullahalmaeeni7-dot/noop-custom1/tree/backup/noop-before-whoop-5e7f970). Its app targets, packages, tools and workflows have been removed from this branch. The root LICENSE, NOTICE, ATTRIBUTION.md and DISCLAIMER.md are retained as historical copyright and attribution records for that prior source; their descriptions of NOOP do not describe the current application.
