import SwiftUI
import SwiftData
import UIKit
import Charts
import PDFKit
import UniformTypeIdentifiers
import Vision

struct BiologicalAgeHistoryPoint: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var biologicalAge: Double
    var chronologicalAge: Double
    var evidenceCount: Int
}

enum BiologicalAgeHistoryBuilder {
    static func build(
        biomarkers: [BiomarkerRecord],
        currentChronologicalAge: Double,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> [BiologicalAgeHistoryPoint] {
        let days = Set(biomarkers.map { calendar.startOfDay(for: $0.date) }).sorted()
        return days.compactMap { day in
            let records = latestRecords(upTo: day, from: biomarkers, calendar: calendar)
            let yearsAgo = max(0, asOf.timeIntervalSince(day) / (365.25 * 86_400))
            let ageAtDate = max(0, currentChronologicalAge - yearsAgo)
            let result = BiologicalAgeEngine().calculate(input: BiologicalAgeInput(
                chronologicalAge: ageAtDate,
                biomarkers: records
            ))
            guard result.isPhenoAge else { return nil }
            return BiologicalAgeHistoryPoint(
                date: day,
                biologicalAge: result.biologicalAge,
                chronologicalAge: ageAtDate,
                evidenceCount: result.factors.count
            )
        }
    }

    private static func latestRecords(
        upTo day: Date,
        from biomarkers: [BiomarkerRecord],
        calendar: Calendar
    ) -> [BiomarkerRecord] {
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        var seen = Set<String>()
        return biomarkers
            .filter { $0.date < end }
            .sorted { $0.date > $1.date }
            .filter { seen.insert(normalizedName($0.name)).inserted }
    }

    private static func normalizedName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


struct HealthRecordBiomarkerCandidate: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var valueText: String
    var unit: String
    var referenceMinText: String
    var referenceMaxText: String
    var isIncluded = true
}

struct HealthRecordReviewDraft: Identifiable {
    let id = UUID()
    let sourceName: String
    var candidates: [HealthRecordBiomarkerCandidate]
}

enum HealthRecordImportError: LocalizedError {
    case unsupportedFile
    case unreadableFile
    case noRecognizedBiomarkers

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "暂不支持这个文件格式。请选择 PDF、文本或图片。"
        case .unreadableFile: "无法读取这份文件。"
        case .noRecognizedBiomarkers: "没有找到可可靠识别的常见化验指标。请改用手工录入，并核对原始报告。"
        }
    }
}

enum HealthRecordTextExtractor {
    static func extract(from url: URL) async throws -> String {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)

        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(data: data) else { throw HealthRecordImportError.unreadableFile }
            let text = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
            guard !text.isEmpty else { throw HealthRecordImportError.unreadableFile }
            return text
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw HealthRecordImportError.unsupportedFile
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        guard !text.isEmpty else { throw HealthRecordImportError.unreadableFile }
        return text
    }
}

enum HealthRecordBiomarkerParser {
    private struct Definition {
        let canonicalName: String
        let aliases: [String]
        let unit: String
        let range: ClosedRange<Double>
    }

