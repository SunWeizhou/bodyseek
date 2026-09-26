# Vela Core Metrics Scoring Specification v1.0

> Status: Historical design reference / reconciliation pending
> Last verified: 2026-08-21
> Scope: 核心生理评分算法（Sleep, Recovery, Strain, Stress, Energy, HealthAge）数学模型、基线逻辑与输入协议
> Does not define: 产品业务层级（见 [PRD.md](PRD.md)）、AI 交互协议（见 [AI_AGENT_SPEC.md](AI_AGENT_SPEC.md)）
> Medical Disclaimer: **Not a medical diagnostic system**. All scores are wellness proxies intended for personal lifestyle interpretation, athletic self-tracking, and trend observation.

> 接手说明（2026-09-06）：本文件含 HealthAge、Readiness Cockpit 和 v1 设计描述；当前产品范围以 PRD 为准，生产输出/版本以 `VelaApp/Scoring/ScoringCore.swift` 为准。本文尚未完成与当前源码的逐公式对齐，UI 不据此新增指标、阈值或重新计算分数。Energy 模型卡也存在版本差异，见 TAKEOVER 的 F5。

---

# 1. 统一输出协议 (MetricResult)

为了避免各个评分引擎各自为战，所有核心评分（睡眠、恢复、负荷、压力、精力、生物年龄）在底层及 API 数据交换层均通过统一的 `MetricResult` 数据格式对外暴露，确保可解释性与数据可审计性。

```swift
struct MetricResult: Codable, Hashable {
    var name: String                  // 指标名称 (e.g., "Sleep", "Recovery", "Strain")
    var value: Double?                // 0–100 综合得分；如果不可计算则为 nil
    var band: MetricBand              // veryLow / low / normal / high / veryHigh 等语义分档
    var confidence: MetricConfidence // low / medium / high
    var components: [String: Double]  // 各分项子分数
    var componentWeights: [String: Double] // 子分数对应权重系数
    var reasons: [String]             // 用户可读的成因解释列表（直接作为 AI Coach 的分析依据）
    var missingInputs: [String]       // 缺失的输入信号字段名称
    var dataWindow: DateInterval      // 用于计算该分数的数据时间跨度
    var source: MetricSource         // healthKit / userInput / derived / mixed
    var algorithmVersion: String      // 算法版本号 (e.g., "v1.3")
    var lastUpdated: Date             // 刷新时间
}
```

任何评分要呈现在 **Readiness Cockpit** (首页驾驶舱)，必须完全满足上述协议要求。

---

# 2. 睡眠分数 (Sleep Score v1.0)

Vela 舍弃了传统的 5 维均等分配模型，采用与 **Apple-compatible / Levine 兼容**的 3 因子模型，满分 100 分。

```text
SleepScore = DurationScore (0-50) + ConsistencyScore (0-30) + InterruptionScore (0-20)
```

## 2.1 时长分数 (Duration Score: 0–50)
评估昨夜睡眠时长与个人目标的契合度。
- **默认目标**：优先使用用户自定义目标；若未设置，则默认 `target = 450` 分钟 (7.5小时)。
- **计算算法**：
  - 若 `totalSleepMinutes` 缺失，则该分项为 `nil`。
  - 若睡眠时长在 `[target - 30, target + 60]` 区间，得满分 `50`。
  - 若睡眠少于 `target - 30`（睡太少，惩罚较重）：
    $$\text{durationScore} = 50 \times \text{clamp}\left(\frac{\text{totalSleepMinutes} - 240}{(target - 30) - 240}, 0, 1\right)$$
  - 若睡眠长于 `target + 60`（睡太多，轻度惩罚）：
    $$\text{durationScore} = 50 \times \text{clamp}\left(1 - \frac{\text{totalSleepMinutes} - (target + 60)}{240}, 0.35, 1\right)$$

## 2.2 作息一致性 (Consistency Score: 0–30)
评估入睡和起床时间偏离历史基线的程度。为了解决跨午夜（24:00）作息偏移，采用 **Circular Time** 空间映射算法：
- **正午基线偏移 (Minutes from Noon)**：
  将时间转换为以正午 12:00 为原点的分钟数（跨午夜时间加上 1440 分钟）。
- **算法细节**：
  1. 采用最近 13 晚有效 bedtime 集合，计算中位数作为滚动基线：`baselineBedtime = median(last13Bedtimes)`。
  2. 计算今日 bedtime 相对基线偏移：`diff = abs(todayBedtime - baselineBedtime)`。
  3. **等级分配**：
     - `diff <= 30` 分钟：`30` 分
     - `diff <= 60` 分钟：`24` 分
     - `diff <= 90` 分钟：`18` 分
     - `diff <= 120` 分钟：`12` 分
     - `diff <= 180` 分钟：`6` 分
     - 超过 180 分钟：`0` 分
  4. 若历史数据不足 5 晚，此分项输出 `nil`，且 confidence 强制降级。

