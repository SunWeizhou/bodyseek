# BodySeek — Recovery Editorial UI / Cursor integration handoff

## Read this before editing

Repo: `SunWeizhou/bodyseek`  
Target branch: `cursor/recovery-detail-v2-1d20`  
Observed head SHA at handoff: `67a3da5327ae6b645b5bec09a872371d502ec737` (2026-10-08).

I have supplied `RecoveryDetailV2Editorial.swift` as a standalone, new SwiftUI View that **consumes existing** `RecoveryDetailV2Model` and `DetailTimeRange` from `VelaApp/Features/Minimal/RecoveryDetailV2.swift`. It is a visual implementation reference and deliberately does NOT redefine model, scoring, HealthKit, persistence, or baseline contracts.

## What to do

1. Work **only** on the latest Recovery branch; do not make changes to `main` until reviewed.
2. Review `AGENTS.md`, `CONTEXT.md`, `docs/PRD.md`, `docs/collaboration/UI_WORKFLOW.md` before changes.
3. Add `RecoveryDetailV2Editorial.swift` to `VelaApp/Features/Minimal/` and register it with the Xcode project if needed.
4. Preserve `RecoveryDetailV2Builder`, `RecoveryDetailV2Model`, `RecoveryDetailV2Source`, `RecoveryDetailV2Series`, the existing test fixtures, and all existing app data contracts.
5. **Only in the currently wired Recovery page host**, replace the original `RecoveryDetailV2View(model:selectedRange:onAskCoach:)` call with `RecoveryDetailV2EditorialView(model:selectedRange:onAskCoach:)`. Inspect the actual host to ensure it rebuilds the model when `selectedRange` changes. If not, fix that UI assembly narrowly; do not compute trends inside the View.
6. Preserve accessibility identifiers expected by existing UI tests (`metric-detail-hero`, `recovery-detail-chart`, `recovery-detail-observations`, `recovery-detail-finding`, `recovery-detail-evidence-toggle`). Run UI tests to discover any additionally required identifiers rather than blindly deleting expectations.
7. If compilation fails, fix only the SwiftUI presentation and target-registration issues; do not loosen model tests to accommodate visual code.
8. Make a dedicated UI commit, with genuine iOS Simulator screenshots.

## Design intent (not optional)

- A coherent **editorial body report**, not 5 stacked 20pt white cards.
- Section order: `Recovery today → history + baseline → physiological observations → one analysis finding → methodology footnote`.
- The 68pt typographic score is the first-viewport anchor. A small fine progress track shows score position; a thin tick shows the point baseline only when real data exists.
- The green `VelaTheme.recoveryColor` represents the Recovery signal. Blue `VelaTheme.rhythmDeep` remains reserved for link/action controls. Do NOT turn all elements green.
- Chart lines break at missing calendar days. Missing values must remain nil, not zero. The shaded band is drawn **only** if the model supplies `baselineBand`; a point baseline renders as a dashed RuleMark. A view must not synthesize a normal range.
- For small-viewport / large accessibility font, recover via ViewThatFits, adaptive grid, menu-driven time selector, Dynamic Type.
- `model.findingText` is descriptive statistics. `model.candidateExplanation` must be labeled as an unconfirmed candidate association, not causality.
- Avoid verbose tags such as repeating `当前数值` and `统计描述` before every card; show evidence category only in the expandable data lines.

## Actual checks, not just code generation

- `xcodebuild` build for configured iOS target.
- Existing `RecoveryDetailV2Tests` and related UI-navigation tests.
- Preview scenarios: ready, known zero, no score, point baseline only, explicit baseline band, missing days, partial signals.
- iPhone SE / small device and a modern full-size iPhone, light and dark mode, larger Dynamic Type.
- Confirm time selector really changes data + finding, not just the label.
- Confirm chart includes 0 safely and still breaks over missing days, and no fabricated band is shown.
- Confirm accessibility labels/identifiers and VoiceOver reading order.
- Provide real screenshots and a concise before/after comparison. Do not claim builds or screenshots without actually running them.

## Caution

`RecoveryDetailV2Editorial.swift` passed `swiftc -frontend -parse` in a Linux environment. This is only Swift syntax parsing, **not** SwiftUI type checking or an iOS/Xcode build. Please fix any platform-specific compile issues in Xcode before integration.
