# M0 Baseline Commit Report: BodySeek V3 TCA + Spezi 重写收口

- **日期**: 2026-11-19
- **分支**: `codex/ui/ios26-native-bodyseek`
- **基准 `HEAD` 提交（提交前）**: `f5271882a683a82ca998a272c8840dc41d107742`
- **授权依据**: BodySeek V5 蓝图 §16 第 1 条（作者已授权仅在当前功能分支 `codex/ui/ios26-native-bodyseek` 提交未提交的 V3 重写，不 push `main`、不 merge、不发布）。

## 一、提交前 Dirty 状态清单（共 271 项）

- **已删除旧实现（`D = 252`）**:
  - `VelaApp/`: `199` 个旧手写模块文件（`Features` 77、`Core` 33、`AI` 27、`Scoring` 21、`Persistence` 15、`Health` 13、`TrainingIntelligence` 9、`App` 2、`Compatibility` 1、`Journal` 1）
  - `VelaAppTests/`: `28` 个旧测试与 fixture 文件
  - `BodySeekDomain/`: `23` 个旧领域核心与敏感性回放测试文件
  - `VelaUITests/`: `1` 个旧 UI 测试文件（`VelaSmokeUITests.swift`）
  - `VelaWatch/`: `1` 个独立 Watch Target 入口（`VelaWatchApp.swift`）
- **已修改现有文件（`M = 10`）**:
  - `Vela.xcodeproj/project.pbxproj`、`Package.resolved`、`Vela.xcscheme`
  - `VelaApp/App/VelaApp.swift`
  - `VelaApp/Resources/Assets.xcassets/`（`AccentColor`、`AppIcon.png`、`LaunchMark.svg`）
  - `docs/PRD.md`、`docs/VELA_DESIGN_LANGUAGE.md`、`docs/adr/README.md`
- **新增未跟踪文件（`?? = 9` 顶层条目）**:
  - `BodySeekKit/`（`Package.swift`、`Package.resolved`、新增 `.gitignore` 忽略 `.build/`、35 个源文件和 3 个测试文件）
  - `project.yml`
  - `VelaApp/Resources/BodySeekIcon.icon/`（`icon.json` 与双 SVG 图层）
  - `VelaAppTests/BodySeekAppIntegrationTests.swift`
  - `VelaUITests/BodySeekUITests.swift`
  - `docs/adr/0018-ios26-native-architecture-and-bevel-visual-reset.md`
  - `docs/validation/ios26-native-redesign-2026-11-16.md`
  - `docs/validation/tca-spezi-migration-2026-11-16.md`
  - `docs/validation/v3-opensource-ecosystem-2026-11-16.md`
  - `docs/validation/m0-v3-baseline-commit-2026-11-19.md`（本报告）

## 二、基线验证命令与结果

| 检查项 | 命令 | 退出码 | 结果 |
| --- | --- | --- | --- |
| Swift Package 单元测试 | `swift test --package-path BodySeekKit` | `0` | 10 / 10 passed (`0.430s`) |
| 隐私与产物隔离 | 核查 `git status`（排除 `.build/`、无 `.DS_Store`/`.sqlite`/`.zip`/`.xml`） | `0` | Clean |

## 三、未验证风险与交接说明

1. 本提交旨在固化 2026-11-16 的 V3 重写现场，使后续 M0–M4 开发有可回溯的 Git 起点；V3 重写对 `score-v2`、`ADR 0019`、Keychain 迁移与性能基线的对齐均在随后的 M0-2 至 M0-7 原子提交中逐一完成。
2. 遵循 V5 约束，本提交前不重写历史，仅本地提交到 `codex/ui/ios26-native-bodyseek`。
