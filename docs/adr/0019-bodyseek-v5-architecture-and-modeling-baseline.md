# 0019. BodySeek V5 Architecture, GRDB Persistence, Native Visualization, Watch-First Fitness, and Personal Modeling Baseline

- **Status**: Accepted
- **Date**: 2026-11-19
- **Supersedes / Updates**: Updates ADR 0012 (primary Tab layout & plan surface placement), ADR 0017 (legacy `BodySeekDomain` / SwiftData wording), and ADR 0018 (SwiftData V3 32-model preservation & Tab 2 Plan wording); keeps ADR 0001–0011 core domain/safety/AI-ownership invariants intact.

## Context

Between 2026-11-16 and 2026-11-19, the BodySeek/Vela repository underwent a major structural reset (`commit a9f32e64`): ~60k lines of legacy handwritten UI/domain code (`VelaApp/`, `BodySeekDomain/`, `VelaWatch/`) were replaced by a modular Swift 6 package `BodySeekKit` built on Point-Free TCA and Stanford `SpeziHealthKit`, with the four root iOS 26 Liquid Glass tabs becoming `今日` / `健身` / `趋势` / `问身体`.

However, an engineering audit (`bodyseek_v4_review.md`) and real-device usage on `iPhone 16 Pro` + `Apple Watch` identified critical mismatches and product gaps:
1. Documentation (ADR 0017/0018, PRD, `TECH_ARCHITECTURE`, model cards) still described deleted `BodySeekDomain`, `VelaWatch`, 32 SwiftData models, and a standalone `计划` tab while actual production scoring used `BevelScoringEngine` and SwiftData JSON blobs (`FitnessStoreClient`).
2. Interactive fluidity suffered due to eager multi-canvas chart rendering, uncached reducer computed properties (`TrendsFeature.activeSeries` / `allMetricSeries`), and unthrottled HealthKit updates.
3. Charts wrapped stock-ticker library `liveline-swift`, creating a hand-rolled visual feel rather than native Apple Fitness / Apple Health design quality.
4. `CoachAIClient` temporarily stored the cloud API key in `UserDefaults`, pulled heavy `SpeziLLM` / OpenAPI generator transitive dependencies, and lacked deterministic evaluation gates and numeric provenance checks.
5. Real 3-year exported HealthKit data (`3,140,392` records across `1,180+` days, `2,001` workouts, `496` `WorkoutEffortScore` entries, plus `PhysicalEffort` and `AppleSleepingWristTemperature`) highlighted missed physiological signals and motivated a rigorous, baseline-first personal modeling roadmap rather than premature black-box deep learning or invalid observational counterfactual claims.

## Decision

