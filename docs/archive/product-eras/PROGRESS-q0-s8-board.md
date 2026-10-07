> 归档：这不是现行产品规格。现行版本以 `docs/PRD.md`、`CONTEXT.md` 与分支 `cursor/today-brief-ui-clarity-6bf9` 的源码为准。2026-10-06 从仓库根目录移入。

# 执行进度｜初始状态

所有任务目前均未由本包执行。填写时区分 IMPLEMENTED、VERIFIED、BLOCKED，不把文件存在视为验证。

| 卡号 | 任务 | 前置 | 状态 | 实际 SHA | 证据 |
|---|---|---|---|---|---|
| Q0 | 恢复当前 iOS 可验证基线 | 无；先核对 HEAD 和工作区未提交改动 | VERIFIED | 7f23f61b | docs/validation/Q0_HANDOFF.md |
| U1 | 建立真实 UI 基线并完成一套组件精修 | Q0 实际通过 | VERIFIED | 6c8d5d13 | docs/validation/U1_HANDOFF.md |
| U2 | Today 三加二精修到正式可用 | U1；保留评分数据不变 | VERIFIED | 358033f9 | docs/validation/U2_HANDOFF.md |
| U3 | 恢复详情标杆页与正确返回 | U2 | VERIFIED | 2bffa05b | docs/validation/U3_HANDOFF.md |
| U4 | 睡眠详情精修与真实时间轴 | U3；睡眠算法保持不变 | VERIFIED | cc67be11 | docs/validation/U4_HANDOFF.md |
| U5 | Trends 与首页小趋势的统一数据图形 | U3；如缺日期合同需先 S1 的最小投影 | VERIFIED | cc67be11 | docs/validation/U5_HANDOFF.md |
| U6 | 其余详情与交互收尾 | U3/U4/U5 | VERIFIED | cc67be11 | docs/validation/U6_HANDOFF.md |
| S1 | 真实观测窗口与质量合同 | Q0；与 UI 公共投影变更串行 | VERIFIED | 72c0f91a | docs/validation/S1_S8_HANDOFF.md |
| S2 | 长期 as-of 生产链回归 | Q0；保留已实现日期过滤 | VERIFIED | 72c0f91a | docs/validation/S1_S8_HANDOFF.md |
| S3 | HRV 方法分离与附加 PSTI 约束 | S1；S2 推荐完成 | VERIFIED | 72c0f91a | docs/validation/S1_S8_HANDOFF.md |
| S4 | 睡眠事实与充分性政策分离 | S1；UI与公式改动分提交 | VERIFIED | 72c0f91a | docs/validation/S1_S8_HANDOFF.md |
| S5 | 负荷测量方法、单位与活动重叠 | S1 | VERIFIED | 72c0f91a | docs/validation/S1_S8_HANDOFF.md |
| S6 | 日负荷时间轴与 EWMA 缺失 | S5 的单位/方法政策已明确 | VERIFIED | 72c0f91a | docs/validation/S1_S8_HANDOFF.md |
| S7 | 生理压力的真实时间尺度 | S1；相关负荷方法明确 | VERIFIED | 72c0f91a | docs/validation/S1_S8_HANDOFF.md |
| S8 | 能量估计与上游质量传播 | S1/S7；与共享合同修改串行 | VERIFIED | 72c0f91a | docs/validation/S1_S8_HANDOFF.md |
| V1 | 建立可复跑的算法比较与模型卡 | S1–S8 中相关修复已验收；可分指标先做 | VERIFIED | 0b7d8adf | docs/validation/V1_HANDOFF.md |
| R1 | 真机发布与用户体验验收 | 本轮选定 U/S/V 卡均完成，不强迫未授权研究候选上线 | VERIFIED | fc2c40ab | docs/validation/R1_HANDOFF.md |

每次只将有实际证据的卡标为 VERIFIED。若最新HEAD已经完成某卡，先补真实证据再标记，不重复实施。

> 注（2026-09-26）：R1 表内旧写 `0c1449d4` 在仓库对象中不存在；以 `main` 上实际部署提交 `fc2c40abd10ae43a9a04c77aec0280ae1eb24131`（`feat(deploy): … Card R1 VERIFIED`）为准。本表记录历史验证卡，不代表后续未合入 `main` 的特性分支状态。
