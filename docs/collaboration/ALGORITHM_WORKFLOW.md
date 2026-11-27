# 算法与数据工作流

算法主责维护从 HealthKit 采集、BodySeekCore 确定性计算到 GRDB ReadModel 的可信链路。生产装配见 [技术架构](../TECH_ARCHITECTURE.md)。

每项变更都要明确：

- 输入信号、来源、观测时间和覆盖范围；
- `available`、`knownZero`、`missing`、`excluded(reason)` 四态；
- 历史日期的 as-of 规则，不能使用未来数据；
- 算法、输入和 schema 版本；
- 固定回放、生产路径单测和必要的真机验证。

算法输出先成为稳定的数据合同，UI 只消费合同，不自行重新推导分数或缺失语义。评分回归沿当前 BodySeekKit 和 iOS 生产接线验证。
