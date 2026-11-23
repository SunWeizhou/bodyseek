import BodySeekCore
import SwiftUI

/// 设计系统画廊：所有 `BS*` 组件 × 四态 × 浅色 / 深色 × 默认 / 最大字号。
///
/// 用于视觉评审和截图测试。第二轮尚未接入 App 启动参数（`-bodyseekGallery`），
/// 需要改 `VelaApp` 或 `BodySeekFeatures`，留待后续；目前通过 `#Preview` 或把它放进临时入口查看。
public struct DesignSystemGallery: View {
    private enum Scheme: String, CaseIterable, Identifiable {
        case system = "跟随系统"
        case light = "浅色"
        case dark = "深色"

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    @State private var isLoading = false
    @State private var largeText = false
    @State private var scheme: Scheme = .system

    /// 创建画廊。
    public init() {}

    public var body: some View {
        NavigationStack {
            BSPage("设计系统", isLoading: isLoading) {
                controls
            } sections: {
                GalleryRings(isLoading: isLoading)
                GalleryData(isLoading: isLoading)
                GalleryCharts(isLoading: isLoading)
                GalleryCoach(isLoading: isLoading)
                GalleryStructure()
                GalleryV4(isLoading: isLoading)
            }
        }
        .dynamicTypeSize(largeText ? .accessibility3 : .large)
        .preferredColorScheme(scheme.colorScheme)
    }

