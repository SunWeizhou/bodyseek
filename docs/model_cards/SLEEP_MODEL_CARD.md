# 睡眠评分指标模型卡 (Sleep Score Model Card)

- **指标及算法版本**：`BevelScoringEngine score-v2`（`AlgorithmVersion.scoreV2`, `score-v2@2.0.0`）
- **实现位置**：`BodySeekKit/Sources/BodySeekCore/BevelScoringEngine.swift`（`computeSleep`）
- **当前状态**：工程回归与 3 年历史回放已验证（见 [m0-score-v1-vs-v2-replay-2026-11-19.md](../validation/m0-score-v1-vs-v2-replay-2026-11-19.md)） / 临床有效性未验证 / 无 PSG 多导睡眠图金标准对比

## 1. v1.0 → `score-v2` 变更摘要
1. **维度构成转换**：由 v1（时长 50% / 入睡一致性 30% / 清醒中断 20%，无分期时 79 分封顶）调整为 **时长达成度 55% / 深睡+REM 修复比例 25% / 在床连续效率 20%**；
2. **长睡眠边界变化**：v1 对超长睡眠（`> target + 60m`）线性惩罚至 0 分，导致约 12+ 小时样本（含叠加片段）在 3 年回放中骤降至 `6–25` 分；`score-v2` 将时长比钳位至 `1.08` 封顶，消除过长惩罚断崖（M1 需同步落地主睡眠与午睡分离合并策略）；
3. **3 年真实回放表现（1,508 生理日）**：v1 与 v2 覆盖完全一致（各 `670` 天）；均值由 `67.79 ± 24.19` 提升至 `75.19 ± 14.50`（中位 `77.00` vs `78.00`, Bias `+7.41`, Pearson `r = 0.6839`）。

## 2. 用途与不适用用途
- **适用用途**：综合睡眠总时长、深度/REM 修复比例与卧床效率，提供 1–100 昨夜睡眠支持度参考及相对 28 天基线的分钟偏差。
- **不适用用途**：严禁用于睡眠呼吸暂停（OSA）、失眠症、异态睡眠等临床诊断，不能替代多导睡眠图（PSG）。

## 3. 输入信号、基线窗与四态规则
- `sleepAsleepMinutes`（有效睡眠总分钟，必须 `> 0`；缺失或 `<= 0` 时严格返回 `value = nil` 与 `.missing`）。
- `deepMinutes`、`remMinutes`、`coreMinutes`、`awakeMinutes`、`sleepInBedMinutes`（可选分期输入；缺分期时修复比例取中性默认 `0.36`，缺少卧床时长时按 `asleep + (awake ?? 15)` 估算）。
- `goalMinutes`：用户目标（默认 `450` 分钟 = 7.5 小时，最低钳位 `300`）。
- **个人基线**：`baselineDelta` 基于目标日之前 28 天 `sleepAsleepMinutes` 中位数计算，绝不泄露未来日期。

## 4. `score-v2` 计算公式
- $\text{durationRatio} = \text{clamp}(\text{asleep} / \max(300,\, \text{goal}),\; 0,\; 1.08)$
- $\text{durationScore} = \text{clamp}(\text{durationRatio} \times 90,\; 20,\; 96)$（权重 `0.55`）
- $\text{restorativeRatio} = (\text{deep} + \text{rem}) / \max(\text{asleep}, 1)$（无分期数据时 `0.36`）
- $\text{stageScore} = \text{clamp}((\text{restorativeRatio} / 0.42) \times 90,\; 35,\; 98)$（权重 `0.25`）
- $\text{efficiency} = \text{clamp}(\text{asleep} / \max(\text{inBed}, \text{asleep}),\; 0.55,\; 1.0)$
- $\text{continuityScore} = \text{clamp}(((\text{efficiency} - 0.65) / 0.32) \times 92,\; 35,\; 98)$（权重 `0.20`）
- $\text{Sleep} = \text{clamp}(0.55\,\text{durationScore} + 0.25\,\text{stageScore} + 0.20\,\text{continuityScore},\; 1,\; 100)$

## 5. 状态区间与局限性
- **状态标签**：`>= 80`「睡眠充分」、`60..<80`「整体平稳」、`< 60`「睡得偏短」。
- **已知局限**：Apple Watch 睡眠分期来自体动与光学心率模型；未接入夜间规律性偏移（将在模型报告 M4a 中作为独立特征评估）；未分离午睡前可能高估长睡眠日分数。

## 6. 参考文献
- Watson NF, et al. *Sleep*, 2015.
- Phillips AJK, et al. *Sci Rep*, 2017.
