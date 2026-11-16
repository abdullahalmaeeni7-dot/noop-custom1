# Home native review — 16 November 2026

Actual SwiftUI iPhone 15 Pro captures from source `b28fd8cc7eb09537c11543f42085a5f14266aceb`, [successful simulator run 43935305671](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43935305671). Original PNGs are 1179 × 2556 pixels (393 × 852 points at 3×).

[Project before/after](before-after.jpg) · [English/Arabic Home](comparison.jpg) · [English Home](02-home-en.png) · [Arabic Home](02-home-ar.png) · [First launch, English](01-first-launch-en.png) · [First launch, Arabic](01-first-launch-ar.png)

The PNGs are unmodified native screenshots. Comparison sheets resize them and add labels outside the screenshots. “Before” is this project's prior native review at `17f90c4`, not an official-app screenshot. Home measurements and the Alex Avery profile are synthetic, injected only into the disposable simulator. First launch is unseeded apart from the language preference. Production does not open with these measurements.

## Differences corrected

- Standard cards now have opaque reference-colored surfaces without the previous glass borders; glass remains on floating controls.
- Navigation has Home, Health, Community and More, with Nutrition under More. The floating bar has a darker backing to reduce underlying text bleed.
- The date strip has a separate flat selected center; Home's opening spacing and three-ring geometry are shared with the reference tokens.
- Removed extra prior-day markers from Home rings. The insight has a left title/body and compact right check badge instead of the unrelated HRV value.
- Home Health Monitor opens the monitor directly; More Profile uses the full profile screen.
- Arabic translates the insight heading and mirrors directional navigation. Ring paths and numbers retain their original direction.
- Captures now allow startup/font loading and compare successive frames. Color sampling confirms full ring fill in both languages: Sleep about 35.3%, Recovery 40.3%, Strain 77.8–78.1% of the sampled circumference, including the rounded caps. These correspond to the fixture's 33%, 38%, and 15.8/21 scores rather than a partially animated frame. This is a settled-frame diagnostic, not a pixel match to the reference.
- Membership-expiry banner remains removed.

## Visible Home differences still present

- The tracker header uses a system wearable glyph, and several monitor/navigation icons differ from the supplied screenshot.
- A disconnected tracker has no fabricated battery value or green connection dot.
- Monitor cards show measurement/data actions when their specific status readings are unavailable, rather than the reference's elevated-temperature and numeric-stress states.
- The insight uses recorded strain prose; it does not assert an unavailable proprietary optimal range.
- Sleep Overview shows measured sleep needed and recorded sleep. It is not the reference's recommended-bedtime and device-alarm control.
- User name, status-bar geometry, and content-driven text wrapping differ. The simulator is an iPhone 15 Pro; the user's physical model has not been confirmed.
- Original attachment files are absent from `/reference`. Point sizes and colors are estimated from displayed attachments, so original pixel equality and animation timing are unverified.

The wider app still has the differences and missing service integrations listed in the [screen audit](../../reviews/2026-11-16-reference-audit.md). These images cover Home and first launch, not a complete-app parity claim. Per the user's requested screen-by-screen process, Home is ready for review before the next screen is rebuilt.

## Device package

The [iPhone build](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43935305660) passed portable tests, Apple SDK compilation and arm64 device packaging. The [direct unsigned IPA](https://github.com/abdullahalmaeeni7-dot/noop-custom1/raw/refs/heads/device-download/b28fd8cc7eb09537c11543f42085a5f14266aceb/WHOOP-unsigned.ipa) was downloaded, checked against its published SHA-256 (`e24d670a2ab090fd25706a8b9a5e77b0ec0e8c2d4ca484ac9a6a8c3a063c7854`), and independently validated as an iOS-device app with WorkoutLive extension. Physical signing, camera, Bluetooth and production AI operation remain untested.
