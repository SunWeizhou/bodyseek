# 算法与数据工作流

算法主责维护从 `HealthKit → Daily Health Snapshot → 持久化 → Daily Health Computation → Personal Health Brief` 的可信链路。

每项变更都要明确：

- 输入信号、来源、观测时间和覆盖范围；
- `unknown`、known zero、`excluded(reason)` 的区别；
- 历史日期的 as-of 规则，不能使用未来数据；
- 算法、输入和 schema 版本；
- 固定回放、生产路径单测和必要的真机验证。

算法输出先成为稳定的数据合同，UI 只消费合同，不自行重新推导分数或缺失语义。`BodySeekDomain` 的测试不能替代 Vela iOS 生产评分验证。
