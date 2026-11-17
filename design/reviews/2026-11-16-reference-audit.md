# Reference screen audit

Target: the user-supplied WHOOP screenshots. Do not add the removed membership-expiry banner. Preserve Arabic, Nutrition, Live recording and real data import/export. Nutrition is accessible through More so the floating navigation has the reference's four tabs.

This is an existing SwiftUI iOS project, using its own reusable views, Swift Charts, AppStore/local JSON, CoreBluetooth, AVFoundation and an optional account bridge. No replacement project or auth/storage rewrite is involved.

## Shared corrections in this revision

- Standard cards use the opaque reference surface `#2B3135` and 13-point continuous corners. The system glass previously made their brightness, borders and depth differ across the app.
- Keep system glass on the floating navigation and its adjacent coach control. Restore Home, Health, Community, More at the reference widths; keep Nutrition under More.
- Flat selected date strip with the reference's separate middle capsule; remove the extra glass rim.
- Standard filled actions use white with dark text; secondary actions use the elevated surface and rounded rectangular geometry instead of glass capsules.
- Home's opening spacing is increased. Extra prior-day tick marks are removed from the Home rings; no unsupported optimal-strain target is substituted. Its insight follows the reference's left title/body and small right badge, using the recorded Strain without claiming an unmeasured optimal target.
- Home's Health Monitor shortcut opens the monitor directly. More → Profile opens the same full profile screen as the Home avatar, instead of the older generic profile route.
- More uses the reference-facing Membership and My Account navigation labels while keeping the existing tier/account actions.
- The earlier import/export corrections, removal of the Live source/date banner and startup optimizations remain intact.

## Screen-by-screen status

| Reference | Current route | Remaining differences or service gaps |
| --- | --- | --- |
| Home, all scroll positions | Home | Shared corrections captured and reviewed in English/Arabic on an iPhone 15 Pro simulator; see the final native review below. Sleep overview uses recorded totals; an actual tracker alarm schedule and recommended bedtime are not supplied. Stress is unavailable rather than manufactured. Discover links differ from commerce promotions. |
| Health | Health | Orb, pace card, monitor and stress card exist. Advanced Labs and original upgrade cards are incomplete. Proprietary aging/pace scores are not implemented; the configurable age remains identified as a profile setting. |
| Health Monitor | Health → Health Monitor | HR, respiratory rate, RHR and HRV can use recorded values. SpO₂ and skin-temperature source support is incomplete. No personal medical range assessment is inferred. |
| Stress Monitor | Health → Stress Monitor | Gauge structure exists. A proprietary stress time series is unavailable; recorded HR is labeled as HR. |
| Sleep, Recovery, Strain | Home rings | Functional score details and trends exist. Several stage, consistency and zone fields require additional supported input. |
| Profile, achievements, highlights | Profile | Configurable age/streak and measured peaks/export exist. Official achievement assets and WHOOP community ranking are absent. |
| Live overview/detail modes | Home → + → Live | Shared capture renderer, camera, photos, recording and exports exist. Source/date banner removed. Physical camera/tracker operation still requires device checks. |
| Add/start activity | Home → + | Real local activity forms/recording exist; some reference option rows differ. |
| More and shop | More | Functional local settings/data actions exist. Storefront/member promotions do not yet match the reference. |
| Community | Community | Existing local activity log and unavailable-service state differ substantially from the reference team cards. WHOOP team/referral/family-plan services are not implemented. |
| Coach | Coach control | Current control opens day review. The proprietary WHOOP chat service is not integrated. |
| Device Settings | Header tracker icon | Actual BLE search and supported data streams exist. The reference's full strap administration, battery and haptic controls are incomplete. |
| Welcome | First launch / More → setup | No supplied screenshot shows the official welcome flow. Exact parity cannot be asserted. |
| Nutrition | More → Nutrition | Custom requested feature; no original WHOOP Nutrition reference exists. |

## Comparison method

The original attachments are visible in the conversation but their image files are absent from the workspace's `/reference` folder. Existing tokens therefore explicitly describe estimated colors and point geometry; they are not claimed to be image-sampled or pixel exact. This revision generates actual native Home/first-launch frames in English and Arabic using an isolated simulator. A before/after layout comparison can be made from those files. Official animation timing, missing artwork, private service behavior and pixel equality remain unverified.

Home is the first review screen, following the requested one-screen-at-a-time process. This audit is a record of remaining work, not a claim that the whole app is already an exact WHOOP replacement.

## First native review findings

Run `43928690328` produced actual English and Arabic frames at source `f5c6b53`. The opaque card surfaces, four-item bar and flatter date strip render correctly. The Arabic insight title lacked a translation; this is corrected. The five-second capture delay caught the ring animations part-way through filling, especially in Arabic. The capture helper now waits for startup and compares successive PNG pixel payloads before accepting a settled frame; a failure to settle is reported for manual review. The floating navigation gets a darker backing surface to reduce the visible text bleed from the card beneath it. No claim of pixel equality with the original attachments is made.

Home/date navigation uses semantic forward/backward chevrons so directional controls follow Arabic layout. Physical ring paths and numbers remain left-to-right, as before.

## Final native evidence

Source `b28fd8c` passed the [device workflow](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43935305660) and [native capture workflow](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43935305671). The [Home review](../home/native-review-06/REVIEW.md) contains original English/Arabic PNGs, project before/after sheets, corrected differences, remaining visible differences and the verified direct IPA. Full ring fill, translated Arabic insight and four-tab navigation were inspected in these captures. Exact reference parity is still unverified.

## Automatic tracking follow-up — 17 November

The [tracking revision](../../Docs/ReleaseNotes/2026-11-17-automatic-tracking.md) fixes the live-BPM-only path: received readings now save automatically and can supply an explicitly labeled local Strain estimate. Device Settings shows counts and coverage, with editable local HR limits. WHOOP Recovery and Sleep still require supported provider data; this does not complete the proprietary algorithms or strap-history synchronization. Physical background delivery remains unverified.
