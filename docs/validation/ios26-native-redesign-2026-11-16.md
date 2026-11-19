# BodySeek iOS 26 Native & Brand Redesign Acceptance Report

- **Date**: 2026-11-16
- **Scope**: iOS 26-native `TabView` / Liquid Glass navigation shell, Bevel-inspired adaptive Light/Dark palette (`VelaTheme`), Direction-1 dual-arc `B` brand mark (`BodySeekIcon.icon` + `BodySeekBrandMark`), `Swift Charts` metric detail & Trends upgrades, legacy UI dead-code removal (`VelaBackground.swift`, `VelaTodayViewData.swift`, `VelaLogoMark.swift`), updated docs (`docs/PRD.md`, `docs/VELA_DESIGN_LANGUAGE.md`, `docs/adr/0018-ios26-native-architecture-and-bevel-visual-reset.md`), and aligned `VelaUITests`.
- **Base `HEAD` Commit**: `f5271882a683a82ca998a272c8840dc41d107742`
- **Repository Hygiene**: Dirty working tree containing only scoped refactor, resource, doc, and validation changes (exact `git status --short` recorded at sign-off after creating this report).

## 1. Automated Verification Gates (Post-Final Code Edit)

All automated checks below were executed cleanly **after** the last source/test edit (`VelaMinimalShell.swift`):

| Gate | Command | Outcome | Exit Code | Notes / Artifact |
| --- | --- | --- | --- | --- |
| Domain SPM tests | `swift test --package-path BodySeekDomain` | **41 / 41 passed**, 0 failures | `0` | Deterministic scoring & domain contracts |
| Backend SPM tests | `swift test --package-path VelaBackend` | **3 / 3 passed**, 0 failures | `0` | `AppTests.PromptServiceTests` |
| SwiftData schema fingerprint | `python3 scripts/schema_fingerprint.py --check` | `schema fingerprint OK: 32 live models (VelaSchemaV3 3.0.0), 32 frozen V3 models` | `0` | `VelaSchemaV3` storage contract unchanged |
| Contrast checker | `python3 scripts/check_contrast.py` | `contrast OK: textColor(for:) and deviationInk all >= 4.5:1` | `0` | `deviationInk`: light `#5E5E63` (`5.78:1`), dark `#9A9A9E` (`7.49:1`) |
| Dynamic Type static gate | `python3 scripts/check_fixed_fonts.py --strict` | `171` fixed-font sites (limit `216`) | `0` | Clean under threshold |
| Git patch whitespace check | `git diff --check` | Clean (no trailing whitespace / conflict markers) | `0` | Checked before & after report write |
| watchOS Simulator build | `xcodebuild -project Vela.xcodeproj -scheme VelaWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **` | `0` | Compilation only (no runtime execution) |
| iOS Unit Tests (`VelaTests`) | `xcodebuild test -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -derivedDataPath build/DerivedData -parallel-testing-enabled NO -only-testing:VelaTests CODE_SIGNING_ALLOWED=NO` | **683 / 683 passed**, 0 failures, 0 skipped | `0` | `build/DerivedData/Logs/Test/Test-Vela-2026.11.16_13-38-27-+0800.xcresult` |
| iOS UI Suite (`VelaUITests`, Light) | `TEST_RUNNER_BODYSEEK_WALKTHROUGH_DIR=.../scratch/walkthrough-light TEST_RUNNER_BODYSEEK_WALKTHROUGH_APPEARANCE=light xcodebuild test -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -derivedDataPath build/DerivedData -parallel-testing-enabled NO -only-testing:VelaUITests CODE_SIGNING_ALLOWED=NO` | **48 / 48 passed** (`BodySeekWalkthroughUITests` `1/1`, `VelaSmokeUITests` `47/47`), 0 failures, 0 skipped | `0` | `build/DerivedData/Logs/Test/Test-Vela-2026.11.16_13-16-49-+0800.xcresult` |
| Walkthrough (Dark, `iPhone 17 Pro`) | `TEST_RUNNER_BODYSEEK_WALKTHROUGH_DIR=.../scratch/walkthrough-dark TEST_RUNNER_BODYSEEK_WALKTHROUGH_APPEARANCE=dark xcodebuild test-without-building ... -only-testing:VelaUITests/BodySeekWalkthroughUITests` | **1 / 1 passed** (`97.436` s), `21` PNGs (`01`..`21`) | `0` | `build/DerivedData/Logs/Test/Test-Vela-2026.11.16_13-41-10-+0800.xcresult` |
| Walkthrough (Light, Compact `iPhone 17e`) | `TEST_RUNNER_BODYSEEK_WALKTHROUGH_DIR=.../scratch/walkthrough-compact TEST_RUNNER_BODYSEEK_WALKTHROUGH_APPEARANCE=light xcodebuild test-without-building ... -destination 'id=E7488BF0-8EC4-482B-9599-1A6AEC8711F1' ... -only-testing:VelaUITests/BodySeekWalkthroughUITests` | **1 / 1 passed** (`94.235` s), `21` PNGs (`01`..`21`) | `0` | `build/DerivedData/Logs/Test/Test-Vela-2026.11.16_13-42-59-+0800.xcresult` |

