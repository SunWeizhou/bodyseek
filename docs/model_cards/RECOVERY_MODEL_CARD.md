# 恢复评分指标模型卡 (Recovery Score Model Card)

- **指标及算法版本**：`BevelScoringEngine score-v2`（`AlgorithmVersion.scoreV2`, `score-v2@2.0.0`）
- **实现位置**：`BodySeekKit/Sources/BodySeekCore/BevelScoringEngine.swift`（`computeRecovery`）
- **当前状态**：工程回归与 3 年历史回放已验证（见 [m0-score-v1-vs-v2-replay-2026-11-19.md](../validation/m0-score-v1-vs-v2-replay-2026-11-19.md)） / 临床有效性未验证 / 无临床队列金标准标注

## 1. v1.0 → `score-v2` 变更摘要
1. **基线锚点与线性区间调整**：基线中位锚点由 v1 的 Sigmoid 50 分移至 68 分，HRV 偏离采用相对个人 28 天中位基线的比例缩放（`68 + ratio * 22`, clamp `[15, 99]`），静息心率偏离采用 `(base - rhr) / 5.0 * 20`（`68 + ...`, clamp `[15, 98]`）；
2. **权重重分配**：可用信号加权由 v1（HRV 35% / RHR 25% / Sleep 25% / PriorStrain 15%）调整为 **HRV 52% / RHR 30% / Sleep 18%**；
3. **缺失门控收敛**：只要具备昨夜/当日 `hrvMs` 或 `restingHeartRateBpm` 其一即可按可用权重重归一化产出评分，不再强制因缺少睡眠分段而丢弃心血管恢复评分；若三项信号或核心 CV 信号全缺，严格输出 `nil`（`MetricAvailability.missing`）；
4. **3 年真实回放表现（1,508 生理日）**：v1 有效 `646` 天、v2 有效 `1,193` 天；重合日均值 `v1=53.84`、`v2=68.41`（Bias `+16.38`, Pearson `r = 0.7123`, Spearman `ρ = 0.7155`）。

## 2. 用途与不适用用途
- **适用用途**：基于 Apple Watch 采集的 HRV (`SDNN`)、静息心率（RHR）与昨夜睡眠质量对比个人 28 天滚动中位数基线，给出 1–100 恢复储备倾向参考，辅助当天训练强度取向与作息安排。
- **不适用用途**：严禁用于任何医疗诊断、心律失常筛查、心肌炎/感染判断或自主神经病变评估；绝对不代表医学意义下的心脏健康度。

## 3. 目标人群与未覆盖人群
- **目标人群**：当前 Single-User Daily Driver（健康成年人，规律佩戴 Apple Watch）。
- **未覆盖人群**：心律失常（房颤等）、起搏器佩戴者、影响自主神经药物使用者、孕妇、急性感染发烧期、倒班与未成年人群。

## 4. 输入信号、单位、基线窗与因果约束
- `hrvMs`：ms（Apple Health HRV SDNN）。
- `restingHeartRateBpm`：bpm（HealthKit 静息心率）。
- `sleepScore.value`：0–100（来自同日 `computeSleep` 产物）。
- **个人基线窗口**：严格筛选目标日之前最多 **28 天**（`[dayStart - 28d, dayStart)`）历史样本中位数，绝对排除目标日与未来日（零未来泄露）。
- **四态真值合同**：支持 `available` / `knownZero` / `missing` / `excluded`；Recovery 缺失或不可用时统一输出 `.missing(reason)` 与 `value = nil`，UI 展示 `--`。

## 5. `score-v2` 公式与启发式说明
- 若 `hrvMs == nil && restingHeartRateBpm == nil`：返回 `value = nil`（`.missing`）。
- 各分量按以下公式计算（无 28 天基线时使用冷启动线性映射）：
  - $\text{component}_{\text{HRV}} = \text{clamp}\!\left(68 + \frac{\text{HRV} - \text{base}_{\text{HRV}}}{\max(\text{base}_{\text{HRV}} \times 0.22,\, 6)} \times 22,\; 15,\; 99\right)$（权重 `0.52`）
  - $\text{component}_{\text{RHR}} = \text{clamp}\!\left(68 + \frac{\text{base}_{\text{RHR}} - \text{RHR}}{5} \times 20,\; 15,\; 98\right)$（权重 `0.30`）
  - $\text{component}_{\text{Sleep}} = \text{sleepScore}$（权重 `0.18`，可用时计入）
- 最终评分：$\text{Recovery} = \text{clamp}(\sum (c_i w_i) / \sum w_i,\; 1,\; 100)$，并同时输出结构化 `contributors: [MetricContributor]` 与 `algorithmVersion = score-v2@2.0.0`。
- **启发式边界**：权重配比、68 分中位锚点及冷启动斜率均为产品启发式参数；`score-v2` 当前暂未自动扣减腕温、呼吸率与血氧异常（该类扩展需在 `score-v3` 另立版本并附回放对照）。

## 6. 状态区间与局限性
- **状态标签**：`>= 75`「状态充沛」、`50..<75`「处于平时」、`< 50`「偏疲劳」。该环仅表达生理恢复状态倾向，**并非** Apple 活动环式的“必须刷满 100 分”闭环目标。
- **已知局限**：间歇性夜间 HRV 采样存在噪声；饮酒或高环境温度可压低 HRV 却无法仅从数值区分病因。

## 7. 参考文献
- Task Force of ESC/NASPE. *Circulation*, 1996.
- Plews DJ, et al. *Sports Med*, 2012.
