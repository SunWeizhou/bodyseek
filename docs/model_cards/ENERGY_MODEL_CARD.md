# Energy Bank 模型卡

> 当前生产版本：`energy.v2.1.0`（`VelaApp/Scoring/EnergyBank/EnergyBankEngine.swift`）。本版本只升级负荷数据语义、覆盖门控和解释链，未调整能量权重或主要扣减参数。

状态：工程模型；工程回归可验证；尚未完成临床、生化或主观疲劳金标准验证。该指标不能用于疾病诊断、医疗决策或医学级能量测量。

## 1. 用途与输入

Energy Bank 是 0–100 的日间身体能量代理，用于帮助安排当天的训练、工作和恢复。它接收恢复评分、睡眠评分、夜间体征、清醒时长、压力代理、当日训练负荷和有限的恢复行为输入。`strainScore` 只用于日间训练消耗；ATL、CTL、TSB、ACWR 使用 TRIMP 域的 `DailyLoadObservation`，不把 0–100 评分域当作训练负荷。

主要输入及单位：

- `recoveryScore`、`sleepScore`、`strainScore`、`stressIndex`：0–100 评分。
- `todayLoad` 及历史负荷：TRIMP 域数值。
- `hoursSinceWake`：小时；`mindfulMinutes`、`napMinutes`：分钟。
- `bodyTempDelta`、`respiratoryRateZ`、`SpO2`：夜间稳定性信号。

## 2. 输出与公式

有恢复或睡眠评分时，模型先计算早间能量。两者均有时：

```text
morningEnergy = 0.45 × recoveryScore
              + 0.35 × sleepScore
              + 0.20 × overnightStability
```

只提供其中一项时，使用该项 0.70 与夜间稳定性 0.30 的降级组合；两项都缺失时，Energy 的 `value` 为 `nil`。夜间稳定性有信号时从 100 扣除体温、呼吸率和血氧异常项；完全缺失时使用中性基准 50，并写入 `missingInputs` 和 `reasons`。

早间能量再按充能效率修正：`(chargeEfficiency - 0.6) × 12`。日间能量为：

```text
currentEnergy = clamp(
    morningEnergy
    - 0.35 × strainScore
    - 0.25 × stressIndex
    - clamp(hoursSinceWake / 16 × 12, 0, 12)
    - loadDrain
    + min(8, 0.15 × mindfulMinutes + 0.20 × napMinutes),
    0,
    100
)
```

当压力因运动窗口被排除且存在正向训练负荷时，压力扣减为 0，但不会把该压力观测解释成已测得的零；当压力缺失且没有运动证据时，保留缺失原因。训练负荷状态为 `elevated` 或 `highRisk` 时，`loadDrain` 分别为 5 或 10，其余状态为 0。

## 3. 训练负荷证据合同

计算层使用 `DailyLoadObservation`，不修改 SwiftData schema：

```swift
enum TrainingLoadAvailability {
    case observed       // 有真实负荷值
    case knownZero      // 数据源覆盖完整，明确当天负荷为零
    case missing        // 没有足够证据判断当天负荷
    case excluded       // 明确排除窗口或业务原因
}
```

`observed` 和 `knownZero` 可以进入 EWMA；`missing` 和 `excluded` 保留日期位置用于时间衰减，但不增加有效观测天数，也不构成“今天没有负荷”的解释。每条观测可带 `reason`、`observedWindow` 和日期，便于重放和证据展示。

历史网格按真实日历日期排序。缺失日期不会被压缩，也不会被改写为已观测零值。只有至少 7 个有效历史观测、且今日负荷为 `observed` 或 `knownZero` 时，Energy 才发布 `atl`、`ctl`、`tsb` 和 `acwr`；否则这些组件保持缺失，并同步记录 `missingInputs` 与原因。有效天数不足不会生成伪造的负荷状态。

## 4. 缺失、零值和不确定性

- 缺失不等于零：不可估计的组件不写入 `0.0`。
- 已知零是有效观测：它能进入历史 EWMA，并与缺失产生不同的有效天数和解释。
- 排除不是零：排除窗口会保留原因，不参与负荷判断。
- `confidence` 描述输出可信度，`dataCoverage`、`missingInputs` 和 `reasons` 描述证据覆盖；它们不替代彼此。
- `components` 只包含确实计算出的量。`MetricResult.value` 可以为 `nil`，页面和 Coach 必须传播“未知”状态。

## 5. 时间与版本政策

所有历史输入按评估时间 `asOf` 截断，未来日期不得进入当前能量或负荷基线。缺失日期允许时间衰减，但不改变有效观测统计。`energy.v2.1.0` 表示数据语义和输出覆盖契约升级；后续权重或公式变化必须单独升级版本，不能与语义修复混合发布。

2026-09-22 上游修订：`strain.v2.1.0` 保留全活动缺失日为 missing，`sleep.v2.2.0` 修正历史日历窗和时区传递，五项复合缓存版本随之更新，Energy 公式版本不变。已有明确零活动证据的七日历史仍按原规则处理。生产金样本的 snapshot 血氧单位由错误 0.98 改为 98 后，真实回放 Energy 从约 42.31 变为 47.91081014037653（+5.6），Recovery 从约 60.70 变为 68.69935060540107（+8）；这是 fixture 合同修复，不是精度或临床有效性提升。

## 6. 工程验证与边界

当前验证关注确定性回归、缺失诚实性、边界稳定性、版本和 provenance。正式 replay 资料必须同时记录五项评分、Energy 组件、覆盖、置信度、缺失输入、原因和算法版本；历史 `docs/validation/v1/replay_comparison.*` 仅作审计资料，不自动视为新版本 golden。

尚未完成临床标签、血乳酸、肌酸激酶、代谢测量或主观疲劳量表对照，因此不能宣称准确率、临床有效性或疲劳预测能力提升。咖啡因、酒精、主观动机、倒班和多相睡眠等因素也不在模型范围内。

## 7. 来源

- Borbély AA. A two process model of sleep regulation. *Hum Neurobiol*, 1982。该文仅支持睡眠过程的背景概念，不为本产品参数提供验证。
- Marcora SM, et al. Mental fatigue impairs physical performance in humans. *J Appl Physiol*, 2009。该文仅作为压力与主观用力关系的背景，不为本产品扣减系数提供验证。
