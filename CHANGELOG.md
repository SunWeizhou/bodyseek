# Changelog

所有值得记录的变更。格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

> 现行版本（2026-11-22）：分支 `codex/ui/ios26-native-bodyseek`，主屏幕名 BodySeek，bundle `com.sunweizhou.Vela4`，部署底线 iOS 26.0，五个一级页面：今日 / 健身 / 营养 / 趋势 / Coach。架构为 `BodySeekKit`（SwiftUI + TCA + GRDB + HealthKit）加薄壳 `VelaApp`。下面 2026-10-06 之前的条目描述的是已被取代的 iOS 17、四个一级页面时代。

## [Unreleased]

### UI v4 融合（2026-11-23）

> 规格：`docs/design/ui-v4-integration.md`；报告：`docs/validation/ui-v4-2026-11-23.md`。分支 `v6/ui-v4`。

- 文档：dataviz 作废"过程用灰色、只有结论用颜色"；AI 估算改为 45° 斜纹，排除改为中性灰块；design-system §5 指向 v4 规格。
- 后续步骤（令牌与骨架、平时范围逐日滚动、今日、趋势、营养、健身、Coach 核对）逐步追加于此。

### V6 第六轮：页面迁移与图表重画（2026-11-23）

> 详见 `docs/validation/v6-round6-2026-11-22.md`。设计门禁 769 / 66 → 0 / 0。

#### Added

- `BSBodyMap`（包装 `MuscleMap`）、`FitnessFatigueChart`、`IntakeBarChart`；`BodySeekCore/FitnessFatigue.swift`（体能 CTL 42 天、疲劳 ATL 7 天，指数加权）与 7 项单元测试。
- 令牌：`BSSpace.none`、`BSSize.dot / glyph / avatar / bodyMapWidth / bodyMapHeight`、`BSChartStroke.estimateDash`。
- 营养页微量营养素二级页；趋势页"实验室"二级页（预测、规律、个人对照实验）。

#### Changed

- 五个一级页面按 L0–L3 重排：今日（分数环 + 简报 + 行动 / 睡眠 / 体征 / 摘要）、健身（肌群图 + 体能疲劳 + 待复盘行动行）、营养（摄入环 + 简报 + 本周热量）、趋势（五项分数纵览 + 五张统计头联动的趋势图 + 实验室）、Coach 与指标详情（`BSCard` 与令牌）。
- 图表按 dataviz §4 重画：去掉渐变、多余图层和多余虚线，线宽与颜色改用令牌。
- `BSScoreRing`、`BSActionRow`、`BSStateView`、`BSCoachNote` 增加无障碍标识与 zoom 来源参数。

#### Removed

- 今日页的快速结论横幅、主动洞察列表、AI 参考依据折叠区；营养页的"AI 解读"按钮和底部快捷栏；趋势页的指标切换条、恢复与负荷对照卡。`TrainingLoadDashboardCard`、`LoadRecoveryComboChart` 文件保留，页面不再调用。

### V6 第五轮：每日简报（2026-11-22）

> 详见 `docs/validation/v6-round5-2026-11-22.md`。

#### Added

- `DailyBrief`：唯一的结论对象（headline、changes、actions、各页面解读、证据）。引擎顺序为云端 → 端侧 → 本地模板，含未核实数字时回落；按输入摘要缓存，输入变化即过期重生成。
- `BriefFeedbackBar`：准 / 不准 / 没用，写入 `brief_feedback`。
- 测试：`DailyBriefTests`。

#### Changed

- 营养页、趋势页的 AI 解读槽位改读简报的 `pageNotes`，不再各自调用 `generatePageInsight`。
- `BSReceipt` 的无障碍层级由 `combine` 改为 `contain`，撤销按钮可单独点击并带标识（`coach-receipt-undo`）。
- UI 测试 `testCoachAnnotationConfirmAndUndo`、`testM3CoachProposals…` 改为断言回执卡与撤销。

### V6 第四轮：读写通路与动作层（2026-11-22）

> 未编译。详见 `docs/validation/v6-round4-2026-11-22.md`。

#### Added

