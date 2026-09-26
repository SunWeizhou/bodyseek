# 睡眠评分指标模型卡 (Sleep Score Model Card)

指标及算法版本：SleepScoreEngine v2.2.0 (ScoringAlgorithmVersions.sleep)
状态：v2.2 Domain 14/14 及 Vela 生产回归通过（全量 598/598） / 生理有效性未验证 / 无真实多导睡眠图 (PSG) 临床金标准对比

## 1. 用途与不适用用途
- **适用用途**：基于 Apple Watch 采集的睡眠分期与时长数据，评估个人作息目标的达成度、入睡时间一致性及睡眠中断扰动，输出 0–100 分综合睡眠质量参考，用于帮助用户建立规律健康的作息习惯。
- **不适用用途**：严禁用于睡眠呼吸暂停（OSA）、失眠症（Insomnia）、异态睡眠或发作性睡病等临床睡眠障碍的诊断或治疗依据；不能替代多导睡眠监测（PSG）。

## 2. 目标人群与未覆盖人群
- **目标人群**：规律作息的健康成年人群（18–65岁），夜间佩戴 Apple Watch 开启“睡眠专注模式”。
- **未覆盖人群**：倒班/夜班工作者、多相睡眠者（Polyphasic Sleepers）、频繁跨时区飞行人员、严重睡眠呼吸暂停患者及婴儿/儿童。

## 3. 预测/描述的真实目标
- **真实目标**：结合用户自定义作息目标（默认 7.5 小时），从“时长达成度 (50%)”、“入睡一致性 (30%)”与“夜间清醒中断 (20%)”三个维度评估当晚睡眠对身心恢复的支持能力。

## 4. 输入类型、单位、来源、采样窗口
- `totalSleepMinutes`：分钟 (min)，Apple HealthKit 记录的 `HKCategoryValueSleepAnalysis` 核心睡眠（深睡+浅睡+REM）总和。采样窗口为昨夜入睡至清晨觉醒。
- `sleepTargetMinutes`：分钟 (min)，用户设置的作息目标时长（默认 450 分钟即 7.5 小时，允许配置 5.0–10.0 小时）。
- `todayBedtime`：Date (时间戳)，当晚实际入睡时间戳。
- `recentBedtimes`：[Date]，评估日之前 13 个日历日内的有效入睡时间戳序列，由工厂按 snapshot 所属日筛选；不是向前寻找 13 条任意旧记录。
- `awakeMinutes`：分钟 (min)，夜间睡眠中段清醒总时长。
- `awakeEpisodeCount`：整数 (次)，夜间持续 >= 2 分钟的清醒片段次数。
- `remMinutes` / `deepMinutes`（可选）：分钟 (min)，各睡眠分期时长，用于 Buysse 5D 深度特征呈现。
- 计算层同时携带 `SleepEvidenceContext`，为每个组件标记 `observed`、`estimated`、`missing` 或 `excluded`，并保留查询结果、数据窗口和 freshness。

## 5. 个人基线窗口、有效天数与源/方法变化政策
- **一致性基线**：评估日之前 13 个日历日内的入睡时刻（按正午相对偏移分钟计算，消除跨午夜突变），采用中位数作为入睡时刻基准。
- **有效天数要求**：该日历窗内必须有至少 5 晚有效入睡记录，否则一致性维度判定为数据不足，评分置信度降级。
- **时区合同**：工厂、Domain 引擎和兼容引擎使用同一显式 `Calendar`。入睡时刻与 `dataWindow` 都按其时区计算；夏令时切换的 13 天可能为 313 小时。旧时间戳未保存原始时区，重放采用评估时区，不能声称恢复了旅行当时的当地作息。
- **跨日规则**：睡眠片段使用注入的 `Calendar` 与 `HealthDayBoundary` 归属健康日；查询窗口向前扩展以避免跨午夜片段被拆分。
- **主睡眠规则**：主睡眠段与午睡分离，主睡眠按完整片段和醒来时间选择；未来片段不得进入当前 `asOf` 计算。

