# Changelog

所有值得记录的变更。格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased]

### Changed（2026-10-06 版本锁定）

- 现行版本是分支 `cursor/today-brief-ui-clarity-6bf9`：主屏幕名 BodySeek，四个一级表面，部署底线仍是 iOS 17 / watchOS 10。
- 与现行界面矛盾的根目录旧文稿移入 `docs/archive/product-eras/`。Finder 重复的设计副本已删除。生产路径里注释掉的旧睡眠分调用已去掉。
- 删除未走上生产路径的应用内 `VelaApp/Scoring/Sleep/SleepScoreEngine.swift`。预览改走 `DomainSleepScoreAdapter`。锁定睡眠分行为的测试改打 `BodySeekDomain.SleepScoreEngine`。计分公式未改。

### Fixed（2026-08-23 工程标准审计 C1/C2/H2/H5/H7）

- **SwiftData schema 版本守卫**：新增 `VelaSchemaV3Frozen` 冻结快照（脚本生成）与 `scripts/schema_fingerprint.py --check` CI 门禁；模型图变更必须与版本提升同提交原子完成。
- **HealthKit 错误不再被吞成「无数据」**：仅 `errorNoData` 走空数据分支；授权/参数/数据库错误按组件分类记录并保持当日 dirty 重试；`lastSuccessfulSyncAt` 仅在无失败日推进。
- **查询有界化**：`fetchSnapshots` 降序 + fetchLimit；隐私清点改用 `fetchCount`；流式 markdown 解析缓存（消除 0.5s 心跳全文重解析）。
- **CI 硬化**：schema 守卫、工具链校验、确定性模拟器选择、xcresult 失败上传、`*.log` 出仓、`.xcode-version`。
- **数据删除盲区**：`daily_logs` 明文归档与 `VelaRecovery` 恢复备份纳入「清空本地数据」。

### Fixed（工程标准审计 H1/H3/H4/H6/H8）

- **Dynamic Type**：小字号字体工厂改用系统 TextStyle（默认字号不变、随缩放）。
- **后台预算**：BGAppRefreshTask 复用 App 容器，省去重复打开 store/迁移检查。
- **日志收敛**：16 处 `print` 迁移到 `os.Logger`（带 `privacy` 标注）。
- **对比度**：新增文字用状态色 `VelaTheme.textColor(for:)`（WCAG AA ≥4.5:1），6 处文字切换。
- **可访问性**：3 处低于 44pt 命中区提升到规范值；Tab 栏补 `accessibilityIdentifier`。

### Added

- 新增测试 15 个（schema 守卫 / HealthKit 错误分类 / 隐私删除完整性）；全量套件通过。
- `README.md`、`CHANGELOG.md`、`docs/validation/engineering-audit-2026-08-23.md`（审计报告）。