## 2. Visual Walkthrough Matrix & Observed Layout Checks

- **iPhone 17 Pro (`id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987`, iOS 26.5) — Light & Dark**:
  - `今日`: Top bar `BodySeekBrandMark`, `+` record menu, profile trigger, date/weather pills, 3-ring hero (`恢复 58`, `睡眠 88`, `负荷 35`), Pressure/Energy cards, and bottom `vitalSeries` sparklines (HRV, RHR, Sleep draw curves while SpO2 remains honest dashed `-- %`).
  - `Coach` (`.search` role tab): `BodySeekBrandMark` header badge, inline emerald HRV 14-day sparkline (`VelaTheme.recoveryColor`), plan change confirmation buttons (`确认更改` / `不用了`), composer focus/keyboard dismissal keeping the floating tab bar intact.
  - `趋势` & Pushed Metric Details: Interactive `Swift Charts` views preserve missing-day gaps, hide tab bar cleanly on pushed details (`.toolbar(.hidden, for: .tabBar)`), keep the `"基线"` label unclipped at `.top` / `.trailing`, and render the clean `+` quick-actions sheet (`sparkles` icon replacing legacy mascot).
- **iPhone 17e (`id=E7488BF0-8EC4-482B-9599-1A6AEC8711F1`, iOS 26.5) — Compact Light**:
  - Zero clipping, overlap, or unintended line wrapping across `01-today-top.png`, `04-coach-top.png`, `11-trends-30d.png`, and `19-plan-top.png`.
  - Minor non-blocking note: on 30-day charts (`Trends` and Sleep detail), Swift Charts can occasionally auto-emit a trailing 5th edge tick truncated as `...` or `1...` next to the 4 primary date ticks; underlying curves, baselines, and main labels remain legible and unobstructed.

## 3. Working Tree Inventory

- **Modified**:
  - `Vela.xcodeproj/project.pbxproj`
  - `VelaApp/Compatibility/Today/TodayLegacyCompatibility.swift`
  - `VelaApp/Core/DesignSystem/{VelaCard,VelaChart,VelaDesignSystem,VelaInput}.swift`
  - `VelaApp/Core/Theme/VelaTheme.swift`
  - `VelaApp/Core/Utilities/PreviewDataFactory.swift`
  - `VelaApp/Features/Coach/{CoachView,CoachWelcomeWorkspace}.swift`
  - `VelaApp/Features/Minimal/{DailyStressChartView,MetricChartSection,RecoveryDetailV2,RecoveryDetailV2Editorial,SleepClockWheelView,TodaySignalGrid,TodaySubComponents,VelaMetricDetailData,VelaMetricDetailWidgets,VelaMinimalComponents,VelaMinimalShell,VelaMinimalTodayView,VelaTrainingPlanView}.swift`
  - `VelaApp/Features/Onboarding/VelaOnboardingView.swift`
  - `VelaApp/Features/SharedComponents/{DashboardViewModel,VelaQuickActionsSheet}.swift`
  - `VelaApp/Features/Trends/{TrendsOneMetricChart,VelaTrendsView}.swift`
  - `VelaApp/Health/Services/HealthKitQueryService.swift`
  - `VelaApp/Resources/Assets.xcassets/{AccentColor.colorset/Contents.json,AppIcon.appiconset/AppIcon.png,LaunchMark.imageset/LaunchMark.svg}`
  - `VelaAppTests/TrendsStoreTests.swift`
  - `VelaUITests/VelaSmokeUITests.swift`
  - `docs/PRD.md`, `docs/VELA_DESIGN_LANGUAGE.md`, `docs/adr/README.md`
- **Added**:
  - `VelaApp/Features/Minimal/TodayDashboardSections.swift`
  - `VelaApp/Resources/BodySeekIcon.icon/` (24 assets including `icon.json`, `b-inner.svg`, `b-outer.svg`)
  - `docs/adr/0018-ios26-native-architecture-and-bevel-visual-reset.md`
  - `docs/validation/ios26-native-redesign-2026-11-16.md` (this report)
- **Deleted**:
  - `VelaApp/Core/Theme/VelaBackground.swift`
  - `VelaApp/Features/Minimal/VelaTodayViewData.swift`
  - `VelaApp/Features/SharedComponents/VelaLogoMark.swift`

## 4. Unverified Risks & Remaining Boundaries

- **Physical Device & Live HealthKit**: Automated tests run under `CODE_SIGNING_ALLOWED=NO` with deterministic preview/fixture datasets (`-velaPreviewDashboard`); real-device HealthKit permissions, background workout/sleep ingestion, and haptic behavior are not verified in this simulator run.
- **watchOS Runtime**: `VelaWatch` compiled cleanly for `watchOS Simulator`, but watch companion runtime, WatchConnectivity sync, and complication rendering were not executed.
- **Live AI Network Responses**: Coach prompts in UI tests validate local deterministic/preview handling rather than live backend LLM network streaming and latency.
