import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct iCloudSyncSettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("iCloud 云同步")) {
                Text("尚未接入")
                    .font(.system(.subheadline, design: .default, weight: .bold))

                Text("当前版本只使用本机数据库保存资料，尚未开启 iCloud 跨设备同步。完成合并策略验证前，不会展示自动备份开关。")
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .navigationTitle("iCloud 同步")
    }
}

struct WhatsNewSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Vela \(VelaAppMetadata.marketingVersion) 当前能力")
                    .font(.system(.title2, design: .default, weight: .bold))
                
                Text("当前版本已实现以下本机优先能力：")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.muted)
                
                VStack(alignment: .leading, spacing: 16) {
                    featureUpdateBlock(title: "今日指挥中心", desc: "把准备度、睡眠、恢复、负荷、营养和数据覆盖合成为一个可执行日计划。")
                    featureUpdateBlock(title: "自适应训练座舱", desc: "根据今日计划、局部疲劳和训练记录决定保持、减量、替换或休息。")
                    featureUpdateBlock(title: "Coach 证据边界", desc: "AI 回答会标注数据覆盖状态，缺失健康或训练证据时降低确定性。")
                    featureUpdateBlock(title: "信任中心与隐私控制", desc: "可查看数据覆盖、导出本地资料，并删除对话、记忆、报告和训练记录。")
                    featureUpdateBlock(title: "天气同步", desc: "授权后使用约 3 公里精度获取 Open-Meteo 天气，并缓存位置快照 7 天以减少重复请求。")
                }
                
                Spacer()
            }
            .padding(20)
        }
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("最新变化")
        .velaRhythmDetailChrome()
    }
    
    private func featureUpdateBlock(title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(VelaTheme.systemGreen)
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
            }
            Text(desc)
                .font(.system(.caption, design: .default))
                .foregroundStyle(VelaTheme.muted)
                .lineSpacing(4)
                .padding(.leading, 26)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VelaTheme.secondaryGroupedBackground))
    }
}

struct PrivacyDataCategory: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var count: Int
    var isExported: Bool
}

enum PrivacyDeletionScope: String, Hashable, CaseIterable {
    case aiHistory
    case localLogs
    case allLocalVelaData
}

struct PrivacyDeleteGroup: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var systemImage: String
    var scope: PrivacyDeletionScope
    var isDestructive: Bool
}

struct PrivacyDataInventoryModel: Hashable {
    var categories: [PrivacyDataCategory]
    var deleteGroups: [PrivacyDeleteGroup]
    var localOnlyNotice: String
    var irreversibleWarning: String

    var exportCategories: [PrivacyDataCategory] {
        categories.filter(\.isExported)
    }

    var totalExportedItems: Int {
        exportCategories.reduce(0) { $0 + $1.count }
    }

