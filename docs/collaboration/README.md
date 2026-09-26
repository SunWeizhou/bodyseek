# 双人协作入口

本目录服务于两位开发者共同维护 Vela/BodySeek：一人主责算法、数据和可信性，一人主责 UI、交互和视觉验证。它定义协作边界与交接方式，不取代产品规格、领域术语或架构决策。

## 先读什么

| 需要做什么 | 先读 |
| --- | --- |
| 新 Mac / UI 开发者首次接手 | [`ONBOARDING.md`](ONBOARDING.md) |
| 理解产品和边界 | [`docs/PRD.md`](../PRD.md)、[`CONTEXT.md`](../../CONTEXT.md) |
| 修改算法、HealthKit、持久化 | [`ALGORITHM_WORKFLOW.md`](ALGORITHM_WORKFLOW.md)、[`docs/TECH_ARCHITECTURE.md`](../TECH_ARCHITECTURE.md) |
| 修改 SwiftUI、交互、视觉 | [`UI_WORKFLOW.md`](UI_WORKFLOW.md)、[`docs/VELA_DESIGN_LANGUAGE.md`](../VELA_DESIGN_LANGUAGE.md) |
| 开始一个 GitHub 任务 | [`GITHUB_WORKFLOW.md`](GITHUB_WORKFLOW.md)、[`TASK_TEMPLATE.md`](TASK_TEMPLATE.md) |
| 把工作交给对方 | [`HANDOFF_TEMPLATE.md`](HANDOFF_TEMPLATE.md) |
| 查当前事实和未解决问题 | [`docs/validation/codex-takeover/TAKEOVER.md`](../validation/codex-takeover/TAKEOVER.md) |

## 目录边界

```text
docs/
├── collaboration/       # 双人开发、GitHub、交接和任务模板
├── adr/                 # 需要长期保留的架构取舍
├── architecture/        # 稳定的数据合同与模块合同
├── validation/          # 可复核的构建、测试、真机和 UI 证据
├── model_cards/         # 五项评分模型与版本说明
└── archive/             # 已废弃或历史材料，只供追溯
```

目录只能帮助定位，不能单独决定所有权。`Features` 中还包含 Store、数据读取与建议策略。文件边界和例外见 [UI 工作流](UI_WORKFLOW.md)；跨边界功能先固定合同，再分别实现。

## 完成标准

一个任务只有在代码、测试、验证证据和交接说明都能被另一位开发者复核时才算完成。模拟数据可以帮助开发，但不能替代 HealthKit 真机证据。
