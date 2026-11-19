# 生理压力指标模型卡 (Physiological Stress Index Model Card)

- **指标及算法版本**：`BevelScoringEngine score-v2`（`AlgorithmVersion.scoreV2`, `score-v2@2.0.0`）
- **实现位置**：`BodySeekKit/Sources/BodySeekCore/BevelScoringEngine.swift`（`computeStress`, `buildStressTimeline`）
- **当前状态**：工程回归与 3 年历史回放已验证（见 [m0-score-v1-vs-v2-replay-2026-11-19.md](../validation/m0-score-v1-vs-v2-replay-2026-11-19.md)） / 临床有效性未验证 / 无皮质醇与皮电（EDA）金标准对照

## 1. v1.0 → `score-v2` 变更摘要
1. **严格心血管信号门控**：v1 在缺乏 HRV 与静息心率时仍凭日常负荷/睡眠债务发布压力值（在 3 年回放中多产生 `267` 天无心率压力值）；`score-v2` 强制要求至少具备 `restingHeartRateBpm`、`daytimeMeanHeartRateBpm` 或 `hrvMs` 其一，否则输出 `nil`（`.missing`）；
2. **引入全天平均心率偏离**：纳入 `daytimeMeanHeartRateBpm - baselineRHR` 项（覆盖 `186` 个缺失 HRV/RHR 但有全天心率的日期）；
3. **简化三分量均值**：当前使用可获得的「日间心率升高」、「HRV 相对基线抑制」、「当日 Strain 负荷」等权平均；
4. **3 年真实回放表现（1,508 生理日）**：v1 有效 `1,307` 天、v2 有效 `1,226` 天（重合 `1,040` 天）；Bias `+0.46`（几乎无系统偏置），Pearson `r = 0.5124`，`<= 10 分` 占比 `51.4%`。
5. **待在 M1 恢复的排除窗口**：当前 `score-v2` 日间 12 段序列仍为模拟波型且未显式渲染运动后 90 分钟 `excluded(.postWorkoutWindow)`，将在 M1-Data/UI 中恢复真实小时心率窗口与排除态渲染。

## 2. 用途与不适用用途
- **适用用途**：衡量自主神经系统相对个人基线的交感激活 / 负荷应激代理水平（0–100，越高越紧张），辅助作息调节。
- **不适用用途**：**绝对严禁**用于焦虑症、抑郁症、精神障碍或急性医学危象诊断；不能代表主观心理压力（心理压力由 `DailyCheckIn` 单独采集）。

## 3. 输入信号与基线
- `daytimeMeanHeartRateBpm`（日间心率均值）、`hrvMs`（HRV SDNN）、`restingHeartRateBpm`（静息心率）、`strain.value`（同日负荷分）。
- **个人基线**：严格使用目标日前 28 天（不含当日）HRV 与静息心率中位数。

## 4. `score-v2` 计算公式
- 若 `restingHeartRateBpm == nil && daytimeMeanHeartRateBpm == nil && hrvMs == nil`：返回 `value = nil`（`.missing`）。
- 可用分量集合 `components`：
  - 日间心率升高：`clamp((max(0, meanHR - baselineRHR) / 32.0) * 78.0, 12, 95)`
  - HRV 抑制：`clamp(44.0 + ((baselineHRV - hrv) / baselineHRV) * 65.0, 12, 92)`
  - 运动负荷牵引：`clamp(strain * 0.65 + 15.0, 10, 88)`
- $\text{Stress} = \text{round}(\text{clamp}(\text{mean}(\text{components}),\; 5,\; 98))$

## 5. 状态区间与局限性
- **状态标签**：`>= 65`「压力偏高」、`35..<65`「负荷可控」、`< 35`「放松平稳」。
- **已知局限**：咖啡因、高温环境、脱水、饮酒或日间身体活动均可拉高全天心率均值，单独看日均值存在运动与静坐心率混杂（将在 M1 通过小时心率聚合 + 运动后排除窗口改善）。

## 6. 参考文献
- Thayer JF, et al. *Front Neurosci*, 2012.
- Stanley J, et al. *Sports Med*, 2013.