## 2.3 睡眠中断分数 (Interruption Score: 0–20)
评估昨夜睡眠期间发生的清醒事件。
- **输入指标**：夜间清醒总时长 (`awakeMinutes`) 和持续 2 分钟以上的醒来次数 (`awakeEpisodeCount`)。
- **惩罚公式**：
  $$\text{penalty} = 0.45 \times \text{awakeMinutes} + 2.5 \times \text{awakeEpisodeCount}$$
  $$\text{interruptionScore} = \text{clamp}(20 - \text{penalty}, 0, 20)$$

## 2.4 缺省重归一化策略
若部分传感器数据（如睡眠阶段）不可用：
- `finalScore = sum(availableComponentScores) / sum(availableWeights) * 100`。
- Confidence 将降级为 `medium` 或 `low`，并在 UI 显著位置以气泡警示“缺少睡眠中断数据”。

---

# 3. 恢复分数 (Recovery Score v1.0)

恢复分数通过偏离个人健康基线的程度进行评估，坚决避免使用绝对的人群均值。

## 3.1 稳健滚动基线 (Robust Baseline with MAD)
对 HRV (采用 SDNN 字段) 和 RHR 进行最近 **21 至 42 天** 滚动数据提取，运用 **绝对中位偏差 (MAD)** 消除历史异常噪声的干扰：
- $$\text{baselineMedian} = \text{median}(\text{history})$$
- $$\text{MAD} = \text{median}(|x_i - \text{baselineMedian}|)$$
- $$\text{robustSD} = 1.4826 \times \text{MAD}$$
- *若滚动波动极小以致 $\text{robustSD} \approx 0$，采用物理硬垫防爆机制*：
  - HRV 最小标准差下限：`baselineMedian * 0.12`
  - RHR 最小标准差下限：`max(2.5, baselineMedian * 0.04)`

## 3.2 恢复因子拆解
- **HRV Component (35%)**：
  由于 HRV 呈高度偏态，先做自然对数转换 $\ln(\text{HRV})$，计算今日对数值对基线中位数的偏离 $z$-score：
  $$\text{hrvZ} = \frac{\ln(\text{HRV}_{\text{today}}) - \ln(\text{HRV}_{\text{baseline}})}{\text{lnHRV\_SD}}$$
  $$\text{hrvComponent} = \text{clamp}(50 + 18 \times \text{hrvZ}, 0, 100)$$
  - *副交感反反弹限制 (Parasympathetic Rebound Guard)*：若昨日经历了极大负荷（Strain > 75）且今日 HRV 出现异常暴涨（$hrvZ > 2.2$），这并非极佳恢复，而是剧烈疲劳下的应激反弹。强制将 `hrvComponent` 斩断至最高 `65` 分，并给出成因解释。
- **RHR Component (25%)**：
  评估 quiet RHR（低活动静息心率）偏移：
  $$\text{rhrZ} = \frac{\text{RHR}_{\text{today}} - \text{RHR}_{\text{baseline}}}{\text{RHR\_SD}}$$
  $$\text{rhrComponent} = \text{clamp}(50 - 18 \times \text{rhrZ}, 0, 100)$$
- **Sleep Component (25%)**：
  直接挂接昨夜的 `SleepScore`。
- **Prior Strain Component (15%)**：
  昨日负荷对今日精力的透支折算：`priorStrainComponent = clamp(100 - Strain_yesterday, 0, 100)`。

## 3.3 生理红旗指标修正 (Red Flag Modifiers)
在计算加权均值后，系统将审视其余关键生命体征，发现异常时在最终 Recovery 分数中直接扣减（扣完为止）：
1. **体温异常**： wrist temperature 偏离基线 $\Delta T \ge 0.5^\circ\text{C}$，扣减 `8` 分。
2. **夜间呼吸率高起**：睡眠呼吸频率 $z$-score $\ge 1.5$，扣减 `5` 分。
3. **血氧异常**： 昨夜最低血氧 $\text{SpO}_2 < 94\%$，扣减 `8` 分。
4. **生理严重失调**： $\text{RHR\_z} > 2.0$ 且 $\text{HRV\_z} < -1.0$，触发交叉扣减 `8` 分。

---

# 4. 耗力分数与训练负荷 (Strain & ACWR v1.0)

