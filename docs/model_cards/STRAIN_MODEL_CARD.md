# 训练负荷/耗力指标模型卡 (Strain Score Model Card)

- **指标及算法版本**：`BevelScoringEngine score-v2`（`AlgorithmVersion.scoreV2`, `score-v2@2.0.0`）
- **实现位置**：`BodySeekKit/Sources/BodySeekCore/BevelScoringEngine.swift`（`computeStrain`, `computeACWR`）
- **当前状态**：工程回归与 3 年历史回放已验证（见 [m0-score-v1-vs-v2-replay-2026-11-19.md](../validation/m0-score-v1-vs-v2-replay-2026-11-19.md)） / 生理有效性未验证 / 无运动科学实验室气体代谢与血乳酸标定

## 1. v1.0 → `score-v2` 变更摘要
1. **日度负荷饱和基准改进**：v1 基于步数+能量构造负荷并除以近期低中位数基线，导致早期低基线阶段轻度步行即触发 `82–100` 虚高分；`score-v2` 使用个人 28 天 `activeEnergyKcal` 中位数并设定 **`baselineKcal >= 320` kcal 保底**，联合 `exerciseMinutes` 计算 0–100 负荷；
2. **明确区分 `knownZero` vs `missing`**：授权且全部活动输入缺失输出 `nil`（`.missing`）；当全天极低活动且 `workouts` 为空（`kcal <= 10 && exMin == 0 && steps < 100`）时诚实发布 `value = 0` 与 `.knownZero`；
3. **ACWR 计算独立清晰**：`computeACWR` 优先采用 Watch 5 区间 `TRIMP`，无心率分区时回退日 `Strain` 分，历史不足 7 天或慢性总负荷极低时标记为 `.insufficientData`；
4. **3 年真实回放表现（1,508 生理日）**：覆盖率一致（`1,508 / 1,508`）；均值 `v1=52.97 ± 23.21` vs `v2=57.16 ± 25.80`，Bias `+4.19`，Pearson `r = 0.6568`。由于公式钳位机制，当前 `score-v2` 实际最大值封顶为 **`93`**（`85 * 0.68 + 35 = 92.8`）。

## 2. 用途与不适用用途
- **适用用途**：跟踪全天活动消耗与运动锻炼相对个人 28 天基准的生理负荷刺激，并结合 7d/28d ACWR 辅助控制每周增量与减量节奏。
- **不适用用途**：严禁用于专业运动员竞赛极限备战、过度训练综合征临床筛查；心率未反映纯高阻/低心率静态力量训练的肌原纤维微损伤（需在 `健身` Tab 与动态肌群恢复模型中补充）。

## 3. 输入信号与四态政策
- `activeEnergyKcal`（优先系统去重后的活动能量）、`exerciseMinutes`、`steps`、`workouts`（含 `WorkoutHeartRateZones` 与用户 `WorkoutEffortScore`）。
- **四态**：全部活动输入缺失 → `.missing`（UI 显示 `--`）；已授权且明确零活动 → `value = 0`（`.knownZero`）。

## 4. `score-v2` 计算公式
- $\text{baselineKcal} = \max(320,\; \text{median}_{28\text{d}}(\text{activeEnergyKcal}) ?? 480)$
- $\text{energyLoad} = \text{clamp}\!\left(\frac{\text{kcal}}{\text{baselineKcal} \times 1.35} \times 75,\; 0,\; 85\right)$
- $\text{exerciseBonus} = \text{clamp}\!\left(\frac{\text{exerciseMinutes}}{75} \times 35,\; 0,\; 35\right)$
- $\text{Strain} = \text{round}(\text{clamp}(0.68 \times \text{energyLoad} + \text{exerciseBonus},\; 1,\; 100))$（理论极值 `93`，后续如需映射到 100 需升级 `score-v3`）
- **ACWR 分区**：`< 0.80`（偏低 `undertraining`）、`0.80...1.32`（甜蜜区 `sweetSpot`）、`> 1.32`（高风险 `highRisk`）。

## 5. 状态区间与局限性
- **状态标签**：`>= 70`「高强度输出」、`40..<70`「中等负荷」、`< 40`「日常活动」、`knownZero`「休息中」。分值高仅代表当日物理/心血管负荷大，不等于“好/健康”。
- **已知局限**：`score-v2` 主观负荷修正与 `PhysicalEffort` 信号将在后续模型版本验证后按版本迭代。

## 6. 参考文献
- Banister EW. *Physiological Testing of the High-Performance Athlete*, 1991.
- Gabbett TJ. *Br J Sports Med*, 2016.
