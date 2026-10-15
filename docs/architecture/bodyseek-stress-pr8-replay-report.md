# BodySeek ARCH-08 / PR8 Stress replay evidence

Status: `StressIndexEngine` and `StressIndexInput` live in `BodySeekDomain`.
The app `StressIndexEngine` maps the domain result back to the app
`MetricResult`. `BodySeekDomain.DailyHealthComputation` still leaves the
stress slot unavailable; production scoring remains the app
`DailyHealthComputation`. No scoring formula change is included. The emitted
algorithm version remains `ScoringAlgorithmVersions.physiologicalStress`
(`physiologicalStress.v2.0.0`).

The replay evaluates at `2026-07-31T12:00:00Z`. The canonical fingerprint is
recorded in `docs/baselines/stress-replay-fixtures.json`. Package assertions
are `BodySeekDomainTests/StressReplaySensitivityTests`. App adapter assertions
are `VelaAppTests/StressReplaySensitivityTests`.

## Deterministic baseline

Quiet heart rate 62 against baseline 58 (SD 3), HRV 45 against baseline 50
(SD 8), respiratory rate 15 against 14 (SD 0.8), temperature delta +0.2°C,
sleep score 77.43, and strain score 65.53. The input is outside the workout
window and has no long-term heart-rate gate.

The oracle returns `56.2142645029`, confidence `high`, and no missing inputs.

## Sensitivity evidence

| Case | Controlled change | Value | Confidence |
| --- | --- | ---: | --- |
| baseline | none | 56.2142645029 | high |
| high-rhr-72 | quiet heart rate 72 | 62.7142645029 | high |
| low-hrv-28 | HRV 28 | 65.751 | high |
| high-temp-1.1 | temperature delta +1.1°C | 62.2142645029 | high |

A long-term quiet-heart-rate median of 72 neutralizes the short-term RHR
component to 50 when today's quiet heart rate is 70. Inside the workout
window the result stays `nil`, coverage is `unavailable`, formatted score is
`--`, and the missing input is `quietWindow`. No excluded value is coerced
to zero.

Focused command:

```text
swift test --package-path BodySeekDomain --filter StressReplaySensitivityTests
```
