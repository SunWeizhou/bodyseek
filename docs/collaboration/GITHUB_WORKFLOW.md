# GitHub 双人工作流

## 分支

`main` 只接收可复核的变更。每个任务建立一条短分支：

```text
codex/algo/<topic>
codex/ui/<topic>
```

一条分支只服务一个用户可感知结果。不要在同一分支混入算法、UI 和无关清理。

## Issue

每个 Issue 写清楚用户结果、代码边界、依赖、验收证据和未解决风险。使用 [`TASK_TEMPLATE.md`](TASK_TEMPLATE.md)；Issue 标题以 `[ALGO]`、`[UI]`、`[CONTRACT]` 或 `[VALIDATION]` 开头。

## Pull Request

PR 必须说明：改了什么、为什么、测试命令和退出码、设备或模拟器配置、截图/录屏证据、是否改变数据语义或算法版本。UI PR 需要真实 SwiftUI 证据；算法 PR 需要固定输入回放或生产路径测试。

## 合并顺序

跨边界功能按这个顺序走：

1. 算法主责提出输入、输出、缺失状态和版本字段。
2. 双方确认合同与固定样例后，可以并行实现算法与 UI；共用文件指定一位写入。
3. 先集成合同，再集成算法和 UI 的适配；UI 可用测试/Preview 样例提前开发。
4. 双方完成各自验证，另一人复核 PR；最终以集成提交的 CI 与所需页面证据验收。

`Vela.xcodeproj/project.pbxproj`、共享领域模型、SwiftData schema 和公共 DTO 同一时间只允许一个人修改。

## 同步

开始工作先检查工作区，再由开发者或已获授权的 Agent 同步远端；结束时在 PR 或 [`HANDOFF_TEMPLATE.md`](HANDOFF_TEMPLATE.md) 中记录 HEAD、改动文件、验证结果和下一步。不得用 reset、clean 或覆盖方式解决冲突。

## 首次上线协作配置

当前模板仅在本地，推送后才成为远端仓库内容。GitHub 的成员权限、main 分支保护和必需检查需单独核对配置；这些文档不会自动设置它们。PR 最少请另一位开发者复核，关键合同和 schema 由双方阅读。公开仓库的提交只包含可公开内容，原始资料包不要用 `git add .` 全量带入。
