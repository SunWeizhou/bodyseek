# 训练负荷/耗力指标模型卡 (Strain Score Model Card)

指标及算法版本：StrainScoreEngine v2.1.0 (`ScoringAlgorithmVersions.strain`)
状态：v2.1 生产失败样例已复现，修复后生产回归通过（全量 598/598） / 生理有效性未验证 / 无真实运动人体科学实验室（摄氧量/乳酸阈值）金标准标定

## 1. 用途与不适用用途
- **适用用途**：结合训练期间心率储备指数（Banister TRIMP）、非运动日常基础活动（活动能量、步数、活动时长）以及过去 28 天慢性负荷基线，输出 0–100 的日度耗力评分及 ATL/CTL 训练负荷状态比，用于日常运动强度管理。
- **不适用用途**：严禁用于专业运动员极限竞技备战精准处方、过度训练综合征（Overtraining Syndrome）临床筛查或心血管运动风险预警。

## 2. 目标人群与未覆盖人群
- **目标人群**：从事有氧跑步、骑行、健身操、日常步行的健康运动爱好者。
- **未覆盖人群**：纯静力力量举/大重量抗阻训练者（心率无法有效反映神经肌肉负荷）、心血管疾病患者、佩戴设备松动导致心率严重失真者。

## 3. 预测/描述的真实目标
- **真实目标**：衡量当日心血管刺激总量相对于个人 28 天慢性负荷的饱和比例（对数压缩呈现为 0–100 分），并跟踪 7 天急性负荷 (ATL) 与 28 天慢性负荷 (CTL) 的动态比例关系。

## 4. 输入类型、单位、来源、采样窗口
- `workouts`：包含持续时间（分钟）、平均心率或逐秒心率采样点序列、主观疲劳度（RPE 1–10）、活动类型 UUID。
- `activeEnergyToday`：千卡 (kcal)，Apple Watch 记录的日活动消耗。
- `exerciseMinutesToday`：分钟 (min)，Apple 锻炼分钟数。
- `stepCount`：步数 (steps)，Apple 计步器步数。
- `restingHR`：次/分 (bpm)，个人近期静息心率。
- `maxHR`：次/分 (bpm)，个人最大心率（当前 profile 采用用户配置或 `220-age` 估计；不是 Tanaka 公式）。
- `biologicalSex`：字符串 ("male", "female", other)，决定 Banister 指数增长系数。
- `dailyLoadObservations`：[DailyLoadObservation]，生产路径的连续日历负荷网格，保留 `observed`、`knownZero`、`missing`、`excluded`。缺失日期仅参与时间衰减，不构成零负荷观测或有效天数。
- `last28DaysDailyLoads`：[Double]，兼容旧调用的负荷数组；当前生产路径以 typed observations 为准。
- `validObservedDaysCount`：整数，过去 28 天中实际有佩戴和活动记录的天数。

## 5. 个人基线窗口、有效天数与源/方法变化政策
- **基线窗口**：过去 28 天真实日历天负荷中位数（`PersonalBaselineEngine.median`）；无历史时使用静态 60.0 参考刻度（显式提示非个人基线）。
- **有效天数门控**：
  - 有效观测天数 $< 7$ 天：**严格停用 ATL/CTL 负荷状态评估**（不给出过载/减量结论），置信度标记为 `low`；
  - 有效天数在 7–27 天：启用估算评估，置信度标记为 `medium`；
  - 有效天数 $\ge 28$ 天：基线稳固，置信度为 `high`。
- **断续日期衰减政策**：采用基于真实日历时间的 EWMA 衰减。未佩戴且无活动观测的日期保留为 missing；明确观测的零保留为 knownZero。两者都不压缩时间轴，但只有后者增加有效观测天数。

## 6. 缺失、零值、排除窗口、异常值政策
- **输入缺失政策**：训练为空且活动能量、运动分钟与步数全为 nil 时，耗力评分严格不可估计（输出 `nil`），不发布 `daily_load`、ATL/CTL 或训练状态，写回 snapshot 的 `dailyLoad` 仍为 nil。任一来源有明确零观测时继续计算，不丢弃其他可用来源。
- **旧零记录兼容**：旧 snapshot 的 `dailyLoad=0`，且 workouts 为空、activeCalories/activeMinutes/workoutDuration/steps 全缺失时，按 missing 处理。存在任一原始活动观测的零保持 knownZero；正数历史值继续兼容。
- **心率储备缺失**：若缺少静息心率或最大心率，退化使用 Foster RPE（$load = \text{duration} \times \text{rpe} \times 0.3$）或时长保底估计（$load = \text{duration} \times 1.5$），置信度降为 `low`。
- **重复训练去重**：训练列表强制按 UUID 去重，防止同一运动记录重复积分。

## 7. 时间 as-of 与输入修订政策
- **As-of 边界**：仅统计当日截至当前调用时间的训练与活动，严禁未来数据计入。

## 8. 公式/参数与每个参数依据
- **心率储备分级 Banister TRIMP**：
  $$\text{HRR} = \text{clamp}\left(\frac{\text{HR} - \text{HR}_{\text{rest}}}{\text{HR}_{\text{max}} - \text{HR}_{\text{rest}}}, 0.01, 1.0\right)$$
  - 男性：$\alpha = 0.64, \beta = 1.92$
  - 女性：$\alpha = 0.86, \beta = 1.67$
  - 未指定：$\alpha = 0.75, \beta = 1.80$（中性插值）
  - 逐点积分：$\text{Load}_{\text{workout}} = \sum \Delta t \times \text{HRR} \times \alpha \times e^{\beta \times \text{HRR}}$
