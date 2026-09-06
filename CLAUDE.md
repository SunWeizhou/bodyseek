# CLAUDE.md — Agent & Developer Workspace Handbook

> Status: Canonical
> Last reviewed: 2026-09-06（交接入口、平台和构建步骤；未重新验证全文）
> Scope: Agent 工作方式、构建/测试/部署命令、工程规则与关键代码入口
> Does not define: 产品业务需求（见 [docs/PRD.md](docs/PRD.md)）、领域语言定义（见 [CONTEXT.md](CONTEXT.md)）

> 平台状态：Accepted ADR 0017 确定 iOS 17 / watchOS 10 shipping floor；ADR 0013–0016 已被取代。Xcode 工具链要求以 `.xcode-version` 和当前 CI 为准。

---

## 1. 必读文档与权威顺序

在进入代码修改或任务执行前，必须按以下顺序了解仓库：

1. [`docs/PRD.md`](docs/PRD.md) — 唯一当前产品规格、四大 Tab 与北极星指标
2. [`CONTEXT.md`](CONTEXT.md) — 唯一领域术语表（Health Signal, Baseline, Brief, Body State, Training Decision 等）
3. [`docs/adr/README.md`](docs/adr/README.md) — 架构决策记录（以 `Accepted` 为当前依据，`Superseded` 仅供追溯）
4. [`docs/TECH_ARCHITECTURE.md`](docs/TECH_ARCHITECTURE.md) — 当前实现的技术架构与数据流
5. 双人协作入口：[`docs/collaboration/README.md`](docs/collaboration/README.md)
6. 专项文档：
   - 设计语言：[`docs/VELA_DESIGN_LANGUAGE.md`](docs/VELA_DESIGN_LANGUAGE.md)
   - AI 上下文与 Agent 协议：[`docs/AI_AGENT_SPEC.md`](docs/AI_AGENT_SPEC.md)
   - 指标与算法协议：[`docs/SCORING_SYSTEM_V1_0.md`](docs/SCORING_SYSTEM_V1_0.md)

---

## 2. 工程信息与构建命令

- 工程与 Scheme：`Vela.xcodeproj` / `Vela`；单测 target 为 `VelaTests`。
- 新机器接手、构建和测试步骤统一见 [`docs/collaboration/ONBOARDING.md`](docs/collaboration/ONBOARDING.md)。
- 在各自 Mac 的非 iCloud 目录克隆工程，命令在仓库根目录执行。
- 真机签名与设备属于各自机器的本地配置；通过 `xcrun devicectl list devices` 查询本机设备。安装、启动或发布前遵循 `AGENTS.md` 的授权约定，不能复用另一位开发者的设备 ID 或签名身份。

---

## 3. 仓库规则与安全护栏

1. **非 iCloud 工作区**：工程源码与 DerivedData 必须位于非 iCloud 同步路径（如 `~/Developer/`），避免 `NSFileCoordinator` 死锁。
2. **Git 安全规则**：禁止执行破坏性 git 操作（`git reset --hard`、`git clean -fd` 等）；提交应小步、可回溯。
3. **SwiftData 与并发安全**：
   - `@Model` 实体操作需在正确的 Actor / `@MainActor` 上下文进行；
   - 跨线程数据传递必须使用 DTO 或 Model ID，禁止跨并发域直接传递 SwiftData Live Object。
4. **HealthKit 数据合规**：
   - 原始健康采样数据永不上传云端；
   - 仅向用户配置的 LLM Provider（如 DeepSeek）发送裁剪后的结构化 `AgentContextEnvelope`；
   - 缺失数据客观表达（`--`），严禁在算法或 UI 中伪造生理数据。

---

## 4. 关键目录与代码入口

```text
VelaApp/
├── App/
│   └── VelaApp.swift                   # App 入口、Container、DI 初始化；同文件定义 VelaAppState
├── Core/
│   ├── Theme/VelaTheme.swift           # Rhythm 视觉 Tokens（画布、深墨文字、节律绿、字体、间距）
│   └── DesignSystem/                   # 通用卡片、地平线、胶囊、动效修饰符
├── Features/
│   ├── Minimal/
│   │   ├── VelaMinimalShell.swift      # 根导航（Today / Trends / Plan / Coach 4-Tab 容器）
│   │   ├── VelaMinimalTodayView.swift  # Tab 0: 今日状态与健康地平线
│   │   ├── VelaMinimalFitnessView.swift# 训练能力的兼容/下游视图（不属于一级 Tab）
│   │   └── TrainingHeroSection.swift   # Plan/Coach 内训练决策 Hero、三日预测与分析门户
│   ├── Trends/
│   │   └── VelaTrendsView.swift        # Trends: 多尺度趋势与指标详情
│   ├── Coach/
│   │   ├── CoachView.swift             # Coach: AI 分析工作台、流式对话主场
│   │   └── CoachWelcomeWorkspace.swift # 晨间生理问候与情境分析提问气泡
│   └── Settings/
│       ├── DataCoverageView.swift      # 数据覆盖与权限状态
│       ├── TrustCenterView.swift        # 数据与 AI 信任设置
│       └── BiologyView.swift            # 生理设置
├── Health/
│   ├── Services/HealthKitSyncEngine.swift # HealthKit 两阶段同步与日快照管道
│   └── Coverage/                       # 数据覆盖度计算
├── Scoring/
│   ├── ScoreEngineFactory.swift        # DailyHealthComputation 唯一确定性评分入口
│   └── Recovery/ Sleep/ Strain/ Stress # 各独立指标评分引擎（0-100 标准化）
└── TrainingIntelligence/
    ├── Services/                       # 训练分析、局部肌群疲劳分析、e1RM
    └── Views/                          # 训练详情、活动摘要与历史视图
```
