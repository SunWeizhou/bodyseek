# BodySeekDomain

`BodySeekDomain` is the Foundation-only domain package in the BodySeek
(engineering identity: Vela) migration. It targets iOS 17 and watchOS 10 with
Swift tools 6.0 and is linked from `Vela.xcodeproj`.

## Scope

- Public, `Codable`/`Hashable`/`Sendable` evidence values:
  `DailyHealthSnapshot`, `WorkoutSummary`, sleep values, and score metadata.
- Shared score semantics: `MetricResult`, `ScoringMath`, independent domain
  identifiers, data coverage, missing-value (`nil`) behavior, and algorithm
  version constants.
- `ScoringMath` owns clamping, score bands, confidence, and the shared
  median, sample standard deviation, and robust deviation. `DailyLoadObservation`
  is the evidence-preserving daily load value.
- Parity-preserving `SleepScoreEngine`, `RecoveryScoreEngine`,
  `StrainScoreEngine`, `StressIndexEngine`, and `EnergyBankEngine`. Formulas
  and algorithm versions stay unchanged. Each engine takes an explicit
  `Calendar`. Recovery and Strain use it only for the evidence window, Stress
  uses it for the exclusion and scoring windows, and Energy uses it for the
  legacy load-history dates and the evidence window. Heart-rate zone display
  stays in the app.
- `DailyHealthComputation` assembles all five independent scores. Callers pass
  an explicit recovery long-term context and quiet-heart-rate median. The empty
  `LongTermBaselineReport` value is ignored. No aggregate/readiness score is
  introduced.

## Boundaries

Production files import `Foundation` only. There is no HealthKit, SwiftData,
SwiftUI, UIKit, UserDefaults, ProcessInfo, persistence, networking, or global
singleton. Sleep target hours stay in the app settings adapter.
`LongTermBaselineReport` is still an empty seam placeholder. The median and
deviation statistics Recovery calls live in `ScoringMath`; the rest of the
long-term baseline report stays in the app.

`MetricResult` compatibility projections are optional or unknown-aware: an
unavailable result never projects to numeric `0`, a default strain range, or a
false state. `StandardScoreResult` remains a legacy adapter-only value for
incremental callers and is not used by `DailyHealthComputation`.

## Verification

```sh
swift test --package-path BodySeekDomain
swift build --package-path BodySeekDomain
git diff --check
```

The package replay tests assert Sleep `77.43` within `0.01`, Recovery
`68.8497077483` within `0.0000001`, Strain `65.5297799653` within
`0.0000001`, Physiological Stress `56.2142645029` within `0.0000001`, and
Energy `53.2` within `0.0000001`. The package golden fixture also matches the
production five-score oracle: sleep `77.43`, recovery `68.70`, strain `63.67`,
stress `21.08`, and energy `47.91`, each within `0.01`. An empty snapshot
still has nil values for every score.
