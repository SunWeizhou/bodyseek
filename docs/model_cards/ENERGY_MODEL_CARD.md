# 能量银行指标模型卡 (Energy Bank Model Card)

> 文档状态（2026-09-06）：以下保留 v1.0 历史模型卡。当前生产 `ScoringAlgorithmVersions.energy` 为 `energy.v2.0.0`；旧公式和验证状态未对齐当前版本，不能用本页证明现行算法已验证。版本与公式对齐仍是 TAKEOVER F5 的工作。


指标及算法版本：EnergyBankEngine v1.0 (`ScoringAlgorithmVersions.energy`)
状态：工程回归已验证 / 生理有效性未验证 / 无真实代谢水解或主观疲劳多中心临床对照

## 1. 用途与不适用用途
- **适用用途**：结合晨间身体恢复程度、昨夜睡眠质量、清醒时长基线代谢衰减、日间活动/运动负荷消耗及生理压力应激，模拟并追踪日间“身体可用能量储备”的动态衰减曲线（0–100 分），为日间精力节奏与休憩提供直观指引。
- **不适用用途**：严禁用于慢性疲劳综合征 (CFS)、线粒体脑肌病、严重贫血或内分泌代谢紊乱的临床评估与干预依据；不能作为医疗级可用精力定量测量。

## 2. 目标人群与未覆盖人群
- **目标人群**：一般健康成年人群（18–65岁），按常规单相昼夜节律生活工作。
- **未覆盖人群**：倒班/通宵工作者、多相睡眠者、中枢神经抑制或兴奋类药物服用者、嗜睡症患者。

## 3. 预测/描述的真实目标
- **真实目标**：启发式综合模型，以恢复与睡眠为“初始电量”，随清醒时间（清醒稳态代谢）、耗力运动（负荷消耗）与生理应激（加速消耗）逐步消耗，白天小憩（Nap）或正念冥想提供有限补充。

## 4. 输入类型、单位、来源、采样窗口
- `recoveryScore`：0–100 分，晨间身体恢复评分。
- `sleepScore`：0–100 分，前夜睡眠评分。
- `strainScore`：0–100 分，当日综合耗力评分（用于能量扣减）。
- `todayLoad`：真实 Banister TRIMP 训练负荷，与慢性历史同量纲。
- `stressIndex`：0–100 分，生理压力指数（在运动后 90 分钟排除期间为 nil）。
- `hoursSinceWake`：小时 (h)，自清晨觉醒离开床铺起累计的时间。
- `bodyTempDelta` / `respiratoryRateZ` / `SpO2`：夜间体征偏离，用于计算“夜间稳定性基准”。
- `mindfulMinutes` / `napMinutes`：分钟 (min)，正念呼吸或小憩时长，用于能量补充。

## 5. 个人基线窗口、有效天数与源/方法变化政策
- **初始电量依赖**：依赖当日晨间 `RecoveryScore` 与 `SleepScore`。
- **缺失与降级政策**：若恢复与睡眠信号均缺失，能量评分严格不可估计（输出 `nil`），显示 `--`；若仅有睡眠时长而无 HRV 恢复，置信度标记为 `low`，且附注“基于睡眠时长估算”。

## 6. 缺失、零值、排除窗口、异常值政策
- **运动窗口与压力去重护栏**：
  - 当处于运动中或运动后 90 分钟内时，`stressIndex` 为 `nil`；
  - **核心设计**：此时能量模型仅根据运动负荷（`strainScore`）进行能量扣除，绝不因为压力指标缺失而导致能量异常“回跳”或产生虚假恢复。
- **边界钳制**：全天动态能量值严格限制在 $[0, 100]$ 区间。

## 7. 时间 as-of 与输入修订政策
- **时间演进**：能量随 `hoursSinceWake` 连续单调消耗（除非发生小憩或正念充能）。

## 8. 公式/参数与每个参数依据
- **初始充能 (Morning Initial Energy)**：
  $$\text{InitialEnergy} = 0.55 \times \text{RecoveryScore} + 0.45 \times \text{SleepScore}$$
  （若恢复评分缺失，则以睡眠评分结合夜间稳定性基准折算，置信度降为 `low`）。