- 动作层：`ActionExecutor.executeAction` 按 AppAction 风险级别执行（A、B 级直接执行并返回回执，C 级返回"需要确认"），单事务写入业务数据与 `action_audit`（`risk_level`、`source`、`undo_deadline`、before/after 快照）；`undoAction` 按原操作 ID 撤销，检查冲突，B 级 24 小时期限，训练标注复用原有撤销实现。
- `BodyModelStore`（`BodySeekStore`）：用 `ValueObservation` 广播身体模型只读快照；`AppFeature` 增加数据库观察驱动的刷新，原刷新路径保留作兜底。
- Coach：`execute_action` 工具；`propose_memory`、`propose_workout_annotation` 在有动作层时直接执行并返回回执；`propose_plan_change` 保持 C 级确认卡片；系统提示词补充三级授权；端侧模型新增对应工具。
- `CoachReceiptCard`：用 `BSReceipt` 展示回执并支持撤销，撤销后刷新相关页面。
- `BodySeekStoreClient` 新增 `executeAction`、`undoAction`、`loadRecentActionReceipts`、`loadMessageReceipts`、`observeBodyModel`。
- 测试：`ActionLayerTests`、`CoachActionLayerTests`。

#### Changed

- 设计门禁扫描范围加入 `BodySeekDesign/Components`（Gallery 不纳入），基线 767 / 66 → 769 / 66。
- `undoConflict` 的提示语改为通用。

### V6 第一轮：地基整理（2026-11-22）

> 本轮没有在有 Xcode 工具链的环境里编译和测试；新增 Swift 代码待本机 `swift test` 验证。详见 `docs/validation/v6-round1-2026-11-22.md`。

#### Added

- 设计文档入库：`docs/design/v6-blueprint.md`、`docs/design/design-system.md`、`docs/design/dataviz.md`，可交互原型 `design/prototypes/dataviz-v2.html`，状态均为 Accepted（2026-11-22）。
- ADR 0020（Coach 高度自主与 AppAction 三级授权，取代 ADR 0008 的授权部分）、ADR 0021（四个身体子模型、`DailyBrief` 唯一结论来源、实验室准入）。
- 设计令牌（`BodySeekDesign/Tokens/`）：`BSTokens.swift`（`BSSpace`、`BSRadius`、`BSOpacity`、`BSSize`、`BSChartStroke`）、`BSColor.swift`、`BSText.swift`、`BSMotion.swift`（含 `BSPressableStyle`）。只新增，没有迁移任何页面。
- 设计门禁 `scripts/check_design_system.py` 与基线 `docs/validation/design-system-baseline-2026-11-22.md`；CI 中以只报告方式运行。
- AGENTS.md 与 CLAUDE.md 新增「V6 开发规则」。

#### Changed

- `BodySeekMotion.standard` 的阻尼从 0.82 改为 1.0（默认弹簧不再回弹，唯一调用点是分数环的数值动画）。
- `docs/VELA_DESIGN_LANGUAGE.md` 标注为被 `design-system.md` 取代；`docs/design/chart-grammar.md` 标注视觉画法由 `dataviz.md` 取代，四态语义与 X 轴刻度规则继续有效。
- `docs/architecture/bodyseek-modularization-map.md` 归档到 `docs/archive/architecture/`。
- ADR 索引新增 0020、0021，并在 0008 行标注授权部分被 0020 取代。README、CLAUDE.md、docs/README.md 的设计文档入口指向新文档。
- 本文件顶部的现行版本描述改为当前事实。

### V6 第三轮：数据层（2026-11-22）

> 未编译。详见 `docs/validation/v6-round3-2026-11-22.md`。读源码发现训练模板、训练记录、记忆、Coach 消息早已读写 GRDB，SwiftData 只用于一次性导入，所以本轮只做新增部分。

#### Added

- GRDB 迁移 `v7_daily_brief_and_action_layer`：`daily_brief`、`brief_feedback` 两张表，`action_audit` 加 `risk_level`、`source`、`undo_deadline` 三列。
- `BodySeekRepository+Brief.swift`：简报缓存、过期标记、反馈读写。
- 测试：导入 → 重新打开数据库 → 清空 → 再导入；简报缓存与反馈往返。

#### Changed

- `resetAll` 同步清空新表；迁移标识符稳定性测试加入 v7。

