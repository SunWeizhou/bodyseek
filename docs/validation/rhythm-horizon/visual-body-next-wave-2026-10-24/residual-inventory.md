# Design D next wave · 修改前清单

基线：`f2b83b9cac059f775ad7614b3124fe2051d05cfc`（最新 origin/main，#18 squash）。2026-10-24，起始 dirty 为空。分支 `cursor/visual-body-next-wave-20261024`。

先运行既有 fixed-font strict 与 token report，再扩大到 Swift 的 shorthand colors、UIColor、shadow、stroke、gradient 搜索。旧 token report 不捕获 `.white` / `.indigo`，且把 token 圆角也计为硬编码，因此只作候选清单，不把总数当成违规数。

| 优先级 | 文件（相对 VelaApp） | 当前残留 / 实施边界 |
| --- | --- | --- |
| P1 Settings | Features/Minimal/SettingsCoachModelView.swift | 模型保存/授权/同步 CTA 白字；权限用途彩色；CGM 蓝色装饰、白色卡片；固定 CTA 高度 |
| P1 Settings | Features/Minimal/SettingsAccountView.swift | 档案删除 shorthand red、固定文字字号；资料表单大字体排列抽检 |
| P1 Settings | Features/Minimal/VelaSettingsView.swift; Features/Settings/TrustCenterView.swift; BiologyView.swift | 0.75pt mist 面板；chip 黑色硬编码；Settings pills 大字体截断 |
| P1 Settings | Features/Minimal/PrivacyDataControlsView.swift | 导出 CTA 白字、shorthand error/success 色 |
| P2 Coach | Features/Coach/CoachWelcomeWorkspace.swift | 报告/生成物 `.indigo` / `.orange`；报告列表缺少统一 hairline |
| P2 Coach | Features/Coach/CoachView.swift; WikiProfileView.swift; Features/SharedComponents/CorrelationArtifactView.swift | 输入/次态边框未引用宽度 token；档案保存白字；相关卡片 borderSoft，固定标题字号及 pills |
| P3 Training / Plan | Features/Training/WorkoutDetailView.swift; TrainingIntelligence/Views/StrengthWorkoutDetailView.swift; StrengthWorkoutLogSheetView.swift; Features/Minimal/VelaTrainingPlanView.swift | 路线 marker 白色/阴影；力量指标白色面板和白字；二级页固定文字字号；Plan 次态边框 |
| P4 Sheets / shared | Features/SharedComponents/WeightLogSheetView.swift; VelaQuickActionsSheet.swift; Features/Minimal/TodayEvidenceSheet.swift; TodayHeroCard.swift; JournalTagInsights.swift; Core/DesignSystem/VelaInput.swift; VelaDesignSystem.swift | on-ink 对比、固定高度、Evidence 面板/文字；shared shimmer 白色硬编码 |
| P4 remaining chrome | Features/Minimal/TodayWeatherBar.swift | 0.75pt 硬编码白描边，仅更换 token，不动布局 |

`appleIntelligenceGlow` 已在主线定义为 no-op：调用名仍在，实际没有 glow；不把删除这些调用当成视觉修复。图表线、路线和进度环属于数据 mark，不把所有 lineWidth > 1 机械改成面板 hairline。

刻意跳过：Watch / WidgetKit 视图（含 VelaMetricDetailWidgets 内 widget 预览段）、CoachHistoryDrawer、评分/输入/schema/Store/导航、Today 横条五分/Speak/chips 主布局。保留数据语义色（心率区间/睡眠阶段）、错误/破坏性操作的语义提示；仅将 shorthand 改为语义 token。

证据计划：SE 375pt / iOS 26.5、中文、Dark + Light / AccessibilityXXXL；Settings 子页、Coach workspace 次态与报告/生成物列表、Plan 编辑与 Quick Actions/Evidence/体重 sheet、其它详情大字体。无法构造的 populated artifact/真实训练状态明确标未验证。命令与最终结果追加现有 docs/validation/audit-fix-status.md。

## 首轮截图发现（实施中追加）

- Strength 训练建议出现大块亮黄：`VelaTheme.fillSoft` 使用 RGBA 字符串，但既有 hex helper 按 AARRGGBB 解析。只纠正该视觉 token 的 alpha 字节位置；加两种外观的 achromatic / translucent 回归。
- Strength hero 图标 lightBlueSoft、训练 PR softGold 与 warm neutralCapsule 仍是装饰色，改为现有 mono tokens。
- RecoveryDetailV2 的历史样本 badge、依据三列与缺失天数 caption 在 AccessibilityXXXL 下截断；只做纵向 reflow / 图高调整，不改 model、字符串或统计。
- VelaMinimalShell 的两个黑色 scrim 常量收进语义 VelaTheme.scrim；透明度与动作不变。
- MetricChartSection 的 8pt 基线文字与 shared header 文字改用已有动态字体 token。其余固定字号主要为 SF Symbols / wordmark / widget 显示几何。

- 最终逐图 QA 发现 WeightLogSheet 紧凑 DatePicker 在 AccessibilityXXXL 下横向撑宽；大字体单独用 graphical 日期布局，补视口内 TextField 边界断言与滚动截图，默认字号保持 compact。
