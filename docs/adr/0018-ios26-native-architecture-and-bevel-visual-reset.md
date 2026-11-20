# 0018. iOS 26 Native Architecture and Bevel-Inspired Visual Reset

## Status
Partially superseded by [ADR 0019](0019-bodyseek-v5-architecture-and-modeling-baseline.md)（SwiftData V3 / 32 模型与模块命名部分）。iOS 26.0 部署底线、原生 `TabView` / Liquid Glass 壳层与五域语义色继续有效。

## Context

`ADR 0017` previously locked the iPhone shipping floor to `iOS 17.0` and preserved the monochrome `Design D` shell (`VelaMinimalShell` with a custom top segmented header, underline tabs, and a persistent bottom floating `AskBar` pill). In real daily-driver usage on iOS 26/27 hardware, that custom chrome and monochrome constraint made BodySeek look non-native compared with Apple Fitness, Apple Health, Bevel, and Oura, while hiding rich physiological charts behind flat grayscale boxes.

BodySeek is currently in the Single-User Daily Driver stage (`ADR 0009`) on iPhone 16 Pro running iOS 26/27. Meanwhile, the pure domain core (`BodySeekDomain`), HealthKit two-pass sync, SwiftData V3 schema (`32` models), `TodayStore`, `TrendsStore`, `DailyOperatingPlan`, and `CoachChatVM` / `AgentLoop` are already cleanly separated from the UI layer.

## Decision

1. **Raise the iPhone deployment floor to `iOS 26.0`** (`IPHONEOS_DEPLOYMENT_TARGET = 26.0` on `Vela`, `VelaTests`, and `VelaUITests`). `VelaWatch` remains on `watchOS 10.0` (or may adopt progressive enhancements independently) and `BodySeekDomain` retains Foundation-only portability so `swift test` continues running cleanly on macOS.
2. **Adopt Apple iOS 26 Native Shell Architecture**:
   - Replace the custom top segmented bar and persistent bottom `AskBar` capsule with Apple's native iOS 26 Liquid Glass `TabView`: `今日` (Today), `趋势` (Trends), `计划` (Plan), plus a dedicated trailing `Tab("问身体", systemImage: "sparkles", role: .search)` button for `Coach`.
   - Use `.tabBarMinimizeBehavior(.onScrollDown)` and standard `NavigationStack` titles, native toolbars (`ToolbarSpacer`), sheets, and system grouped backgrounds.
   - Contextual metric/trend/plan drill-downs continue passing structured `CoachScreenContext` directly into Coach without forcing a permanent bottom chat bar on every screen.
3. **Rescind Design D Monochrome Restrictions in Favor of Adaptive Bevel-Inspired Clarity + Rich Visualization**:
   - Use Apple system grouped surfaces (`systemGroupedBackground` `#F2F2F7` light / `#000000` dark and `secondarySystemGroupedBackground` `#FFFFFF` light / `#1C1C1E` dark) paired with SF Pro typography and SF Rounded numerals.
   - Restore the five semantic health domain hues across iOS views: Recovery (emerald), Sleep (indigo), Strain (flame orange), Physiological Stress (coral rose), and Energy (warm amber).
   - Prioritize rich, honest Swift Charts visualizations across Today, Trends, Plan, and Metric Details (score rings, intraday stress/energy sparklines and area charts, sleep stage timelines, personal baseline bands, interactive crosshair inspection, heart-rate zone bars, and training heatmaps).
4. **Preserve Scientific, Domain, and AI Ownership Invariants**:
   - `BodySeekDomain`, deterministic scoring formulas, `unknown` vs `knownZero` vs `excluded(reason)` truth semantics, no aggregate total health score, no biological age on primary surfaces, SwiftData V3 schema (`32` models), and user-confirmed Plan/Memory changes remain unchanged.
5. **Streamline UI Codebase and Upgrade Brand Identity**:
   - Refactor and consolidate legacy `Features/Minimal` dead views and duplicated Design D wrappers into clean, modular native surfaces, and adopt the unified "Precision Dual-Arc Rhythm B" (`BodySeekIcon.icon` / `AppIcon` / `BodySeekBrandMark`) identity.

This decision supersedes the iOS 17 floor and Design D monochrome / anti-TabBar UI constraints of `ADR 0017` and `ADR 0012` while preserving `BodySeekDomain`, `ADR 0001–0011`, and the PR0–PR8 domain separation achievements.

## Consequences

- Devices running iOS 17–25 can no longer run the updated `Vela` iOS target; all production iOS views can use iOS 26 SwiftUI Liquid Glass and native `TabView` / `Charts` APIs directly without `#available` fragmentation.
- `docs/PRD.md`, `docs/VELA_DESIGN_LANGUAGE.md`, `VelaThemeTests`, and `VelaSmokeUITests` are updated alongside the redesign so product specs, tests, and implementation remain aligned.
