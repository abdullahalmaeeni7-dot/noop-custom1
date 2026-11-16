# Live, imports, startup and tracker fixes

WHOOP ZIP/CSV and account imports accept distinct cycles that start on one UTC date. The latest cycle supplies the Home summary; cycle scores are not added or averaged. When a date has multiple cycles, `DailySnapshot.cycleRecords` retains their original start times and measurements. JSON measurement exports and full backups carry these records, and highlights include their peaks. Daily CSV remains a daily summary. Old archives without `cycleRecords` still decode. Conflicting copies of the same cycle, malformed measurements and nested cycle records remain errors.

The measurement export screen now accepts WHOOP ZIP files as well as CSV and JSON. Its import label and the account date explanation describe the supported behavior.

The date/source banner is removed from the reference Live preview, photos and video overlays. Missing readings remain unavailable instead of being fabricated. The preview caches its rendered overlay until the displayed values or dimensions change.

Cold-start disk reads and JSON decoding run off the main actor. Date lookups use an index, and file/account imports merge days by date instead of scanning the entire history for every row. Nutrition caches its calculator source, reuses unchanged calculations, and clears its loading state on cancellation.

Tracker discovery begins with the supported services, then also discovers connectable named wearables that omit those services from advertising. Discovered WHOOP services automatically attempt the existing Hello/heart-rate handshake once their notification channels are ready. Failed attempts do not loop. Both setup and device settings let the user cancel a connection. This does not add proprietary historical sync or establish compatibility with every tracker model.

Welcome has a centered wearable illustration and direct tracker/import/personalization choices. No supplied reference depicts the official welcome screen, so exact visual parity is not asserted. No remote login or provider access is simulated.

Validation: portable Swift regressions cover collisions, exact sleep joins, order independence, JSON/backup preservation, cycle peak highlights, and malformed cycle records. Native build results are recorded by the existing iPhone IPA workflow. Physical Bluetooth pairing, camera behavior and on-device timing require an iPhone and tracker; Linux syntax checks cannot establish those results.

Verified locally: 169 Swift core tests and 13 IPA/package validator tests passed; the generated nutrition bundle matches the canonical calculator; Swift frontend parsing and the Xcode project structural validator passed. These checks do not substitute for an Apple SDK build or physical device verification.