负荷系统分双层运行：每日耗力值评估 (Daily Strain) 和 长期训练状态比值 (Training Load Status)。

## 4.1 每日耗力 (Daily Strain: 0–100)
- **Workout Load (心率区间/TRIMP 积分)**：
  - **Zone 积分法**：根据心率储备 (Heart Rate Reserve, HRR) 划分 5 个运动区间：
    $$HRR = \frac{HR - restingHR}{maxHR - restingHR}$$
    - Zone 1 (0.50–0.60): 权重 1
    - Zone 2 (0.60–0.70): 权重 2
    - Zone 3 (0.70–0.80): 权重 3
    - Zone 4 (0.80–0.90): 权重 5
    - Zone 5 (0.90–1.00): 权重 8
    积分公式：`workoutLoad = sum(minutesInZone_i * zoneWeight_i)`。
  - **Banister TRIMP 法**（在用户生物学性别可用时自动启用）：
    - 男：`TRIMP = Duration * HRr * 0.64 * exp(1.92 * HRr)`
    - 女：`TRIMP = Duration * HRr * 0.86 * exp(1.67 * HRr)`
- **Non-workout Load (非运动活跃负荷)**：
  - 提取全天的活动能量与基础步数：
    $$\text{activityLoad} = 0.02 \times \text{activeEnergyKcal} + 0.0015 \times \text{stepCount} + 0.5 \times \text{exerciseMinutes}$$
- **总每日负荷映射**：
  合并为 `dailyLoad = workoutLoad + activityLoad`。采用指数衰减负荷映射模型：
  $$\text{strainScore} = 100 \times \left(1 - e^{-0.75 \times \frac{\text{dailyLoad}}{\text{baselineDailyLoad}}}\right)$$
  *(基线 baselineDailyLoad 取最近 28 天有效 dailyLoad 中位数；新用户默认使用 60 作为初始基线)*。避免了数值无限膨胀，符合生理负荷递增规律。

## 4.2 长期训练状态 (ACWR)
利用急性与慢性负荷比值 (Acute:Chronic Workload Ratio) 诊断负荷状态：
- **急性负荷 (Acute 7d)**：最近 7 天的每日负荷之和。
- **慢性负荷 (Chronic 28d)**：过去 28 天每日负荷之和除以 4（等价 7 日基值）。
- **ACWR 比值**：`loadRatio = acute7 / chronic28Equivalent`。
  - `loadRatio < 0.60`：**Well Below (低度负荷)** ➡️ 身体正处于显著减载或退化期。
  - `0.60–0.85`：**Below (略低负荷)** ➡️ 建议逐步提升。
  - `0.85–1.20`：**Optimal (最佳区间)** ➡️ 黄金增载适应区，既保证心肺刺激又防范受伤。
  - `1.20–1.50`：**Elevated (负荷高企)** ➡️ 建议短期维持或轻度休息。
  - `> 1.50`：**High Load Signal (高负荷信号)** ➡️ 生理负荷快速上升，建议短期减载并观察恢复；该信号不等同于受伤风险诊断。

---

# 5. 生理压力指数 (Physiological Stress Index v1.0)

生理压力指数是一个**纯生理学代偿指标**，用于捕获自主神经系统的紧绷状态，绝不代表临床心理诊断。

```text
StressIndex = weightedAverage([RHRStress: 25%, HRVStress: 25%, RespStress: 15%, TempStress: 10%, SleepDebtStress: 15%, LoadStress: 10%])
```

## 5.1 六维因子细则
1. **RHRStress (25%)**：静息心率偏离 Z-score 加权 ➡️ `clamp(50 + 18 * rhrZ, 0, 100)`。
2. **HRVStress (25%)**：HRV 偏离 Z-score 反向加权 ➡️ `clamp(50 - 18 * hrvZ, 0, 100)`。
3. **RespStress (15%)**：呼吸频率偏离 Z-score ➡️ `clamp(50 + 15 * respZ, 0, 100)`。
4. **TempStress (10%)**：体温差修正，分段线性映射：
   - $|\Delta T| < 0.3^\circ\text{C}$：`20` 分
   - $0.3 \le |\Delta T| < 0.6^\circ\text{C}$：`50` 分
   - $|\Delta T| \ge 0.6^\circ\text{C}$：`80` 分
5. **SleepDebtStress (15%)**：睡眠债转化 ➡️ `clamp(100 - SleepScore, 0, 100)`。
6. **LoadStress (10%)**：当前的物理负荷输入，采用 `DailyStrainScore`。

