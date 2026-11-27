# 设计系统门禁基线（2026-11-22）

> 状态：基线记录（V6 第一轮，任务 B）
> 依据：[设计系统 §10.3](../design/design-system.md)、[数据可视化规范 §8](../design/dataviz.md)
> 工作树：分支 `codex/ui/ios26-native-bodyseek`，reflog 末条提交 `34b74d40`；第一轮的改动尚未提交
> 命令：`python3 scripts/check_design_system.py`（退出码 0，只报告）。扫描范围 45 个 Swift 文件：`BodySeekFeatures` 与 `BodySeekDesign/Charts`，排除 `BodySeekDesign/Tokens`

## 1. 实测结果

| 规则 | Features | Charts | 合计 |
| :--- | ---: | ---: | ---: |
| `padding` .padding(数字) | 183 | 14 | 197 |
| `spacing` spacing: 数字 | 259 | 42 | 301 |
| `corner-radius` cornerRadius: 数字 | 41 | 14 | 55 |
| `opacity` .opacity(0.xx) | 28 | 57 | 85 |
| `frame` .frame(width/height: 数字) | 39 | 21 | 60 |
| `hex-color` adaptive("# / Color(red: | 0 | 0 | 0 |
| `fixed-font` .font(.system(size: | 0 | 1 | 1 |
| `shadow` .shadow( | 0 | 2 | 2 |
| `gradient` Gradient | 0 | 4 | 4 |
| `plain-button` .buttonStyle(.plain) | 58 | 3 | 61 |
| `fixed-curve` .easeInOut( / .easeOut( / .linear( | 1 | 0 | 1 |
| `damping` dampingFraction / dampingRatio（BSMotion 之外） | 0 | 0 | 0 |
| `kerning` .kerning( / .tracking( | 0 | 0 | 0 |
| `chart-linear-gradient` [Charts] LinearGradient | 0 | 4 | 4 |
| `chart-line-width` [Charts] lineWidth: 数字 | 0 | 46 | 46 |
| `chart-dash` [Charts] dash: [ | 0 | 16 | 16 |
| **通用规则合计** |  |  | **767** |
| **图表专项合计（`chart-linear-gradient` 与 `gradient` 重叠）** |  |  | **66** |

通用规则 13 条合计 **767** 处；不含 `spacing` 为 466 处。

## 2. 违例最多的 10 个文件

| # | 文件 | 违例数 | 主要规则 |
| ---: | :--- | ---: | :--- |
| 1 | `BodySeekKit/Sources/BodySeekFeatures/Views/TrendsView.swift` | 77 | spacing×32, padding×27, corner-radius×7 |
| 2 | `BodySeekKit/Sources/BodySeekFeatures/Views/TodayView.swift` | 77 | spacing×50, padding×16, plain-button×6 |
| 3 | `BodySeekKit/Sources/BodySeekFeatures/Views/WorkoutView.swift` | 74 | padding×27, spacing×20, plain-button×11 |
| 4 | `BodySeekKit/Sources/BodySeekFeatures/Views/Nutrition/NutritionBoardView.swift` | 73 | spacing×27, padding×19, frame×12 |
| 5 | `BodySeekKit/Sources/BodySeekFeatures/Views/CoachView.swift` | 71 | padding×30, spacing×22, plain-button×9 |
| 6 | `BodySeekKit/Sources/BodySeekDesign/Charts/TrainingLoadDashboardCard.swift` | 57 | spacing×15, padding×10, opacity×9 |
| 7 | `BodySeekKit/Sources/BodySeekFeatures/Views/Workout/WorkoutReviewSheetView.swift` | 33 | padding×12, spacing×12, plain-button×5 |
| 8 | `BodySeekKit/Sources/BodySeekDesign/Charts/ForecastFanChart.swift` | 28 | opacity×9, chart-line-width×6, spacing×4 |
| 9 | `BodySeekKit/Sources/BodySeekFeatures/Views/ActiveWorkoutSheetView.swift` | 25 | spacing×11, plain-button×5, frame×4 |
| 10 | `BodySeekKit/Sources/BodySeekFeatures/Views/MetricDetails/StrainDetailView.swift` | 22 | spacing×8, padding×5, frame×4 |

前五个页面级文件（Trends、Today、Workout、NutritionBoard、Coach）合计 372 处，占通用规则总数的约 48%，是第二轮之后逐页迁移的主要工作量。

## 3. 与负责人估算的对照

- 负责人估算总违例约 **440** 处。设计系统 §0 的口径是：padding 197、cornerRadius 55、opacity 95、frame 58、hex 32、固定字号 2、阴影与渐变 8、`.buttonStyle(.plain)` 61、固定曲线 1，合计约 509，不含 `spacing:`。
- 本次实测按 16 条规则逐条统计，**通用规则合计 767**。其中 `spacing: 数字` 单项 301 处（`HStack(spacing: 8)` 这类写法），§0 的表格没有单列这一项；不含 `spacing` 时合计 **466**，与估算（约 440）和 §0（约 509）同一量级。**以 767 作为含 spacing 的正式基线，466 作为与 §0 口径可比的基线。**
- 图表专项（Charts 目录）：LinearGradient 4、`lineWidth: 数字` 46、`dash: [` 16，与 dataviz §8 的数字（4 / 46 / 16）完全一致。
- 与 §0 数字有出入的项：
  - hex 颜色：实测 **0**（§0 为 32）。§0 的 32 处在 `BodySeekDesign/Tokens/BevelTheme.swift` 的 `adaptive("#…")` 里，门禁按规则排除 Tokens 目录；`BodySeekFeatures` 和 Charts 里已经没有 hex 颜色。
  - opacity 实测 85（§0 为 95）、frame 实测 60（§0 为 58）、固定字号实测 1（§0 为 2）、阴影加渐变实测 6（§0 为 8）。差异来自统计口径：脚本先剔除注释，`frame` 按整个调用解析多行参数；以及 §0 统计之后的代码改动。
- 脚本的局限：逐文件文本匹配（已剔除注释），不解析 Swift 语法。跨多行拆开的 `.padding(` 参数，或变量名恰好叫 `width:` 的自定义函数调用，可能有少量漏报或误报。它的目的是给出趋势基线和阻断开关，不是语法检查。

## 4. 用法

```bash
# 只报告（CI 里就是这样跑的，永远不会失败）
python3 scripts/check_design_system.py

# 列出每处违例的行号
python3 scripts/check_design_system.py --details

# 以 Markdown 表格输出（用于更新本文件）
python3 scripts/check_design_system.py --markdown

# 某个页面迁移完成后，把它切换为阻断（该前缀下还有违例就以退出码 1 结束；前缀不存在以退出码 2 结束）
python3 scripts/check_design_system.py --strict BodySeekKit/Sources/BodySeekFeatures/Views/TodayView.swift
```

## 5. 迁移节奏

按 [设计系统 §10.3 与 §11](../design/design-system.md)：先只报告并记录基线（本文件），每迁移完一个页面就把对应前缀加入 `--strict`，五个页面全部迁移后，整个 `BodySeekFeatures` 与 `BodySeekDesign/Charts` 改为阻断。
