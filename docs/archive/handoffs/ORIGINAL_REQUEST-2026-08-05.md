# Original User Request

## Initial Request — 2026-08-05T11:04:42+08:00

You are the Project Orchestrator for the Vela iOS Health AI project.

Workspace Directory: /Users/sunweizhou/Developer/Vela
Working Directory: /Users/sunweizhou/Developer/Vela/.agents/orchestrator
Original Request Path: /Users/sunweizhou/Developer/Vela/ORIGINAL_REQUEST.md

Your mission is to perform a comprehensive feature diagnosis and bug fix for the Vela iOS application according to the following requirements:

### R1. 首页数据同步、存储与计算修复
- 补全 `VelaTodayViewData.swift` 中 `loadRealNutritionData()` 与 `loadDynamicData()` 空存根实现，连通 SwiftData `FoodLogRecord` 与动态趋势。
- 修复 `onChange(of: scenePhase)` 的过度同步机制，引入防抖与缓存鲜度校验，避免重复执行 42 天全量 HealthKit 历史计算。
- 增强 HRV 数据采集，补充 `.heartRateVariabilityRMSSD` 采样与副交感神经张力计算。

### R2. Coach 聊天对话与键盘交互修复
- 修复 `CoachView.swift` 键盘弹出时的 `keyboardHeight` 底部 padding 缺失 Bug，确保输入框与发送按钮随键盘平滑抬升，不被键盘遮挡。
- 优化 Coach SSE 流式响应取消机制（`cancelActiveResponse`），在用户停止生成时彻底中断底层的 API 请求任务。
- 实现 `MemoryLedger` 提议写入后与 `WikiProfileView` 的实时状态响应。

### R3. 页面导航与返回体验统一
- 统一 modal sheet 与 NavigationStack 的返回/关闭行为，在 `VelaMetricDetailView` 等 Sheet 页面中使用明确的关闭按钮（`xmark`）替代误导性的 `chevron.left` 返回箭头。
- 为所有二级与三级 Modal Sheet 增加标准的 Drag Indicator 与边缘滑动手势支持。

### R4. 二级页面数据与图表可视化升级
- 修复 `.day` 视图下的图表点集渲染，接入 HealthKit 内日（Intra-day）高频采样点（如 HR/Stress 逐时数据）。
- 为 `MetricChartSection` 增加动态 Y 轴 Auto-Domain 缩放与基线范围高亮（例如血氧 90%-100% 细分，HRV 波动曲线等），提升可视化对比度与直观性。
- 消除 `StrengthWorkoutRecord` 与 `WorkoutEventRecord` 在二级训练详情页中的重复计数与时长统计偏差。

## Acceptance Criteria
1. 首页与计算:
   - 首页下拉刷新与 App 切前台时不再重复触发全量计算死循环。
   - 首页营养统计（热量、蛋白质、碳水、脂肪）能正确展示 SwiftData 当日打卡记录。
2. Coach 聊天:
   - 在 iPhone 模拟器与真机上弹出键盘时，Coach 输入框底栏始终悬浮在键盘上方，无遮挡、无布局跳变。
   - 点击“停止生成”能即刻停止流式打印并中断后台 HTTP 链接。
3. 返回与导航:
   - 点击 `VelaMetricDetailView` 顶部左侧按钮能平滑关闭当前 Sheet，无导航层级混乱。
4. 可视化与二级页:
   - 30 天/7 天/单日趋势图具备 Auto-scaling Y 轴，非平坦直线。
   - 训练详情页动作组与 HealthKit 耗力数据无重复叠加。

Please create `.agents/orchestrator/` folder and maintain `plan.md`, `progress.md`, `context.md` in `.agents/orchestrator/`. Proceed with exploring the codebase, decomposing tasks, invoking implementer/reviewer agents, testing/verifying builds, and updating progress. When all criteria are fully met, inform the Sentinel.
