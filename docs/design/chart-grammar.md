# BodySeek Chart Grammar — 原生视觉与图表语法规范

> **状态**：Canonical（M1-UI 实施唯一视觉与图表准绳）
> **适用范围**：`BodySeekDesign` 模块内 `BodySeekChart` 组件族（8 类组件）、`BodySeekFeatures` 全部图表调用方、`每日营养素` 状态可视化
> **上位约束**：`docs/VELA_DESIGN_LANGUAGE.md` · `docs/adr/0019-bodyseek-v5-architecture-and-modeling-baseline.md` · V5 蓝图 §7.2

---

## 1. 模块与边界铁律

1. **单一图表组件族 `BodySeekChart`**：`BodySeekFeatures` 与 `VelaApp` **严禁**直接 `import Charts` 或手写 `Chart { ... }`；所有图表统一通过 `BodySeekDesign` 导出的 8 个受控组件渲染。
2. **在设计层复用已验证的实现**：默认使用 **Swift Charts (`Charts`)** 与 **SwiftUI `Canvas`**。允许 `BodySeekDesign` 接入能够保留数据语义的开源组件。今日睡眠摘要的连续分期由 `SleepChartKit 1.2.0` 渲染，有缺测、重叠或需要选点的场景继续使用支持对应语义的原有图表。
3. **Zero Permanent Loop Animation**：禁止在背景渐变、光环、角标或图表中长期运行 `.repeatForever` 动画，减少 120Hz 掉帧与功耗。

---

## 2. 八类图表组件与指标映射

| # | 组件名 | 底层技术 | 适用场景 | 核心视觉元素 |
| :- | :--- | :--- | :--- | :--- |
| 1 | `TrendLineChart` | Swift Charts | **7 天 / 30 天**五项指标趋势、详情页短期趋势 | 分段折线 + 顶部柔和面积渐变 + 个人 IQR 基线带 + 中位虚线 + 缺失断线 + 零值实心点 + 排除斜纹带 |
| 2 | `RangeCapsuleChart` | Swift Charts | **6 个月（按周）/ 3 年（按月）**多周期分布趋势 | min–max 极值细须（`RuleMark`）+ P25–P75 圆角胶囊（`BarMark`）+ 中位圆点（`PointMark`）+ 个人基线带 |
| 3 | `SleepStageChart` | SleepChartKit（连续摘要）或 SwiftUI Canvas（带缺测或交互） | 今日睡眠卡 & 睡眠详情页昨夜睡眠分期 | 4 轨水平时间轴（清醒 / REM / 核心 / 深睡）+ 圆角分期块 + 相邻块半透明阶梯连线 + 入睡/中点/起床刻度 |
| 4 | `IntradayBarChart` | Swift Charts | 24 小时自主神经压力节律（微图 & 详情交互图） | 24 根分时柱 + 压力分档语义着色 + 运动排除窗口斜纹覆盖带（`"运动排除"`） |
| 5 | `EnergyAreaChart` | Swift Charts | 昼夜电池充放电曲线（微图 & 详情交互图） | 平滑 `.catmullRom` 面积折线 + 50% 参考虚线 + 晨起峰值/当前电量点标 |
| 6 | `LoadRecoveryComboChart` | Swift Charts | 趋势页「恢复 × 负荷演化对照」 | 同 0–100 坐标系：日负荷圆角柱（Strain）+ 恢复储备折线（Recovery，缺失断线）+ 内置图例 |
| 7 | `ZoneBar` | SwiftUI Canvas / Geometry | 锻炼心率区间 Z1–Z5 分布（今日训练卡、负荷详情、健身档案） | 比例堆叠圆角段 + AX5 自适应折行分钟图例 + 可选 `TRIMP` 负荷标记 |
| 8 | `MiniSparkline` | SwiftUI Canvas | 今日生理体征 2×2 网格、趋势纵览列表行、Coach 证据卡 | 高帧率轻量绘制：随 `nil` 真实断线 + 柔和面积填充 + 可选基线带 + 末端圆点；不足 2 点显示虚线占位 |

> 本地视觉对齐参考：Apple Fitness（三环与心率区间胶囊比例）、Apple Health（阶梯睡眠分期与多月区间胶囊）、`docs/reference/bevel-3.1.4/`（本地只读对标参考，不入 git）。

---

## 3. 坐标轴、刻度与数值排印

1. **X 轴显式刻度纪律（Zero Truncated Ticks）**：
   - 所有含时间横轴的图表通过共享 helper `ChartAxisSupport.explicitTickDates(start:end:maxTicks: 4)` 显式计算 **最多 4 个**起止对称的刻度位置；
   - **日尺度（24h）**：固定 5 点锚点 `00:00`、`06:00`、`12:00`、`18:00`（紧凑详情可裁剪为 4 个不拥挤标签，末尾不溢出裁切）；
   - **7 天**：`M/d`，首/中/尾最多 4 个刻度；
   - **30 天**：首日、第 10 日、第 20 日、末日（`M/d`，4 个刻度）；
   - **6 个月**：每约 2 个月 1 个刻度（`M月`，最多 4 个刻度）；
   - **3 年（1095 天）**：按年度或 12 个月步进显示 `yyyy年M月` / `'yy/M`（最多 4 个刻度）。
   - **禁止**让系统自动密集排版导致文字截断、重叠或省略号。
