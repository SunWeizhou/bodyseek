# BodySeek TCA + Stanford SpeziHealthKit Architecture Migration Report

- **Date**: 2026-11-16
- **Branch**: `codex/ui/ios26-native-bodyseek`
- **Base `HEAD` Commit**: `f5271882a683a82ca998a272c8840dc41d107742`
- **Migration Summary**:
  - Replaced ~60,000 lines of legacy handwritten `VelaApp/{AI,Compatibility,Core,Features,Health,Journal,Persistence,Scoring,TrainingIntelligence}`, legacy `BodySeekDomain/`, and broken `VelaWatch` target with a modular Swift Package **`BodySeekKit`** (`5,303` source lines across `BodySeekCore`, `BodySeekHealth`, `BodySeekFeatures`) and a 35-line thin entry shell `VelaApp/App/VelaApp.swift`, generated reproducibly via `project.yml` + `xcodegen`.
  - **State & Architecture Framework**: **Point-Free TCA** (`swift-composable-architecture` `1.26.2`, `swift-dependencies` `1.17.2`) with isolated `@Reducer` feature modules (`AppFeature`, `TodayFeature`, `TrendsFeature`, `MetricDetailFeature`, `PlanFeature`, `CoachFeature`, `SettingsFeature`).
  - **HealthKit Infrastructure**: **Stanford SpeziHealthKit** (`1.4.2`) + **Spezi** (`1.10.2`), registering `BodySeekStandard: Standard, HealthKitConstraint`, background/foreground `CollectSamples`, `statisticsQuery`, and built-in overlap-free `SleepSession` (`splitIntoSleepSessions`).
  - **Domain & Persistence Reset**: Lightweight Bevel / Apple Fitness–inspired scoring (`BevelScoringEngine` with 28-day non-leaking rolling baselines and `available / knownZero / missing` honesty) plus atomic JSON persistence (`PlanPersistenceClient`, zero swallowed write errors).

## Automated Verification & Deployment Gates

| Gate | Command / Target | Result | Exit Code | Notes |
| --- | --- | --- | --- | --- |
| Package unit & reducer tests (`BodySeekKitTests`) | `swift test --package-path BodySeekKit` | **8 / 8 passed** (`0.422s`) | `0` | Covers scoring honesty, zero future leakage, `PlanPersistenceClient` error propagation, TCA `TestStore` navigation & Coach confirmation |
| iOS app & UI suite (`VelaTests` + `VelaUITests`, `iPhone 17 Pro` iOS 26.5) | `xcodebuild test -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -derivedDataPath build/DerivedData -parallel-testing-enabled NO -skipMacroValidation CODE_SIGNING_ALLOWED=NO` | **VelaTests 3/3 + VelaUITests 3/3 passed** | `0` | `.xcresult`: `build/DerivedData/Logs/Test/Test-Vela-2026.11.16_17-58-19-+0800.xcresult`; captured Light screenshots `01`..`06` |
| Dark Mode walkthrough (`iPhone 17 Pro` iOS 26.5) | `xcodebuild test-without-building ... -only-testing:VelaUITests/BodySeekUITests/testCaptureLightAndDarkScreenshotsWhenRequested` | **1 / 1 passed** (`18.726s`) | `0` | `.xcresult`: `build/DerivedData/Logs/Test/Test-Vela-2026.11.16_18-01-12-+0800.xcresult`; Dark Mode PNGs inspected |
| Signed iOS device build (`generic/platform=iOS`) | `xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData -skipMacroValidation -allowProvisioningUpdates build` | `** BUILD SUCCEEDED **` | `0` | Signed with team `UHS4N7454X` / `com.sunweizhou.Vela4` |
| Physical iPhone install & launch (`Joe’s iPhone`) | `xcrun devicectl device install app --device 00008140-00164DE022C3801C ... && xcrun devicectl device process launch --device 00008140-00164DE022C3801C com.sunweizhou.Vela4` | Installed & launched (`com.sunweizhou.Vela4`) | `0` | Live on `iPhone 16 Pro` (`iPhone17,1`) |
| Backend SPM tests (`VelaBackend`) | `swift test --package-path VelaBackend` | **3 / 3 passed** | `0` | `AppTests.PromptServiceTests` |
| Patch cleanliness | `git diff --check` | Clean | `0` | Checked at sign-off |

## Unverified Boundaries & Notes

- **Live HealthKit Runtime on Physical Device**: While `Vela.app` compiled, signed, installed, and launched cleanly on `Joe’s iPhone`, real-user HealthKit permission prompt grant/deny toggling and 24h watch background sample delivery are exercised interactively on the physical device rather than automated CI.
- **watchOS Target Streamlined**: Per user direction, legacy `VelaWatch` was removed from `project.yml` / `Vela.xcodeproj` so iOS phone stability and build speed come first.
- **Minor Chart Edge Tick Observation**: On 30-day charts (`03-recovery-detail.png`, `05-trends.png`), Swift Charts occasionally auto-renders a partial trailing edge tick (`1...`) next to the 4 primary date ticks; curves, baseline line (`基线 74`), and primary ticks remain readable and unclipped.