    static func build(counts: [String: Int]) -> PrivacyDataInventoryModel {
        let categories = [
            PrivacyDataCategory(
                id: "daily_summaries",
                title: "每日健康摘要",
                detail: "恢复、睡眠、负荷、HRV、静息心率、步数和活动摘要。",
                count: counts["daily_summaries", default: 0],
                isExported: true
            ),
            PrivacyDataCategory(
                id: "strength_workouts",
                title: "力量训练记录",
                detail: "训练标题、组次、重量、RPE、训练量和本地分析结果。",
                count: counts["strength_workouts", default: 0],
                isExported: true
            ),
            PrivacyDataCategory(
                id: "journals",
                title: "日记与行为信号",
                detail: "你手动记录的标签、文字备注、数值和单位。",
                count: counts["journals", default: 0],
                isExported: true
            ),
            PrivacyDataCategory(
                id: "food_logs",
                title: "饮食日志",
                detail: "餐食、营养估算、来源、图片分析摘要和改进建议。",
                count: counts["food_logs", default: 0],
                isExported: true
            ),
            PrivacyDataCategory(
                id: "biomarkers",
                title: "手动化验指标",
                detail: "你录入的生物标志物、参考范围和来源文件名。",
                count: counts["biomarkers", default: 0],
                isExported: true
            ),
            PrivacyDataCategory(
                id: "wiki_documents",
                title: "本地 Coach 记忆",
                detail: "Vela 生成或你确认的身体画像、基线和长期偏好。",
                count: counts["wiki_documents", default: 0],
                isExported: true
            ),
            PrivacyDataCategory(
                id: "coach_sessions",
                title: "Coach 对话",
                detail: "本机保存的聊天会话和消息历史。",
                count: counts["coach_sessions", default: 0],
                isExported: false
            ),
            PrivacyDataCategory(
                id: "agent_runs",
                title: "AI 运行日志",
                detail: "Morning Brief、Evening Sync、Coach 工具调用和可审计运行记录。",
                count: counts["agent_runs", default: 0] + counts["agent_artifacts", default: 0],
                isExported: false
            ),
            PrivacyDataCategory(
                id: "decision_feedback",
                title: "建议反馈与产品诊断",
                detail: "建议查看、采纳、准确度、实际行动和本地使用质量事件；仅用于本机个性化与诊断。",
                count: counts["decision_feedback", default: 0] + counts["product_events", default: 0],
                isExported: false
            ),
            PrivacyDataCategory(
                id: "personal_experiments",
                title: "个人实验",
                detail: "睡眠与行为实验方案、每日执行情况和本机结果比较。",
                count: counts["personal_experiments", default: 0] + counts["experiment_checkins", default: 0],
                isExported: false
            )
        ]

        return PrivacyDataInventoryModel(
            categories: categories,
            deleteGroups: [
                PrivacyDeleteGroup(
                    id: "ai_history",
                    title: "删除 Coach 与 AI 历史",
                    detail: "删除对话、AI 报告、运行日志和 Agent 产物；不会删除健康摘要或训练记录。",
                    systemImage: "sparkles.rectangle.stack.fill",
                    scope: .aiHistory,
                    isDestructive: true
                ),
                PrivacyDeleteGroup(
                    id: "local_logs",
                    title: "删除手动日志",
                    detail: "删除日记、饮食、化验指标和力量训练记录；不会删除 Apple Health 原始数据。",
                    systemImage: "list.bullet.clipboard.fill",
                    scope: .localLogs,
                    isDestructive: true
                ),
                PrivacyDeleteGroup(
                    id: "all_local",
                    title: "清空 Vela 本地数据",
                    detail: "删除 Vela 本机数据库中的摘要、日志、计划、对话、AI 产物、明文归档（daily_logs）和记忆。Keychain 中的 API Key、Apple Health 原始数据与 iCloud 备份不会被清除。",
                    systemImage: "trash.fill",
                    scope: .allLocalVelaData,
                    isDestructive: true
                )
            ],
            localOnlyNotice: "Vela 的本地数据库与 Apple Health 原始数据分离。导出或删除 Vela 数据不会删除 Apple Health 中的原始记录。",
            irreversibleWarning: "删除后无法从 Vela 内恢复。建议先导出本地备份。"
        )
    }

    func category(id: String) -> PrivacyDataCategory? {
        categories.first { $0.id == id }
    }
}

@MainActor
enum PrivacyDataInventoryBuilder {
    static func build(modelContext: ModelContext) -> PrivacyDataInventoryModel {
        PrivacyDataInventoryModel.build(counts: [
            "daily_summaries": count(DailyHealthSummaryRecord.self, in: modelContext),
            "strength_workouts": count(StrengthWorkoutRecord.self, in: modelContext),
            "workout_events": count(WorkoutEventRecord.self, in: modelContext),
            "journals": count(JournalEntryRecord.self, in: modelContext),
            "food_logs": count(FoodLogRecord.self, in: modelContext),
            "biomarkers": count(BiomarkerRecord.self, in: modelContext),
            "wiki_documents": max(
                count(UserWikiDocumentRecord.self, in: modelContext),
                WikiFileService.localDocumentCount()
            ),
            "coach_sessions": count(CoachSessionRecord.self, in: modelContext),
            "coach_interactions": count(CoachInteractionRecord.self, in: modelContext),
            "coach_artifacts": count(CoachArtifactRecord.self, in: modelContext),
            "ai_reports": count(AIReportRecord.self, in: modelContext),
            "agent_runs": count(AgentRunRecord.self, in: modelContext),
            "agent_artifacts": count(AgentArtifactRecord.self, in: modelContext),
            "training_plans": count(TrainingPlanRecord.self, in: modelContext),
            "decision_feedback": count(DailyDecisionFeedbackRecord.self, in: modelContext),
            "product_events": count(VelaEventRecord.self, in: modelContext),
            "personal_experiments": count(PersonalExperimentRecord.self, in: modelContext),
            "experiment_checkins": count(ExperimentCheckInRecord.self, in: modelContext)
        ])
    }