- **非运动活动负荷与重叠抑制**：
  $$\text{RawActivityLoad} = 0.02 \times \text{Energy} + 0.0015 \times \text{Steps} + 0.5 \times \text{ExerciseMin}$$
  - 若当日有已记录训练，日常活动乘数降为 0.35（避免锻炼能量被双重全额计算）；若无训练则按 1.0 计。
- **日度耗力评分映射**：
  $$\text{StrainScore} = 100 \times \left(1 - e^{-0.75 \times \frac{\text{DailyLoad}}{\text{BaselineLoad}}}\right)$$
- **急性/慢性负荷比 (ACWR)**：
  - $\text{ATL} = \text{EWMA}_{\text{day}=7}(\text{DailyLoad})$
  - $\text{CTL} = \text{EWMA}_{\text{day}=28}(\text{DailyLoad})$
  - $\text{Ratio} = \frac{\text{ATL}}{\text{CTL}}$（$<0.60$ 显著停训/减量；$0.85–1.20$ 维持/适宜；$>1.50$ 过载高风险）。

## 9. 哪些是文献支持的概念，哪些是本产品启发式
- **文献支持概念**：
  - Banister 冲量响应理论 (TRIMP) 与指数型心血管负荷积分；
  - Gabbett 急性/慢性负荷比 (ACWR) 负荷管理框架与时间常数选择（7 天 / 28 天）；
  - Foster 会话自我疲劳评级 (sRPE)。
- **本产品启发式**：
  - 0–100 对数饱和曲线参数（0.75）；
  - 非运动日常活动估算参数（0.02/0.0015/0.5）以及 0.35 重复抑制乘数；
  - 未指定性别参数插值（0.75 / 1.80）；
  - 推荐区间按恢复评分分段：缺失时 40–70，低于 40 时 15–40，40..<70 时 35–65，70 及以上时 55–85。

## 10. 结果刻度/方向/状态文案
- **刻度**：0–100 分。
- **引擎 band**：通用 `ScoringMath.band` 为 `<25 veryLow`、`25..<45 low`、`45..<75 normal`、`75..<90 high`、`>=90 veryHigh`。ATL/CTL 的 TrainingLoadStatus 是另一输出；值高代表负荷大，不等于健康更好。

## 11. 数据质量与模型不确定性如何分开
- **数据质量**：逐点心率、平均心率、RPE 和时长是不同输入方法，不直接构成已验证的精度等级。当前 confidence 同时取决于活动能量是否可用、心率储备和历史覆盖；缺少心率储备时 low 可被后续 7–27 天历史分支覆盖为 medium，属于已记录、尚未在本次修复的限制。
- **模型不确定性**：在 `reasons` 明确注明所采用的计算方式（如“缺少个人静息心率或最大心率，心率数据未用于个体化负荷计算”）。

## 12. 已执行工程测试与结果
- **2026-09-22 v2.1**：生产红测复现全活动 missing 发布 `daily_load=0`，连续写回七日后错误启用负荷比 3.625。新测试同时保留有原始 steps=0 证据的历史零，避免一律删除零值。生产回归命令和结果记录在对应 GitHub PR；固定反例见 `VelaAppTests/ScoringEngineTests.swift` 与 `VelaAppTests/StrainReplaySensitivityTests.swift`。
- 以下为此前工程记录，不自动表示 v2.1 回归已经完成：
- `StrainEngineTests.swift`：全面覆盖 4 种计算分支（Method A/B/C/D）、训练 UUID 去重、ATL/CTL 连续日历网格衰减与不足 7 天停用门控，全部通过。

## 13. 对照基线、留出策略与真实样本
- **真实运动实验室对照**：**未做（无实测气体代谢与血乳酸对比）**。
- **工程基线**：以当前确定性重放测试集作为回归基准。

## 14. 实际效果/误差/校准/区间
- **临床有效性/负荷模型相关度**：**未做（严禁编造）**。

## 15. 已知限制与失败情境
- 无法度量力量训练中肌肉离心收缩损伤；
- 光学心率传感器（PPG）在剧烈挥臂或冲刺时可能存在心率“锁频”步频现象；
- 炎热或脱水环境下相同功率导致的心血管漂移（Cardiac Drift）会被误计为真实机械负荷增加。

## 16. 新旧版本影响/下游连锁
- **v2.1 语义修订**：只修全活动缺失的输出和旧零历史兼容，不改变 TRIMP、活动系数、饱和曲线、推荐区间或 EWMA 参数。复合缓存版本随 Strain 版本更新；七日 missing 不再被当作七日有观测休息，从而避免下游凭伪历史额外扣 10 分。
- **下游消费**：昨日负荷传入次日 `RecoveryScoreEngine` 作为惩罚因子（15%）；当日负荷传入 `EnergyBankEngine` 作为能量耗竭驱动量。
- **隔离控制**：当负荷为 `nil` 时，能量引擎不扣减运动能量，保持基线代谢消耗。

## 17. 发布/回滚条件
- **发布条件**：Banister 指数积分单调性测试通过，连续日历 EWMA 验证通过。
- **回滚条件**：发现多重计算导致的负荷无限膨胀或极端心率导致 exp 溢出时立即回滚。

## 18. 来源链接及读取日期
- Banister EW. Modeling elite athletic performance. *Physiological Testing of the High-Performance Athlete*, 1991. (读取日期: 2026-08-20)
- Gabbett TJ. The training—injury prevention paradox: should athletes be training smarter and harder? *Br J Sports Med*, 2016. (读取日期: 2026-08-20)