## 6. 缺失、零值、排除窗口、异常值政策
- **核心缺失**：若 `totalSleepMinutes` 缺失或 <= 0，睡眠评分严格返回 `nil`（不可估计，显示 `--`），置信度标记为 `low`。
- **零值语义**：查询窗口没有有效睡眠片段时视为未知，不发布“0 小时睡眠”作为真实观测。
- **组件语义**：缺失 REM、Deep、卧床时长或清醒阶段时保持未知；由其他观测推导的效率或醒来次数标记为 `estimated`，不能当作直接观测。
- **排除语义**：明确被业务窗口排除的组件标记为 `excluded`，不得转换成零值。
- **查询失败**：`noData`、`denied`、`unavailable`、`transient`、`failed` 时保留最后可信快照，并在本次评分中标记 `stale`、降低置信度和记录查询原因。
- **辅助缺失与置信度门控**：
  - 具备时长 + 一致性 + 中断 3 项维度：置信度为 `high`；
  - 具备 2 项维度：置信度为 `medium`；
  - 仅具备时长维度：置信度严格为 `low`，且**评分上限强制封顶为 79 分**，防止仅凭时长虚假膨胀为“优秀睡眠”。

## 7. 时间 as-of 与输入修订政策
- **As-of 切点**：以次日清晨觉醒离开床铺（或当日评估调用时点）为准。
- **历史数据修订**：若 Apple 健康重新同步了睡眠阶段片段，按最新 snapshot 重算，历史评估版本打上新时间戳。

## 8. 公式/参数与每个参数依据
- **时长分 (0–50)**：
  - 处于 $[target - 30, target + 60]$ 分钟内得满分 50 分；
  - 低于 $target - 30$：线性衰减至 240 分钟（4 小时）得 0 分；
  - 高于 $target + 60$：过长睡眠呈倒 U 型惩罚，超额 240 分钟线性降至 0 分。
- **一致性分 (0–30)**：
  - $|today - baseline| \le 30$ 分钟：30 分；
  - $\le 60$ 分钟：24 分；
  - $\le 90$ 分钟：18 分；
  - $\le 120$ 分钟：12 分；
  - $\le 180$ 分钟：6 分；
  - $> 180$ 分钟：0 分。
- **中断分 (0–20)**：
  - $	ext{Penalty} = 0.45 	imes 	ext{awakeMinutes} + 2.5 	imes 	ext{awakeCount}$
  - $	ext{InterruptionScore} = 	ext{clamp}(20 - 	ext{Penalty}, 0, 20)$
- **综合重归一化**：
  $$	ext{SleepScore} = rac{\sum 	ext{Score}_{	ext{available}}}{\sum W_{	ext{available}}} 	imes 100$$
  若置信度为 `low`，强制 $	ext{SleepScore} = \min(	ext{SleepScore}, 79)$。

## 9. 哪些是文献支持的概念，哪些是本产品启发式
- **文献支持概念**：
  - AASM (American Academy of Sleep Medicine) 成人健康睡眠时长建议（7–9小时）；
  - 睡眠规律性与心血管代谢健康的密切相关性（Sleep Regularity Index, Phillips et al., 2017）；
  - Buysse 匹兹堡睡眠质量指数量表 (PSQI) 的多维分解构想（时长、效率、潜伏期、障碍、药物）。
- **本产品启发式**：
  - 50/30/20 的权重配比方案；
  - 睡眠中断惩罚公式（0.45 分/分钟 + 2.5 分/次）；
  - 低置信度 79 分硬封顶阈值；
  - 当用户自定义目标低于 7 小时（420 分钟）时，显示免责提示“达成个人作息目标不代表生理充分满足”。

## 10. 结果刻度/方向/状态文案
- **刻度**：0–100 分。
- **引擎 band**：通用 `ScoringMath.band` 为 `<25 veryLow`、`25..<45 low`、`45..<75 normal`、`75..<90 high`、`>=90 veryHigh`。它与数据置信度 high/medium/low 是不同字段；页面领域文案由展示层另行映射。

