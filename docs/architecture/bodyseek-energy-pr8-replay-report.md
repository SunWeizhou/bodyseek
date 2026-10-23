# BodySeek ARCH-08 / PR8 Energy replay evidence

Status: `EnergyBankEngine` and `EnergyBankInput` live in `BodySeekDomain`.
The app `EnergyBankEngine` maps the domain result back to the app
`MetricResult`. `MetricConfidence` and `TrainingLoadStatus` are domain
types, aliased in the app so existing callers keep compiling.
`BodySeekDomain.DailyHealthComputation` still leaves the energy slot
unavailable; production scoring remains the app `DailyHealthComputation`.
No scoring formula change is included. The emitted algorithm version remains
`energy.v2.1.0`. The domain constant previously said `energy.v2.0.0`; it now
matches the production constant.

The replay evaluates at `2026-07-31T12:00:00Z`. The canonical fingerprint is
recorded in `docs/baselines/energy-replay-fixtures.json`. Package assertions
are `BodySeekDomainTests/EnergyReplaySensitivityTests`. App adapter assertions
are `VelaAppTests/EnergyReplaySensitivityTests`.

## Deterministic baseline

Recovery 70, sleep 80, strain 40, stress 30, HRV 50/50, resting heart rate
58/60, fourteen prior daily loads of 60, today load 55, temperature delta
+0.2°C, 8 hours since waking, respiratory-rate Z 0.2, and SpO2 98.

The oracle returns `53.2`, confidence `high`, morning energy `80.7`, ATL
`58.75`, CTL `59.7674418605`, TSB `1.0174418605`, and ACWR `0.9848265896`.

## Sensitivity evidence

| Case | Controlled change | Value |
| --- | --- | ---: |
| baseline | none | 53.2 |
| high-strain-80 | strain score 80 | 39.2 |
| elevated-load | training-load status elevated | 48.2 |

When recovery and sleep are both missing, the result stays `nil`, coverage is
`unavailable`, and the formatted score is `--`. No missing upstream score is
coerced to zero.

Focused command:

```text
swift test --package-path BodySeekDomain --filter EnergyReplaySensitivityTests
```
