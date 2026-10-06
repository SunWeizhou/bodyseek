# Vela Health Intelligence — Domain Glossary

> Status: Canonical
> Last verified: 2026-10-06
> Scope: Vela 全局唯一领域术语定义与受控词汇表（Domain Ubiquitous Language）
> Does not define: 页面结构与 UI 组件（见 [docs/PRD.md](docs/PRD.md)）、代码实现细节（见 [docs/TECH_ARCHITECTURE.md](docs/TECH_ARCHITECTURE.md)）

BodySeek（工程身份 Vela）是建立在 Apple 健康之上的个人身体状态仪表与 AI 分析助手：用个人长期数据量化当下状态，让用户为真实感受找到客观线索，而不是把疲惫或不适简单归咎于意志力；Agent 负责解释、追问与把理解转化为可调整的日常计划。

> 核心原则：不做只陈列指标、不能解释个人状态和变化的健康数据面板。
> 价值层级：1. 看见身体数据 → 2. 理解当前状态与长期趋势 → 3. 由 Agent 解释原因并联系不同信号 → 4. 在需要时给出训练与生活建议。

## Language

### Product identity

**BodySeek**:
对外发布的产品名称；指向五项独立身体状态评分、个人基线、趋势和行动解释组成的产品体验。
_Avoid_: BoySeek, Vela（在对外产品文案中）

**Vela**:
当前工程、仓库、Xcode 项目、bundle identity 和既有 Swift 类型使用的名称；在未完成独立迁移前不做全局重命名。主屏幕显示名是 BodySeek，iPhone bundle 仍是 `com.sunweizhou.Vela4`。
_Avoid_: 把 Vela 与 BodySeek 当成两个产品

### Product boundary

**Primary User**:
The owner-developer whose real Apple Watch, training, research-work, eating, and recovery routines define Vela's current product requirements. Hypothetical general users do not outweigh observed Primary User behavior during the personal Daily Driver phase.
_Avoid_: Target persona, early adopter cohort, average user

**Trusted Health Brief Day**:
A day when Vela reliably answers three fundamental questions for the Primary User: (1) How am I overall right now? (2) What has changed recently? (3) Do I need to take action? A day where state is stable and no plan change is needed is just as valuable as a day requiring a decision.
_Avoid_: Active day, engagement day, compliant day, decision-only day

### Health evidence

**Health Signal**:
A measured or user-entered health fact with a source, timestamp, freshness, unit, and availability state. Missing data stays missing; it is not written as 0 and it is not forged.
_Avoid_: Metric value, raw field, data point, missing-as-zero

**Daily Health Snapshot**:
The normalized set of Health Signals assigned to one calendar day before scores or recommendations are derived.
_Avoid_: Daily record, summary row, cache entry

**Personal Baseline**:
The slowly adapting historical reference used to interpret a Health Signal or Scored Health Evidence relative to the same person. It is protected from abrupt single-day shifts and never represents a population diagnosis.
_Avoid_: Normal range, standard value, average user

**Personal Baseline Deviation**:
An unusual departure from the Primary User's Personal Baseline, detected for a Health Signal or Scored Health Evidence time series. It means "unusual for you", not automatically "bad", "dangerous", or medically abnormal; validated absolute safety rules remain a separate concern.
_Avoid_: Abnormality, danger alert, diagnosis, bad score

**Data Coverage**:
The explicit account of which required Health Signals are available, fresh, and authorized for a calculation.
_Avoid_: Data quality score, completeness guess

### Daily interpretation

**Daily Health Computation**:
The single deterministic transformation from a Daily Health Snapshot plus Personal Baselines into scored health evidence. It owns missing-data rules and produces the same result for foreground refresh, background sync, and historical backfill.
_Avoid_: Metric pipeline, score factory, dashboard calculation

**Scored Health Evidence**:
The five independently interpretable 0–100 results produced by Daily Health Computation: Recovery, Sleep, Strain, Physiological Stress, and Energy. Each result carries direction, confidence, Data Coverage, contributing Health Signals, Personal Baseline comparisons, an algorithm version, and a data window. Vela does not collapse these results into one total health score: higher Strain means more load and higher Physiological Stress means more concern, so a single total would create false precision.
_Avoid_: Overall health score, readiness total, wellness grade

**Body State**:
A conservative, uncertainty-aware interpretation of the body's current latent condition from the five Scored Health Evidence results, their Personal Baseline Deviations, Data Coverage, and optional Lived State. Body State is not directly measurable, is not assumed to follow one permanent formula, and never becomes a sixth or aggregate score.
_Avoid_: Readiness score, diagnosis, physical condition, fixed latent variable, total score

