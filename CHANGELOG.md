# Changelog

所有值得记录的变更。格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

> 现行版本（2026-11-22）：分支 `codex/ui/ios26-native-bodyseek`，主屏幕名 BodySeek，bundle `com.sunweizhou.Vela4`，部署底线 iOS 26.0，五个一级页面：今日 / 健身 / 营养 / 趋势 / Coach。架构为 `BodySeekKit`（SwiftUI + TCA + GRDB + HealthKit）加薄壳 `VelaApp`。下面 2026-10-06 之前的条目描述的是已被取代的 iOS 17、四个一级页面时代。

## [Unreleased]

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
