# Design D · 实机审查后的修复证据

代码起点：`53d173c3ab69aef9d5ec798a77e4e257cbb58c79`（wave25）。
代码提交：`e470e38d0c58b22de16b272dec539db969eac4bf`；档案/训练 QA：`ec2689cd6ec22d87b66a3c3cc8de5fdb3e8d5a3b`；最终代码：`07b85e8ba98bd3c3a526723ad50c6dd984495fc5`（最大字号宽度修复）。
`origin/main`：`b26ca52580b9ef507ee5de824f3347a04d9e66d7`。分支保留 wave22–25 的已有修改；本轮增量相对 wave25 单独可审。

完整问题及处理边界见 [audit-fix-status.md](../../audit-fix-status.md)。[source-manifest.json](source-manifest.json) 记录最终源码 SHA-256；后续文档提交不修改这些文件。

## 配置与证据边界

- Xcode 27.1 / 27A9275；仓库 pin 26.5.0 未修改，本机构建不能替代 CI 对 pinned toolchain 的结果。
- iPhone SE 3（375pt）与 iPhone 17 Pro Simulator，iOS 26.5，简体中文，L / AccessibilityXXXL，深浅色。
- `-velaPreviewDashboard` 使用既有只读合成样例；新增 `-velaPreviewEmptyDashboard` 只在 DEBUG preview 分支返回空快照。没有写入健康数据或把示例用作生产默认值。
- 真实 iPhone 镜像只用于前置审查。当前设备 Git SHA 未确认，此前镜像处于 Touch ID 锁定，尚未安装候选；后续安装状态见本报告末尾的部署更新。本目录仅包含模拟器合成数据截图，没有真实个人健康数据、密钥或镜像截图。

## Red → Green

1. `DeviceAuditRed2.xcresult`：空闲 AskBar 高度 **99pt > 76pt**，回归失败；嵌套随手记聚焦后关闭已通过，因此不能声称关闭失效根因已被复现。
2. `DeviceAuditMissingRed.xcresult`：睡眠缺失被显示成“0 分钟”，回归失败。
3. `DeviceAuditHeaderRed.xcresult`：Today 摘要 y=35.5，分段导航底 y=69，回归失败。全新启动可稳定复现，排除旧滚动位置；将外层 safeAreaInset 改为明确的垂直布局后通过，同时检查 AskBar 屏内可见。
4. `DeviceAuditFinalUI17.xcresult`：11/12 通过；唯一失败是测试把系统键盘“发送”键与 AskBar 同名按钮混查。测试已改用既有 `bodyseek-send` 标识，产品发送逻辑未改。
5. `DeviceAuditRegression1.xcresult`：10 条 UI 通过；并行 unit clone 启动失败，668 项通过后停止推进，运行中止（退出 143），bundle 未完整收尾。未将其记作全量通过，也不依赖该 bundle 作为唯一证据。

6. `DeviceAuditAXRed.xcresult`：最大字号首页左边缘 **−219pt**，新增 viewport 回归失败。长 chip 原用无限宽测量并固定单行；限制测量/摆放宽度、允许换行，同时调整署名和顶栏的大字布局后通过。修复组合的单项贡献未分别隔离。

最终结果由 [test-summary.json](test-summary.json) 与下表记录，保留失败尝试，避免将重跑过程当作一次全绿。

## 可重跑命令

`BODYSEEK_SIMULATOR_UDID` 取 `xcrun simctl list devices available` 的一个 iOS 26.5 设备；result bundle 路径每次使用新目录。

```sh
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination "platform=iOS Simulator,id=$BODYSEEK_SIMULATOR_UDID" \
  -derivedDataPath build/VisualResidualDerivedData \
  -resultBundlePath build/DeviceAuditRerun.xcresult \
  -parallel-testing-enabled NO -only-testing:VelaTests \
  '-only-testing:VelaUITests/VelaSmokeUITests/testDeviceAuditAccessibilityStaysWithinViewport()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testDeviceAuditHeaderKeepsSummaryVisible()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testDeviceAuditEmptyReadingsAndComposer()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testDeviceAuditMissingDetailReadings()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testDeviceAuditFilledProfileKeepsLabels()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testDeviceAuditTrainingReturnsToPlanAfterTabSwitch()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testDeviceAuditNestedQuickNoteClosesAfterFocus()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testDeviceAuditSecondaryReadingAndSheets()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testVisualBodyWave25Snapshots()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testNetworkAgentNavigationAndReturn()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testVisualNextWaveSettingsSnapshots()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testVisualNextWaveAccessibilitySnapshots()' \
  '-only-testing:VelaUITests/VelaSmokeUITests/testAskBarOffersExplicitSendAndStaysOnCurrentPage()' \
  CODE_SIGNING_ALLOWED=NO test
```

本机 Xcode 27.1 的方法筛选包含 `()`；初次省略括号时执行了 0 tests，已识别并纠正，未计入验收。

```sh
python3 scripts/check_fixed_fonts.py --strict
python3 scripts/check_contrast.py
python3 scripts/schema_fingerprint.py --check
bash scripts/audit_design_tokens.sh
git diff --check
```

