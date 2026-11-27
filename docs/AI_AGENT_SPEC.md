# BodySeek V5 AI Agent 开发指南

> Status: Canonical
> 核对日期：2026-11-21
> 范围：Coach、今日 AI 建议与 AI 记饮食的现行接线、数据合同和验证边界。
> 本轮开发按 [Coach 实施工单](design/coach-agent-implementation.md) 验收。对话写入、Ontology 与持续任务的产品目标见 [Coach Agent 顶层设计](design/coach-agent.md)。
> 核对基线：`codex/ui/ios26-native-bodyseek` 的 `63b8a9e8`，包含 `607e4494` 的实现。**接手时重新核对当前分支、HEAD、工作树和验证记录。** 产品需求见 [PRD](PRD.md)，架构见 [ADR 0019](adr/0019-bodyseek-v5-architecture-and-modeling-baseline.md)。8 月的 [L1–L4、Wiki 与固定报告规格](archive/product-eras/AI_AGENT_SPEC-2026-08-23.md) 已归档。

## 1. 生产入口与模型路由

从 [AppFeature](../BodySeekKit/Sources/BodySeekFeatures/Reducers/AppFeature.swift) 查看 GRDB ReadModel 如何接入今日、健身、营养、趋势和 Coach。从 [CoachFeature](../BodySeekKit/Sources/BodySeekFeatures/Reducers/CoachFeature.swift) 跟踪发送、上下文、回复及提案状态，再读 [CoachAIClient](../BodySeekKit/Sources/BodySeekAgent/CoachAIClient.swift) 和 [CoachToolRegistry](../BodySeekKit/Sources/BodySeekAgent/CoachToolRegistry.swift)。

