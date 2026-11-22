# BodySeek

个人身体面板与 AI 健康分析助手：建立在 Apple 健康之上，帮助看见当前身体状态和长期趋势，理解变化原因，并将理解转化为训练与生活调整建议。

现行版本使用 iOS 26 及以上。五个一级表面为今日、健身、营养、趋势、Coach。工程 bundle 为 `com.sunweizhou.Vela4`。

> 产品规格与领域语言以 `docs/PRD.md` 与 `CONTEXT.md` 为唯一权威；工程规范见 [CLAUDE.md](CLAUDE.md)。V6 重构设计见 [V6 蓝图](docs/design/v6-blueprint.md)、[设计系统](docs/design/design-system.md)、[数据可视化规范](docs/design/dataviz.md)。

## 技术栈

- VelaApp 薄壳与 Swift 6 `BodySeekKit`，采用 SwiftUI、TCA、GRDB 和 HealthKit。平台及模块边界见 [ADR 0018/0019](docs/adr/README.md)。
- Apple Watch 训练由系统「体能训练」采集，经 HealthKit 进入 iPhone 力量复盘与肌群恢复流程。
- Coach 使用本地评分与任务型工具，可通过用户配置的 OpenAI 兼容模型或 Apple Foundation Models 回复。模型、数据和权限边界见 [V5 AI Agent 开发指南](docs/AI_AGENT_SPEC.md)。

## 构建与测试

首次克隆、工具链检查、模拟器构建和测试命令见 [新开发者接手步骤](docs/collaboration/ONBOARDING.md)。测试数量与通过状态以目标提交的实际结果为准。

CI 配置见 [`.github/workflows/quality.yml`](.github/workflows/quality.yml)：包含 BodySeekKit 测试、对比度门禁、warnings-as-errors 构建、iOS 单测、UI 冒烟和后端测试。固定字体与 SwiftLint 为 report-only；配置存在不等于本次 GitHub 运行已经通过。

## 常用脚本

| 脚本 | 用途 |
| :--- | :--- |
| `scripts/check_contrast.py` | BevelTheme 文字 token 对画布的 WCAG AA 对比度门禁 |
| `scripts/check_fixed_fonts.py` | 固定字号扫描（report-only，追踪 Dynamic Type 清理） |
| `scripts/audit_design_tokens.sh` | 设计 Token 审计 |
| `scripts/check_design_system.py` | V6 设计系统门禁（间距、圆角、不透明度、尺寸、颜色、动效；默认只报告，`--strict <前缀>` 阻断） |

## 文档地图

- `docs/PRD.md` — 产品规格（五个一级表面：今日 / 健身 / 营养 / 趋势 / Coach）
- `CONTEXT.md` — 领域术语表（唯一权威）
- `docs/TECH_ARCHITECTURE.md` — 技术架构与数据流
- [`docs/design/`](docs/design/) — V6 重构蓝图（`v6-blueprint.md`）、设计系统（`design-system.md`）、数据可视化规范（`dataviz.md`）；旧的 `docs/VELA_DESIGN_LANGUAGE.md` 已被取代
- `docs/adr/` — 架构决策记录（以 README 中的 Accepted 为当前依据；Superseded 仅供追溯）
- [`docs/AI_AGENT_SPEC.md`](docs/AI_AGENT_SPEC.md) — Coach、今日 AI 建议和 AI 记饮食的现行开发指南
- `docs/validation/` — 验证与审计证据（含 2026-08-23 工程标准审计报告）
- `docs/collaboration/` — 双人 GitHub 工作流、算法/UI 分工、任务与交接模板

## 双人开发入口

算法与数据工作从 [`docs/collaboration/ALGORITHM_WORKFLOW.md`](docs/collaboration/ALGORITHM_WORKFLOW.md) 开始；UI 与交互工作从 [`docs/collaboration/UI_WORKFLOW.md`](docs/collaboration/UI_WORKFLOW.md) 开始。GitHub Issue、分支、PR 和交接规则见 [`docs/collaboration/GITHUB_WORKFLOW.md`](docs/collaboration/GITHUB_WORKFLOW.md)。