## 刻意保留的边界

- VB-16：那次实机关闭失效仍需新包重复验证；模拟器修复前后均正常，不声称已定位该次根因。
- VB-22：已区分实时原始信号、7/30 天样本与日期化评分快照；没有同日同源回放，未修改 Store / 缓存 TTL / 计算管线来“消除”未知状态。
- 不改评分公式、共享模型/schema、导航 IA、Watch、WidgetKit 或对话历史。未改变真实个人资料、已保存计划、密钥、授权开关；未测试真实联网连接。
- 未自动改写档案正文。默认空模板在阅读页显示待填写状态；自写内容保留原文并使用既有 MarkdownText 渲染器。


## 最终验证

| 代码 / result bundle | 配置 | 结果 |
| --- | --- | --- |
| e470e38d · DeviceAuditCandidateFinal | SE 3 / iOS 26.5 / 串行 | 683 unit + 12 UI，695/695，exit 0 |
| ec2689cd · DeviceAuditScreenshotQA | iPhone 17 Pro / iOS 26.5 | 683 unit + 2 UI，685/685，exit 0；档案和训练截图复核通过 |
| 07b85e8b 同版生产代码 · DeviceAuditAXGreen | SE 3 / L 与 AccessibilityXXXL | 2 UI，exit 0；新增宽度回归 + Today/Trends/Plan 快照 |
| 07b85e8b · DeviceAuditVerifiedTip | SE 3 / iOS 26.5 / 串行 | 683 unit + 4 UI，687/687，exit 0；发送、AX viewport、空态及详情缺失值 |

共 **13 条不同 UI 路径分批通过**；不是把不同批次重复测试相加当作独立覆盖。最后一次生产代码变更后重跑全量 683 项 unit；未改动的二级页路径由前一批及对应的定向复验覆盖。Xcode 并行 clone 失败与 selector 修正见上方尝试记录。

固定字号 strict：178 / 阈值 216；contrast OK；schema fingerprint：32 live / 32 frozen V3，均 exit 0。Token audit 合计 577，为 report-only，不能解读为全仓零残留。没有新增 palette。图标的固定 44pt 控制内只约束图形尺寸，正文与导航文字仍响应 Dynamic Type。

## 截图索引

22 张原始 PNG，取自真实 SwiftUI / XCTest；来源测试、代码版本与 SHA-256 见 [screenshots.json](screenshots.json)。

- Today：[空数据/浅色](device-audit-today-empty-light.png)、[有数据/深色](wave25-today-hero-dark.png)、[最大字号](device-audit-accessibility-today-bounds.png)。
- Trends / Plan：[趋势日期参照](wave25-trends-hierarchy-dark.png)、[趋势最大字号](device-audit-accessibility-trends-bounds.png)、[计划](wave25-plan-dark.png)、[训练返回栏](device-audit-training-return.png)。
- Metric detail：[睡眠缺失/首屏](device-audit-metric-detail-sleep-empty-top.png)、[睡眠缺失/下部](device-audit-metric-detail-sleep-empty.png)、[能量缺失/首屏](device-audit-metric-detail-energy-empty-top.png)。
- Journal / Sheets：[快捷操作](device-audit-quick-actions-dark.png)、[Journal](device-audit-journal-dark.png)、[随手记/软件键盘](device-audit-note-focused.png)。
- Settings：[已填资料](device-audit-filled-profile.png)、[资料最大字号](profile-accessibility.png)、[档案空模板阅读](device-audit-archive-reading-dark.png)、[数据覆盖](device-audit-raw-coverage-light.png)、[数据来源](next-sources-dark-scrolled.png)、[沟通方式](next-personality-dark.png)、[信任中心](next-trust-dark.png)、[联网 Agent 配置](wave21-agent-destination-dark.png)。


## 真机部署更新

用户随后明确要求“推送到手机”。已在 iPhone 16 Pro 上覆盖安装本轮签名构建，未卸载 App，也未执行数据删除。

- 安装来源：`7c62a0d1a29598f12256b7d488f772015923a857`（生产代码 `07b85e8b`）；构建前工作区 clean。
- `xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'id=<paired iPhone>' -derivedDataPath build/DeviceAuditPhoneDerivedData -allowProvisioningUpdates build`：exit 0。
- `codesign --verify --deep --strict <Vela.app>`：exit 0。
- `xcrun devicectl device install app --device <paired iPhone> <Vela.app>`：exit 0，安装 receipt 为 success。Bundle `com.sunweizhou.Vela4`，版本 4.0.0 (1)。
- 随后两次前台启动均被 iOS 以 `Locked` 拒绝，尚未验证运行/首屏，不把安装成功等同于真机 UI 验收。已请求用户解锁；VB-16 / VB-22 仍未闭环。

脱敏安装凭据：[phone-install-receipt.json](phone-install-receipt.json)。不提交设备 UDID、签名账户、安装容器路径或真实健康数据。此部署只更新手机包，没有单独向 Watch 部署。
