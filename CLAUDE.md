# CLAUDE.md — Agent & Developer Workspace Handbook

> Status: Canonical
> Last reviewed: 2026-11-21（更新 V5 Agent、营养和接手入口，其他章节沿用原核对记录）
> Scope: Agent 工作方式、构建/测试/部署命令、工程规则与关键代码入口
> Does not define: 产品业务需求（见 [docs/PRD.md](docs/PRD.md)）、领域语言定义（见 [CONTEXT.md](CONTEXT.md)）

> 平台状态：ADR 0018 将 iPhone 部署底线提升到 iOS 26.0；ADR 0019 是当前 V5 架构、GRDB 持久化与个人建模基线（Accepted）。ADR 0017 及更早的平台/UI 方案已被 0018/0019 取代。Watch 端不设独立 target，训练由系统「体能训练」采集后经 HealthKit 汇入。Xcode / Swift 版本以 `.xcode-version`、`project.yml` 和 CI 为准。
>
> 现行版本：主屏幕名 BodySeek，bundle `com.sunweizhou.Vela4`。五个一级表面：今日 / 健身 / 营养 / 趋势 / Coach。五项分数各自独立，`score-v2` 在 `BodySeekCore.BevelScoringEngine`；生产装配由 `AppFeature` 直接读取 GRDB ReadModel；睡眠合并在 `BodySeekCore.SleepMergePolicy`。以生产源码和工作树确认已实现行为，以 PRD 和有效 ADR 确认产品目标及约束。

---

## 1. 必读文档与权威顺序

在进入代码修改或任务执行前，必须按以下顺序了解仓库：

1. [`docs/PRD.md`](docs/PRD.md) — 唯一当前产品规格、五个一级表面与北极星指标
2. [`CONTEXT.md`](CONTEXT.md) — 唯一领域术语表（Health Signal, Baseline, Brief, Body State, Training Decision 等）
3. [`docs/adr/README.md`](docs/adr/README.md) — 架构决策记录（以 `Accepted` 为当前依据；`0019` 最新，`0018` 的 iOS 26 原生壳层仍有效，`0017` 及更早仅供追溯）
4. [`docs/TECH_ARCHITECTURE.md`](docs/TECH_ARCHITECTURE.md) — 当前实现的技术架构与数据流
5. 双人协作入口：[`docs/collaboration/README.md`](docs/collaboration/README.md)
6. 专项文档：
   - 设计语言：[`docs/VELA_DESIGN_LANGUAGE.md`](docs/VELA_DESIGN_LANGUAGE.md)
   - 图表规范：[`docs/design/chart-grammar.md`](docs/design/chart-grammar.md)
   - [Coach 实施工单](docs/design/coach-agent-implementation.md)（近期开发顺序与验收）与 [V5 AI Agent 开发指南](docs/AI_AGENT_SPEC.md)（现行实现）

> [`docs/SCORING_SYSTEM_V1_0.md`](docs/SCORING_SYSTEM_V1_0.md) 是历史协议；公式以 `BodySeekCore/BevelScoringEngine.swift` 与 `docs/model_cards/` 为准。

---

## 2. 工程信息与构建命令

- 工程由 [`project.yml`](project.yml)（XcodeGen）生成 `Vela.xcodeproj`；修改 target、scheme 或依赖后运行 `xcodegen generate` 并同时提交两者。
- Swift Package：[`BodySeekKit/Package.swift`](BodySeekKit/Package.swift)；产品为 `BodySeekCore` / `BodySeekDesign` / `BodySeekStore` / `BodySeekHealth` / `BodySeekAgent` / `BodySeekFeatures`。`VelaApp` 只保留入口与装配。
- Scheme：`Vela`；测试 target：`BodySeekKitTests`、`BodySeekAgentEvals`（SwiftPM），`VelaTests`、`VelaUITests`（Xcode）。
- 新机器接手、构建和测试步骤统一见 [`docs/collaboration/ONBOARDING.md`](docs/collaboration/ONBOARDING.md)；命令在仓库根目录执行。
- `swift test --package-path BodySeekKit` 覆盖合约、存储、评分、Agent 评测与 Feature 测试。
- 模拟器命令使用设备 `id`，不要用 `name=iPhone 17 Pro`（Xcode 27.1 会解析到 27.0 runtime 而失败）：

  ```bash
  xcodebuild test -project Vela.xcodeproj -scheme Vela \
    -destination 'id=<SIMULATOR_UDID>' \
    -skipMacroValidation -skipPackagePluginValidation
  ```

