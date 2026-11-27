# 能量储备指标模型卡 (Energy Bank Model Card)

- **指标及算法版本**：`BevelScoringEngine score-v2`（`AlgorithmVersion.scoreV2`, `score-v2@2.0.0`）
- **实现位置**：`BodySeekKit/Sources/BodySeekCore/BevelScoringEngine.swift`（`computeEnergy`, `buildEnergyCurve`）
- **当前状态**：工程回归与 3 年历史回放已验证（见 [m0-score-v1-vs-v2-replay-2026-11-19.md](../validation/m0-score-v1-vs-v2-replay-2026-11-19.md)） / 临床与主观疲劳金标准验证未完成（将于 M0–M4 联合每日 `DailyCheckIn` 评估）

## 1. v1.0 → `score-v2` 变更摘要
1. **简化可用输入门控**：上游只要有 `recovery.value` 或 `sleep.value` 其一即可估算能量（v1 强制要求同时具备或依赖独立夜间稳定性项），在 3 年回放中使有效覆盖从 `670` 天提升至 `1,217` 天；
2. **充放电系数收敛**：晨起充能简化为 `0.64 * Recovery + 0.36 * Sleep`（缺一则互斥替补），日间消耗改为 `0.42 * Strain + 0.16 * Stress`；
3. **3 年真实回放表现（1,508 生理日）**：重合 `670` 天中，Energy 是五项里均值最无偏的指标——Bias 仅 **`-0.23`**（`v1=38.98 ± 16.91` vs `v2=35.69 ± 17.48`），Pearson `r = 0.6558`，MAE `10.80`，`<= 10 分` 占比 `54.9%`。

## 2. 用途与不适用用途
- **适用用途**：以 8–99 的直观日间“身体电池”代理值反映晨起恢复储备减去日间运动/自主神经消耗后的余量，辅助训练与休息节奏分配。
- **不适用用途**：不可作为医学疲劳综合征评估、代谢热量测算或临床决策依据。

## 3. 输入信号与四态政策
- 上游评分：`recovery.value`、`sleep.value`、`strain.value`、`stress.value`。
- 若 `recovery.value == nil && sleep.value == nil`：严格返回 `value = nil`（`.missing(reason: "需要恢复或睡眠数据才能计算能量电量")`），绝不返回 0。

## 4. `score-v2` 计算公式
- $\text{morningCharge} = \text{clamp}(0.64 \times \text{Recovery} + 0.36 \times \text{Sleep},\; 20,\; 100)$
- $\text{strainDrain} = 0.42 \times (\text{Strain} ?? 0)$
- $\text{stressDrain} = 0.16 \times (\text{Stress} ?? 25)$
- $\text{Energy} = \text{round}(\text{clamp}(\text{morningCharge} - \text{strainDrain} - \text{stressDrain},\; 8,\; 99))$
- 并产出 11 个日内时间锚点（`0..22h`）的 `energyCurve` 与结构化 `contributors`。

## 5. 状态区间与局限性
- **状态标签**：`>= 65`「电量充足」、`38..<65`「节奏均衡」、`< 38`「建议省电」。
- **已知局限**：`0.64/0.36` 与 `0.42/0.16` 系数及日内 11 点曲线目前为启发式设定；主观精力感受的真实个体化映射将通过 M0 上线的 `DailyCheckIn` 每日标签在 M4 个人模型中检验与校准。

## 6. 参考文献
- Borbély AA. *Hum Neurobiol*, 1982.
- Marcora SM, et al. *J Appl Physiol*, 2009.