    private static func count<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) -> Int {
        // 只取行数：不要物化全部行（agent_runs/product_events 等可积累数千行，审计 H2）
        (try? modelContext.fetchCount(FetchDescriptor<T>())) ?? 0
    }
}

@MainActor
enum PrivacyDataDeletionService {
    static func delete(
        scope: PrivacyDeletionScope,
        modelContext: ModelContext,
        wikiDirectoryURL: URL? = nil
    ) throws -> Int {
        var deleted = 0

        switch scope {
        case .aiHistory:
            deleted += try deleteAll(CoachSessionRecord.self, in: modelContext)
            deleted += try deleteAll(CoachInteractionRecord.self, in: modelContext)
            deleted += try deleteAll(CoachArtifactRecord.self, in: modelContext)
            deleted += try deleteAll(AIReportRecord.self, in: modelContext)
            deleted += try deleteAll(AgentRunRecord.self, in: modelContext)
            deleted += try deleteAll(AgentArtifactRecord.self, in: modelContext)
        case .localLogs:
            deleted += try deleteAll(JournalEntryRecord.self, in: modelContext)
            deleted += try deleteAll(FoodLogRecord.self, in: modelContext)
            deleted += try deleteAll(BiomarkerRecord.self, in: modelContext)
            deleted += try deleteAll(StrengthWorkoutRecord.self, in: modelContext)
            deleted += try deleteAll(WorkoutEventRecord.self, in: modelContext)
            deleted += try deleteAll(TrainingResponseRecord.self, in: modelContext)
            deleted += try deleteAll(DailyDecisionFeedbackRecord.self, in: modelContext)
            deleted += try deleteAll(PersonalExperimentRecord.self, in: modelContext)
            deleted += try deleteAll(ExperimentCheckInRecord.self, in: modelContext)
        case .allLocalVelaData:
            for scope in [PrivacyDeletionScope.aiHistory, .localLogs] {
                deleted += try delete(
                    scope: scope,
                    modelContext: modelContext,
                    wikiDirectoryURL: wikiDirectoryURL
                )
            }
            deleted += try deleteAll(DailyHealthSummaryRecord.self, in: modelContext)
            deleted += try deleteAll(SleepSummaryRecord.self, in: modelContext)
            deleted += try deleteAll(UserWikiDocumentRecord.self, in: modelContext)
            deleted += try deleteAll(DailyOperatingPlanRecord.self, in: modelContext)
            deleted += try deleteAll(TrainingPlanRecord.self, in: modelContext)
            deleted += try deleteAll(WorkoutTemplateRecord.self, in: modelContext)
            deleted += try deleteAll(ActiveWorkoutDraftRecord.self, in: modelContext)
            deleted += try deleteAll(ExerciseDefinitionRecord.self, in: modelContext)
            deleted += try deleteAll(TrainingPlanAdaptationRecord.self, in: modelContext)
            deleted += try deleteAll(MemoryEventRecord.self, in: modelContext)
            deleted += try deleteAll(DeletedWorkoutRecord.self, in: modelContext)
            deleted += try deleteAll(OnboardingState.self, in: modelContext)
            deleted += try deleteAll(XunjiDailyCacheRecord.self, in: modelContext)
            deleted += try deleteAll(XunjiWorkoutMirrorRecord.self, in: modelContext)
            deleted += try deleteAll(VelaEventRecord.self, in: modelContext)
            // These two are in the container model list but were missing from
            // delete-all — "clear all local data" left the raw intraday health
            // buckets and every proactive insight behind, silently.
            deleted += try deleteAll(IntradaySignalBucketRecord.self, in: modelContext)
            deleted += try deleteAll(ProactiveInsightRecord.self, in: modelContext)
            deleted += try WikiFileService.deleteLocalDocuments(at: wikiDirectoryURL)
            WristSnapshotBridge.shared.clearCachedSnapshot()
            // 明文归档与恢复备份也是 Vela 本地数据（审计 H7）：daily_logs 按天写入
            // 的 md 含当日完整身体数据，VelaRecovery 是 store 的恢复副本——
            // 「清空本地数据」必须一并删除，否则删除承诺未兑现且随 iCloud 备份离机。
            deleted += try DailyLogService.deleteLocalLogs()
            deleted += try VelaModelContainer.deleteRecoveryBackups()
        }

        try modelContext.save()
        return deleted
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) throws -> Int {
        let records = try modelContext.fetch(FetchDescriptor<T>())
        records.forEach(modelContext.delete)
        return records.count
    }
}

