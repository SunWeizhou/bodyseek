# BodySeekML（个人身体模型离线实验室）

本目录承载 BodySeek Blueprint V5 §10（M4a–d）的离线分析与个人模型流水线，与 iOS 主工程（`BodySeekCore`）共享生理日定义、睡眠合并策略与四态真值掩码规格。

## 隐私与仓库边界

- Raw Apple Health 导出包（`*.zip`、`导出.xml`、`*.gpx`、ECG）、本地 Parquet 特征表（`BodySeekML/data/*.parquet`）以及含原始设备名称的审计细节（`BodySeekML/data/*.json`）**严禁提交到 git**，均已被 `.gitignore` 屏蔽。
- 进入版本库的文档（`docs/validation/personal-patterns-v1-*.md`）仅保留脱敏后的聚合统计、匿名设备编号与分布滞后关联结果。

## M4a 管线设计

1. **流式解析（`export_parser.py`）**
   - 直接从 Apple Health 导出压缩包中流式读取 XML（按 `depth == 1` 即时清理 DOM，支持 GB 级导出包低内存解析）。
   - 按本地时区 **04:00 生理日切点**（与 `BodySeekCore.DayKey` 对齐）汇总每日指标。
   - **四态掩码（`available` / `knownZero` / `missing` / `excluded`）**：绝不将缺测静默填零；仅在有佩戴信号且无锻炼时将训练时长标记为 `knownZero`；已为饮食模块预留 `eating_context_state = "missing"`。
   - **Effort 严格分离**：`effort_user_mean` 仅汇总 `WorkoutEffortScore`，`effort_estimated_mean` 仅汇总 `EstimatedWorkoutEffortScore`。
   - **睡眠合并策略 `sleep-merge-v1`**：复刻 `SleepMergePolicy.swift`，按 90 分钟簇拆分、扫描线按来源优先级（Apple Watch 分期 > AutoSleep > 第三方可穿戴 > iPhone/卧床）去重。
2. **来源与去重审计（`dedup_audit.py`）**
   - 完整盘点所有 `sourceName`，不按名字静默丢弃历史设备；输出睡眠/步数/活动能量重叠去重前后对比及脱敏设备归属核对表。
3. **分布滞后个人规律（`patterns.py`）**
   - 按日历连续时间轴对齐（防止缺测日错位与未来数据泄露）。
   - 使用 **7 天移动块自助法（Block Bootstrap，2000 次）** 保持序列自相关，并经 **Benjamini-Hochberg FDR** 校正，产出需经用户确认后才进入 `pattern_finding` 的候选规律（诚实标注关联性而非因果性）。

## 运行方式

```bash
cd BodySeekML
uv sync
uv run pytest -v
uv run bodyseek-ml run-m4a \
  --export-zip "~/Downloads/导出.zip" \
  --out-dir data \
  --report ../docs/validation/personal-patterns-v1-2026-11-20.md
```
