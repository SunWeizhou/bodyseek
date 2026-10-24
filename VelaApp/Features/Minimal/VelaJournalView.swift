import SwiftUI
import SwiftData

struct VelaJournalView: View {
    let selectedDate: Date
    var onSelectDate: (Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var appState = VelaAppState.shared
    @State private var personalExperiments: [PersonalExperimentRecord] = []
    @State private var experimentCheckIns: [ExperimentCheckInRecord] = []
    @State private var experimentHealthSummaries: [DailyHealthSummaryRecord] = []

    init(selectedDate: Date, onSelectDate: @escaping (Date) -> Void = { _ in }) {
        self.selectedDate = selectedDate
        self.onSelectDate = onSelectDate
    }

    private static let lookbackDays = 42
    private var lookbackStart: Date {
        Calendar.current.date(byAdding: .day, value: -Self.lookbackDays, to: selectedDate) ?? selectedDate
    }

    @State private var entries: [JournalEntryRecord] = []

    // Local states for custom segmented values (0:✕, 1:–, 2:✓)
    @State private var lowCarbState: Int = 1
    @State private var addedSugarState: Int = 1
    @State private var ketoDietState: Int = 1
    @State private var bedDeviceState: Int = 1
    @AppStorage("vela_custom_journal_habits") private var customHabitsRaw = ""
    @State private var customHabitStates: [String: Int] = [:]
    
    // Log row dynamic display values
    @State private var caffeineValueText: String = "- mg"
    @State private var hydrationValueText: String = "- ml"
    @State private var moodValueText: String = "-"
    @State private var alcoholValueText: String = "- 杯"
    
    // For navigation/sheet triggers
    @State private var showCaffeineLogger = false
    @State private var showMoodLogger = false
    @State private var showWaterLogger = false
    @State private var showAlcoholLogger = false
    @State private var showBehaviorQuickNote = false
    @State private var showPersonalExperiment = false
    @State private var showCustomHabitManager = false
    @State private var entryPendingDeletion: JournalEntryRecord?
    @State private var entryMutationError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Journal Header Title Row
                journalHeader
                
                // 2. Weekly Calendar Checks strip
                weeklyChecksStrip

                behaviorQuickNoteCard

                PersonalExperimentCard(
                    experiment: activePersonalExperiment,
                    checkIns: experimentCheckIns,
                    onTap: { showPersonalExperiment = true }
                )
                
                // 3. Category daytime title
                VStack(alignment: .leading, spacing: 12) {
                    Text(dateSectionTitle(for: selectedDate))
                        .font(.system(.callout, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.fg)
                        .padding(.top, 4)
                    
                    Text("习惯与记录")
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.muted)
                        .textCase(.uppercase)
                        .padding(.leading, 2)
                    
                    VStack(spacing: 0) {
                        segmentedJournalRow(
                            icon: "fork.knife",
                            title: "低碳水化合物",
                            state: $lowCarbState
                        )
                        habitRowDivider
                        inputJournalRow(
                            icon: "cup.and.saucer.fill",
                            title: "咖啡因",
                            valuePlaceholder: caffeineValueText,
                            onTap: { showCaffeineLogger = true }
                        )
                        habitRowDivider
                        inputJournalRow(
                            icon: "face.smiling.fill",
                            title: "每日心情",
                            valuePlaceholder: moodValueText,
                            onTap: { showMoodLogger = true }
                        )
                        habitRowDivider
                        segmentedJournalRow(
                            icon: "birthday.cake.fill",
                            title: "添加糖",
                            state: $addedSugarState
                        )
                        habitRowDivider
                        segmentedJournalRow(
                            icon: "leaf.fill",
                            title: "生酮饮食",
                            state: $ketoDietState
                        )
                        habitRowDivider
                        inputJournalRow(
                            icon: "drop.fill",
                            title: "补水",
                            valuePlaceholder: hydrationValueText,
                            onTap: { showWaterLogger = true }
                        )
                        habitRowDivider
                        inputJournalRow(
                            icon: "wineglass.fill",
                            title: "酒",
                            valuePlaceholder: alcoholValueText,
                            onTap: { showAlcoholLogger = true }
                        )
                        habitRowDivider
                        segmentedJournalRow(
                            icon: "iphone",
                            title: "在床上使用设备",
                            state: $bedDeviceState
                        )
                        ForEach(customHabits, id: \.self) { habit in
                            habitRowDivider
                            segmentedJournalRow(
                                icon: "tag.fill",
                                title: habit,
                                state: customHabitBinding(for: habit)
                            )
                        }
                    }
                    .velaNativeCard(radius: VelaTheme.radiusSm)

                    Button {
                        showCustomHabitManager = true
                    } label: {
                        Label("管理自定义习惯", systemImage: "slider.horizontal.3")
                            .font(VelaTheme.caption1().weight(.semibold))
                            .foregroundStyle(VelaTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget)
                    }
                    .buttonStyle(.cardPress)
                }
                
                JournalEntryList(entries: selectedDayEntries) { entry in
                    entryPendingDeletion = entry
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, VelaFloatingNavigationMetrics.contentBottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .onAppear {
            loadRealJournalData()
        }
        .onChange(of: selectedDate) { _, _ in
            loadRealJournalData()
        }
        .onChange(of: entries) { _, _ in
            loadRealJournalData()
        }
        .onChange(of: appState.localDataRevision) { _, _ in
            loadRealJournalData()
        }
        .alert(
            "删除这条手记？",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            presenting: entryPendingDeletion
        ) { entry in
            Button("删除", role: .destructive) {
                deleteEntry(entry)
                entryPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: { entry in
            Text("将永久删除“\(entry.uiDisplayTitle)”。")
        }
        .alert("无法更新手记", isPresented: Binding(
            get: { entryMutationError != nil },
            set: { if !$0 { entryMutationError = nil } }
        )) {
            Button("好", role: .cancel) { entryMutationError = nil }
        } message: {
            Text(entryMutationError ?? "")
        }
        .sheet(isPresented: $showCaffeineLogger) {
            CaffeineLoggerView { amount in
                saveQuickEntry(tags: ["caffeine", "咖啡因"], note: "摄入咖啡因 \(Int(amount)) mg", value: amount, unit: "mg")
            }
            .presentationDetents([.medium])
            .presentationBackground(VelaTheme.rhythmCanvas)
        }
        .sheet(isPresented: $showWaterLogger) {
            WaterLoggerView { amount in
                saveQuickEntry(tags: ["hydration", "补水"], note: "饮水 \(Int(amount)) ml", value: amount, unit: "ml")
            }
            .presentationDetents([.medium])
            .presentationBackground(VelaTheme.rhythmCanvas)
        }
        .sheet(isPresented: $showMoodLogger) {
            MoodLoggerView { score, note in
                let moodText = formatMoodValue(score)
                saveQuickEntry(tags: ["mood", "每日心情"], note: "心情: \(moodText). 备注: \(note)", value: score)
            }
            .presentationDetents([.medium])
            .presentationBackground(VelaTheme.rhythmCanvas)
        }
        .sheet(isPresented: $showAlcoholLogger) {
            AlcoholLoggerView { amount in
                saveQuickEntry(tags: ["alcohol", "酒"], note: "饮酒 \(amount) 标准杯", value: amount, unit: "杯")
            }
            .presentationDetents([.medium])
            .presentationBackground(VelaTheme.rhythmCanvas)
        }
        .sheet(isPresented: $showBehaviorQuickNote) {
            BehaviorQuickNoteSheet { note in
                saveBehaviorQuickNote(note)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(VelaTheme.rhythmCanvas)
        }
        .sheet(isPresented: $showPersonalExperiment) {
            PersonalExperimentHubSheet(
                activeExperiment: activePersonalExperiment,
                latestExperiment: personalExperiments.first,
                checkIns: experimentCheckIns,
                healthSummaries: experimentHealthSummaries
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(VelaTheme.rhythmCanvas)
        }
        .sheet(isPresented: $showCustomHabitManager) {
            CustomJournalHabitSheet(habits: $customHabitsRaw)
                .presentationDetents([.medium, .large])
                .velaSheetSurface()
        }
    }

    private var activePersonalExperiment: PersonalExperimentRecord? {
        let today = Calendar.current.startOfDay(for: Date())
        return personalExperiments.first {
            $0.status == "active" && $0.endDate >= today
        }
    }

    private var selectedDayEntries: [JournalEntryRecord] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: selectedDate)
        return entries.filter { calendar.isDate($0.createdAt, inSameDayAs: targetDay) }
            .sorted(by: { $0.createdAt > $1.createdAt })
    }

    private func deleteEntry(_ entry: JournalEntryRecord) {
        modelContext.delete(entry)
        do {
            try modelContext.save()
            VelaAppState.shared.markLocalDataChanged()
            loadRealJournalData()
        } catch {
            modelContext.rollback()
            entryMutationError = "这条手记未删除。请稍后重试。"
        }
    }

    private func headerDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private func dateSectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天的条目"
        } else if calendar.isDateInYesterday(date) {
            return "昨天的条目"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日的条目"
            return formatter.string(from: date)
        }
    }

    private func formatMoodValue(_ val: Double) -> String {
        let intVal = Int(val)
        switch intVal {
        case 1: return "😞 糟糕"
        case 2: return "😐 平淡"
        case 3: return "🙂 还行"
        case 4: return "😃 开心"
        case 5: return "🤩 极佳"
        default: return "🙂 还行"
        }
    }

    private func fetchEntries() {
        let calendar = Calendar.current
        let refDate = selectedDate
        let startOfDayRef = calendar.startOfDay(for: refDate)
        
        let startLimit = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -Self.lookbackDays, to: startOfDayRef) ?? startOfDayRef)
        let endLimit = calendar.date(byAdding: .day, value: 1, to: startOfDayRef) ?? startOfDayRef
        
