# BodySeek ARCH-08 / PR8 Recovery replay evidence

Status: RecoveryScoreEngine and the baseline math it calls now live in
`BodySeekDomain`. The app `RecoveryScoreEngine` maps the domain result back to
the app `MetricResult`. `BodySeekDomain.DailyHealthComputation` still leaves
the recovery slot unavailable; production scoring remains the app
`DailyHealthComputation`. No scoring formula or algorithm-version change is
included in this slice.

The replay evaluates at `2026-07-31T12:00:00Z` using the same inputs as
`docs/baselines/recovery-replay-fixtures.json`. Package assertions are
`BodySeekDomainTests/RecoveryReplaySensitivityTests`. App adapter assertions
remain `VelaAppTests/RecoveryReplaySensitivityTests`.

## Deterministic baseline

The replay evaluates at `2026-07-31T12:00:00Z` using a Gregorian UTC clock,
14-day HRV/RHR/respiratory histories, HRV 54 against baseline 50, RHR 57
against baseline 60, sleep 77.43, and yesterday's strain 52. The canonical
fingerprint is recorded in `docs/baselines/recovery-replay-fixtures.json`.

The oracle returns `68.8497077483`, confidence `high`, algorithm version
`recovery.v2.0.0`, and no missing inputs. Package assertions live in
`BodySeekDomainTests/RecoveryReplaySensitivityTests.swift`. App adapter
assertions live in `VelaAppTests/RecoveryReplaySensitivityTests.swift`.

## Sensitivity evidence

| Case | Controlled change | Value | Confidence |
| --- | --- | ---: | --- |
| baseline | none | 68.8497077483 | high |
| short-sleep-360 | sleep score 53.62 | 62.8972077483 | high |
| high-strain-90 | prior strain 90 | 59.6418762029 | high |
| high-temperature | temperature delta +1.0°C | 60.8497077483 | high |
| low-spo2 | SpO2 93% | 60.8497077483 | high |

When both cardiovascular signals are absent, the result remains `nil`, data
coverage is `unavailable`, formatted score is `--`, and both missing input
names are retained. No missing value is coerced to zero.

Focused command:

```text
xcodebuild test -project Vela.xcodeproj -scheme Vela \
  -destination 'platform=iOS Simulator,id=BCAD01D0-CB5A-4277-B622-269479D0E159' \
  -only-testing:VelaTests/RecoveryReplaySensitivityTests
```