## 11. 数据质量与模型不确定性如何分开
- **数据质量**：`MetricConfidence`（high/medium/low）反映可用组件、估计组件、历史覆盖和 freshness；陈旧值可以参与计算，但会降低置信度。
- **证据质量**：`missingInputs` 与 `reasons` 明确列出缺失、估计、排除和查询状态，不把缺失静默写成零。
- **模型不确定性**：50/30/20、0.45 分钟惩罚、2.5 分/次和 79 分封顶仍是工程启发式，不代表临床测量。

## 12. 已执行工程测试与结果
- **2026-09-22 v2.2**：修复前，生产 DST 与稀疏历史测试失败；Domain 稀疏历史返回 100（应为 79），DST 一致性为 24（应为 30）。修复后 `swift test --package-path BodySeekDomain` 共 14 项通过，包含显式 Calendar、跨 DST、午夜相邻和 13 日窗。Vela 生产测试命令与结果记录在对应 GitHub PR；不以 Domain 结果替代。
- 下列是此前工程证据，不自动表示 v2.2 的生产回归已完成：
- `SleepScoreEngineTests.swift`：覆盖时长区间、零睡眠未知、跨午夜健康日边界、清醒中断观测/估算、缺失 REM/Deep、估计效率、陈旧保留值与 79 分封顶截断逻辑，全部通过。
- `HealthSyncErrorHandlingTests.swift`：覆盖失败查询保留最后可信睡眠字段、`queryOutcome`/`freshness`/`SleepEvidenceContext` 的 stale 传播，全部通过。
- `DataCoverageAndEvidenceTests.testGenerateSleepSemanticsReplayContract`：生成 [sleep_semantics_replay.json](../validation/v1/sleep_semantics_replay.json)，记录 observed/estimated/missing、旧新值、coverage、confidence、query outcome、freshness、缺失输入和原因。

## 13. 对照基线、留出策略与真实样本
- **真实 PSG 临床对比**：**未做（无院内多导睡眠图对照数据）**。
- **工程基线**：以当前工程实现的合成数据集与重放用例为基线。

## 14. 实际效果/误差/校准/区间
- **临床灵敏度/特异度/MAE**：**未做（严禁编造）**。

## 15. 已知限制与失败情境
- Apple Watch 依赖加速度计与光学心率推断睡眠分期，若用户在床上静卧看手机，可能误判为浅睡；
- 跨时区旅行发生生物钟跳变时，近期 13 晚入睡中位数会产生短暂迟滞；
- 白天小憩（Nap）目前未合并计入主睡眠评分，作为日间额外恢复单独记录。

## 16. 新旧版本影响/下游连锁
- **下游消费**：睡眠评分是 `RecoveryScoreEngine`（权重 25%）、`StressIndexEngine`（睡眠债务压力 15%）以及 `EnergyBankEngine`（晨间初始充电量）的关键上游输入。
- **隔离控制**：当睡眠评分为 `nil` 时，恢复与能量引擎启动降级保护，绝不使用假定 0 分或 100 分；Coach、BodyState 和 Agent context 展示未知或陈旧原因。
- **版本边界**：v2.2.0 修正 13 日基线窗与 Calendar 传递，保持 v2.1.0 的数据覆盖合同及既有 50/30/20、评分曲线、79 封顶。Sleep 版本改变会更新五项复合缓存版本；Recovery/Energy 若因上游变动而变化，应在五项回放中解释，不代表其公式升级。

## 17. 发布/回滚条件
- **发布条件**：工程单测通过，跨午夜无负数计算异常，低质量封顶有效。
- **回滚条件**：分期数据解析崩溃或目标时间设置导致溢出时回滚。

## 18. 来源链接及读取日期
- Watson NF, et al. Recommended Amount of Sleep for a Healthy Adult: A Joint Consensus Statement of the AASM and SRS. *Sleep*, 2015. (读取日期: 2026-08-20)
- Phillips AJK, et al. Irregular sleep/wake patterns are associated with poorer academic performance and delayed circadian and sleep/wake timing. *Sci Rep*, 2017. (读取日期: 2026-08-20)