## 5.2 运动屏蔽保护 (Workout Windows Guarding)
**🔥 [CRITICAL] 物理心率噪声过滤**：当发生真实的 workout 事件时，心率会物理上升、HRV 会物理骤降，这是正常的训练适应，而非系统性紧绷。**因此，运动期间以及运动结束后的 90 分钟内，压力引擎会彻底屏蔽静息生理压力计算**，确保压力曲线 of 科学性。

---

# 6. 精力电池 (Energy Bank v1.0)

将睡眠、恢复、压力、负荷及时间跨度，映射成更易于消费和理解的“身体电量电池”模型。

## 6.1 清晨起始电量 (Morning Energy)
醒来时的基准电量，基于夜间系统稳定度计算：
- `OvernightStability = 100` (发生体温异常减 15，SpO2 偏低减 10，呼吸频率异常减 10)
- $$\text{MorningEnergy} = 0.45 \times \text{RecoveryScore} + 0.35 \times \text{SleepScore} + 0.20 \times \text{OvernightStability}$$

## 6.2 日内电量消耗 (Day Drain)
身体电量从醒来那一刻起，开始在物理负荷、生理应激和时间进程中不断“放电”：
- **物理负荷消耗**：`strainDrain = 0.35 * StrainScore`
- **生理压力消耗**：`stressDrain = 0.25 * StressIndex`
- **时间自然衰减**：`timeDrain = clamp(hoursSinceWake / 16 * 12, 0, 12)` （随着清醒时间拉长，腺苷累积带来的自然耗散）
- **过度训练惩罚**：若今日 `TrainingLoadStatus` 处于 `elevated` 额外追加扣除 `5` 分，处于 `highRisk` 额外扣除 `10` 分。

## 6.3 充电补偿机制 (Recharge)
用户若在日内进行了正念冥想 (`mindfulMinutes`) 或小憩 (`napMinutes`)，精力电池会获得即时“充电”：
$$\text{recharge} = \min(8, \text{mindfulMinutes} \times 0.15 + \text{napMinutes} \times 0.20)$$

最终电量：
$$\text{CurrentEnergy} = \text{clamp}(\text{MorningEnergy} - \text{strainDrain} - \text{stressDrain} - \text{timeDrain} - \text{loadDrain} + \text{recharge}, 0, 100)$$

---

# 7. 生物与健康年龄 (Biological Age & Health Age v1.0)

解耦为严谨的“健康演变趋势”和由学术模型（PhenoAge）支撑的“生物学年龄”，杜绝低质量的娱乐化年龄猜测。

## 7.1 健康年龄趋势 (Health Age Trend Beta)
利用多维可穿戴生命体征的长期轨迹（最近 90 天），分析判断整体生理机能方向：
- 评估因子：VO2Max、RHR 偏离、平均睡眠分数、每日步数负荷、体脂率、肌肉量、血压。
- 计算方式：对各个因子的 90 天演进趋势评估为 `positive (+1)` / `neutral (0)` / `negative (-1)`，随后计算平均值 `trendScore`：
  - `trendScore >= 0.35` ➡️ **Improving (持续改善)**
  - `trendScore` 在 `[-0.34, 0.34]` ➡️ **Stable (状态稳定)**
  - `trendScore <= -0.35` ➡️ **Worsening (正在变差)**

## 7.2 临床生物年龄估算 (Levine PhenoAge Estimate)
仅在用户录入足够完整且高可信度的 **9 项化验室血液指标** 时，才正式开启 PhenoAge 核心数学方程式计算。
- **必需指标**：
  1. 白蛋白 (Albumin)
  2. 肌酐 (Creatinine)
  3. 血糖 (Glucose)
  4. C反应蛋白 (CRP)
  5. 淋巴细胞百分比 (Lymphocyte Percent)
  6. 平均红细胞体积 (MCV)
  7. 红细胞分布宽度 (RDW)
  8. 碱性磷酸酶 (Alkaline Phosphatase)
  9. 白细胞计数 (WBC)
  10. 实际年龄 (Chronological Age)
- **硬性约束**：
  - 若有任何一项化验指标缺失，该引擎**强制返回 `nil`**，并向 UI 输送 pending 缺省提示，决不以可穿戴数据对血液标志物进行盲目猜测。
  - 单位必须严格经过校验，转换后方可代入 PhenoAge 方程式以保证医学统计科学性。

---

# 8. 智能决策引擎与限制因子 (Limiter Rule Engine)

Vela 每日计划与训练动作（Keep/Reduce/Swap/Rest）基于**规则引擎（Rule Engine）**决策，AI 仅负责对结论进行温暖而精准的表达，规避了直接让大模型输出带来的随机性。

