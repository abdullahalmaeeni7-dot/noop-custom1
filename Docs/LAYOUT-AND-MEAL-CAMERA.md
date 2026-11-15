# Reference layout and meal camera

The existing SwiftUI project, first-use setup, storage, imports, tracker and Live recording remain in place. Home now uses the reference hierarchy: centered day capsule, avatar/streak, watch connection, three animated rings, insight, paired monitors, My Day, sleep, activity card, journal, plan and dashboard. Bottom navigation is Home, Health, Nutrition, Community and More, plus a separate day-review control. Sleep, Recovery and Strain still open from the rings. Health uses the age/monitor card hierarchy. No membership-expiry banner is added.

Measurements and summaries use saved data. Unsupported stress/aging/social outputs are not replaced by screenshot values. WHOOP Age and streak overrides remain labeled profile preferences. This does not establish exact official-app visual or feature parity.

## Meal camera

Nutrition has a direct camera button. Add food → AI photo offers Take Photo and Library. The capture flow uses the existing AVFoundation engine, requests video access only, supports flipping, recovers denied permission through iPhone Settings, and releases the session on dismissal/backgrounding. Permission and setup callbacks are generation-guarded so a stale attempt cannot mark a dismissed camera ready; readiness also checks that the capture session is actually running. Meal captures use the original photo aspect and no workout overlay. Temporary capture files are removed after loading; a bounded JPEG thumbnail strips metadata before upload. Nothing uploads until Analyze is tapped, and estimated rows remain editable before saving.

The existing authenticated server routes are retained. The form links directly to connection settings and distinguishes missing service, unlinked account, rate limit, unavailable provider, timeout and invalid response. A server configured with `AI_API_KEY`, `AI_API_URL` and a vision-capable `AI_MODEL` is still required for photo analysis. Do not put keys into the iOS app. No production AI service or credentials were supplied or deployed in this change. Manual logging remains offline.

## Verification

Swift frontend parsing and project structure checks passed. The existing calculator/route/server suite passed, including authenticated photo-analysis request and failure contracts with a synthetic provider. A native device build is tracked in VALIDATION.json. The workflow also attempts a disposable iPhone simulator review: first launch empty, then Home with synthetic fixture data seeded only into that simulator. Its image branch and artifact are separate from the production app. Neither a simulator image nor a successful build verifies physical camera hardware or a production AI provider.

The final arm64 iPhone build passed at source `12cba1ea5d478b323494b185951478e705c01246` ([device job](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43764324402/job/132965899700)). The [3.94 MB artifact ZIP](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43764324402/artifacts/14182026860) contains the unsigned IPA and its checksum. Sign it before installation. Its artifact-archive digest is recorded in VALIDATION.json.

Actual native images were captured and inspected in two iterations. The [final preview, before/after and remaining differences](../design/home/native-review-02/REVIEW.md) record the final result. The first Intel simulator attempt failed, the next timed out; the separate Apple Silicon Release workflow succeeded and produces readable evidence status even when rendering fails. No browser reconstruction is presented as native evidence. Physical camera behavior and the production AI service still need real-device/configuration testing.
