# BodySeek / Vela architecture baseline (ARCH-00 / PR0)

This directory is the reproducibility handoff for the architecture-v2 migration. It records facts and deterministic assertions at commit `0bf536b93ae32082821ba57fa2d65fa07788e759` (`docs: adopt BodySeek architecture baseline v2`, 2026-09-04). The prior implementation checkpoint is `1620d62a290afbd6fd86743160a330ba9253940a`.

The artifacts are intentionally additive: they do not change app behavior, deployment settings, SwiftData models, tests, or the Xcode project.

## Platform and toolchain facts

| Fact | Observed value | Source |
|---|---|---|
| Shipping floor (iOS) | iOS 17.0 | `Vela.xcodeproj/project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET`) |
| Shipping floor (watchOS) | watchOS 10.0 | `Vela.xcodeproj/project.pbxproj` (`WATCHOS_DEPLOYMENT_TARGET`) |
| Swift language mode | Swift 6.0 | `Vela.xcodeproj/project.pbxproj` (`SWIFT_VERSION`) |
| Local Xcode | Xcode 26.6, build 17F113 | `xcodebuild -version` |
| Repository Xcode pin | 26.5.0 | `.xcode-version` |
| Local Swift compiler | Apple Swift 6.3.3, swift-driver 1.148.6 | `swift --version` |

ADR 0017 is authoritative: iOS 26/watchOS 26 remain progressive capabilities, not the shipping floor. The local Xcode is newer than the repository pin; hosted exact-Xcode validation remains a release gate.

## Verification evidence

The full iOS unit + UI result is preserved outside Git at `/tmp/Vela-Wave4-Release.xcresult`:

```text
xcrun xcresulttool get test-results summary \
  --path /tmp/Vela-Wave4-Release.xcresult
result=Passed; total=520; passed=520; failed=0; skipped=0
device=iPhone 17 Pro; platform=iOS Simulator; OS=26.5
```

The result includes 6 UI smoke tests and 514 unit/integration tests. It is the current release evidence referenced by the command center; rerun it if source behavior changes.

Guard commands at this baseline:

> 2026-11-20 更新：SwiftData schema guard 已随 GRDB 迁移退役，存储 schema 由 `swift test --package-path BodySeekKit --filter BodySeekStoreTests` 的迁移标识守卫覆盖。以下命令记录的是该基线当时的结果。

```text
swift test --package-path BodySeekKit --filter BodySeekStoreTests
# migration identifiers stable

python3 scripts/check_contrast.py
# contrast OK: textColor(for:) all >= 4.5:1
# graphic palette warnings are informational

git diff --check
# exit 0
```

## Deterministic golden inventory

[`golden-inventory.json`](golden-inventory.json) is generated from existing deterministic XCTest fixtures rather than a new runtime path. It records the exact fixture inputs, expected five independent scores, algorithm-version assertions, and conservative empty/body-state invariants. The source tests remain executable proof:

- `VelaAppTests/ScoringEngineTests.swift:458` (`testDailyHealthComputationGoldenFixtureAndVersionConsistency`)
- `VelaAppTests/DataCoverageAndEvidenceTests.swift:56` (`testEmptyDashboardProducesUnavailableSignalsAndNoAggregateReadinessScore`)
- `VelaAppTests/Milestone1ChallengeTests.swift:322` (`testWorseLivedStateAlignmentLowersConfidenceButKeepsObjectiveScores`)

The numeric values are test assertions, not hand-entered production telemetry. The inventory must be regenerated or reviewed whenever a scoring algorithm version or fixture changes; no formula change is authorized by PR0.

## UI baseline

[`ui/today-preview-iphone17pro-ios26.5.png`](ui/today-preview-iphone17pro-ios26.5.png) was captured on 2026-09-04 from the clean simulator app built in `/tmp/Vela-Wave4-Release-Derived/Build/Products/Debug-iphonesimulator/Vela.app`, using:

```text
simulator: iPhone 17 Pro, iOS 26.5
launch args: -vela_onboarding_completed YES -vela_app_language simplifiedChinese
             -velaPreviewDashboard -velaLegacyInterface -velaInitialTab 0
```

This is a preview-data rendering baseline (not a HealthKit/device truth baseline). It is suitable for layout comparison only. Existing images under `docs/reference/**` and `docs/validation/**` are legacy or parity references and are not claimed as current output here.

## Machine-specific documentation audit

See [`machine-specific-audit.md`](machine-specific-audit.md). The audit is report-only; historical files were not rewritten as part of PR0.

## ARCH-01 recommendation

Proceed to PR1 only after this manifest, the golden inventory, and the 520-test result are accepted. Extract a Foundation-only `BodySeekDomain` package with the dependency direction from ADR 0017. Run the same golden fixture before/after extraction and require byte-for-byte-equivalent score values and unchanged missing-data semantics. Do not combine the extraction with a deployment-floor bump, product rename, scoring formula change, Widget target, or SwiftData migration.
