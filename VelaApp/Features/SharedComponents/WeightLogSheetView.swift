import SwiftUI
import SwiftData

struct WeightLogSheetView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var weightString = ""
    @State private var bodyFatString = ""
    @State private var date = Date()
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                VelaTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if let errorMsg = errorMsg {
                            HStack {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(VelaTheme.rhythmInk)
                                Text(errorMsg)
                                    .font(.caption)
                                    .foregroundStyle(VelaTheme.fg)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(VelaTheme.rhythmInk.opacity(0.12))
                            .cornerRadius(VelaTheme.radiusSm)
                        }

                        VStack(spacing: 16) {
                            StyledTextField(
                                label: AppLanguage.stored.isChinese ? "体重 (公斤)" : "Weight (kg)",
                                placeholder: "e.g., 72.5",
                                text: $weightString
                            )
                            .keyboardType(.decimalPad)

                            StyledTextField(
                                label: AppLanguage.stored.isChinese ? "体脂率 (%) - 可选" : "Body Fat (%) - Optional",
                                placeholder: "e.g., 15.4",
                                text: $bodyFatString
                            )
                            .keyboardType(.decimalPad)

                            Group {
                                if dynamicTypeSize.isAccessibilitySize {
                                    VStack(alignment: .leading, spacing: VelaTheme.space2) {
                                        Text(AppLanguage.stored.isChinese ? "记录日期" : "Date")
                                        recordDatePicker.datePickerStyle(.graphical)
                                    }
                                } else {
                                    recordDatePicker
                                }
                            }
                            .tint(VelaTheme.accent)
                            .font(.subheadline.bold())
                            .foregroundStyle(VelaTheme.fg)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                                    .fill(VelaTheme.cardBg.opacity(0.6))
                            )
                        }

                        Spacer(minLength: 20)

                        Button {
                            saveWeight()
                        } label: {
                            Text(AppLanguage.stored.isChinese ? "保存记录" : "Save Record")
                                .font(VelaTheme.headline())
                                .foregroundStyle(VelaTheme.accentOn)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, VelaTheme.space3)
                                .frame(minHeight: VelaTheme.minimumHitTarget)
                                .background(VelaTheme.accent, in: Capsule())
                        }
                    }
                    .padding(VelaTheme.pagePadding)
                }
            }
            .navigationTitle(AppLanguage.stored.isChinese ? "记录体重体脂" : "Log Weight & Body Fat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.stored.isChinese ? "取消" : "Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(VelaTheme.fg2)
                }
            }
        }
    }

    private var recordDatePicker: some View {
        DatePicker(
            AppLanguage.stored.isChinese ? "记录日期" : "Date",
            selection: $date,
            displayedComponents: .date
        )
    }

    private func saveWeight() {
        guard let weightVal = Double(weightString), weightVal > 0 else {
            errorMsg = AppLanguage.stored.isChinese ? "请输入有效的体重值。" : "Please enter a valid weight."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let trimmedBodyFat = bodyFatString.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyFatValue: Double?
        if trimmedBodyFat.isEmpty {
            bodyFatValue = nil
        } else if let value = Double(trimmedBodyFat), value > 0, value <= 100 {
            bodyFatValue = value
        } else {
            errorMsg = AppLanguage.stored.isChinese ? "请输入 0 到 100 之间的有效体脂率。" : "Please enter a valid body fat percentage between 0 and 100."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // 1. Save weight as BiomarkerRecord
        let weightRecord = BiomarkerRecord(
            name: "Weight",
            value: weightVal,
            unit: "kg",
            date: date,
            isOptimal: true,
            referenceMin: 45.0,
            referenceMax: 120.0
        )
        modelContext.insert(weightRecord)

        // 2. Save body fat if available
        if let fatVal = bodyFatValue {
            let fatRecord = BiomarkerRecord(
                name: "Body Fat",
                value: fatVal,
                unit: "%",
                date: date,
                isOptimal: true,
                referenceMin: 8.0,
                referenceMax: 25.0
            )
            modelContext.insert(fatRecord)
        }

        // 3. 手记体重成为档案覆盖值（手填优先解析语义）；在「账户与特征基准」
        //    清空体重字段即可恢复跟随 Apple 健康。
        if (25...350).contains(weightVal) {
            UserDefaults.standard.set(weightVal, forKey: UserProfileSettings.weightKey)
        }

        // Log weight event
        VelaEventService.shared.log(
            modelContext: modelContext,
            type: "weight_log",
            title: AppLanguage.stored.isChinese ? "记录体重" : "Log Weight",
            detail: AppLanguage.stored.isChinese 
                ? "体重: \(weightVal) kg" + (bodyFatValue != nil ? ", 体脂率: \(bodyFatValue!)%" : "")
                : "Weight: \(weightVal) kg" + (bodyFatValue != nil ? ", Body Fat: \(bodyFatValue!)%" : ""),
            metadata: ["weight": weightVal, "body_fat": bodyFatValue ?? 0.0]
        )

        // Try to update daily summary record if exists
        let calendar = Calendar.current
        let dayId = DailyHealthSummaryRecord.dayIdentifier(for: date, calendar: calendar)
        if let first = try? SwiftDataDailyHealthSummaryRepository(modelContext: modelContext).fetchRecord(dayIdentifier: dayId) {
            first.bodyWeight = weightVal
            if let fatVal = bodyFatValue {
                first.bodyFatPercent = fatVal
            }
        } else {
            modelContext.insert(
                DailyHealthSummaryRecord(
                    dayIdentifier: dayId,
                    date: calendar.startOfDay(for: date),
                    bodyWeight: weightVal,
                    bodyFatPercent: bodyFatValue
                )
            )
        }

        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMsg = AppLanguage.stored.isChinese ? "保存失败，请重试。" : "Save failed, please try again."
        }
    }
}
