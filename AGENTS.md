# BodySeek / Vela 工程约定

- 产品读 [PRD](docs/PRD.md)，术语读 [CONTEXT](CONTEXT.md)，平台与架构读 [ADR 0018/0019](docs/adr/README.md) 和 [技术架构](docs/TECH_ARCHITECTURE.md)。现行基线为 iOS 26、BodySeekKit 与 GRDB。
- Coach 开发先读 [实施工单](docs/design/coach-agent-implementation.md)，按取证、训练标注与撤销的顺序验收。核对既有功能时读 [V5 AI Agent 开发指南](docs/AI_AGENT_SPEC.md)，产品边界见 [Coach 顶层设计](docs/design/coach-agent.md)。
- 对外产品名 BodySeek；GitHub 仓库为 `SunWeizhou/bodyseek`，本地目录、Xcode 工程、bundle 与 Swift 标识保持 Vela。Today、Trends、五项详情优先，不新增总健康分或扩张产品线。
- 按当前 BodySeekKit 生产入口核对实现。使用 available、knownZero、missing、excluded(reason) 四态，保留各自的覆盖与来源。
- 记录 HEAD、dirty 状态、命令、退出码、配置与产物；不 reset/clean/stash/pull/merge/push/真机部署或发布，除非明确授权。保留用户改动。
- HealthKit→snapshot→持久化→计算→UI 的时间、来源、覆盖与原因必须可追溯；历史评分不得使用未来数据。算法/输入语义变化要分版本。
- 回归遵循先复现、最小修复、再回归；写入失败不得吞掉。UI 验收需真实 SwiftUI 证据；合成样例不等于临床有效性。
- 证据写在对应 PR 和 `docs/validation/` 里已有的报告。不要依赖不存在的 `docs/validation/codex-takeover/TAKEOVER.md`。共享数据合同、schema、算法策略和 UI 精修分开提交。
- 双人协作入口见 `docs/collaboration/README.md`；算法/数据与 UI/交互按该目录的责任边界拆分，跨边界工作先确认数据合同再实现。
- GitHub Issue、分支、PR 和交接必须遵循 `docs/collaboration/GITHUB_WORKFLOW.md`；每项工作记录 HEAD、dirty 状态、验证命令、退出码和未验证风险。

- 新机器或 UI 开发者首次接手，先读 `docs/collaboration/ONBOARDING.md`。根目录不再放旧主开发提示。`Features` 下的 Store、ViewState、数据投影仍属共享边界，具体见 `docs/collaboration/UI_WORKFLOW.md`。

## V6 开发规则

- 权威顺序在 PRD、CONTEXT、ADR 之外，加入 [V6 蓝图](docs/design/v6-blueprint.md) → [设计系统](docs/design/design-system.md) → [数据可视化规范](docs/design/dataviz.md) → [ADR 0020](docs/adr/0020-coach-autonomy-and-action-layer.md) / [ADR 0021](docs/adr/0021-body-model-layers-and-daily-brief.md)。0020/0021 是目标结构，按蓝图阶段落地，落地前代码仍按 V5 行为。
- `BodySeekFeatures` 里禁止直接写间距、圆角、不透明度、尺寸数字和 hex 颜色，只能使用 `BS*` 令牌和 `BS*` 组件；可点击元素用 `BSPressableStyle`，不用 `.buttonStyle(.plain)`。
- 新功能必须先进「实验室」。开分支前先写一页规格：要解决的问题、属于哪一层（L0–L3 或实验室）、用哪些典型日验收。
- 验证记录按功能写成独立文件 `docs/validation/<功能>-<日期>.md`，不再往 `m3-agent-validation-2026-11-20.md` 里追加。
- 提交前运行 `python3 scripts/check_design_system.py`；已迁移完成的页面用 `--strict <路径前缀>` 检查。
- `BodySeekDesign` 同时支持 iOS 26 与 macOS 15：UIKit 专有 API 用 `#if canImport(UIKit)` 包裹并提供等价实现。
