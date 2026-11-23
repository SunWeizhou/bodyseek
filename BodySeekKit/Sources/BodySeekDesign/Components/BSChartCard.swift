import BodySeekCore
import SwiftUI

/// 图表高度，只能取 `BSSize` 里的四档。
public enum BSChartHeight: Sendable, Hashable, CaseIterable {
    /// `BSSize.chartMicro`。
    case micro
    /// `BSSize.chartCompact`。
    case compact
    /// `BSSize.chartStandard`。
    case standard
    /// `BSSize.chartDetail`。
    case detail

    var points: CGFloat {
        switch self {
        case .micro: BSSize.chartMicro
        case .compact: BSSize.chartCompact
        case .standard: BSSize.chartStandard
        case .detail: BSSize.chartDetail
        }
    }
}

/// 图表统计头（照搬 Apple 健康）：标签、大数字 + 单位、日期范围、右侧读数。
///
/// 选中某个点时，调用方把 `label` 换成选中日期、`value` 换成选中值，并传入 `onClear`，右侧出现"清除"。
public struct BSChartHeader<Trailing: View>: View {
    private let label: String
    private let value: String?
    private let unit: String
    private let range: String
    private let onClear: (() -> Void)?
    private let trailing: Trailing

    /// 创建统计头。
    /// - Parameters:
    ///   - label: 标签，例如"平均"；选中时换成日期。
    ///   - value: 已格式化的数值；`nil` 显示 `--`。
    ///   - unit: 单位。
    ///   - range: 日期范围，例如"10月24日–11月22日"。
    ///   - onClear: 选中状态下的"清除"动作；为 `nil` 时不显示。
    ///   - trailing: 右侧读数，例如 `BSDeltaBadge`。
    public init(
        label: String,
        value: String?,
        unit: String = "",
        range: String = "",
        onClear: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.range = range
        self.onClear = onClear
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: BSSpace.s) {
            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                Text(label)
                    .bsText(.label)
                HStack(alignment: .firstTextBaseline, spacing: BSSpace.xxs) {
                    Text(value ?? "--")
                        .bsText(.number)
                    if !unit.isEmpty {
                        Text(unit)
                            .bsText(.label)
                    }
                }
                if !range.isEmpty {
                    Text(range)
                        .bsText(.caption)
                }
            }
            Spacer(minLength: BSSpace.xs)
            VStack(alignment: .trailing, spacing: BSSpace.xxs) {
                trailing
                if let onClear {
                    Button("清除选中", action: onClear)
                        .font(.subheadline)
                        .buttonStyle(BSPressableStyle())
                        .frame(minHeight: BSSize.hitTarget)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

public extension BSChartHeader where Trailing == EmptyView {
    /// 创建没有右侧读数的统计头。
    init(
        label: String,
        value: String?,
        unit: String = "",
        range: String = "",
        onClear: (() -> Void)? = nil
    ) {
        self.init(label: label, value: value, unit: unit, range: range, onClear: onClear) {
            EmptyView()
        }
    }
}

/// 图表卡外壳：标题 + 统计头 + 一张图 + 覆盖率说明。页面里不能直接放裸图表。
///
/// 四态：有数据和已知为零显示图表；缺失和排除用灰色底加原因文字取代图表（不用 0 或插值掩盖）。
public struct BSChartCard<Chart: View>: View {
    private let title: String
    private let label: String
    private let value: String?
    private let unit: String
    private let range: String
    private let side: String?
    private let availability: MetricAvailability
    private let height: BSChartHeight
    private let caption: String?
    private let isLoading: Bool
    private let onClear: (() -> Void)?
    private let chart: Chart

    /// 创建图表卡。
    /// - Parameters:
    ///   - title: 卡片标题，写清问题范围，例如"夜间 HRV · 30 天"。
    ///   - label: 统计头标签。
    ///   - value: 统计头数值；`nil` 显示 `--`。
    ///   - unit: 单位。
    ///   - range: 日期范围。
    ///   - side: 统计头右侧的次要读数文字，例如"较前 28 天 -4 ms"。
    ///   - availability: 四态可用性。
    ///   - height: 图表高度档位。
    ///   - caption: 覆盖率和数据来源，例如"覆盖 23/28 天 · Apple 健康"。
    ///   - isLoading: 为 `true` 时显示骨架。
    ///   - onClear: 选中状态下的"清除"动作。
    ///   - chart: 图表本体（现有图表组件）。
    public init(
        title: String,
        label: String,
        value: String?,
        unit: String = "",
        range: String = "",
        side: String? = nil,
        availability: MetricAvailability = .available,
        height: BSChartHeight = .standard,
        caption: String? = nil,
        isLoading: Bool = false,
        onClear: (() -> Void)? = nil,
        @ViewBuilder chart: () -> Chart
    ) {
        self.title = title
        self.label = label
        self.value = value
        self.unit = unit
        self.range = range
        self.side = side
        self.availability = availability
        self.height = height
        self.caption = caption
        self.isLoading = isLoading
        self.onClear = onClear
        self.chart = chart()
    }

    public var body: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                Text(title)
                    .bsText(.cardTitle)
                BSChartHeader(label: label, value: headerValue, unit: unit, range: range, onClear: onClear) {
                    if let side {
                        Text(side)
                            .bsText(.label)
                    }
                }
                chartRegion
                if let footer = footerText {
                    Text(footer)
                        .bsText(.caption)
                }
            }
            .redacted(reason: isLoading ? .placeholder : [])
        }
    }

    @ViewBuilder
    private var chartRegion: some View {
        switch availability {
        case .available, .knownZero:
            chart
                .frame(height: height.points)
        case let .missing(reason), let .excluded(reason):
            RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous)
                .fill(BSColor.surfaceInset)
                .frame(height: height.points)
                .overlay {
                    Text(reason)
                        .bsText(.label)
                        .multilineTextAlignment(.center)
                        .padding(BSSpace.m)
                }
        }
    }

    private var headerValue: String? {
        switch availability {
        case .available: value
        case .knownZero: "0"
        case .missing, .excluded: nil
        }
    }

    private var footerText: String? {
        if case let .knownZero(reason) = availability {
            return [reason, caption].compactMap { $0 }.joined(separator: " · ")
        }
        return caption
    }
}