        self.entries = (try? SwiftDataJournalRepository(modelContext: modelContext).fetchEntries(
            from: startLimit,
            through: endLimit
        )) ?? []
        personalExperiments = (try? PersonalExperimentRepository(modelContext: modelContext)
            .fetchAllSortedByCreatedAt()) ?? []
        experimentCheckIns = (try? ExperimentCheckInRepository(modelContext: modelContext)
            .fetchAllSortedByDate()) ?? []
        experimentHealthSummaries = (try? SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
            .fetchAllSortedByDate(newestFirst: true)) ?? []
    }

    private func loadRealJournalData() {
        fetchEntries()
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: selectedDate)
        
        let dayEntries = entries.filter { entry in
            calendar.isDate(entry.createdAt, inSameDayAs: targetDay)
        }
        
        lowCarbState = 1
        addedSugarState = 1
        ketoDietState = 1
        bedDeviceState = 1
        customHabitStates = Dictionary(customHabits.map { ($0, 1) }, uniquingKeysWith: { first, _ in first })
        
        caffeineValueText = "- mg"
        hydrationValueText = "- ml"
        moodValueText = "-"
        alcoholValueText = "- 杯"
        
        let sortedDayEntries = dayEntries.sorted(by: { $0.createdAt > $1.createdAt })
        
        for entry in sortedDayEntries {
            if entry.tags.contains("低碳水化合物"), let val = entry.value {
                lowCarbState = Int(val)
                break
            }
        }
        for entry in sortedDayEntries {
            if entry.tags.contains("添加糖"), let val = entry.value {
                addedSugarState = Int(val)
                break
            }
        }
        for entry in sortedDayEntries {
            if entry.tags.contains("生酮饮食"), let val = entry.value {
                ketoDietState = Int(val)
                break
            }
        }
        for entry in sortedDayEntries {
            if entry.tags.contains("在床上使用设备"), let val = entry.value {
                bedDeviceState = Int(val)
                break
            }
        }
        for habit in customHabits {
            if let entry = sortedDayEntries.first(where: { $0.tags.contains(habit) }),
               let value = entry.value {
                customHabitStates[habit] = Int(value)
            }
        }
        
        let caffeineSum = dayEntries.filter { $0.tags.contains("caffeine") || $0.tags.contains("咖啡因") }.map { $0.value ?? 0.0 }.reduce(0.0, +)
        if caffeineSum > 0 {
            caffeineValueText = "\(Int(caffeineSum)) mg"
        }
        
        let hydrationSum = dayEntries.filter { $0.tags.contains("hydration") || $0.tags.contains("补水") }.map { $0.value ?? 0.0 }.reduce(0.0, +)
        if hydrationSum > 0 {
            hydrationValueText = "\(Int(hydrationSum)) ml"
        }
        
        let alcoholSum = dayEntries.filter { $0.tags.contains("alcohol") || $0.tags.contains("酒") }.map { $0.value ?? 0.0 }.reduce(0.0, +)
        if alcoholSum > 0 {
            alcoholValueText = String(format: "%.1f 杯", alcoholSum)
        }
        
        if let latestMoodEntry = sortedDayEntries.first(where: { $0.tags.contains("mood") || $0.tags.contains("每日心情") }) {
            if let moodVal = latestMoodEntry.value {
                moodValueText = formatMoodValue(moodVal)
            }
        }
    }

    private var journalHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("手记")
                    .font(.system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
                Text(headerDateString(for: selectedDate))
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(VelaTheme.muted)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    VelaAppState.shared.routeToCoach(question: journalAnalysisQuestion, surface: .journal)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                        Text("分析")
                            .font(.system(.footnote, design: .default, weight: .bold))
                    }
                    .foregroundStyle(VelaTheme.fg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .velaNativeCard(radius: VelaTheme.radiusCard)
                }
                .buttonStyle(.plain)
                
                Menu {
                    Button("复制昨日条目", systemImage: "doc.on.doc") {
                        copyPreviousDayEntries()
                    }
                    Button("管理自定义习惯", systemImage: "tag") {
                        showCustomHabitManager = true
                    }
                    Divider()
                    Button("记录咖啡因") {
                        showCaffeineLogger = true
                    }
                    Button("记录饮水") {
                        showWaterLogger = true
                    }
                    Button("记录心情") {
                        showMoodLogger = true
                    }
                    Button("记录饮酒") {
                        showAlcoholLogger = true
                    }
                    Button("随手记一餐/行为") {
                        showBehaviorQuickNote = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(VelaTheme.fg)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(VelaTheme.cardBg))
                        .overlay(Circle().stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var journalAnalysisQuestion: String {
        "请结合我在 \(dateSectionTitle(for: selectedDate)) 的手记、标签和健康数据，分析可能影响恢复、睡眠和训练状态的模式，并给出下一步建议。"
    }

    private var behaviorQuickNoteCard: some View {
        Button {
            showBehaviorQuickNote = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmDeepOn)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VelaTheme.rhythmDeep))

                VStack(alignment: .leading, spacing: 4) {
                    Text("随手记一餐或一个行为")
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.fg)
                    Text("一句话即可：火锅、啤酒、睡前咖啡、吃撑、喝水少。无需估克重。")
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(VelaTheme.muted)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(VelaTheme.accent)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).fill(VelaTheme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
        }
        .buttonStyle(.plain)
    }

    private var weeklyChecksStrip: some View {
        let calendar = Calendar.current
        let selected = selectedDate
        let weekday = calendar.component(.weekday, from: selected)
        let daysToSubtract = weekday - 1
        let sunday = calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: selected)) ?? selected
        
        let weekDates: [Date] = (0..<7).compactMap { idx in
            calendar.date(byAdding: .day, value: idx, to: sunday)
        }
        
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { idx in
                let date = weekDates[idx]
                let isSelected = calendar.isDate(date, inSameDayAs: selected)
                let isToday = calendar.isDate(date, inSameDayAs: Date())
                let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
                let dayNumber = calendar.component(.day, from: date)
                
                let hasEntry = entries.contains { entry in
                    calendar.isDate(entry.createdAt, inSameDayAs: date)
                }
                
                Button {
                    onSelectDate(date)
                } label: {
                    VStack(spacing: 8) {
                        Text(weekdays[idx])
                            .font(.system(.caption2, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.muted)
                        
                        Text("\(dayNumber)")
                            .font(.system(.footnote, design: .default, weight: .bold))
                            .foregroundStyle(isSelected ? VelaTheme.rhythmDeepOn : VelaTheme.fg)
                            .frame(width: 26, height: 26)
                            .background(
                                Group {
                                    if isSelected {
                                        Circle()
                                            .fill(VelaTheme.accent)
                                    } else if isToday {
                                        Circle()
                                            .stroke(VelaTheme.accent, lineWidth: VelaTheme.hairlineWidth)
                                    }
                                }
                            )
                        
                        if hasEntry {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(VelaTheme.systemYellow)
                        } else {
                            Image(systemName: "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(VelaTheme.hairline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
                .opacity(isFuture ? 0.38 : 1)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .velaNativeCard(radius: VelaTheme.radiusCard)
    }

    private func segmentedJournalRow(icon: String, title: String, state: Binding<Int>) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(VelaTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(VelaTheme.accent.opacity(0.12)))
                
                Text(title)
                    .font(.system(.footnote, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
            }
            
            Spacer()
            
            HStack(spacing: 0) {
                segmentButton(title: title, index: 0, state: state)
                
                Rectangle()
                    .fill(VelaTheme.separatorSoft)
                    .frame(width: 0.5, height: 20)
                
                segmentButton(title: title, index: 1, state: state)
                
                Rectangle()
                    .fill(VelaTheme.separatorSoft)
                    .frame(width: 0.5, height: 20)
                
                segmentButton(title: title, index: 2, state: state)
            }
            .background(VelaTheme.rhythmMist.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var habitRowDivider: some View {
        Divider()
            .padding(.leading, 56)
    }

    private func segmentButton(title: String, index: Int, state: Binding<Int>) -> some View {
        let isActive = state.wrappedValue == index
        let activeLabelText = index == 0 ? "✕" : (index == 2 ? "✓" : "–")
        return Button {
            VelaHaptic.selection()
            state.wrappedValue = index
            saveQuickEntry(tags: [title], note: "习惯打卡: \(title) - \(activeLabelText)", value: Double(index))
        } label: {
            Group {
                switch index {
                case 0:
                    Image(systemName: isActive ? "xmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isActive ? VelaTheme.danger : VelaTheme.meta)
                case 2:
                    Image(systemName: isActive ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isActive ? VelaTheme.success : VelaTheme.meta)
                default:
                    Image(systemName: isActive ? "circle.fill" : "circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? VelaTheme.muted : VelaTheme.meta)
                }
            }
            .frame(width: 38, height: 32)
            .background(
                Group {
                    if isActive {
                        VelaTheme.cardBg
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func inputJournalRow(icon: String, title: String, valuePlaceholder: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(VelaTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(VelaTheme.accent.opacity(0.12)))
                    
                    Text(title)
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.fg)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Text(valuePlaceholder)
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.meta)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VelaTheme.meta)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(VelaTheme.rhythmMist.opacity(0.4)))
                        .overlay(Circle().stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func saveQuickEntry(tags: [String], note: String, value: Double? = nil, unit: String? = nil) {
        let calendar = Calendar.current
        let now = Date()
        let selected = selectedDate
        
        var components = calendar.dateComponents([.year, .month, .day], from: selected)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        
        let targetDate = calendar.date(from: components) ?? selected
        let targetStart = calendar.startOfDay(for: targetDate)
        let targetEnd = calendar.date(byAdding: .day, value: 1, to: targetStart) ?? targetDate
        
        let habitTags = Set(["低碳水化合物", "添加糖", "生酮饮食", "在床上使用设备", "mood", "每日心情"] + customHabits)
        let isHabitOrMood = tags.contains(where: { habitTags.contains($0) })
        
        if isHabitOrMood {
            if let existingRecords = try? SwiftDataJournalRepository(modelContext: modelContext)
                .fetchEntries(from: targetStart, until: targetEnd) {
                if let matched = existingRecords.first(where: { rec in
                    rec.tags.contains(where: { tags.contains($0) })
                }) {
                    matched.value = value
                    matched.note = note
                    matched.unit = unit
                    matched.createdAt = targetDate
                    do {
                        try modelContext.save()
                        VelaAppState.shared.markLocalDataChanged()
                        loadRealJournalData()
                    } catch {
                        modelContext.rollback()
                        entryMutationError = "本次记录未保存。请稍后重试。"
                    }
                    return
                }
            }
        }
        
        let entry = JournalEntryRecord(createdAt: targetDate, tags: tags, note: note, value: value, unit: unit)
        modelContext.insert(entry)
        VelaEventService.shared.log(
            modelContext: modelContext,
            type: "journal_log",
            title: AppLanguage.stored.isChinese ? "记录日志" : "Log Journal",
            detail: "Tags: \(tags.joined(separator: ", ")), Note: \(note)",
            metadata: ["tags": tags, "note": note]
        )
        do {
            try modelContext.save()
            VelaAppState.shared.markLocalDataChanged()
            loadRealJournalData()
        } catch {
            modelContext.rollback()
            entryMutationError = "本次记录未保存。请稍后重试。"
        }
    }

    private func saveBehaviorQuickNote(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let createdAt = selectedDayWithCurrentTime()
        let signals = BehaviorSignalExtractor.extract(from: trimmed, createdAt: createdAt, confidence: .aiInferred)
        let signalTags = signals.flatMap { signal in
            [
                "behavior:\(signal.tag.rawValue)",
                "intensity:\(signal.intensity.rawValue)",
                "timing:\(signal.timing.rawValue)"
            ]
        }
        let tags = Array(Set(["behavior_signal", "随手记"] + signalTags)).sorted()
        let entry = JournalEntryRecord(createdAt: createdAt, tags: tags, note: trimmed)
        modelContext.insert(entry)
        VelaEventService.shared.log(
            modelContext: modelContext,
            type: "journal_log",
            title: AppLanguage.stored.isChinese ? "快捷日志随手记" : "Quick journal note",
            detail: "Tags: \(tags.joined(separator: ", ")), Note: \(trimmed)",
            metadata: ["tags": tags, "note": trimmed]
        )
        do {
            try modelContext.save()
            VelaAppState.shared.markLocalDataChanged()
            loadRealJournalData()
        } catch {
            modelContext.rollback()
            entryMutationError = "随手记未保存。请稍后重试。"
        }
    }

    private var customHabits: [String] {
        customHabitsRaw
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func customHabitBinding(for habit: String) -> Binding<Int> {
        Binding(
            get: { customHabitStates[habit] ?? 1 },
            set: { customHabitStates[habit] = $0 }
        )
    }

    private func copyPreviousDayEntries() {
        let calendar = Calendar.current
        let selectedStart = calendar.startOfDay(for: selectedDate)
        guard let previousStart = calendar.date(byAdding: .day, value: -1, to: selectedStart),
              let previousEnd = calendar.date(byAdding: .day, value: 1, to: previousStart),
              let selectedEnd = calendar.date(byAdding: .day, value: 1, to: selectedStart) else {
            return
        }
        let previous = entries.filter { $0.createdAt >= previousStart && $0.createdAt < previousEnd }
        let existing = entries.filter { $0.createdAt >= selectedStart && $0.createdAt < selectedEnd }
        var inserted = 0

        for source in previous {
            guard JournalDayCopyPlanner.shouldCopy(source: source, existing: existing) else { continue }
            modelContext.insert(
                JournalEntryRecord(
                    createdAt: JournalDayCopyPlanner.targetDate(
                        sourceDate: source.createdAt,
                        selectedDate: selectedStart,
                        calendar: calendar
                    ),
                    tags: source.tags,
                    note: source.note,
                    value: source.value,
                    unit: source.unit
                )
            )
            inserted += 1
        }

        guard inserted > 0 else {
            entryMutationError = previous.isEmpty ? "昨日没有可复制的条目。" : "昨日条目已经复制到这一天。"
            return
        }
        do {
            try modelContext.save()
            appState.markLocalDataChanged()
            loadRealJournalData()
        } catch {
            modelContext.rollback()
            entryMutationError = "昨日条目未复制。请稍后重试。"
        }
    }

    private func selectedDayWithCurrentTime() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let selected = selectedDate
        var components = calendar.dateComponents([.year, .month, .day], from: selected)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        return calendar.date(from: components) ?? selected
    }
}

enum JournalDayCopyPlanner {
    static func shouldCopy(
        source: JournalEntryRecord,
        existing: [JournalEntryRecord]
    ) -> Bool {
        !existing.contains {
            Set($0.tags) == Set(source.tags) && $0.note == source.note
        }
    }

    static func targetDate(
        sourceDate: Date,
        selectedDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let sourceTime = calendar.dateComponents([.hour, .minute, .second], from: sourceDate)
        var target = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        target.hour = sourceTime.hour
        target.minute = sourceTime.minute
        target.second = sourceTime.second
        return calendar.date(from: target) ?? calendar.startOfDay(for: selectedDate)
    }
}

private struct CustomJournalHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var habits: String
    @State private var draft = ""

    private var values: [String] {
        habits.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("新增") {
                    HStack {
                        TextField("例如：晚餐后散步", text: $draft)
                        Button("添加") { add() }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("自定义习惯") {
                    if values.isEmpty {
                        Text("尚未添加自定义习惯")
                            .foregroundStyle(VelaTheme.muted)
                    }
                    ForEach(values, id: \.self) { value in
                        Text(value)
                    }
                    .onDelete(perform: remove)
                }
                Section {
                    Text("自定义习惯会出现在每日行为板中，默认状态为“未记录”。")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.muted)
                }
            }
            .navigationTitle("自定义习惯")
            .velaRhythmFormSurface()
            .velaRhythmDetailChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func add() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !values.contains(value), !value.contains("|") else { return }
        habits = (values + [value]).joined(separator: "|")
        draft = ""
    }

    private func remove(at offsets: IndexSet) {
        var next = values
        next.remove(atOffsets: offsets)
        habits = next.joined(separator: "|")
    }
}
