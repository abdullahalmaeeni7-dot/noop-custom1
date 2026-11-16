# Final native layout and Arabic review

Actual SwiftUI iPhone 15 Pro captures from source `17f90c402ac426ef1ba42c632b98e617e093ecd9`, [run 43823242961](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43823242961). Capture outcome: success. Original PNGs are 1179 × 2556 pixels (393 × 852 points at 3×).

[English/Arabic Home and first-launch comparison](comparison.jpg) · [Arabic before/after](before-after.jpg)

The PNGs are unmodified simulator screenshots. The comparison sheets resize them to logical point dimensions and add headings outside the images. Home uses synthetic imported measurements and profile choices seeded only into a disposable simulator. First launch has a language preference only, with no measurements. The production app does not seed those scores.

## Differences found and corrected

- Vector branding had mirrored with the Arabic layout. Wordmark and monogram now retain their original direction.
- Gauge arcs had mirrored with the layout. They now use the same clockwise fill in English and Arabic while the page order follows RTL.
- The first safe-area adjustment raised the bottom bar. The final code measures the UIWindow inset, accounting for its internal 3-point padding, to place the visible shape 26 points above the screen bottom.
- The separate round navigation control now measures 58 points, with a 29-point inner ring and 18 × 15-point mark.
- Home uses the common 81-point rings, 5.8-point strokes, 13-point card corners, 14.5-point page inset and 126-point date strip.
- Arabic text uses an Arabic-capable system font with joining intact. Numeric fields parse Arabic/Persian digits and Arabic decimals without accepting a truncated integer prefix.

Home and first-launch screenshots were inspected in both languages. Branding, arc direction, translated labels and navigation placement are confirmed in these captures. The supplied reference was available as displayed attachments, not original image bytes: colors and geometry are estimates, not a quantified pixel-perfect match. The additional Nutrition tab, requested system glass, live/saved data and missing-measurement states intentionally affect the appearance. Official animation timing is not established by screenshots.

Physical-device camera capture, signed installation and production Gemini calls were not exercised. Nutrition AI requires the separately deployed private service described in [the setup guide](../../../Server/NUTRITION-SETUP.md).
