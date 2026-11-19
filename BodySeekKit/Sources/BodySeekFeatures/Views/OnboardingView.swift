import BodySeekCore
import SwiftUI

public struct OnboardingView: View {
    public let onAuthorizeAndStart: () -> Void
    public let onStartDirectly: () -> Void

    public init(onAuthorizeAndStart: @escaping () -> Void, onStartDirectly: @escaping () -> Void) {
        self.onAuthorizeAndStart = onAuthorizeAndStart
        self.onStartDirectly = onStartDirectly
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BevelAmbientAura(recoveryScore: 84)

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    BodySeekBrandMark(size: 52)
                    Text("BodySeek")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(BevelTheme.ink)
                    Text("结合 Apple 健康、SpeziHealthKit 与 AI 智能体工具链，把你的恢复、肌群负荷、睡眠与力量训练融合成同一套日常系统。")
                        .font(.body)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                VStack(spacing: 12) {
                    featureRow(
                        icon: "figure.strengthtraining.traditional",
                        tint: BevelTheme.strainColor,
                        title: "全身肌群热图 & 力量训练日志",
                        detail: "由 MuscleMap 驱动 72 小时疲劳分布，组间倒计时同步手表通知并写回 Apple 健康。"
                    )
                    featureRow(
                        icon: "bed.double.fill",
                        tint: BevelTheme.sleepColor,
                        title: "睡眠分期阶梯 & 昼夜压力能量图",
                        detail: "集成 SleepChartKit 阶梯分期图、24 小时压力节律与 ACWR 负荷平衡。"
                    )
                    featureRow(
                        icon: "sparkles",
                        tint: BevelTheme.brand,
                        title: "双引擎真 AI 教练 & 长期记忆",
                        detail: "支持 Apple 端侧智能与 DeepSeek，主动记住伤病偏好并生成可一键开练的处方。"
                    )
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: onAuthorizeAndStart) {
                        Text("连接 Apple 健康并开始")
                            .font(.headline)
                            .foregroundStyle(BevelTheme.onBrand)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityIdentifier("onboarding-authorize-start")

                    Button(action: onStartDirectly) {
                        Text("先进入主页再授权")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BevelTheme.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .accessibilityIdentifier("onboarding-skip-button")
                }
            }
            .padding(24)
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
    }

    private func featureRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        BevelCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
            }
        }
    }
}