    private static let definitions = [
        Definition(canonicalName: "Albumin", aliases: ["albumin", "白蛋白"], unit: "g/dL", range: 3.5...5.0),
        Definition(canonicalName: "Creatinine", aliases: ["creatinine", "肌酐"], unit: "mg/dL", range: 0.6...1.2),
        Definition(canonicalName: "Glucose", aliases: ["glucose", "葡萄糖", "血糖"], unit: "mg/dL", range: 70...100),
        Definition(canonicalName: "CRP", aliases: ["crp", "c-reactive protein", "c反应蛋白"], unit: "mg/L", range: 0...3),
        Definition(canonicalName: "Lymphocyte Percentage", aliases: ["lymphocyte", "淋巴细胞百分比"], unit: "%", range: 20...40),
        Definition(canonicalName: "MCV", aliases: ["mcv", "平均红细胞体积"], unit: "fL", range: 80...100),
        Definition(canonicalName: "RDW", aliases: ["rdw", "红细胞分布宽度"], unit: "%", range: 11...15),
        Definition(canonicalName: "Alkaline Phosphatase", aliases: ["alkaline phosphatase", "alp", "碱性磷酸酶"], unit: "U/L", range: 44...147),
        Definition(canonicalName: "WBC", aliases: ["wbc", "white blood cell", "白细胞"], unit: "10^3/uL", range: 4...11),
        Definition(canonicalName: "Vitamin D", aliases: ["vitamin d", "25-oh", "维生素d"], unit: "ng/mL", range: 30...100),
        Definition(canonicalName: "Ferritin", aliases: ["ferritin", "铁蛋白"], unit: "ng/mL", range: 30...400),
        Definition(canonicalName: "HbA1c", aliases: ["hba1c", "glycated hemoglobin", "糖化血红蛋白"], unit: "%", range: 4...5.6)
    ]

    static func parse(_ text: String) -> [HealthRecordBiomarkerCandidate] {
        let lines = text.components(separatedBy: .newlines)
        var found: [String: HealthRecordBiomarkerCandidate] = [:]
        for line in lines {
            let normalized = line.lowercased()
            guard let definition = definitions.first(where: { definition in
                definition.aliases.contains { normalized.contains($0.lowercased()) }
            }), let value = firstNumber(afterAny: definition.aliases, in: line) else { continue }
            found[definition.canonicalName] = HealthRecordBiomarkerCandidate(
                name: definition.canonicalName,
                valueText: value,
                unit: detectedUnit(in: line) ?? definition.unit,
                referenceMinText: definition.range.lowerBound.formatted(),
                referenceMaxText: definition.range.upperBound.formatted()
            )
        }
        return found.values.sorted { $0.name < $1.name }
    }

    private static func firstNumber(afterAny aliases: [String], in line: String) -> String? {
        let source = line as NSString
        guard let alias = aliases.first(where: {
            source.range(of: $0, options: .caseInsensitive).location != NSNotFound
        }) else { return nil }
        let aliasRange = source.range(of: alias, options: .caseInsensitive)
        let suffix = source.substring(from: NSMaxRange(aliasRange))
        guard let regex = try? NSRegularExpression(pattern: "[-+]?[0-9]+(?:[.,][0-9]+)?"),
              let match = regex.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)),
              let swiftRange = Range(match.range, in: suffix) else { return nil }
        return String(suffix[swiftRange]).replacingOccurrences(of: ",", with: ".")
    }

    private static func detectedUnit(in line: String) -> String? {
        ["mg/dL", "mg/L", "g/dL", "ng/mL", "U/L", "fL", "%", "10^3/uL"]
            .first { line.localizedCaseInsensitiveContains($0) }
    }
}

