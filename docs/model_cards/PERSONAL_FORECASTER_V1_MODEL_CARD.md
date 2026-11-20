# Model Card: `personal-forecaster-v1@1.0.0`（端侧个人多目标预测模型）

## 1. 模型定位与架构

- **Artifact**：`BodySeekPersonalForecasterV1.mlpackage`（CoreML `mlprogram`，Float32，Minimum Deployment Target: iOS 18+）
- **共享特征合同**：[`personal_forecaster_v1_spec.json`](../../BodySeekKit/Sources/BodySeekCore/Resources/personal_forecaster_v1_spec.json)（31 维严格因果特征，包含观察掩码 `*_mask0`、Banister $\tau_g=42/\tau_h=7$ 状态特征、分开建模的主观/估算 Effort，以及预留 `eating_context_mask0` 进食节律位）。
- **预测目标**：次日夜间 HRV (SDNN, ms)、次日静息心率 (RHR, bpm)、次日睡眠效率 (ratio) 点估计及 Split-Conformal 80%/90% 预测区间。
- **结构选型依据**：依据 M4b + M4c 月度 Walk-Forward 配对检验（见 [`m4b-forecasting-backtest-2026-11-20.md`](../validation/m4b-forecasting-backtest-2026-11-20.md) 与 [`m4c-deep-model-comparison-2026-11-20.md`](../validation/m4c-deep-model-comparison-2026-11-20.md)），正则化低方差线性/状态空间模型在个人生理单序列上显著稳健且零过拟合，遂作为 v1 生产 CoreML 导出架构。

## 2. 实测回测与区间校准（Walk-Forward 24 个月起训按月滚动）

| 目标 | M4b Ridge MAE | M4b Best Baseline (MAE) | Split-Conformal 80% 区间覆盖率 | 导出的 80% 半宽 (`±`) |
|---|---:|---|---:|---:|
| `hrv_sdnn_ms` | `6.3285` | `LightGBM` (`6.3103`) | `80.3%` | `±8.9223` |
| `resting_hr_bpm` | `2.8567` | `Banister` (`2.7589`) | `80.8%` | `±5.1535` |
| `sleep_efficiency` | `0.0319` | `LightGBM` (`0.0298`) | `80.8%` | `±0.0354` |

## 3. 双端对拍与不变量

- Python NumPy 参考实现 vs 导出 `BodySeekPersonalForecasterV1.mlpackage`（24 组合成与边界特征向量）最大相对误差：`9.40e-08`（门禁上限 `<= 1e-3`）。
- Swift `PersonalForecasterEngine` 与真实 `CoreML` 运行时通过 `Bundle.module` 对拍同一份 24 组 Golden Vectors。
- **因果与医学免责边界**：本模型属于统计预测与个体状态辅助评估，**不构成医疗诊断**，亦不能作为因果干预证明（建议结合 `Trends` 页 N-of-1 自实验模板实测验证）。
