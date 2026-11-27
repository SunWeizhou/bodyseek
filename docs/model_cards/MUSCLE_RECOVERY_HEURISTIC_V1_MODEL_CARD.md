# 肌群恢复启发式估计模型卡 (Muscle Recovery Heuristic v1 Model Card)

- **算法版本**：`MuscleRecoveryEngine recovery-heuristic-v1`（`AlgorithmVersion.recoveryHeuristicV1`, `recovery-heuristic-v1@1.0.0`）
- **实现位置**：`BodySeekKit/Sources/BodySeekCore/MuscleRecoveryEngine.swift`（`MuscleRecoveryEngine`, `WorkoutAutoAttributor`）与 `BodySeekKit/Sources/BodySeekCore/WorkoutReviewParser.swift`
- **当前状态**：**启发式估计（工程单测与 GRDB 事务审计已验证 / 生理与临床肌电有效性未验证）** — 所有 UI 面板及 Coach 工具返回必须显式带有「**启发式估计**」标注。

## 1. 数学模型（非负指数疲劳累积）

遵照 V4 审查意见 §2.4，摒弃可能出现负恢复值的线性相减形式 $1 - \sum L \cdot e^{-\Delta t/\tau}$，采用**严格有界的非负指数衰变模型**：

$$F_m(t) = \sum_{i:\; t_i \le t} L_{m,i} \cdot \exp\!\left(-\frac{t - t_i}{\tau_m \cdot \alpha_{\text{sys}}(t)}\right)$$

$$R_m(t) = \exp\!\left(-F_m(t)\right) \in (0,\, 1]$$

其中：
- **部位时间常数 $\tau_m$**（经验启发式参数）：
  - 下肢与后链大肌群（`quadriceps` / `hamstring` / `gluteal` / `lowerBack`）：`60 h`
  - 躯干核心推拉大肌群（`chest` / `upperBack`）：`48 h`
  - 肩袖与上背稳定肌群（`deltoids` / `trapezius`）：`42 h`
  - 远端与高频恢复肌群（`biceps` / `triceps` / `forearm` / `calves` / `abs` / `obliques`）：`30 h`
- **全身恢复调节系数 $\alpha_{\text{sys}} \in [0.80, 1.30]$**：
  - **无循环依赖保证**：$\alpha_{\text{sys}}$ **仅**读取昨夜原始睡眠时长（`sleepAsleepMinutes`）与今晨原始静息自主神经指标（`hrvMs`、`restingHeartRateBpm`）及其此前 28 日历史基线，**严禁**读取当日 `Strain`、`Recovery` 合成总分或训练列表，防止反馈环路。
  - 若上述原始信号缺测，保持中性系数 $\alpha_{\text{sys}} = 1.0$，绝不将缺测当零压低系数。
- **预计就绪时间 $t_{\text{ready}}$**：以 $R_m \ge 0.85$（即 $F_m \le -\ln(0.85) \approx 0.1625$）作为主项就绪参考阈值：

$$t_{\text{ready}} = \begin{cases} 0, & F_m \le -\ln(0.85) \\ \tau_m \cdot \alpha_{\text{sys}} \cdot \ln\!\left(\dfrac{F_m}{-\ln(0.85)}\right), & F_m > -\ln(0.85) \end{cases}$$

## 2. 负荷来源与 Effort 分离策略

1. **有氧/持拍运动自动归因 (`WorkoutAutoAttributor`)**：
   - `Running` / 跑步、`Walking` / 步行、`Badminton` / 羽毛球、骑行、划船、游泳按持续时间、心率区间 `TRIMP`（无分区时回退平均心率或时长）及 `Settings -> dominantHand`（持拍手）自动生成启发式负荷，写入 `workout_muscle_load` 并标为 `autoAttributed`。
2. **力量训练进入待复盘 Inbox (`WorkoutReviewState.unreviewed`)**：
   - 力量类记录不猜测具体部位，进入待复盘 Inbox，经用户一句话复盘确认后在事务内落盘 `workout_annotation` + `workout_muscle_load`。
   - `WorkoutEffortScore`（`effort_user`）与 `EstimatedWorkoutEffortScore`（`effort_estimated`）始终分字段存储与展示。

## 3. 适用范围与局限性

- **适用用途**：直观呈现近 7 天局部肌群刺激叠加大致节奏，防止连续高容量撞车；触发练后身体不适信号（如“右肩紧”）转入 14 天过期保护约束。
- **不适用用途与已知局限**：$\tau_m$（30–60h）与自动归因权重属于单用户经验启发式，未经过肌酸激酶（CK）、表面肌电或等速肌力测力标定；实际恢复高度受蛋白质摄入、局部拉伸、主观疲劳与动作离心比例影响。