**Health Trend Finding**:
A multi-scale (7d, 30d, 6m, 3y) statistical finding for a specific health metric, capturing direction, magnitude, baseline deviation, historical percentile position, and uncertainty.
_Avoid_: Raw difference, isolated daily variance

**Personal Health Brief**:
The canonical, structured daily intelligence object answering "How am I overall? What is changing? Is it noteworthy? What might be driving it? Does it need action?". Consumed synchronously by Today, Trends, Plan, and Coach.
_Avoid_: Workout prescription, isolated score summary

**Lived State**:
The Primary User's optional self-reported felt experience after seeing the computed evidence: consistent with the scores, feeling worse, feeling better, or uncertain, with optional detail such as mental stress, soreness, perceived energy, appetite disruption, and felt recovery. It calibrates interpretation; absence is unknown rather than zero, and disagreement with Body State never invalidates the user's experience.
_Avoid_: Mood score, emotion diagnosis, subjective readiness

**Personal Response Model**:
The evolving, uncertainty-aware account of how the Primary User's Health Signals, Lived State, Training Constraints, actions, and later responses relate over time. It supports future decisions but does not convert correlations into diagnoses or permanent traits.
_Avoid_: Digital twin, personality model, user score

**Personal Response Insight**:
A concise, testable claim derived from the Personal Response Model when it is relevant to a current decision. It stays implicit in the primary journey, while an on-demand evidence view exposes supporting observations, confidence, and controls to rate or correct the claim.
_Avoid_: Profile card, hidden label, permanent conclusion

**Training Decision**:
The canonical daily choice to keep, reduce, swap, or recover, with reasons and confidence grounded in Body State and Data Coverage.
_Avoid_: AI recommendation, workout verdict, readiness label

**Daily Operating Plan**:
A locally available plan created for every day that protects Health Rhythm through one primary action and at most two supporting actions across training, movement, eating, stress recovery, and sleep. Deterministic evidence establishes safety constraints, the Agent expresses and organizes them naturally, and the Primary User may edit, delete, reschedule, or replace any action. A saved canonical action sequence stays in place when body state changes; Plan shows a candidate instead of replacing it. It does not become a general work or calendar manager.
_Avoid_: Today card, generated brief, coach plan, silent regeneration

**Plan Proposal**:
A reviewable, material candidate change to an existing Daily Operating Plan produced from new context or Coach reasoning. It shows the proposed diff and expected trade-offs, but becomes canonical only after explicit user confirmation; direct user edits do not require Agent approval.
_Avoid_: AI override, automatic plan, chat suggestion

**Health Rhythm**:
The sustainable pattern formed across sleep, eating, work stress, movement, training, and recovery over time. When short-term fat loss, training continuity, and recovery conflict, Vela protects or restores Health Rhythm before optimizing the narrower goal.
_Avoid_: Perfect routine, wellness score, daily compliance

**Compensatory Action**:
An exercise or eating restriction performed primarily to cancel out a perceived dietary failure. Vela does not prescribe Compensatory Actions; it redirects the Daily Operating Plan toward normal eating, proportionate movement, and recovery.
_Avoid_: Calorie correction, punishment cardio, earning food

**Daily Check-in**:
A low-friction entry for recording Lived State or exceptional life context. It appears after the objective scores, may strengthen or change a Daily Operating Plan, and may be skipped without blocking guidance or implying that an unreported condition is absent.
_Avoid_: Required questionnaire, daily compliance task, assumed zero

**Proactive Touchpoint**:
A bounded, optional moment when Vela surfaces information without requiring the user to open the app first. The default cadence is one morning plan, one post-session annotation invitation, and a conditional evening adjustment only when available evidence would materially change the Daily Operating Plan.
_Avoid_: Continuous coaching, engagement notification, mandatory reminder

### Eating context

**Eating Rhythm**:
The sustainable pattern of regular, sufficient, and proportionate eating across days. Vela interprets Eating Rhythm alongside stress, sleep, training, and recovery rather than reducing it to a daily calorie target.
_Avoid_: Diet compliance, calorie score, clean eating

**Eating Disruption**:
A user-reported departure from Eating Rhythm, such as overeating, binge eating, skipped meals, or irregular eating. It is contextual evidence for restoring Health Rhythm, not a moral failure and not a trigger for a Compensatory Action.
_Avoid_: Cheat meal, bad day, dietary failure

**Meal Detail**:
Optional information about a meal, including foods, portions, photos, calories, or nutrients. Meal Detail may improve an explanation but is never required for Vela to recognise an Eating Disruption or provide guidance.
_Avoid_: Required food log, exact intake, inferred consumption

