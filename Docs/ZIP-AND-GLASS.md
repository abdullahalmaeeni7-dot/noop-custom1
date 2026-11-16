# WHOOP ZIP import, date-free Live and glass surfaces

## Import the original web export

First-run data setup and More → Your data now accept ZIP, individual official WHOOP CSV, app JSON, and heart-rate CSV. No bridge or account connection is needed for a downloaded export. ZIPFoundation 0.9.20 is pinned in Package.swift and Package.resolved; its MIT license is in ThirdParty/ZIPFoundation-LICENSE.txt and is also bundled with the app alongside the existing Inter font notice.

The ZIP reader handles stored and deflated entries and recognizes physiological_cycles.csv, sleeps.csv and workouts.csv, including a containing directory. It imports the existing model's Recovery, daily Strain, resting HR, HRV, respiratory rate, energy, primary sleep totals/need/performance, and workouts with supplied Strain. Nap rows do not duplicate primary sleep. Local timestamps require the exported timezone; explicit ISO timestamps and IANA zones are supported. Day grouping follows the application's UTC convention. Distinct cycles on one UTC date are retained under `cycleRecords`; Home shows the latest cycle, and JSON exports/full backups preserve the originals. Conflicting duplicate rows for the identical cycle start still stop import.

Average/max heart-rate columns are not fabricated into continuous samples. Journal answers and unsupported metric columns are not mapped into unrelated fields. A journal-file notice is included in the successful import report. Existing non-example days and workouts are merged transactionally using the current local store; repeated CSV workouts receive stable identities. Existing heart-rate samples and unrelated known measurements are preserved when a CSV omits them. The full-backup JSON flow is unchanged. Setup preserves the selected imported day when opening Home, so an older export is immediately visible.

ZIP entries are read into bounded memory, never extracted to disk. CRC checks, duplicate-name checks, path and symlink rejection, 256-entry and 32 MB expanded-total limits, a 10 MB input/per-CSV limit, row bounds and metric validation run before saving. Failed imports leave the store unchanged.

## Live

Both Live implementations remove the date from preview and media-overlay source text. Recorded-day selection stays in the controls so users can select the measurements used. Provenance labels such as EXAMPLE or RECORDED DAY remain; there is no date printed above the rings.

## Installed skill and SwiftUI adaptation

The requested [gpui-liquid-glass skill](../.agents/skills/gpui-liquid-glass/SKILL.md) is installed in .agents/skills/gpui-liquid-glass from sxhxliang/gpui-liquid-glass commit dce9a4dffa353b39ba96266307892cdf249f2c42. Its instructions target Rust GPUI and AppKit desktop applications and explicitly exclude SwiftUI. No Rust/AppKit bridge is injected into the iPhone app. The user's requested visual adaptation uses SwiftUI's own system material APIs and follows the applicable geometry, state, background-sampling and accessibility guidance.

AppGlassSurface is called by WCard, PulseCard, primary/secondary buttons, tracker buttons, date controls, the floating bottom navigation, onboarding controls and Live capture controls. Native iOS 26 glassEffect uses the app's actual background; the main background provides muted radial color behind the surfaces. Older iOS uses system ultra-thin material with a restrained tint. Reduce Transparency selects opaque material; increased contrast strengthens the edge; existing reduced-motion behavior is preserved. Content remains above the system material. No background-sampling claim is based on an opacity-only screenshot.

## Verification

160 portable core tests pass, including 14 new official ZIP/CSV tests for metrics, UTC offsets, IANA zones, naps, stable workout IDs, invalid data, checksums, duplicates, path safety and expanded-size bounds. All 13 packaging tests pass. Swift frontend syntax, direct shared-core imports, Xcode project structure, and workflow Bash/Python/YAML syntax are checked. The native workflow explicitly selects an installed Xcode 26 SDK and runs a real arm64 iPhone build with package validation.

The first Apple build found an oversized RootView expression; layout, presentation, data I/O and alert modifiers are now split into smaller typed view properties. The corrected [Apple device build](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43736442549) passed in 4m 35s, including the Mac test step, native iOS 26 glass API compilation, arm64 build, package validation and artifact upload. The [unsigned IPA artifact](https://github.com/abdullahalmaeeni7-dot/noop-custom1/actions/runs/43736442549/artifacts/14171160235) is 3.76 MB. Real iPhone material sampling, older-iOS fallback, accessibility settings, file picking and physical tracker compatibility require device execution; compilation alone is not recorded as a visual test. The user's own export ZIP was not provided; supported schemas are exercised with synthetic official-format fixtures.