- **清醒时间基线衰减 (Awake Drain)**：
  $$\text{AwakeDrain} = 2.0 \times \text{hoursSinceWake} + 0.05 \times (\text{hoursSinceWake})^2$$
- **体力负荷消耗 (Strain Drain)**：
  $$\text{StrainDrain} = 0.35 \times \text{StrainScore}$$
- **压力加速消耗 (Stress Drain)**：
  若 $\text{StressIndex} > 50$，超额部分加速扣除：
  $$\text{StressDrain} = 0.20 \times (\text{StressIndex} - 50) \times \frac{\text{hoursSinceWake}}{12.0}$$
- **日间补充 (Recharge)**：
  $$\text{Recharge} = \min(15.0, 0.25 \times \text{NapMinutes} + 0.15 \times \text{MindfulMinutes})$$
- **当前能量**：
  $$\text{CurrentEnergy} = \text{clamp}(\text{InitialEnergy} - \text{AwakeDrain} - \text{StrainDrain} - \text{StressDrain} + \text{Recharge}, 0, 100)$$

## 9. 哪些是文献支持的概念，哪些是本产品启发式
- **文献支持概念**：
  - 双过程睡眠调节模型（Process S 睡眠压力/疲劳随清醒时间递增；Borbély, 1982）；
  - 心理生理应激对中枢疲劳和感知努力程度 (RPE) 的加速消耗作用（Marcora et al., 2009）。
- **本产品启发式**：
  - 初始电量 55/45 的恢复与睡眠权重切分；
  - 清醒消耗的二次项参数（$2.0h + 0.05h^2$）；
  - 训练负荷 0.35 转换系数与压力大于 50 后的扣减斜率。

## 10. 结果刻度/方向/状态文案
- **刻度**：0–100 分。
- **状态分段**：
  - 0–20：Depleted / Critical（电量告急，建议立即休整睡眠）
  - 21–50：Low（电量偏低，避免过度负荷）
  - 51–75：Moderate（适中，胜任常规工作活动）
  - 76–100：Fully Charged（充沛，适宜高强度产出与训练）

## 11. 数据质量与模型不确定性如何分开
- **数据质量**：`confidence`。若恢复或睡眠为 `low`，能量置信度相应限制为 `low`；若缺少醒来时间则降级。
- **解释文案**：在 `reasons` 中分解电量当前消耗构成（如“清醒 8 小时基础消耗约 19 分，运动消耗 14 分”）。

## 12. 已执行工程测试与结果
- `EnergyBankEngineTests.swift`：覆盖一整天单调衰减、运动扣减、小憩回充、极端缺失降级等测试，全部通过。

## 13. 对照基线、留出策略与真实样本
- **真实临床/生化疲劳对照**：**未做（无实测血乳酸、肌酸激酶或多中心主观疲劳量表对照）**。
- **工程基线**：以当前确定性重放数据集为工程回归基准。

## 14. 实际效果/误差/校准/区间
- **主观疲劳量表 (VAS/MFI-20) 相关性**：**未做（严禁编造）**。

## 15. 已知限制与失败情境
- 无法感知主观心理动力（如极度兴奋时暂时压制生理疲劳感）；
- 未知睡眠中断如果漏测，会导致初始电量虚高；
- 咖啡因/酒精摄入对主观精力的掩盖效应未建模。

## 16. 新旧版本影响/下游连锁
- **下游消费**：作为主页仪表盘与健康趋势分析中用户感知最直接的动态晴雨表。
- **隔离控制**：严格继承上游恢复与睡眠的不确定性，不假装精确。

## 17. 发布/回滚条件
- **发布条件**：单调性与日间衰减测试无反弹逻辑错误。
- **回滚条件**：发现醒来时间解析为负值导致电量无限回充时立即回滚。

## 18. 来源链接及读取日期
- Borbély AA. A two process model of sleep regulation. *Hum Neurobiol*, 1982. (读取日期: 2026-08-20)
- Marcora SM, et al. Mental fatigue impairs physical performance in humans. *J Appl Physiol*, 2009. (读取日期: 2026-08-20)
