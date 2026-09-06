# Vela

个人身体面板与 AI 健康分析助手：建立在 Apple 健康之上，帮助看见当前身体状态和长期趋势，理解变化原因，并将理解转化为训练与生活调整建议。

> 产品规格与领域语言以 `docs/PRD.md` 与 `CONTEXT.md` 为唯一权威；工程规范见 [CLAUDE.md](CLAUDE.md)。

## 技术栈

- **平台与部署基准**：**iOS 17+ / watchOS 10+** · SwiftUI + SwiftData + HealthKit · Swift 6；根据 [ADR 0017](docs/adr/0017-bodyseek-architecture-and-product-baseline-v2.md) 确立，对外产品名为 **BodySeek**（工程内部与 bundle 保持 Vela），较高系统能力渐进增强，不作为发布门槛。
- 本地确定性评分（`VelaApp/Scoring`）→ 多尺度趋势（`HealthTrendEngine`）→ 权威简报（`PersonalHealthBrief`）→ 四个 canonical surface（Today / Trends / Plan / Coach）
- AI Coach 直连 DeepSeek API（Keychain 存 Key）；原始健康采样永不上传，仅发送裁剪的 `AgentFactSnapshot`

## 构建与测试

首次克隆、工具链检查、模拟器构建和测试命令见 [新开发者接手步骤](docs/collaboration/ONBOARDING.md)。测试数量与通过状态以目标提交的实际结果为准。

CI 配置见 [`.github/workflows/quality.yml`](.github/workflows/quality.yml)：包含 schema 守卫、对比度检查、构建、iOS 单测、UI 冒烟和后端测试。固定字体与 SwiftLint 为 report-only；配置存在不等于本次 GitHub 运行已经通过。

## 常用脚本

| 脚本 | 用途 |
| :--- | :--- |
| `scripts/schema_fingerprint.py --check` | SwiftData 模型图守卫（CI 门禁；模型变更时按错误提示做版本提升） |
| `scripts/schema_fingerprint.py --emit-frozen` | 重新生成 `VelaSchemaV3Frozen.swift` 冻结快照 |
| `scripts/audit_design_tokens.sh` | 设计 Token 审计 |

## 文档地图

- `docs/PRD.md` — 产品规格（四大 Tab、北极星 Trusted Health Brief Day）
- `CONTEXT.md` — 领域术语表（唯一权威）
- `docs/TECH_ARCHITECTURE.md` — 技术架构与数据流
- `docs/adr/` — 架构决策记录（以 README 中的 Accepted 为当前依据；Superseded 仅供追溯）
- `docs/AI_AGENT_SPEC.md` — Coach Agent 协议与上下文规格
- `docs/validation/` — 验证与审计证据（含 2026-08-23 工程标准审计报告）
- `docs/collaboration/` — 双人 GitHub 工作流、算法/UI 分工、任务与交接模板

## 双人开发入口

算法与数据工作从 [`docs/collaboration/ALGORITHM_WORKFLOW.md`](docs/collaboration/ALGORITHM_WORKFLOW.md) 开始；UI 与交互工作从 [`docs/collaboration/UI_WORKFLOW.md`](docs/collaboration/UI_WORKFLOW.md) 开始。GitHub Issue、分支、PR 和交接规则见 [`docs/collaboration/GITHUB_WORKFLOW.md`](docs/collaboration/GITHUB_WORKFLOW.md)。
