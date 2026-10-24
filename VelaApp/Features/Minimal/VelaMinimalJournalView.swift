import SwiftUI
import SwiftData

// MARK: - Historical backfill page

/// 三年 Apple 健康历史回填页面：进度条 + 开始/停止 + 错误提示。
/// 任务由 HistoricalBackfillCoordinator.shared 持有，退出页面也会继续跑。
struct HistoricalBackfillView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: VelaServices
    @ObservedObject private var coordinator = HistoricalBackfillCoordinator.shared
    @ObservedObject private var scoreCoordinator = HistoricalScoreBackfillCoordinator.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .frame(width: 42, height: 42)
                        .background(VelaTheme.rhythmMist, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("回填三年健康历史")
                            .font(.system(.body, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text(coordinator.stateText)
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 2)

                Text("先将 Apple 健康近三年的原始日汇总保存到本机，再补算尚未评分的历史日。原始汇总回填完成，不代表每一天都有足够证据生成五项评分。")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    ProgressView(value: coordinator.progress.percent)
                        .tint(VelaTheme.rhythmDeep)

                    HStack {
                        Text("\(coordinator.progress.completedDays) / \(coordinator.progress.totalDays) 天")
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        Spacer()
                        Text("可随时停止，进度已保存")
                            .font(.system(.caption2, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.8))
                    }
                }
                .padding(16)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                }

                if let error = coordinator.lastError {
                    Text("回填中断：\(error)")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.textColor(for: .poor))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    if coordinator.isRunning {
                        coordinator.cancel()
                    } else {
                        coordinator.start(
                            queryService: services.queryService,
                            modelContext: modelContext
                        )
                    }
                } label: {
                    Text(coordinator.isRunning ? "停止回填" : "开始回填")
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(VelaTheme.rhythmDeep, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.cardPress)
                .disabled(scoreCoordinator.isRunning || (coordinator.progress.isComplete && !coordinator.isRunning))

                if coordinator.progress.isComplete {
                    Text("原始汇总回填完成。你可以继续补算历史评分；证据不足的日期会保留缺失。")
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .frame(maxWidth: .infinity)
                }
                Divider().padding(.vertical, 8)
                Text("补算已有历史评分").font(VelaTheme.headline())
                Text("使用当前个人设置和现有算法，只补算从未评分的历史日，保留已有分数。计算仅使用截至该日的健康记录；不请求联网 AI。")
                    .font(VelaTheme.footnote()).foregroundStyle(VelaTheme.rhythmInkSecondary)
                if scoreCoordinator.isRunning || scoreCoordinator.progress.total > 0 {
                    ProgressView(value: Double(scoreCoordinator.progress.completed), total: Double(max(1, scoreCoordinator.progress.total)))
                    Text("已检查 \(scoreCoordinator.progress.completed)/\(scoreCoordinator.progress.total) 天 · \(scoreCoordinator.progress.scored) 天生成评分 · \(scoreCoordinator.progress.insufficient) 天证据不足")
                        .font(VelaTheme.caption1())
                }
                if let error = scoreCoordinator.lastError {
                    Text("补算中断：" + error).font(VelaTheme.footnote()).foregroundStyle(VelaTheme.deviationInk)
                }
                Button(scoreCoordinator.isRunning ? "暂停评分补算" : scoreCoordinator.lastError == nil ? "补算缺少的历史评分" : "重试评分补算") {
                    if scoreCoordinator.isRunning { scoreCoordinator.cancel() }
                    else { scoreCoordinator.start(modelContext: modelContext) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isRunning)
                .accessibilityIdentifier("history-score-repair")
                if scoreCoordinator.didFinish {
                    Text(scoreCoordinator.progress.total == 0 ? "没有尚未计算的原始汇总。已有缺失可能来自证据不足或尚未同步。" : "本轮检查完成。已保存结果，原始记录与已有评分保留。")
                        .font(VelaTheme.caption1()).foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("历史回填")
        .velaRhythmDetailChrome()
        .onAppear {
            coordinator.refreshState()
        }
    }
}

/// 深度专项批次 3：训记历史批量回填页——逐日拉取训记训练（动作/组数/重量），
/// 断点续传。三年 e1RM/容量/肌群频率轨迹的前置条件。
struct XunjiHistoryBackfillView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var service = XunjiHistoryBackfillService.shared
    @State private var apiKey = ""
    @State private var loadKeyFailed = false

    private var progressPercent: Double {
        guard service.totalDays > 0 else { return 0 }
        return min(1, Double(service.completedDays) / Double(service.totalDays))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .frame(width: 42, height: 42)
                        .background(VelaTheme.rhythmMist, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("回填训记训练历史")
                            .font(.system(.body, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text("逐日补全动作、组数与重量")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 2)

                Text("把训记里的历史训练（动作、组数、重量、时长）逐日读入 Vela，用于个人纪录、容量轨迹与肌群疲劳的长期分析。原始数据只留在本机；进度会保存，可随时停止续传。")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if loadKeyFailed {
                    Text("未找到训记密钥。请先在训练页填写训记 API Key。")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.textColor(for: .poor))
                }

                VStack(alignment: .leading, spacing: 12) {
                    ProgressView(value: progressPercent)
                        .tint(VelaTheme.rhythmDeep)

                    HStack {
                        Text("\(service.completedDays) / \(service.totalDays) 天 · 已导入 \(service.importedCount) 条")
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        Spacer()
                        Text("可随时停止，进度已保存")
                            .font(.system(.caption2, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.8))
                    }
                }
                .padding(16)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                }

                if let error = service.errorMessage {
                    Text("回填暂停：\(error)")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.textColor(for: .poor))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await startOrStop() }
                } label: {
                    Text(service.isRunning ? "停止回填" : "开始回填")
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(VelaTheme.rhythmDeep, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.cardPress)

                if service.completedDays >= service.totalDays, service.totalDays > 0 {
                    Text("回填已完成。历史动作、组数与重量已可用于长期分析。")
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("训记历史回填")
        .velaRhythmDetailChrome()
        .onAppear {
            if let saved = try? KeychainService.shared.read(account: "xunji_open_api_key") {
                apiKey = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    @MainActor
    private func startOrStop() async {
        if service.isRunning {
            service.cancel()
            return
        }
        guard !apiKey.isEmpty else {
            loadKeyFailed = true
            return
        }
        loadKeyFailed = false
        try? KeychainService.shared.save(apiKey, account: "xunji_open_api_key")
        await service.run(modelContext: modelContext, apiKey: apiKey)
        VelaAppState.shared.markLocalDataChanged()
    }
}