### 1. Target Unidirectional Module Architecture (`BodySeekKit` + Thin `VelaApp` Shell)
All production logic converges onto a clean acyclic dependency graph inside `BodySeekKit` (with incremental splitting — no empty packages):
- **`BodySeekCore`** (pure `Foundation`, runs via `swift test` on macOS): shared canonical contracts (`DayKey`, `HealthObservation<Value>`, `Provenance`, `AlgorithmVersion`, `ActionProposal`, `MetricContributor`), deterministic `score-v2` engine (`BevelScoringEngine`), rolling baselines, TRIMP/ACWR, `recovery-heuristic-v1`, pattern findings, and shared `feature_spec` calculations. (`HealthObservation` avoids shadowing Apple's system `Observation` module under `@Model` / `@Observable`.)
- **`BodySeekStore`** (split in M1): GRDB 7 SQLite database (`DatabaseMigrator`), typed tables & foreign keys, `ActionAuditLog`, precomputed `ReadModel` / `ChartSeriesSnapshot` via `ValueObservation`.
- **`BodySeekHealth`**: `SpeziHealthKit` adapter, `SyncEngine` actor with `HKAnchoredObjectQuery` incremental sync + 3s debounce, resumable 3-year monthly backfill, `sleepMergePolicy` overlap dedup, and `KeychainService` credential storage.
- **`BodySeekAgent`** (split in M3 when removing `SpeziLLM`): lightweight `OpenAICompatibleClient` (`URLSession` + `Codable`) + Apple `FoundationModels` with explicit degradation logging (never `try?`), task-oriented read tools, proposal generators, numeric provenance validator, 3-tier memory, and evaluation harness.
- **`BodySeekDesign`** (split in M1-UI): design tokens & `BodySeekChart` native Swift Charts family governed by `docs/design/chart-grammar.md`.
- **`BodySeekFeatures`**: TCA Reducers + L1/L2/L3 depth Views (`Today`, `Workout`, `Trends`, `Coach`, `Settings`) with zero derived calculations in View body or Reducer state.

### 2. Data Truth, Time Cutover & Versioning Invariants
- **Four-state truth**: `HealthObservation<Value>` carries `.available`, `.knownZero`, `.missing`, and `.excluded`, propagated from HealthKit → GRDB → `BodySeekCore` → `BodySeekChart` → Coach tools → ML missingness masks.
- **Physiological `DayKey`**: Defaults to `04:00` local time cutover (`year-month-day`), paired with UTC timestamps and `TimeZone` metadata.
- **Algorithm versioning**: Every scoring, sleep-merge, muscle-recovery, NL-parser, and ML artifact carries explicit `AlgorithmVersion`; changes require replay comparison in `docs/validation/` and updated model cards.
- **No swallowed errors**: Persistence, Keychain, HealthKit, network, and model execution paths never use silent `try?`; failures surface to logs and visible UI state.

### 3. Persistence: GRDB 7 Direct (Replacing SwiftData JSON Blobs)
- Adopt `groue/GRDB.swift` (v7.x) for typed relational schema, `DatabaseMigrator` migrations, transactions across annotations + muscle load + audit logs, FTS5 search, and zero-stall cold-start snapshot reads.
- **Boundary**: HealthKit remains the sole source of truth for raw high-frequency heart rate samples; SQLite stores derived daily/hourly aggregates, deduped sleep episodes, workout summaries, user/AI records, confirmed proposals, audit logs, and versioned score snapshots.

### 4. Apple Fitness Native Visualization & 120fps Performance
- **Charts**: Remove `liveline-swift` in M1-UI (and evaluate/remove `SleepChartKit` in favor of unified native styling). Standardize all charting inside `BodySeekChart` built purely on Apple `Swift Charts`, designed against `docs/design/chart-grammar.md` and benchmarked against `docs/design/references/`. Feature modules must not construct raw `Chart {}` directly.
- **Three-ring semantics**: Today L1 Recovery / Sleep / Strain rings communicate independent physiological states (including baseline balance), NOT "close-the-ring daily compliance goals".
- **Instruments budgets (measured on iPhone 16 Pro Release)**: cold start to first cached frame `≤ 400 ms`, tab switch `≤ 100 ms` hitch-free, chart scrub/scroll hitch ratio `< 5 ms/s`, `3y` horizon switch `≤ 150 ms`, and zero redundant UI refreshes when HealthKit content hash is unchanged. Tracked via `os_signpost`.

### 5. Watch-First Fitness & Dynamic Muscle Recovery
- **Collection**: Native Apple Watch Workout app + HealthKit remains primary (`VelaWatch` stays retired). Existing `ActiveWorkoutSheetView` and `RestTimerClient` are demoted to manual fallback entry rather than deleted.
- **Post-workout flow**: Unreviewed strength/mixed Watch workouts enter an Inbox on `健身`; users log a single sentence (text or dictation) parsed via `FoundationModels` (`@Generable`) with deterministic Chinese exercise lexicon fallback (`≥ 50`-sample offline benchmark), producing a user-confirmable `ActionProposal`.
- **Badminton lateralization**: Default `dominantHand = .right` (configurable in Settings) assigns dominant shoulder rotator-cuff and forearm load alongside lower-body load.
- **Heuristic muscle recovery (`recovery-heuristic-v1`)**:
  $$F_m(t) = \sum_i L_{m,i} \exp\!\left(-\frac{t - t_i}{\tau_m \cdot \alpha_{\text{sys}}}\right), \qquad R_m(t) = \exp\!\left(-F_m(t)\right)$$
  where $\alpha_{\text{sys}}$ reads strictly prior-night sleep and HRV baseline deviation (never same-day Recovery score, avoiding circularity), and UI explicitly labels outputs as heuristic estimates (`启发式估计`).
- Distinguish user-entered `WorkoutEffortScore` from Apple `EstimatedWorkoutEffortScore`.

### 6. Daily Operating Plan Continuity & Primary Surfaces
- Primary tabs remain `今日`, `健身`, `趋势`, and `.search` `问身体`.
- **ADR 0007 / ADR 0008 continuity**: Instead of dropping plan ownership silently when retiring the standalone `计划` tab, the Daily Operating Plan (`plan_item`, 1 primary + up to 2 supporting actions) lives in the **Today action card (`今日行动卡`)** on `今日` L1, with user edits preserved and AI modifications surfaced only as reviewable `ActionProposal` diffs.

### 7. Coach Agent Architecture, Security & Evaluation
- API Key stored strictly in Keychain (`com.sunweizhou.Vela4`); migrate and purge legacy `UserDefaults` key.
- Default cloud LLM endpoint is DeepSeek (`api.deepseek.com/v1`), receiving only aggregated tool outputs — never raw biometric sample streams — with full outbound payload inspectable in Settings.
- Remove `SpeziLLM`, `swift-openapi-*`, and `DynamicServerURLMiddleware` in M3; replace with custom tested `OpenAICompatibleClient` + recorded fixtures.
- Task-oriented typed read tools (`get_today_context`, `get_metric_trend`, `get_workouts_and_muscles`, `get_sleep_detail`, `get_patterns`, `find_similar_days`, reserved `get_eating_context`) + proposal-only write tools + numeric provenance checker (`未核实` flag on ungrounded numbers) + `BodySeekAgentEvals` (`≥ 30` cases, `≥ 85%` pass gate).

### 8. Personal Data Modeling (`BodySeekML/`) & Honest Science
- **Daily subjective labels**: Upgrade `CheckInSheetView` to collect daily energy, mood, stress, and muscle soreness (`DailyCheckIn`) starting in M0.
- **Baseline-first walk-forward evaluation**: Offline Python (`uv`, PyTorch/sklearn/LightGBM/coremltools) in `BodySeekML/` (raw `data/` strictly `.gitignore`d) compares Persistence, Ridge, Banister state-space, and LightGBM on strictly chronological expanding windows (e.g., 24m initial train, monthly walk-forward). Lightweight DL (Masked TCN / PatchTST-Lite) is a research track promoted/ensembled ONLY upon statistically significant paired-fold improvement over the best baseline.
- **No observational causal/counterfactual claims**: UI and Coach NEVER present observational predictions as causal "what-if" outcomes. Instead, pair `find_similar_days` (k historical similar states with outcome distribution & sample count `n`) with **N-of-1 Experiments** (`Experiments` template, baseline/intervention windows, pre-registered metrics, report).

### 9. Daily Nutrition & Energy Balance Integration (GRDB Schema v2, User-Requested 2026-11-19 Addendum)
- Integrating the user's validated Obsidian vault specification (`每日营养素`: `AGENTS.md`, `营养目标.js`, `food_database.md`) directly into `BodySeekCore` and GRDB Schema `v2_nutrition_schema` rather than deferring to a disconnected post-V5 project.
- Three-role Agent workflow preserved explicitly: `nutrition-library` (traceable per-100g/100mL food database + chemical forms), `health-record` (meal logging, portion scaling, three orthogonal completion flags `diet_day_complete` / `diet_partial_fields` / `health_confirmed_fields`), and `health-coach` (personal DRIs target generation, weekly/monthly board review, recovery-aware nutrition & workout advice).
- Non-fabrication & energy invariants: `missingAsZero = false` for nutrient metrics; incomplete or unclosed days display `unknown` (`暂不判断`); `calorie_surplus_kcal` (`diet_kcal - (bmr_kcal + sport_kcal)`) is computed ONLY when intake closure (`diet_day_complete == true`), BMR reference, and full-day expenditure are present — never replacing total energy expenditure with single-session exercise calories or incentivizing compensatory starvation/cardio.
- Reserved Coach tool name `get_eating_context` (implemented in M3 alongside M1-UI nutrition dashboard views).

## Consequences
- All M0–M4 implementation PRs have one single canonical architectural and scientific baseline (`ADR 0019` + V5 Blueprint).
- Legacy `BodySeekDomain` vs `score-v2` shifts are quantified transparently via 3-year real-data replay before any ML baseline is trained.
- Raw user health archives (`/Users/sunweizhou/Downloads/导出.zip`, XML, ECG, GPX) remain strictly local and excluded from version control.