private struct HealthRecordReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let draft: HealthRecordReviewDraft
    @State private var candidates: [HealthRecordBiomarkerCandidate]
    @State private var testDate = Date()
    @State private var errorMessage: String?

    init(draft: HealthRecordReviewDraft) {
        self.draft = draft
        _candidates = State(initialValue: draft.candidates)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("原始记录") {
                    LabeledContent("文件", value: draft.sourceName)
                    DatePicker("检测日期", selection: $testDate, displayedComponents: .date)
                    Text("原始文件不会被 Vela 保留；只保存你确认的结构化指标和来源文件名。")
                        .font(.caption)
                        .foregroundStyle(VelaTheme.muted)
                }

                ForEach($candidates) { $candidate in
                    Section {
                        Toggle("保存此指标", isOn: $candidate.isIncluded)
                        TextField("指标名称", text: $candidate.name)
                        HStack {
                            TextField("数值", text: $candidate.valueText)
                                .keyboardType(.decimalPad)
                            TextField("单位", text: $candidate.unit)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            TextField("参考下限", text: $candidate.referenceMinText)
                                .keyboardType(.decimalPad)
                            TextField("参考上限", text: $candidate.referenceMaxText)
                                .keyboardType(.decimalPad)
                        }
                    } header: {
                        Text(candidate.name)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(VelaTheme.danger)
                    }
                }
            }
            .navigationTitle("审核识别结果")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认保存") { save() }
                }
            }
        }
    }

    private func save() {
        let included = candidates.filter(\.isIncluded)
        guard !included.isEmpty else {
            errorMessage = "请至少选择一项指标。"
            return
        }
        for candidate in included {
            guard let value = Double(candidate.valueText),
                  let minimum = Double(candidate.referenceMinText),
                  let maximum = Double(candidate.referenceMaxText),
                  value.isFinite, minimum.isFinite, maximum.isFinite,
                  minimum <= maximum,
                  !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !candidate.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "请核对每项数值、单位和参考区间。"
                return
            }
            modelContext.insert(BiomarkerRecord(
                name: candidate.name.trimmingCharacters(in: .whitespacesAndNewlines),
                value: value,
                unit: candidate.unit.trimmingCharacters(in: .whitespacesAndNewlines),
                date: testDate,
                isOptimal: value >= minimum && value <= maximum,
                referenceMin: minimum,
                referenceMax: maximum,
                sourceDocumentName: draft.sourceName
            ))
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "健康记录未保存，请重试。"
        }
    }
}