## 8.1 疼痛/限制因子 (Limiter)
```swift
struct Limiter {
    var id: String
    var severity: Int // 严重度等级 (1–3)
    var reason: String
    var recommendation: String
}
```
## 8.2 限制规则判定
- **睡眠不足**：若昨晚睡眠分数 $< 60$ 或睡眠时长 $< 6$ 小时，生成 severity = 2 的限制因子。
- **深度疲劳**：若 Recovery 分数 $< 45$，生成 severity = 3 的限制因子；若在 `[45, 60)` 之间，生成 severity = 2 的限制因子。
- **高生理紧绷**：若 StressIndex $> 75$，生成 severity = 3；若在 `[60, 75]` 之间，生成 severity = 2。
- **过度负荷**：若长期训练负荷状态 (Training Load Status) 处于 `highRisk`，生成 severity = 3；处于 `elevated`，生成 severity = 2。
- **发热红旗**：若 wrist temperature delta $> 0.6^\circ\text{C}$，生成 severity = 3。
- **手记疼痛/生病**：若今日 Journal 标记了 `sick` 或 `injured`，强制生成 severity = 3 限制。

## 8.3 运动决策逻辑
- **严重限制 (Any severity 3 limiter)** ➡️ **Rest / Recovery (建议停练)**。允许极限负荷强度限制在 Zone 1 或被动的拉伸活动。
- **累积中度限制 (Total severity >= 4)** ➡️ **Reduce (建议减载)**。强制强度上限限制在 Zone 2，且运动容量减至 `0.6` 倍。
- **无限制且恢复极佳 (Recovery >= 75 且 Sleep >= 75 且 Stress < 50)** ➡️ **Push / Peak (建议突破)**。建议运动容量可加成至 `1.0–1.1` 倍。
- **常规状态 (无特殊严重指标)** ➡️ **Normal (常规训练)**。容量维持在 `0.8–1.0` 倍。

---

# 9. 习惯滞后关联 (Lag Correlation Analysis)

对于 Journal 手记记录的微观行为（咖啡、酒精、夜宵）与次日生理体征（HRV、RHR、睡眠质量、恢复分数），Vela 坚决不使用“前置因果”描述，仅展示具有统计支持的 **滞后关联性 (Lag Correlation)**：
- **Lag Windows**：关联分析默认评估行为发生在第 $t$ 天，体征体现在第 $t+1$ 天。
- **分析算法**：
  - 对连续变量行为（如咖啡因 mg、正念分钟），计算 **Spearman 秩相关系数**。
  - 对二元变量行为（如是否饮酒、是否夜宵），计算 **点二列相关系数 (Point-Biserial Correlation)**。
- **混杂控制 (Confounding Control)**：采用偏相关系数控制周中效应 (dayOfWeek)、当天训练负荷 (trainingLoad) 和睡眠时长 (sleepDuration) 的干扰。
- **置信度与展示门槛**：
  - 样本量要求：样本积累数 $n < 14$ 天不予显示；$14 \le n < 28$ 天置信度输出 `low`；超过 `60` 天输出 `high`。
  - **🔥 最低样本门槛已提高**：单个标签至少需要 5+ 天匹配数据才纳入关联分析，避免 2 天伪相关。
  - 强度过滤：只展示绝对相关系数 $|r| \ge 0.20$ 的因子：
    - `0.20–0.35` ➡️ **Weak (弱相关)**
    - `0.35–0.50` ➡️ **Moderate (中等相关)**
    - `> 0.50` ➡️ **Strong (强相关)**
  - UI 强制免责声明：*”根据您过去 30 天手记，晚间摄入酒精与次日 HRV 偏低呈强负相关（r = -0.52，样本量 16 天）。此数据仅代表统计关联，不代表医学因果。”*

---

# 10. 数据可靠性刷新通道 (HK Sync Pipeline)

为了消除 UI 数据波动、缓存不一致及后台计算延迟，Vela 确立了统一的**三层数据同步和处理计算管线**：

```text
Apple HealthKit Raw Samples 
    ↓ (Query & Normalized)
HealthKitSyncEngine 
    ↓ (Cached Snapshot Builder)
DailyHealthSnapshot / SwiftData Model Context
    ↓ (Trigger calculation)
DailyHealthComputation (Scoring Engines)
    ↓ (Format conversion)
MetricResult 
    ↓ (EnvironmentObject Broadcast)
Readiness Cockpit / Detail UI Surfaces
```

首页与二级详情页决不允许直接去 HealthKit 执行零碎的 Query，必须通过本计算管线由 SwiftData 数据新鲜度驱动进行重算，确保分数的绝对一致性。