struct PrivacyDataControlsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var inventory = PrivacyDataInventoryModel.build(counts: [:])
    @State private var pendingDeleteGroup: PrivacyDeleteGroup?
    @State private var statusMessage = ""
    @State private var isError = false

    var body: some View {
        Form {
            Section("本地优先") {
                Label(inventory.localOnlyNotice, systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(VelaTheme.muted)
            }

            Section("联网 AI") {
                Label("手动发送 Coach 消息时，消息和完成回答所需的健康、训练上下文会发送给你配置的 DeepSeek 服务。", systemImage: "network")
                Label("餐食照片只会在确认分析后发送给 Kimi；后台自动分析默认关闭，需要单独授权。", systemImage: "hand.raised.fill")
            }
            .font(.footnote)

            Section("可导出数据") {
                ForEach(inventory.exportCategories) { category in
                    privacyCategoryRow(category)
                }

                NavigationLink(destination: ExportDataSettingsView()) {
                    Label("导出本地备份", systemImage: "square.and.arrow.up.fill")
                }
            }

            Section("本机保存但默认不导出") {
                ForEach(inventory.categories.filter { !$0.isExported }) { category in
                    privacyCategoryRow(category)
                }
            }

            Section("删除控制") {
                Text(inventory.irreversibleWarning)
                    .font(.footnote)
                    .foregroundStyle(VelaTheme.muted)

                ForEach(inventory.deleteGroups) { group in
                    Button(role: .destructive) {
                        pendingDeleteGroup = group
                    } label: {
                        Label(group.title, systemImage: group.systemImage)
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(isError ? VelaTheme.rhythmInk : VelaTheme.rhythmInk)
                }
            }
        }
        .navigationTitle("隐私与数据控制")
        .onAppear {
            reloadInventory()
        }
        .confirmationDialog(
            pendingDeleteGroup?.title ?? "确认删除",
            isPresented: Binding(
                get: { pendingDeleteGroup != nil },
                set: { if !$0 { pendingDeleteGroup = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let group = pendingDeleteGroup {
                Button(group.title, role: .destructive) {
                    delete(group)
                }
            }
            Button("取消", role: .cancel) {
                pendingDeleteGroup = nil
            }
        } message: {
            Text(pendingDeleteGroup?.detail ?? inventory.irreversibleWarning)
        }
    }

    private func privacyCategoryRow(_ category: PrivacyDataCategory) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                Text(category.detail)
                    .font(.caption)
                    .foregroundStyle(VelaTheme.muted)
            }
            Spacer()
            Text("\(category.count)")
                .foregroundStyle(VelaTheme.muted)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func reloadInventory() {
        inventory = PrivacyDataInventoryBuilder.build(modelContext: modelContext)
    }

    private func delete(_ group: PrivacyDeleteGroup) {
        do {
            let deleted = try PrivacyDataDeletionService.delete(scope: group.scope, modelContext: modelContext)
            pendingDeleteGroup = nil
            reloadInventory()
            statusMessage = "已删除 \(deleted) 条本地记录。"
            isError = false
            VelaAppState.shared.markLocalDataChanged()
        } catch {
            statusMessage = "删除失败：\(error.localizedDescription)"
            isError = true
        }
    }
}

struct ExportDataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showExporter = false
    @State private var exportData: Data?
    @State private var statusMessage = ""
    @State private var isError = false
    
    var body: some View {
        Form {
            Section(header: Text("数据导出与备份")) {
                Text("Vela 采用本机优先的数据策略，你的健康数据默认保留在设备本地。为了迁移或备份，你可以导出健康摘要与日志；导出过程中数据不会离开你的设备。")
                    .font(.footnote)
                    .foregroundStyle(VelaTheme.muted)
                    .padding(.vertical, 4)
                
                Button {
                    exportData = exportHealthData(modelContext: modelContext)
                    if exportData != nil {
                        showExporter = true
                    } else {
                        statusMessage = "生成导出数据失败。"
                        isError = true
                    }
                } label: {
                    Label("导出本地健康数据", systemImage: "doc.text.fill")
                        .font(.system(.subheadline, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.accentOn)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusMd).fill(VelaTheme.accent))
                }
                .buttonStyle(.plain)
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(isError ? VelaTheme.danger : VelaTheme.success)
                }
            }
        }
        .navigationTitle("数据导出")
        .fileExporter(
            isPresented: $showExporter,
            document: exportData.flatMap { JSONExportDocument(data: $0) },
            contentType: .json,
            defaultFilename: "vela_health_export_\(Date().formatted(.iso8601).prefix(10)).json"
        ) { result in
            switch result {
            case .success(let url):
                statusMessage = "导出成功至: \(url.lastPathComponent)"
                isError = false
            case .failure(let error):
                statusMessage = "导出失败: \(error.localizedDescription)"
                isError = true
            }
        }
    }
    
    private func exportHealthData(modelContext: ModelContext) -> Data? {
        let summaries = (try? SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
            .fetchAllSortedByDate()) ?? []
        let exportSummaries: [[String: Any]] = summaries.map { record in
            var dict: [String: Any] = [
                "date": record.date.formatted(.iso8601),
                "dayIdentifier": record.dayIdentifier
            ]
            if let val = record.sleepScore { dict["sleepScore"] = val }
            if let val = record.recoveryScore { dict["recoveryScore"] = val }
            if let val = record.strainScore { dict["strainScore"] = val }
            if let val = record.stressIndex { dict["stressIndex"] = val }
            if let val = record.morningEnergy { dict["morningEnergy"] = val }
            if let val = record.currentEnergy { dict["currentEnergy"] = val }
            if let val = record.energyBank { dict["energyBank"] = val }
            if let val = record.hrvAverage { dict["hrvAverage"] = val }
            if let val = record.restingHeartRate { dict["restingHeartRate"] = val }
            if let val = record.sleepHours { dict["sleepHours"] = val }
            if let val = record.deepSleepPercent { dict["deepSleepPercent"] = val }
            if let val = record.remSleepPercent { dict["remSleepPercent"] = val }
            if let val = record.sleepEfficiency { dict["sleepEfficiency"] = val }
            if let val = record.steps { dict["steps"] = val }
            if let val = record.activeCalories { dict["activeCalories"] = val }
            if let val = record.activeMinutes { dict["activeMinutes"] = val }
            if let val = record.workoutCount { dict["workoutCount"] = val }
            if let val = record.workoutDuration { dict["workoutDuration"] = val }
            if let val = record.bodyWeight { dict["bodyWeight"] = val }
            if let val = record.bodyFatPercent { dict["bodyFatPercent"] = val }
            if let val = record.oxygenSaturation { dict["oxygenSaturation"] = val }
            if let val = record.respiratoryRate { dict["respiratoryRate"] = val }
            if let val = record.wristTemperature { dict["wristTemperature"] = val }
            if let val = record.dailyLoad { dict["dailyLoad"] = val }
            return dict
        }

        let workouts = (try? WorkoutHistoryRepository(modelContext: modelContext).fetchStrengthWorkoutsSortedByStart()) ?? []
        let exportWorkouts: [[String: Any]] = workouts.map { record in
            var dict: [String: Any] = [
                "id": record.id.uuidString,
                "title": record.title,
                "startedAt": record.startedAt.formatted(.iso8601),
                "durationMinutes": record.durationMinutes,
                "notes": record.notes
            ]
            if let val = record.linkedWorkoutEventId { dict["linkedWorkoutEventId"] = val.uuidString }
            if let val = record.sourceTemplateId { dict["sourceTemplateId"] = val.uuidString }
            if let val = record.planDayId { dict["planDayId"] = val.uuidString }
            if let val = record.sessionRPE { dict["sessionRPE"] = val }
            if let val = record.completedAt { dict["completedAt"] = val.formatted(.iso8601) }
            if let val = record.analyticsJSON { dict["analyticsJSON"] = val }
            if let exercisesObj = try? JSONSerialization.jsonObject(with: record.exercisesData) {
                dict["exercises"] = exercisesObj
            }
            return dict
        }

        let journals = (try? SwiftDataJournalRepository(modelContext: modelContext).fetchAllSortedByCreatedAt()) ?? []
        let exportJournals: [[String: Any]] = journals.map { record in
            var dict: [String: Any] = [
                "createdAt": record.createdAt.formatted(.iso8601),
                "tags": record.tags,
                "note": record.note
            ]
            if let val = record.value { dict["value"] = val }
            if let val = record.unit { dict["unit"] = val }
            return dict
        }

        let foodLogs = (try? FoodLogRepository(modelContext: modelContext)
            .fetchAllSortedByCreatedAt(newestFirst: false)) ?? []
        let exportFoodLogs: [[String: Any]] = foodLogs.map { record in
            var dict: [String: Any] = [
                "id": record.id.uuidString,
                "mealName": record.mealName,
                "createdAt": record.createdAt.formatted(.iso8601),
                "updatedAt": record.updatedAt.formatted(.iso8601),
                "source": record.source,
                "totalCalories": record.totalCalories,
                "proteinGrams": record.proteinGrams,
                "carbsGrams": record.carbsGrams,
                "fatGrams": record.fatGrams,
                "fiberGrams": record.fiberGrams,
                "healthScore": record.healthScore,
                "rawAnalysis": record.rawAnalysis
            ]
            if let foodsData = record.serializedFoods.data(using: .utf8),
               let foodsObj = try? JSONSerialization.jsonObject(with: foodsData) {
                dict["foods"] = foodsObj
            }
            if let suggestionsData = record.serializedSuggestions.data(using: .utf8),
               let suggestionsObj = try? JSONSerialization.jsonObject(with: suggestionsData) {
                dict["suggestions"] = suggestionsObj
            }
            return dict
        }

        let biomarkers = (try? BiomarkerRepository(modelContext: modelContext)
            .fetchAllSortedByDate(newestFirst: false)) ?? []
        let exportBiomarkers: [[String: Any]] = biomarkers.map { record in
            var dict: [String: Any] = [
                "id": record.id.uuidString,
                "name": record.name,
                "value": record.value,
                "unit": record.unit,
                "date": record.date.formatted(.iso8601),
                "isOptimal": record.isOptimal,
                "referenceMin": record.referenceMin,
                "referenceMax": record.referenceMax
            ]
            if let val = record.sourceDocumentName { dict["sourceDocumentName"] = val }
            return dict
        }

        let exportWikiDocs: [[String: Any]] = WikiFileService.loadAllDocuments().map { document in
            [
                "filename": document.filename,
                "title": document.title,
                "markdownContent": document.content,
                "updatedAt": document.updatedAt.formatted(.iso8601)
            ]
        }

        let export: [String: Any] = [
            "app": "Vela",
            "export_date": Date().formatted(.iso8601),
            "config_version": VelaAppMetadata.configVersion,
            "summaries": exportSummaries,
            "workouts": exportWorkouts,
            "journals": exportJournals,
            "food_logs": exportFoodLogs,
            "biomarkers": exportBiomarkers,
            "wiki_documents": exportWikiDocs
        ]

        return try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
    }
}

struct JSONExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
