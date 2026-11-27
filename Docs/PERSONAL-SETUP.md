# Personal setup and file-based data

First launch keeps the existing welcome animation and progresses through personal details, tracker pairing, and data import/export. English and العربية are visible language tabs on Welcome; the existing language preference continues to control translation and right-to-left layout.

Personal details require a date of birth, Man or Woman, and Left wrist or Right wrist. The date picker includes a year wheel; age is calculated from the birth date. These fields are editable in Profile and included in JSON and profile/highlights CSV exports. Previously saved profiles remain readable and are completed when setup or profile editing is used.

The data choices are Import and Export. WHOOP account and Apple Health entry points were removed from setup, Home, Health, More, Device Settings and Export. Existing saved measurements are preserved. Import accepts ZIP, CSV and app JSON; export retains its existing format and date-range controls. The hidden integration implementation is retained for compatibility, without account or Health connection choices in navigation.

Tracker pairing and storage are unchanged. Live Bluetooth heart-rate readings and supported tracker history can supply local estimates, while official Recovery scores still need recorded data. This revision does not establish physical-band compatibility or equivalence to proprietary WHOOP calculations.

## Verification

- 221 portable Swift tests pass, including required details, birth-date age calculation, future-date rejection, legacy profiles, and profile round trips.
- Swift source parsing and whitespace checks pass.
- The Apple device build passed for source `d3f617333be00fd3861e35ec6ce569588b66f3be`. The downloaded unsigned IPA checksum and arm64 device package were verified.
- Setup UI coverage now selects the required fields and checks that account/Health choices are absent. Updated simulator interactions have not yet been verified; no physical tracker test was performed.