### V6 第二轮：组件库（2026-11-22）

> 只改 `BodySeekDesign`，未编译。详见 `docs/validation/v6-round2-2026-11-22.md`。

#### Added

- `BodySeekDesign/Components/`：`BSPage`、`BSSection`、`BSCard`、`BSNavRow`、`BSLabEntry`、`BSScoreRing`（L/M/S 与 `.group` 排布）、`BSMetricTile`、`BSMetricGrid`、`BSDeltaBadge`、`BSVerdictChip`、`BSVerdictGrid`、`BSIntakeRing`、`BSStateView`、`BSCoachNote`、`BSActionRow`、`BSReceipt`、`BSEvidenceChip`、`BSAskCoachButton`、`BSChartCard`、`BSChartHeader`。组件内置四态、加载骨架、按压反馈，并适配减弱动态效果、降低透明度、增强对比度、区分颜色。
- `BodySeekDesign/Gallery/DesignSystemGallery.swift` 与 `#Preview`（尚未接入 App 启动参数）。

#### Changed

- `bsText(.label / .caption)` 在增强对比度下升为一级文字色。

### 2026-11-16 至 2026-11-22：V5 重建

> 来源：`.git/logs/HEAD` 中 2026-10-06 之后的提交信息。2026-10-08 至 2026-10-26 之间的约 50 个 Design D 单色界面提交（`cursor/*`、`codex/ui/*` 分支）已被 11-16 之后的重建取代，这里不逐条展开。

#### Added

- 2026-11-19：Swift 6 `BodySeekKit`（TCA + Spezi）重写基线（`a9f32e6`），ADR 0019，并同步 PRD、TECH_ARCHITECTURE 与 CONTEXT。
- `BodySeekCore` V5 共享合同（`HealthObservation`、四态 `MetricAvailability`）；`score-v2` 版本化，3 年新旧引擎真实回放对比，五份模型卡更新。
- GRDB 7 `BodySeekStore`（Schema v1、`SleepMergePolicy`、`ChartContracts`）、`ReadModel` 与预计算 `ChartSeriesSnapshot`、每日营养素数据层；`SyncEngine` 锚点增量同步、3 年可续传回填、3 秒防抖。
- 原生 `BodySeekDesign` 与 8 类 `BodySeekChart` 图表；今日行动卡、五项专属详情页、趋势 3 年胶囊图、每日营养素看板。
- Watch-First 肌群恢复启发式引擎（`recovery-heuristic-v1`）、自动归因、一句话复盘解析器、55 例评测集，以及待复盘 Inbox、肌群恢复详情、训练档案。
- `BodySeekAgent`：轻量客户端、四态只读工具、数字溯源校验、30 题评测集；三层记忆管理、提案确认卡片、主动洞察、隐私数据预览。
- 每日体感打卡（精力 / 情绪 / 压力 / 酸痛）。
- `BodySeekML` 离线建模：个人规律报告 v1、M4b 滚动回测、M4c Masked TCN / PatchTST-Lite 配对检验、M4d CoreML 导出；CoreML 个人预测双端对拍、N-of-1 自实验模板、趋势预测卡片。
- AI 记饮食草稿多餐落库、Coach Markdown 回复；DeepSeek 联网搜营养、中式快餐优化、营养页 Coach 建议；微量营养估算状态与结账缺项提示。
- 7 天 / 28 天恢复证据查询与类型化来源核验；唯一 Watch 标注、跨页刷新与可撤销审计。
- `os_signpost` 性能探针与 M0 性能基线。

#### Changed

- 部署底线升至 iOS 26，采用原生 `TabView` 与 Liquid Glass（ADR 0018，分支 `codex/ui/ios26-native-bodyseek`）。
- API Key 迁回 Keychain，并清除持久化与网络路径上的静默 `try?`。
- CI：修复失效门禁并启用第一方 warnings-as-errors；固定 Xcode 26.5.0；xcodebuild 加 `-skipMacroValidation`；beta lane 使用 Release 并校验导出 IPA。
- 趋势全窗口胶囊图并统一为 `TrendHorizonChart`，分周期桶粒度进入数据合同；全面升级 Apple Swift Charts，重构健身负荷仪表盘并移除旧手动模块；今日仪表盘重排。
- 性能：图表快照共享日索引、N-of-1 评估状态缓存、HealthKit 窗口查询并行化、视图日期格式化静态缓存、启动只做一次 recent sync 并读 ReadModel、v6 睡眠目标缓存键与批量写入。