    private var controls: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                Toggle("加载骨架", isOn: $isLoading)
                Toggle("最大字号", isOn: $largeText)
                Picker("外观", selection: $scheme) {
                    ForEach(Scheme.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

private struct GalleryRings: View {
    let isLoading: Bool

    private let scores: [BSScoreItem] = [
        BSScoreItem(kind: .recovery, value: 78, statusText: "充沛"),
        BSScoreItem(kind: .sleep, value: 71, statusText: "平时"),
        BSScoreItem(kind: .strain, value: 0, availability: .knownZero(reason: "今日休息")),
        BSScoreItem(kind: .stress, value: nil, availability: .missing(reason: "未佩戴手表")),
        BSScoreItem(kind: .energy, value: nil, availability: .excluded(reason: "运动后窗口已排除")),
    ]

    var body: some View {
        BSSection("五项分数") {
            BSCard {
                BSScoreRing.group(scores, isLoading: isLoading) { _ in }
            }
            BSCard {
                HStack(spacing: BSSpace.m) {
                    BSScoreRing(kind: .recovery, value: 78, size: .small, isLoading: isLoading)
                    BSScoreRing(kind: .sleep, value: 71, size: .medium, isLoading: isLoading)
                    BSScoreRing(kind: .energy, value: 64, size: .large, isLoading: isLoading)
                }
            }
        }
    }
}

private struct GalleryData: View {
    let isLoading: Bool

    private let verdicts: [BSVerdictRow] = [
        BSVerdictRow(
            id: "adapt", name: "训练适应", basis: "体能较前 12 周上升",
            verdict: .stronger, trend: [3, 4, 4, 5, 6, 6, 7, 8]
        ),
        BSVerdictRow(
            id: "sleep", name: "睡眠", basis: "睡眠债 2 小时，作息稳定",
            verdict: .stable, trend: [5, 5, 6, 5, 5, 6, 5, 5]
        ),
        BSVerdictRow(
            id: "recovery", name: "恢复能力", basis: "HRV 慢基线下降",
            verdict: .overreaching, trend: [8, 7, 7, 6, 6, 5, 4, 4]
        ),
        BSVerdictRow(id: "body", name: "体型", basis: "有效样本不足 14 天", verdict: .insufficient),
    ]

    private let macros: [BSMacroProgress] = [
        BSMacroProgress(name: "蛋白质", value: 96, target: 130),
        BSMacroProgress(name: "碳水", value: 180, target: 250),
        BSMacroProgress(name: "脂肪", value: 52, target: 70),
    ]

    var body: some View {
        BSSection("关键体征") {
            BSMetricGrid {
                BSMetricTile(
                    title: "夜间 HRV", value: "52", unit: "ms",
                    delta: -4, trend: [48, 50, 55, 53, 49, 52],
                    tint: BSColor.recovery, isLoading: isLoading
                )
                BSMetricTile(
                    title: "静息心率", value: "58", unit: "bpm",
                    delta: 0, trend: [], isLoading: isLoading
                )
                BSMetricTile(
                    title: "呼吸率", value: nil, availability: .missing(reason: "昨夜无数据"),
                    isLoading: isLoading
                )
                BSMetricTile(
                    title: "额外训练", value: nil, availability: .knownZero(reason: "今日休息"),
                    isLoading: isLoading
                )
            }
            BSStateView(.unauthorized, message: "需要读取 Apple 健康数据", actionTitle: "去授权") {}
        }
        BSSection("走向与摄入") {
            BSVerdictGrid(rows: verdicts, isLoading: isLoading) { _ in }
            BSIntakeRing(
                calories: 1480, target: 2200, isEstimate: true,
                macros: macros, isLoading: isLoading
            )
            BSDeltaBadge(delta: 4, unit: "ms")
            HStack {
                ForEach(BSVerdict.allCases, id: \.self) { verdict in
                    BSVerdictChip(verdict)
                }
            }
        }
    }
}

private struct GalleryCharts: View {
    let isLoading: Bool

    private let points: [Double] = [48, 50, 55, 53, 49, 52, 57, 54, 51, 56]

    var body: some View {
        BSSection("夜间 HRV · 30 天") {
            BSChartCard(
                title: "夜间 HRV · 30 天", label: "平均", value: "52", unit: "ms",
                range: "10月24日–11月22日", side: "较前 28 天 -4 ms",
                height: .compact, caption: "覆盖 23/28 天 · Apple 健康", isLoading: isLoading
            ) {
                BSMiniLine(points: points, color: BSColor.recovery, endDotColor: BSColor.recovery)
            }
            BSChartCard(
                title: "静息心率 · 30 天", label: "平均", value: nil,
                availability: .missing(reason: "近 30 天没有静息心率"),
                height: .compact, isLoading: isLoading
            ) {
                EmptyView()
            }
            BSChartCard(
                title: "压力 · 今天", label: "范围", value: nil,
                availability: .excluded(reason: "运动时段已排除"),
                height: .compact, isLoading: isLoading
            ) {
                EmptyView()
            }
        }
    }
}

private struct GalleryCoach: View {
    let isLoading: Bool

    var body: some View {
        BSSection("Coach") {
            BSCoachNote(
                "昨晚睡得比平时短，今天的恢复偏低，建议把高强度训练挪到明天。",
                engine: .cloud,
                evidence: ["睡眠 · 昨晚 · 小时", "HRV · 11月22日 · ms"],
                isLoading: isLoading,
                onEvidenceTap: { _ in },
                onAsk: {}
            )
            BSActionRow(title: "把今天的腿部训练改为轻量", basis: "恢复 41，腿部疲劳偏高", onExecute: {})
            BSActionRow(title: "补记午餐", basis: "午餐时段没有记录", status: .running)
            BSActionRow(title: "补训练标注", basis: "周二的训练还没有复盘", status: .done, onUndo: {})
            BSActionRow(title: "调整睡眠目标", basis: "过去 14 天平均睡 6.8 小时", status: .failed)
            BSReceipt(title: "已记录午餐", detail: "11月22日 · 鸡胸肉沙拉", level: .automatic, onUndo: {})
            BSReceipt(
                title: "已修改蛋白质目标", detail: "营养目标", level: .highlighted,
                before: "120 g", after: "130 g", onUndo: {}
            )
            BSReceipt(
                title: "修改睡眠目标", detail: "睡眠目标", status: .failed, failureReason: "目标超出允许范围"
            )
            BSAskCoachButton {}
        }
    }
}

private struct GalleryV4: View {
    let isLoading: Bool

    var body: some View {
        BSSection("UI v4") {
            BSCard {
                VStack(alignment: .leading, spacing: BSSpace.s) {
                    BSPageHeader("今日", subtitle: "11月23日 周一") {
                        BSHeaderButton(
                            systemImage: "square.and.pencil", label: "打卡", identifier: "gallery-header-button"
                        ) {}
                    }
                    estimateBar
                    HStack(spacing: BSSpace.s) {
                        swatch(BSColor.heart, "心率")
                        swatch(BSColor.respiration, "呼吸")
                        swatch(BSColor.oxygen, "血氧")
                    }
                }
                .redacted(reason: isLoading ? .placeholder : [])
            }
        }
    }

    private var estimateBar: some View {
        HStack(spacing: BSSpace.none) {
            Capsule()
                .fill(BSColor.energy)
                .frame(width: BSSize.ringL)
            BSStripeFill(color: BSColor.energy)
                .frame(width: BSSize.ringM)
            Spacer(minLength: BSSpace.none)
        }
        .frame(height: BSSize.dot)
        .background(BSColor.surfaceInset, in: Capsule())
        .clipShape(Capsule())
    }

    private func swatch(_ color: Color, _ name: String) -> some View {
        HStack(spacing: BSSpace.xxs) {
            Circle().fill(color).frame(width: BSSize.dot, height: BSSize.dot)
            Text(name).bsText(.caption)
        }
    }
}

private struct GalleryStructure: View {
    var body: some View {
        BSSection("结构", actionTitle: "全部", action: {}) {
            BSCard {
                VStack(spacing: 0) {
                    BSNavRow("五项指标详情", systemImage: "list.bullet", value: "5 项") {
                        Text("详情页")
                    }
                    Divider()
                    BSLabEntry("明日预测") {
                        Text("实验室")
                    }
                }
            }
        }
    }
}

#Preview {
    DesignSystemGallery()
}
