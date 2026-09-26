# BodySeek / Vela 工程约定

- 权威产品与术语文档：`docs/PRD.md`、`CONTEXT.md`；平台与架构以 Accepted ADR（特别是 `docs/adr/0017-bodyseek-architecture-and-product-baseline-v2.md`）为准，旧平台描述不覆盖 ADR 0017。
- 对外产品名 BodySeek；仓库、Xcode 工程、bundle 与 Swift 标识保持 Vela。Today、Trends、五项详情优先，不新增总健康分或扩张产品线。
- 先核对当前源码和生产入口；`BodySeekDomain` 测试不能替代 Vela iOS 生产评分验证。区分 unknown、known zero、excluded(reason)，不得把缺失静默当零。
- 记录 HEAD、dirty 状态、命令、退出码、配置与产物；不 reset/clean/stash/pull/merge/push/真机部署或发布，除非明确授权。保留用户改动。
- HealthKit→snapshot→持久化→计算→UI 的时间、来源、覆盖与原因必须可追溯；历史评分不得使用未来数据。算法/输入语义变化要分版本。
- 回归遵循先复现、最小修复、再回归；写入失败不得吞掉。UI 验收需真实 SwiftUI 证据；合成样例不等于临床有效性。
- 接手与后续证据统一写入 `docs/validation/codex-takeover/TAKEOVER.md`；共享数据合同、schema、算法策略和 UI 精修分开提交。
- 双人协作入口见 `docs/collaboration/README.md`；算法/数据与 UI/交互按该目录的责任边界拆分，跨边界工作先确认数据合同再实现。
- GitHub Issue、分支、PR 和交接必须遵循 `docs/collaboration/GITHUB_WORKFLOW.md`；每项工作记录 HEAD、dirty 状态、验证命令、退出码和未验证风险。

- 新机器或 UI 开发者首次接手，先读 `docs/collaboration/ONBOARDING.md`；根目录 `FIRST_MESSAGE.md` 等是旧主开发接手资料，不自动作为新任务指令。`Features` 下的 Store、ViewState、数据投影仍属共享边界，具体见 `docs/collaboration/UI_WORKFLOW.md`。
