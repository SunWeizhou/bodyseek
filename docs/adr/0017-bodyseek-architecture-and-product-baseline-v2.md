# 0017. BodySeek architecture and product baseline v2

## Status
Superseded by [ADR 0018](0018-ios26-native-architecture-and-bevel-visual-reset.md)（iOS 26 原生壳层与部署底线）与 [ADR 0019](0019-bodyseek-v5-architecture-and-modeling-baseline.md)（BodySeekKit / GRDB / Agent / 个人建模基线）。本文件保留 2026-11-16 的历史决策与迁移顺序；平台底线、持久化与模块边界以 0018/0019 为准。

## Context

The repository has a stable Vela implementation and a canonical five-score
Today/Trends product direction, but earlier proposals left the external name,
shipping floor, and architecture transition order ambiguous. A Big Bang rewrite
would make the existing release evidence and algorithm behaviour harder to
trust. The team needs one durable baseline for parallel agents before the next
architecture wave begins.

## Decision

1. The external product name is **BodySeek**. The repository, Xcode project,
   bundle identity, and existing Swift symbols remain **Vela** until a separate
   rename migration is approved.
2. The current shipping floor remains **iOS 17 / watchOS 10** with Swift 6 and
   Xcode 26.x. iOS 26 capabilities may be progressive enhancements; raising the
   minimum deployment target requires its own ADR, PR, and device evidence.
3. The target architecture is an **Apple-native modular monolith with a pure
   domain core**. The first compile-protected module is a local
   `BodySeekDomain` Swift Package that initially imports Foundation only.
   Features depend on the domain and design system; data adapters depend on the
   domain; the domain does not depend on SwiftUI, UIKit, SwiftData, HealthKit,
   or UserDefaults. No third-party DI framework or cross-platform rewrite is
   introduced.
4. Today and Trends remain P0. The five scores—Recovery, Sleep, Strain,
   Physiological Stress, and Energy—stay independent; no aggregate score or
   Health/Biological Age enters the formal product. Plan, Coach, Nutrition, and
   Experiments remain bounded downstream capabilities and must not expand the
   Dashboard main chain during this architecture wave.
5. The migration order is staged: PR0 facts and golden baselines; PR1 domain
   extraction; PR2 explicit dependencies; PR3 Today state/store; PR4 3+2
   Dashboard; PR5 Trends state/store; PR6 persistence/sync concurrency; PR7
   score contract v2; PR8 one algorithm at a time; PR9 release quality. No
   scoring formula changes are bundled with domain extraction or UI rewrites.
6. SwiftData remains behind repositories or ModelActor-owned adapters. Feature
   Views consume ViewState and emit Actions; SwiftData models and raw HealthKit
   samples do not cross feature or actor seams.

This decision supersedes the earlier iOS 26 floor direction and the subsequent
product/platform proposals in ADR 0013, ADR 0014, and ADR 0015. It incorporates
the bounded Widget preview intent from ADR 0016 without making a Widget
extension part of the current critical path.

## Consequences

- Parallel agents get a stable vocabulary and dependency direction while the
  current Vela release remains buildable.
- Existing scoring formulas are protected until old outputs, fixtures, and
  replay evidence are captured.
- The first architectural deliverable is a small, reviewable Domain Package,
  not a repository-wide rename or a collection of empty packages.