#### Fixed

- 3 年趋势时间轴、Coach 滚动顶栏、BodySeek 权限文案、趋势区间图年月刻度；`PreviewSeedFactory` 生理日 key。
- 多候选忽略与撤销按钮禁用状态；撤销快照解析失败返回明确错误；溯源解析中剩余的静默 `try?`。
- AI 记饮食：分析超时重试与截断重试，照片后台缩放与并行食物库匹配。
- 审计修复：重置二次确认与范围透明、禁止非预览态写入预置规律、复盘防空白误写、打卡实时同步 Coach、营养月看板防卡死；ACWR 基线覆盖判定、预测逐指标证据透明度、压力能量未来时间线口径、营养联网隐私最小化与完整审计、AI 解读版本防过期；大字号引导与今日页截断、趋势图读数锁留去遮挡、营养月矩阵全 30 天覆盖。
- 同步：阻止旧数据重现、串行同步并表达睡眠删除；今日按生理日选取并补齐预测日历；异步请求身份绑定并截断已结束实验；衍生分数与游标同事务提交；下拉刷新数据未变时仍重生成简报。

### 历史条目（以下为 2026-10-06 及更早，描述的是已被取代的 iOS 17 / 四个一级页面时代）

### Changed（2026-10-06 版本锁定）

- （历史，已被取代）当时的现行版本在分支 `cursor/recovery-detail-v2-1d20`：四个一级表面，部署底线 iOS 17 / watchOS 10。
- 与现行界面矛盾的根目录旧文稿移入 `docs/archive/product-eras/`。Finder 重复的设计副本已删除。生产路径里注释掉的旧睡眠分调用已去掉。
- 删除未走上生产路径的应用内 `VelaApp/Scoring/Sleep/SleepScoreEngine.swift`。预览改走 `DomainSleepScoreAdapter`。锁定睡眠分行为的测试改打 `BodySeekDomain.SleepScoreEngine`。计分公式未改。

### Fixed（2026-08-23 工程标准审计 C1/C2/H2/H5/H7）

- **SwiftData schema 版本守卫**：新增 `VelaSchemaV3Frozen` 冻结快照（脚本生成）与 `scripts/schema_fingerprint.py --check` CI 门禁；模型图变更必须与版本提升同提交原子完成。
- **HealthKit 错误不再被吞成「无数据」**：仅 `errorNoData` 走空数据分支；授权/参数/数据库错误按组件分类记录并保持当日 dirty 重试；`lastSuccessfulSyncAt` 仅在无失败日推进。
- **查询有界化**：`fetchSnapshots` 降序 + fetchLimit；隐私清点改用 `fetchCount`；流式 markdown 解析缓存（消除 0.5s 心跳全文重解析）。
- **CI 硬化**：schema 守卫、工具链校验、确定性模拟器选择、xcresult 失败上传、`*.log` 出仓、`.xcode-version`。
- **数据删除盲区**：`daily_logs` 明文归档与 `VelaRecovery` 恢复备份纳入「清空本地数据」。

### Fixed（工程标准审计 H1/H3/H4/H6/H8）

- **Dynamic Type**：小字号字体工厂改用系统 TextStyle（默认字号不变、随缩放）。
- **后台预算**：BGAppRefreshTask 复用 App 容器，省去重复打开 store/迁移检查。
- **日志收敛**：16 处 `print` 迁移到 `os.Logger`（带 `privacy` 标注）。
- **对比度**：新增文字用状态色 `VelaTheme.textColor(for:)`（WCAG AA ≥4.5:1），6 处文字切换。
- **可访问性**：3 处低于 44pt 命中区提升到规范值；Tab 栏补 `accessibilityIdentifier`。

### Added

- 新增测试 15 个（schema 守卫 / HealthKit 错误分类 / 隐私删除完整性）；全量套件通过。
- `README.md`、`CHANGELOG.md`、`docs/validation/engineering-audit-2026-08-23.md`（审计报告）。