- 在各自 Mac 的非 iCloud 目录克隆工程。真机签名与设备属于各自机器的本地配置；通过 `xcrun devicectl list devices` 查询本机设备。安装、启动或发布前遵循 `AGENTS.md` 的授权约定，不能复用另一位开发者的设备 ID 或签名身份。
- `BodySeekML/` 是 Mac 本地 Python 建模实验（`uv run --project BodySeekML pytest`）；`VelaBackend/` 是独立的 Swift Package，CI 单独跑测试。

---

## 3. 仓库规则与安全护栏

1. **非 iCloud 工作区**：工程源码与 DerivedData 必须位于非 iCloud 同步路径（如 `~/Developer/`），避免 `NSFileCoordinator` 死锁。
2. **Git 安全规则**：禁止执行破坏性 git 操作（`git reset --hard`、`git clean -fd` 等）；提交应小步、可回溯。
3. **GRDB 与并发安全**：
   - 所有业务写入经 `BodySeekRepository` / `ActionExecutor`：提案 → 用户确认 → 单事务写入并记录 `action_audit`，不得在对话回合内静默写库；
   - `BodySeekDatabase` 的 `DatabaseMigrator` 迁移标识由 `BodySeekStoreTests.testMigrationIdentifiersAreStable` 守卫；改 schema 必须同步迁移、测试与重试幂等；
   - TCA reducer 与视图状态在 `@MainActor`；跨并发域只传 DTO / 值类型，禁止传递数据库句柄或 SwiftData live object。
4. **HealthKit 数据合规**：
   - 原始健康采样数据永不上传云端；
   - Coach 云端请求的对话窗口、摘要和按需工具结果见 [AI Agent 开发指南](docs/AI_AGENT_SPEC.md#2-coach-可使用的证据)；
   - 缺失数据客观表达（`--`），`available` / `knownZero` / `missing` / `excluded(reason)` 四态严格区分，严禁在算法或 UI 中伪造生理数据；
   - API Key 只存 Keychain，不得回落到 `UserDefaults`。

---

## 4. 关键目录与代码入口

```text
VelaApp/
└── App/
    └── VelaApp.swift                  # SpeziAppDelegate + TCA Store + RootTabView 装配壳

BodySeekKit/Sources/
├── BodySeekCore/                     # 纯 Foundation：Contracts、score-v2、基线、睡眠合并、营养/训练/预测模型
│   ├── BevelScoringEngine.swift      # 五项评分的唯一确定性入口
│   ├── Contracts.swift               # DayKey、HealthObservation 四态、ActionProposal、算法版本
│   ├── TodayActionEngine.swift       # 今日建议的确定性生成
│   ├── MuscleRecoveryEngine.swift    # recovery-heuristic-v1 肌群恢复
│   └── SleepMergePolicy.swift        # Watch > AutoSleep > iPhone 睡眠合并
├── BodySeekStore/                    # GRDB 7
│   ├── BodySeekDatabase.swift        # DatabaseMigrator 与 schema
│   ├── BodySeekRepository.swift      # 读模型与查询
│   ├── BodySeekReadModel.swift       # 预计算 ChartSeriesSnapshot
│   └── ActionExecutor.swift          # 提案确认后的原子写入与审计
├── BodySeekHealth/                   # SpeziHealthKit
│   ├── SyncEngine.swift              # 锚点增量同步、3 年回填、防抖
│   ├── BodySeekStandard.swift        # Spezi 配置与模块注册
│   └── KeychainService.swift         # 云端凭据
├── BodySeekDesign/                   # 视觉层
│   ├── Tokens/BevelTheme.swift       # 画布、墨色、五域语义色
│   └── Charts/                       # 8 类原生 Swift Charts / Canvas 组件
├── BodySeekAgent/                    # Coach 与建模
│   ├── OpenAICompatibleClient.swift  # SSE 流式工具循环
│   ├── CoachToolRegistry.swift       # 只读四态工具 + 提案工具
│   ├── NumericProvenanceVerifier.swift
│   └── MealDraftAnalysis.swift       # AI 记饮食草稿
└── BodySeekFeatures/
    ├── Reducers/                     # AppFeature / Today / Trends / Workout / Nutrition / Coach / Settings / MetricDetail
    └── Views/                        # RootTabView（五个 Tab）与各一级/二级页面
```

- 今日建议：`TodayActionGenerator`；肌群恢复：`MuscleRecoveryEngine`；预测：`PersonalForecasterEngine`（CoreML + 统计回归）。
- Coach 工具：`CoachToolRegistry`（`get_today_context`、`get_metric_trend`、`get_workouts_and_muscles`、`get_sleep_detail`、`get_patterns`、`find_similar_days`、`get_eating_context`、`search_exercise_catalog` 与提案工具）；写入只经提案。
- 预览与测试入口：`-velaPreviewDashboard`、`-velaPreviewEmptyDashboard`、`-velaInitialTab <n>`。
