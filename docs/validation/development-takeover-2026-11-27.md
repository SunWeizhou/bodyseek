# BodySeek 开发接手盘点 · 2026-11-27

## 当前开发基线

本次从 `bodyseek-1` 的 `v6/ui-v4`、`a340c9dac91b7637160923c52188bd0fa1c09b1a` 和当时的本地改动验收。工作区有 15 个已跟踪文件改动（+651/−119），另有 2 个未跟踪测试和 5 张未跟踪截图。测试覆盖了这份组合状态。临时计时测试 `ZZPerfScratchTests.swift` 明确标注为本地诊断用，其余改动涉及四条线：

| 范围 | 已看到的改动 |
| --- | --- |
| 体验 | 营养目标与估算样式、趋势概览、健身肌群卡 |
| 数据与性能 | 图表日期生成与增量评分、读取摘要、Core ML 后台预热与预测计算 |
| Coach | 今日五项分数的派生数据、带类型和单位的证据、数字归因 |
| 证据 | 宏量营养与 Coach 工具测试、三年数据量计时、体验截图 |

远端 `main` 为 `b26ca525`，本地 HEAD 包含该提交并领先 105 个提交。远端 `codex/ui/ios26-native-bodyseek` 为 `63b8a9e8`，本地 HEAD 领先 63 个提交。远端当前没有 `v6/*` 分支。GitHub 有 6 个较早的 UI Draft PR、2 个开放 Issue，未列出 GitHub Release。最近成功的 GitHub Actions 运行对应 V5 的 `63b8a9e8`。远端 `main` 当前提交的最近一次运行已取消。当前配置只在推送 `main`、`codex/**` 或触发 pull request 时启动 Quality。[V5 CI](https://github.com/SunWeizhou/bodyseek/actions/runs/44850773465) · [main CI](https://github.com/SunWeizhou/bodyseek/actions/runs/40068714203)

## 实现与待验收范围

| 模块 | 当前实现 | 后续范围 |
| --- | --- | --- |
| iPhone App | `VelaApp` 挂载 TCA `AppFeature`，五个一级入口为今日、健身、营养、趋势、Coach。V6 设计系统和 UI v4 已进入 SwiftUI 生产入口 | 真机验证不同字号、深色、趋势拖动和真实资料密度 |
| HealthKit / 数据库 / 评分 | SpeziHealthKit 和 `SyncEngine` 负责同步，GRDB 持久化，`score-v2` 生成五项评分，展示层有逐日 28 天滚动平时范围。已存在 v7 迁移、`BodyModelStore`、动作审计与简报缓存 | 验证真机初次回填、后台增量、训练删除、重启和 04:00 生理日切换。SwiftData 作为旧数据导入、清理的兼容层仍在。生产 `FitnessStoreClient` 的日常读写经 GRDB |
| 今日与 Coach | 有 `DailyBrief`、反馈、云端及端侧路由和本地简报兜底。训练标注、记忆、餐食删除等动作已有调用路径。训练计划变更仍需确认 | 核对真实模型、端侧 Foundation Models、数字日期证据及撤销闭环。蓝图要求的 Coach 一句话记餐、营养刷新和撤销尚未形成一条已验收的 `execute_action` 链路 |
| 健身 / 营养 | Watch 通过系统体能训练写入 HealthKit，iPhone 有复盘、肌群和体能疲劳展示。营养支持记餐、草稿确认、记录与估算标记 | 真机 Watch 回流、重启后的复盘与餐食操作。e1RM 仍为空态。计划撤销、进步三栏及营养和晨间主动功能仍有蓝图缺口 |
| 趋势 / 离线建模 | 四档时间跨度、指标切换、长期胶囊和实验室入口可用。预测、规律及 N-of-1 已有实现。BodySeekML 有回放和 Core ML 流水线 | HRV 和实睡时长尚未加入趋势纵览，V6 长周期评估和 score-v3 回放仍待完成 |
| 后端与发布 | Vapor 独立包可构建，测试目前覆盖提示词和工具注册。当前 iPhone target 使用 BodySeekKit，Coach 直连所配兼容模型或走本机框架。Fastlane 提供 TestFlight 发布入口 | 当前 V6 的签名、Release 归档、TestFlight 和正式交付链路未验收。部署脚本仍硬编码旧工程路径。App Store Connect 状态未查 |

依据见 [AGENTS](../../AGENTS.md)、[V6 蓝图](../design/v6-blueprint.md)、[UI v4 记录](ui-v4-2026-11-23.md)、[v7 数据层记录](v6-round3-2026-11-22.md) 和 [Xcode 工程规格](../../project.yml)。V5 后续的工程审计修复已进入当前分支的祖先历史（最后提交为 `34b74d40`），包括同步与游标事务、重置、异步请求身份、评分日期和 IPA 检查。PRD 和协作文档仍有旧版本描述，后续按任务涉及的生产入口逐条对齐。

## 本次复现的日期问题

1. **Coach 把前天当成昨天。** 合成历史含 11 月 21 日和 23 日，22 日缺测。调用 `get_today_context`，恢复项仍输出 `yesterday = 55` 和 `vsYesterday = 8`，其他四项也有同类结果。当前实现按历史数组最后一行取昨天，近期均值按行数切窗。第一批用例应覆盖精确的 04:00 生理日、稀疏日历和快照意外带未来数据。见 [CoachToolRegistry.swift](../../BodySeekKit/Sources/BodySeekAgent/CoachToolRegistry.swift#L569)。
2. **趋势缓存可能跨午夜沿用旧图。** UTC 下以相同 GRDB 合成数据依次加载 11 月 23 日 23:30 和 24 日 00:30。两次摘要相同，后一次取到的缓存曲线仍以 23 日为末日，直接重建则以 24 日为末日。缓存按生理日与快照内容去重，曲线按日历日构建。该差异在生产读路径上可以复现。修复前应先明确两个时间边界的产品合同。见 [BodySeekReadModel.swift](../../BodySeekKit/Sources/BodySeekStore/BodySeekReadModel.swift#L147)。

复现脚本只用合成数据和内存库，调用这次构建的 BodySeekKit 模块。脚本与输出保存在本机忽略目录中的 `boundary-probe.swift` 和 `boundary-probe.log`。

## 本次验证

本机为 Xcode 27.1（27A9275）、Swift 6.4。iOS 使用 iPhone 17 Pro 模拟器、iOS 26.5、中文环境、Debug、关闭签名、串行 UI 测试。CI 固定 Xcode 26.5.0，本机未找到该工具链。

| 验证 | 结果 |
| --- | --- |
| `swift test --package-path BodySeekKit --skip-update` | 退出 0。包测试 160/160，Coach 离线评测 46/46。主评测 31/31，固定回复共核对 24 个数字，未核对 0 个。 |
| `xcodebuild test` | 退出 0。iOS 集成 4/4，UI 14 通过、0 失败、3 项截图专用测试按设计跳过。 |
| `xcodebuild build`，通用 iPhone，Debug，关闭签名 | 退出 0，生成 `Debug-iphoneos/Vela.app`。 |
| `swift test --package-path VelaBackend --scratch-path <产物目录>/backend-build` | 退出 0，3/3。 |
| 在 BodySeekML 运行 `PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m pytest -q -p no:cacheprovider` | 退出 0，5/5。scikit-learn 产生 432 条数值计算警告，后续建模应定位并确认折间输出。 |
| `python3 scripts/check_design_system.py`、`check_contrast.py`、`check_fixed_fonts.py` | 均退出 0。设计扫描 0 违例，固定字号 0 处。对比度门禁通过，保留 `infoBlue` 2.43:1 提示。 |
| `git diff --check` | 退出 0。 |

本机日志、精确命令、`ios.xcresult` 和源文件摘要位于 `build/takeover-2026-11-27-1795767435996/`。模拟器验收覆盖已有合成和空数据入口。真实 HealthKit、Watch 回流、线上模型、Apple 端侧模型、真机手势、签名与 TestFlight 均待当前版本验证。

## 接手顺序

1. 以当前 V6 和现存改动建立可恢复的基线。按 UI、日期与性能、Coach 证据、营养计算实际依赖拆分，单独核对临时测试和截图，再对齐 GitHub 的目标分支及 CI。老 Draft PR 先和 V6 对照适用性。
2. 优先处理两处已复现的日期问题。覆盖缺测日、未来日、跨午夜与 04:00 的回归，再用固定输入对拍即时评分、缓存和 UI。三年性能用已有计时方法复核，首屏和交互帧耗时用真机采样。
3. 验收日常使用闭环。用同一构建检查首次健康授权、缓存冷启动、后台同步、Watch 训练回流与撤销、营养草稿保存与重启、Coach 云端、端侧及断网兜底。完成后再排 score-v3、健身进步、长周期评估与主动简报。