2. **Y 轴与网格**：
   - 使用极淡的 1pt（或 0.5pt）水平参考线（`BevelTheme.hairline.opacity(0.65)`），Y 轴标签置于 `.trailing`（不挤压左侧绘图区）。
3. **字体与数字对齐**：
   - 图表坐标、核心读数、选中锁定值与百分比统一采用 `.fontDesign(.rounded).monospacedDigit()`；
   - 数值切换使用 `.contentTransition(.numericText())`。

---

## 4. 色彩系统（Light / Dark & 每日营养素四态）

### 4.1 生理领域语义色（继承自 `VELA_DESIGN_LANGUAGE.md` / `BevelTheme`）

| 领域 | Light Hex | Dark Hex | 适用场景 |
| :--- | :--- | :--- | :--- |
| Canvas | `#F2F2F7` | `#000000` | 页面分组底 |
| Card | `#FFFFFF` | `#1C1C1E` | `.bodySeekSurface()` 卡片表面 |
| Brand / Recovery | `#168B70` | `#34D399` | 恢复环、HRV/RHR 曲线、主确认动作 |
| Sleep | `#5E5CE6` | `#8F8DFF` | 睡眠环、睡眠分期主色 |
| Strain | `#D85A20` | `#FF9565` | 负荷环、TRIMP 日柱、高负荷区分 |
| Stress | `#D9466E` | `#FF7596` | 日内压力柱、偏高时段 |
| Energy | `#B4730A` | `#F5BC47` | 充放电面积曲线 |

### 4.2 睡眠四期与每日营养素四态色

| 维度 | Token | Hex（Light/Dark 自适应） | 语义规则 |
| :--- | :--- | :--- | :--- |
| 营养达标 | `nutritionMet` | `#4A9D72` | 满足推荐范围且当日已结账 |
| 营养偏低 | `nutritionLow` | `#D79939` | 低于目标下界且当日已结账 |
| 营养偏高 / 超 UL | `nutritionOver` | `#D65C5C` | 高于目标上界或超过 UL 安全上限 |
| 未知 / 未结账 | `nutritionUnknown` | `#8A9099` | 缺测、样本不全或 `dietDayComplete != true`（绝不当作 0） |

---

## 5. 四态真值视觉表现（Honest Representation）

1. **`available`**：完整实线 / 实色柱 / 实心胶囊与中位圆点。
2. **`knownZero`**：明确记录为 0（如确认休息日 0 锻炼），绘制在基线 `0` 处并以**实心空心外环零值圆点**区分于无数据。
3. **`missing`**：必须**真正断线**（按连续有效段拆分 `segmentID` 传入 `LineMark(series:)`），**严禁跨缺失日直线连接或零填充**；全缺显示 `ChartEmptyPlaceholder`。
4. **`excluded`**：因运动后伪影、低佩戴覆盖或超出生理阈值被排除的区间，以低饱和度**45° 淡斜纹覆盖带（`DiagonalHatchPattern`）**标明，读数条提示具体排除原因，绝不混入正常曲线计算。

---

## 6. 交互、触觉、动效与无障碍

1. **顶部锁定读数条（No Floating Tooltips Over Curve）**：
   - 所有交互图表（`TrendLineChart`, `RangeCapsuleChart`, `SleepStageChart`, `IntradayBarChart`, `EnergyAreaChart`, `LoadRecoveryComboChart`）拖拽或点按时，读数锁定在**图表正上方固定读数栏**中，避免手指或气泡遮挡数据点。
   - 实时拖动选点保存在图表局部 `@State`，仅在选点变化时按需低频通知父级，触发 `.sensoryFeedback(.selection)`。
   - 无选点时读数栏默认显示当前主值/基线摘要；松手后保留最近一次锁定点或轻点切换清除，避免布局跳动。
2. **统一动效 Token**：
   - `BodySeekMotion.standard = .spring(response: 0.35, dampingFraction: 0.82)`；
   - `accessibilityReduceMotion == true` 时关闭弹性过渡，仅做直接状态切换。
3. **Dynamic Type 到 AX5 与 VoiceOver**：
   - 图表顶部读数栏与图例使用自适应 `ViewThatFits` / 换行 `Flow` / 纵向堆栈，保证 AX5（`.accessibilityExtraExtraExtraLarge`）下不截断、不重叠；
   - 主要图表提供 `accessibilityElement(children: .combine)` + 清晰的 `accessibilityLabel`/`accessibilityValue` 以及 `AXChartDescriptorRepresentable` 数据描述符（使 VoiceOver 可按点听读趋势与最值）。