### Training loop

**Training Rotation**:
The user's intended repeating sequence of strength-training focuses. It expresses continuity without fixing each focus to a calendar date, so a Training Decision may delay, reduce, or temporarily substitute the next focus without losing the underlying sequence.
_Avoid_: Fixed schedule, generated program, weekly calendar

**Session Focus**:
The body region or training purpose actually emphasized in a Training Session, such as back, chest, shoulders, legs, accessory muscles, or cardio. A generic activity record does not establish Session Focus unless the user or a linked data source supplies it.
_Avoid_: Workout type, exercise list, inferred muscle group

**Training Constraint**:
A temporary factor that may change the next Training Decision, including incomplete recovery, poor sleep, physiological or mental stress, pain, low motivation, schedule pressure, or disrupted nutrition. It is current context, not a stable trait or diagnosis.
_Avoid_: Excuse, readiness factor, permanent limitation

**Training Session**:
A real-world workout completed by the user and observed by Vela through an external activity record. Vela does not require phone-based exercise, set, repetition, or rest-timer tracking during the session.
_Avoid_: Active workout, in-app workout, training draft

**Training Observation**:
The evidence Vela receives after a Training Session, combining the imported activity record with any optional user-reported experience. It is the factual basis for post-training interpretation and later calibration.
_Avoid_: Workout log, completed plan, execution record

**Session Annotation**:
User-supplied context attached after a Training Session. Its quick layer identifies Session Focus and overall experience; an optional detail layer may add exercises, weights, sets, and a free-form reflection without turning in-session phone logging into a requirement.
_Avoid_: Mandatory workout log, active set tracking, training diary

**Post-Training Check-in**:
A low-friction account of perceived effort, fatigue, pain, and relevant context after a Training Session. It forms the subjective part of a Session Annotation, may be skipped or completed later, and never blocks importing or analysing the session.
_Avoid_: Workout logger, set log, mandatory feedback

### Coach memory

**Agent Fact Snapshot**:
The locale-neutral, deterministic projection used by every AI workflow. It includes the five Scored Health Evidence results and contributors, Personal Baselines and deviations, multi-scale findings, recent daily aggregates, Data Coverage and freshness, Lived State, Training Observations, Daily Operating Plan edits, and confirmed memory or Personal Response Insights. Its semantic content hash excludes snapshot creation time; workflows may query bounded time-series detail through tools instead of uploading raw HealthKit samples.
_Avoid_: Prompt context, context JSON, AI summary

**Coach Artifact**:
A structured, reviewable output produced by the Coach, such as a readiness explanation, training adjustment, or review.
_Avoid_: AI message, report blob, recommendation card

**Memory Proposal**:
A candidate long-term fact or preference that requires user confirmation before it becomes canonical Coach memory.
_Avoid_: Automatic memory, wiki update, inferred profile

## Flagged ambiguities

- “Summary” previously meant both a Daily Health Snapshot and the scored dashboard projection. Use **Daily Health Snapshot** for evidence before computation; use the concrete projection type for display-only output.
- “Readiness” previously referred to a score, a Body State, and a Training Decision. Use **Body State** for interpretation and **Training Decision** for the actionable choice.
- “Score” without a domain is ambiguous. Name the specific **Scored Health Evidence** result: Recovery, Sleep, Strain, Physiological Stress, or Energy.
- “生活健康” is too broad for a product decision. Use **Health Rhythm** when referring to the cross-domain pattern Vela protects across sleep, eating, work stress, movement, training, and recovery.
- “感觉” is ambiguous. Use **Lived State** for the user's reported experience and **Body State** for Vela's evidence-grounded interpretation; disagreement between them is information to learn from, not an error to hide.
- “异常” is ambiguous. Use **Personal Baseline Deviation** for "unusual for this person" and reserve a safety notice for a separately validated absolute safety rule.
- “AI 计划” hides ownership. Use **Daily Operating Plan** for the user-owned canonical plan and **Plan Proposal** only for a material Agent-suggested diff awaiting confirmation.

## Example dialogue

> **Domain expert:** Today has fresh sleep and resting heart rate Health Signals, but HRV is unavailable, so Data Coverage is partial.
>
> **Developer:** Daily Health Computation will use the same missing-data rule during foreground refresh and historical backfill, then produce Body State with reduced confidence.
>
> **Domain expert:** Correct. The Training Decision may reduce training, and the Daily Operating Plan must show why. The user completes the Training Session without needing the phone; Vela later builds a Training Observation from the imported activity and any optional Post-Training Check-in. The Coach may create a Coach Artifact, but any long-term inference remains a Memory Proposal until the user confirms it.