// MARK: - Manual Blood Log Sheet Form
struct BloodLogSheetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var valueString = ""
    @State private var unit = "ng/mL"
    @State private var refMinString = ""
    @State private var refMaxString = ""
    @State private var date = Date()
    @State private var errorMsg: String? = nil

    private let commonBiomarkers = [
        "Albumin", "Creatinine", "Glucose", "CRP", "Lymphocyte Percentage", "MCV", "RDW",
        "Alkaline Phosphatase", "WBC", "Vitamin D", "Cortisol", "Ferritin", "Cholesterol",
        "Testosterone", "TSH", "HbA1c"
    ]

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
                            .background(VelaTheme.rhythmInk.opacity(0.12), in: RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))
                        }

                        // Suggestion chips
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.t("Common Biomarkers", "常用血检指标"))
                                .font(.caption.bold())
                                .foregroundStyle(VelaTheme.fg2)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(commonBiomarkers, id: \.self) { item in
                                        Button {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            name = item
                                            autoFillDefaults(for: item)
                                        } label: {
                                            Text(item)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(name == item ? VelaTheme.bg : VelaTheme.fg)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(name == item ? VelaTheme.accent : VelaTheme.surfaceInset)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }

                        // Fields
                        VStack(spacing: 16) {
                            StyledTextField(label: L10n.t("BIOMARKER NAME", "指标名称"), placeholder: "e.g., Vitamin D", text: $name)

                            HStack(spacing: 12) {
                                StyledTextField(label: L10n.t("VALUE", "数值"), placeholder: "e.g., 42.5", text: $valueString)
                                    .keyboardType(.decimalPad)

                                StyledTextField(label: L10n.t("UNIT", "单位"), placeholder: "e.g., ng/mL", text: $unit)
                            }

                            HStack(spacing: 12) {
                                StyledTextField(label: L10n.t("MIN REFERENCE", "标准下限"), placeholder: "e.g., 30", text: $refMinString)
                                    .keyboardType(.decimalPad)

                                StyledTextField(label: L10n.t("MAX REFERENCE", "标准上限"), placeholder: "e.g., 100", text: $refMaxString)
                                    .keyboardType(.decimalPad)
                            }

                            DatePicker(
                                L10n.t("TEST DATE", "检测日期"),
                                selection: $date,
                                displayedComponents: .date
                            )
                            .tint(VelaTheme.accent)
                            .font(.subheadline.bold())
                            .foregroundStyle(VelaTheme.fg)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                                    .fill(VelaTheme.rhythmCanvasRaised)
                            )
                        }

                        Spacer(minLength: 20)

                        Button {
                            saveBiomarker()
                        } label: {
                            Text(L10n.t("Save Biomarker", "保存指标"))
                                .font(VelaTheme.body().weight(.bold))
                                .foregroundStyle(VelaTheme.bg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(VelaTheme.accent, in: Capsule())
                        }
                    }
                    .padding(VelaTheme.pagePadding)
                }
            }
            .navigationTitle(L10n.t("Log Lab Biomarker", "录入血检数据"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", "取消")) {
                        dismiss()
                    }
                    .foregroundStyle(VelaTheme.fg2)
                }
            }
        }
    }

    private func autoFillDefaults(for bName: String) {
        switch bName {
        case "Albumin":
            unit = "g/dL"
            refMinString = "3.5"
            refMaxString = "5.0"
        case "Creatinine":
            unit = "mg/dL"
            refMinString = "0.6"
            refMaxString = "1.2"
        case "Glucose":
            unit = "mg/dL"
            refMinString = "70"
            refMaxString = "100"
        case "CRP":
            unit = "mg/L"
            refMinString = "0"
            refMaxString = "3"
        case "Lymphocyte Percentage":
            unit = "%"
            refMinString = "20"
            refMaxString = "40"
        case "MCV":
            unit = "fL"
            refMinString = "80"
            refMaxString = "100"
        case "RDW":
            unit = "%"
            refMinString = "11"
            refMaxString = "15"
        case "Alkaline Phosphatase":
            unit = "U/L"
            refMinString = "44"
            refMaxString = "147"
        case "WBC":
            unit = "10^3/uL"
            refMinString = "4"
            refMaxString = "11"
        case "Vitamin D":
            unit = "ng/mL"
            refMinString = "30"
            refMaxString = "100"
        case "Cortisol":
            unit = "mcg/dL"
            refMinString = "6"
            refMaxString = "23"
        case "Ferritin":
            unit = "ng/mL"
            refMinString = "30"
            refMaxString = "400"
        case "Cholesterol":
            unit = "mg/dL"
            refMinString = "100"
            refMaxString = "199"
        case "Testosterone":
            unit = "ng/dL"
            refMinString = "300"
            refMaxString = "1000"
        case "TSH":
            unit = "uIU/mL"
            refMinString = "0.4"
            refMaxString = "4.0"
        case "HbA1c":
            unit = "%"
            refMinString = "4.0"
            refMaxString = "5.6"
        default:
            break
        }
    }

    private func saveBiomarker() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMsg = L10n.t("Name is required.", "请输入指标名称。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard let val = Double(valueString), val.isFinite else {
            errorMsg = L10n.t("Invalid value format.", "请输入有效的数值。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard let rMin = Double(refMinString), let rMax = Double(refMaxString),
              rMin.isFinite, rMax.isFinite else {
            errorMsg = L10n.t("Reference min and max are required.", "请输入标准上限和下限。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMsg = L10n.t("Unit is required.", "请输入单位。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard rMin <= rMax else {
            errorMsg = L10n.t("Reference minimum must not exceed maximum.", "标准下限不能高于上限。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        let isOptimal = val >= rMin && val <= rMax
        let record = BiomarkerRecord(
            name: name,
            value: val,
            unit: unit,
            date: date,
            isOptimal: isOptimal,
            referenceMin: rMin,
            referenceMax: rMax
        )

        modelContext.insert(record)

        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMsg = L10n.t("Could not save biomarker.", "指标保存失败，请重试。")
        }
    }
}

// MARK: - Styled Text Field Helper
struct StyledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .tracking(1)

            TextField(placeholder, text: $text)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .fill(VelaTheme.rhythmCanvasRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                )
                .foregroundStyle(VelaTheme.rhythmInk)
        }
    }
}