| 场景 | 现行行为 |
| --- | --- |
| Coach 与今日 AI 建议 | 配置 API Key 后走用户设定的 OpenAI 兼容端点与模型，空端点或模型名使用 DeepSeek 默认值。Key 存 Keychain。未配置 Key 时按设备实际可用性选择 Apple Foundation Models，或展示未配置状态。云端失败显示连接异常。预览独立使用固定样例。 |
| Coach 连续对话 | 云端附带最近最多 6 条消息，含相关训练提案摘要。端侧以原生 `Transcript` 带入最近最多 4 条消息。历史用于理解追问，本轮引用的健康数值仍须取证。云端工具循环默认上限为 6。 |
| Watch 一句话复盘 | 端侧 Foundation Models 可用时用于解析，中文运动词典提供兜底。日期按实际训练的生理日解析和确认。 |
| 营养页 AI 记饮食 | 独立草稿流程，接收一段全天文字，支持附餐食照片。分析会向用户配置的服务发送本次文字或照片，界面标明发送对象。确认前可核对所选日期并调整餐次、份量和成分。见 [产品规格 §5.7](PRD.md#57-营养与能量平衡nutrition)。 |

以 [AgentRoutingPolicy](../BodySeekKit/Sources/BodySeekAgent/OpenAICompatibleClient.swift) 和实际入口为准。引擎标签用于识别该次响应的路径。诊断回答质量时同时核对工具调用、返回覆盖率、上下文和最终回复。设置页的连接测试仅验证端点可连。

## 2. Coach 可使用的证据

| 能力 | 云端工具 | 端侧适配 | 返回范围 |
| --- | --- | --- | --- |
| 今日状态 | `get_today_context` | 有 | 五项评分、生理指标、负荷与当日打卡 |
| 趋势 | `get_metric_trend` | 有 | 指标在 7 天、30 天、6 个月或 3 年内的聚合值与覆盖情况 |
| 近 7 天恢复证据 | `get_weekly_recovery_evidence` | 有 | 最近 7 个 04:00 生理日与此前 28 天零重叠对照；逐日五项、睡眠、体感、饮食与同日训练；覆盖/样本/四态分列 |
| 训练与肌群恢复 | `get_workouts_and_muscles` | 有 | 近期训练、Effort 来源与肌群恢复启发式估计 |
| 睡眠 | `get_sleep_detail` | 有 | 指定生理日的睡眠分期、效率与目标差值 |
| 饮食 | `get_eating_context` | 有 | 有界时间窗内的日记录、目标、完成状态、热量区间与缺项、宏量营养、纤维和饮水 |
| 已发现规律、相似日、个人预测、动作库 | `get_patterns`、`find_similar_days`、`get_personal_forecast`、`search_exercise_catalog` | — | 按各工具合同返回，守住日期、数据充分性与版本范围 |
| 待确认提案 | `propose_plan_change`、`propose_memory`、`propose_workout_annotation` | 训练计划、记忆 | 返回给 UI 审阅并确认 |

- `AgentExecutionContext` 接收只读快照、训练与标注、饮食、打卡和记忆等数据。注册的工具决定模型实际可查询的字段。`get_weekly_recovery_evidence` 已提供 7 天逐日观测与 28 天聚合，历史计划执行、跨指标原始采样与逐项微量营养仍缺少对应的 Coach 查询合同。
- 使用 `DayKey` 的本地 04:00 切日。证据保留 `available`、`knownZero`、`missing`、`excluded` 四态及来源。**已知缺口**：现有趋势覆盖率以返回的记录数作分母，稀疏历史下可能高估覆盖。改动趋势查询时按请求的日历窗口回归验证。
- 原始 HealthKit 样本留在设备。云端请求包含问题、裁剪后的对话与必要的今日摘要、相关记忆，以及按需返回的工具结果。设置中的隐私预览展示最近一次云端请求的脱敏快照。新增数据字段时核对每条路由的实际载荷。
- 评分由本地引擎计算。回复沿用数字溯源核验，缺少本轮依据的健康数值标注「未核实」。说明日期、单位和数据覆盖。周恢复工具在 `bodyseek-evidence-v1` 信封上增加 `evidence` 数组，每个数字带 metric、窗口/日期、单位和估算标记；核验器会拒绝「同值但错指标/错日期/错单位」的引用。区分用户确认、设备数据、估算与建议。相似日、规律和预测用于提出候选解释，避免因果或医学诊断断言。

## 3. 提案、记忆与产品入口

- 训练计划、记忆和练后标注经提案卡请求用户确认。已确认操作走 [ActionExecutor](../BodySeekKit/Sources/BodySeekStore/ActionExecutor.swift) 审计。Coach 练后标注使用消息 ID 关联事务，重试与重开聊天时沿用现有确认状态。
- Watch 标注由 [WorkoutAnnotationResolver](../BodySeekKit/Sources/BodySeekAgent/WorkoutAnnotationResolver.swift) 统一解析「今天/昨天/前天/昨晚/昨夜/前晚」和唯一 UUID；「昨晚」按本地夜间窗口覆盖午夜至 04:00。无日期时取近 72 小时待复盘力量训练。多候选由聊天卡片按开始时间/类型选择，日期与 UUID 冲突时要求澄清。
- 提交时在事务内重查训练、删除标记、复盘状态与最新标注；展示后记录变化会拒绝写入。`action_audit` v5 保存版本化 before/after 快照和 `undo_of`/`undone_by` 关联。撤销会原子恢复标注、肌群负荷和复盘状态；已撤销、记录后续改动、手改、已删除与旧审计无快照分别返回明确状态。
- 三层记忆为 `profile`、`activeConstraint`、`verifiedPattern`。选择器按领域关联、层级、有效期和确认时间挑选最多 6 条相关记忆。经确认的规律才可进入 `verifiedPattern`。对话上下文窗口和长期记忆各有自己的生命周期。
- 今日有本地行动卡、按需生成的一句 AI 建议及可关闭的规则洞察（每日最多两条）。Coach 复用现有 Markdown 回复、指标依据入口与提案卡。持久化周期报告、自动对话摘要与跨会话事件记忆、历史计划执行复盘尚待实现和验证，持续任务与记忆的产品目标见顶层设计。
- 营养草稿优先采用手工补充，其次使用食物库，最后按登记的营养素及单位合同补齐可估算的指标。估算保留来源、热量区间和逐项标记，未能可靠估算的条目仍可待补。**营养看板能展示的微量营养估算范围大于 Coach 饮食工具的读取范围。**

## 4. 验证与接手

- 近期开发顺序及完成条件以 [Coach 实施工单](design/coach-agent-implementation.md) 为准。按当前生产入口复现，核对使用的模型路由和数据合同。
- 单测与脚本评测入口为 `swift test --package-path BodySeekKit --disable-automatic-resolution`。涉及真实流程时跑对应 Coach 或营养界面回归。用带缺测和已知零的样例验证对比结论，以及连续追问、提案重试和端侧工具受限时的表现。
- 2026-11-21 的扩展营养估算构建记录为 63 项包测试、22 项 Agent 测试通过，默认字号的模拟器全天草稿确认通过。iPhone 16 Pro 原地安装序列为 `1916`。当时锁屏拦截启动请求，真机 UI、在线模型回答质量及实际 Watch 数据回流尚待验证。具体命令、各阶段基线与结果见 [Agent 验证记录](validation/m3-agent-validation-2026-11-20.md#9-2026-11-21-质量修复复测) 和 [健身验证记录](validation/m2-fitness-validation-2026-11-20.md)。
- 2026-11-21 的 Coach 工单 1/2 在模拟器完成：`swift test --package-path BodySeekKit --disable-automatic-resolution` 通过 111 项（89 项包测试 + 22 项 Agent 评测）；`xcodebuild test -only-testing:VelaUITests` 13 项中 12 项通过、1 项预期跳过，新增 `testCoachAnnotationConfirmAndUndo` 覆盖唯一候选确认、撤销和跨页刷新。在线模型、Apple 端侧与真机未在本轮验证；工单 1 的固定夹具在 `WeeklyRecoveryEvidenceTests`，工单 2 的迁移、提交/撤销、冲突和手改用例在 `WorkoutAnnotationUndoTests`/`WorkoutAnnotationResolutionTests`。
