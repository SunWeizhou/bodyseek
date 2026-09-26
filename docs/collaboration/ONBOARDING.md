# 新开发者接手：UI 方向

> 检查日期：2026-09-06。这里记录接手方法和本次交接状态；实际工作以拿到的提交与 CI 结果为准。

## 1. 先拿到同一份代码

仓库为 [SunWeizhou/Vela](https://github.com/SunWeizhou/Vela)。各自克隆到非 iCloud 目录，例如 `~/Developer/Vela`；不复制另一台 Mac 的 build、数据库、Keychain、设备 ID 或 Codex 对话目录。

在仓库根目录记录：

```bash
git remote -v
git branch --show-current
git rev-parse HEAD
git status --short --branch
```

两人用 GitHub PR 和提交 SHA 对齐。Issue 分配主负责人，开始时留言列出计划修改的文件；共享文件有另一人在改时，先调整范围。新分支用 `codex/ui/<topic>` 或 `codex/algo/<topic>`，各自在自己的 checkout 工作。

本次只读检查：远端 main 和本地 HEAD 均为 `fc2c40abd10ae43a9a04c77aec0280ae1eb24131`；但本机存在 10 个未提交的生产/测试文件修改，协作文档和 `AGENTS.md` 也尚未完整进入 Git。此记录不意味着这些内容已发布。正式交接时在 GitHub PR 中记录最终提交 SHA，并让接手者重新核对；未发布前不能只凭本页认定克隆已经包含本地修复。

## 2. 在她的 Mac 建立基线

```bash
cat .xcode-version
xcode-select -p
xcodebuild -version
swift --version
xcrun simctl list devices available
xcodebuild -project Vela.xcodeproj -scheme Vela -showdestinations
```

当前 `.xcode-version` 要求 26.5.0，CI 会严格匹配；本次本机读到 Xcode 26.6。两者不同，因此旧本机构建通过不能代替固定工具链下的 CI 通过。接手机器应核对仓库要求和可用工具链；无法满足时记录环境阻塞，不能为了通过而静默修改 CI。

从仓库根目录构建，产物进入已忽略的 `build/`：

```bash
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/UIOnboardingDerivedData CODE_SIGNING_ALLOWED=NO build
```

测试需要具体可用的模拟器。把下方占位符替换为上述 `-showdestinations` 返回的 UUID；每次运行使用新的 result bundle 路径：

```bash
VELA_SIMULATOR_UDID='<available-simulator-uuid>'
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination "platform=iOS Simulator,id=$VELA_SIMULATOR_UDID" \
  -derivedDataPath build/UIOnboardingDerivedData \
  -resultBundlePath "build/UIOnboarding-$(date +%Y%m%d-%H%M%S).xcresult" \
  -only-testing:VelaTests CODE_SIGNING_ALLOWED=NO test
```

UI 任务根据范围再运行 `VelaUITests` 和实际页面验收；基线记录构建/测试各自退出码、工具链、SHA、dirty diff、设备和产物。基线失败时先区分原有失败与任务引入的失败。模拟器空 HealthKit 数据是需要验收的状态，不能填入伪造的生产读数。

iPhone 验收由各自机器选择本机设备和已有开发团队配置。签名/team/capabilities 的共享更改单独讨论，不把个人设备配置写进公共工程。API Key 由各自在应用中配置，测试截图使用合成输入或去除私人健康信息；公开仓库只存可公开的证据。

## 3. 给她的 Codex 的第一条任务

在克隆仓库中直接使用以下提示；有明确 Issue 时附上其链接和最终基线 SHA：

```text
你接手 BodySeek/Vela 的 UI 与交互方向，我的搭档负责算法、HealthKit 与持久化。
先读根目录 AGENTS.md、docs/collaboration/ONBOARDING.md、UI_WORKFLOW.md，
再定向读 PRD、CONTEXT、ADR 0017 和设计语言文档。
核对当前 HEAD、dirty 状态、工具链、真实 Today/Trends/详情入口，执行本机能运行的基线构建。
先提交一份接手结果：页面入口、允许修改的文件、共享文件、基线结果和一个小 UI 任务的验收条件。
本轮不改生产代码。后续按我指定的 Issue 开发，不自动执行根目录旧 FIRST_MESSAGE/NEXT_MESSAGE 的主开发任务。
无法验证的项目明确写未验证；保留原有改动。未经授权不推送、合并、真机部署或发布。
```

第一次开发可选择单个 Today 卡片或详情页的大字体/空态布局。更改状态解释、建议阈值、历史筛选、缺失判断时，转为共享合同任务。

## 4. 什么需要更新，什么保留历史

- 每次 PR 更新触及的页面规则、数据合同或算法模型卡；目标规范与当前实现分别说明。
- `docs/SCORING_SYSTEM_V1_0.md` 是旧设计参考；Energy 模型卡的 v1 内容也未对齐当前 v2 生产版本。UI 以当前输出字段为准，逐公式核对由算法任务完成。
- 根目录旧 `START_HERE.md` / `FIRST_MESSAGE.md` / `NEXT_MESSAGE.md`、`tasks/`、`reference/` 保留原始基点；新 UI 开发者无需按顺序执行这些历史任务。
- 当前交接事实与证据索引写入 `docs/validation/codex-takeover/TAKEOVER.md`。日常讨论与交接放对应 PR，避免两人同时改中央记录；集成时由一人汇总链接。
- 文档重新导航不需要移动 Swift 源码或重排 Xcode 工程。文件移动属于另外的可验证变更。
