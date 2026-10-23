import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "com.sunweizhou.Vela", category: "WikiFileService")

struct WikiDocument: Hashable, Identifiable {
    var id: String { filename }
    var filename: String
    var title: String
    var content: String
    var updatedAt: Date
}

enum WikiFileService {
    private static let filenames: [(filename: String, title: String)] = [
        ("profile.md", "个人档案"),
        ("goals.md", "健康目标"),
        ("constraints.md", "个人约束"),
        ("preferences.md", "个人偏好"),
        ("habits.md", "生活与训练习惯"),
        ("training_history.md", "训练历史"),
        ("health_context.md", "健康背景"),
        ("baselines.md", "生理基线"),
        ("observations.md", "AI 观察"),
        ("strategies.md", "当前策略"),
        ("notes.md", "备注与发现"),
        ("archive.md", "历史归档"),
        ("diet.md", "饮食偏好与禁忌"),
        ("sleep.md", "睡眠卫生与环境")
    ]

    /// Wiki 合法文件名白名单。写入（updateSection）与提案入口（MemoryLedger.createProposal）
    /// 共用同一集合，防止 LLM 提供的文件名逃逸 user_wiki 目录（路径穿越）。
    static let allowedFilenames = Set(filenames.map(\.filename))

    private static let defaultContentsByFilename: [String: String] = filenames.reduce(into: [:]) {
        $0[$1.filename] = defaultContent(for: $1.filename)
    }

    // MARK: - Dictionary read cache

    private struct WikiFileSignature: Equatable {
        var modificationDate: Date?
        var fileSize: UInt64
    }

    private final class WikiDictionaryCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cachedDictionary: [String: String]?
        private var cachedInitialized: [String: Bool]?
        private var cachedDocuments: [WikiDocument]?
        private var cachedSignature: [String: WikiFileSignature]?

        func value(for signature: [String: WikiFileSignature]) -> [String: String]? {
            lock.lock()
            defer { lock.unlock() }
            guard cachedSignature == signature, let cachedDictionary else { return nil }
            return cachedDictionary
        }

        func initialized(for signature: [String: WikiFileSignature]) -> [String: Bool]? {
            lock.lock()
            defer { lock.unlock() }
            guard cachedSignature == signature, let cachedInitialized else { return nil }
            return cachedInitialized
        }

        func documents(for signature: [String: WikiFileSignature]) -> [WikiDocument]? {
            lock.lock()
            defer { lock.unlock() }
            guard cachedSignature == signature, let cachedDocuments else { return nil }
            return cachedDocuments
        }

        func store(
            _ dictionary: [String: String],
            initialized: [String: Bool],
            signature: [String: WikiFileSignature]
        ) {
            lock.lock()
            defer { lock.unlock() }
            cachedDictionary = dictionary
            cachedInitialized = initialized
            cachedSignature = signature
        }

        func storeDocuments(_ documents: [WikiDocument], signature: [String: WikiFileSignature]) {
            lock.lock()
            defer { lock.unlock() }
            cachedDocuments = documents
            cachedSignature = signature
        }

        func invalidate() {
            lock.lock()
            defer { lock.unlock() }
            cachedDictionary = nil
            cachedInitialized = nil
            cachedDocuments = nil
            cachedSignature = nil
        }
    }

    private static let dictionaryCache = WikiDictionaryCache()

    private static func fileSignature(for url: URL) -> WikiFileSignature {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return WikiFileSignature(modificationDate: nil, fileSize: 0)
        }
        return WikiFileSignature(
            modificationDate: attributes[.modificationDate] as? Date,
            fileSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        )
    }

    private static func currentFileSignatures() -> [String: WikiFileSignature] {
        filenames.reduce(into: [:]) { result, entry in
            result[entry.filename] = fileSignature(for: localURL(for: entry.filename))
        }
    }

    /// 测试或外部代码直接写盘后，可调用此方法强制下一次 loadDictionary 重读文件。
    static func invalidateDictionaryCache() {
        dictionaryCache.invalidate()
    }

    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let empty = [Int](repeating: 0, count: s2.count + 1)
        var last = [Int](0...s2.count)
        var current = empty

        for (i, char1) in s1.enumerated() {
            current[0] = i + 1
            for (j, char2) in s2.enumerated() {
                current[j + 1] = char1 == char2
                    ? last[j]
                    : min(last[j], last[j + 1], current[j]) + 1
            }
            last = current
        }
        return last.last ?? 0
    }

    private static func levenshteinSimilarity(_ s1: String, _ s2: String) -> Double {
        let maxLen = max(s1.count, s2.count)
        guard maxLen > 0 else { return 1.0 }
        let distance = levenshteinDistance(s1, s2)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    /// Levenshtein 相似度（internal 供 MemoryLedger 跨源去重复用）。
    static func textSimilarity(_ s1: String, _ s2: String) -> Double {
        levenshteinSimilarity(s1, s2)
    }

    // MARK: - Read

    /// 本地磁盘上的原始内容（不含 bundle/模板兜底）——用于判断是否已被用户写入。
    static func localContent(for filename: String) -> String {
        guard allowedFilenames.contains(filename) else { return "" }
        return (try? String(contentsOf: localURL(for: filename), encoding: .utf8)) ?? ""
    }

    /// 本地文件「未初始化」：空文件，或仍是默认空模板。
    ///
    /// 历史版本会把空模板落盘（见 `WikiSyncManager.sync` 的修复记录），
    /// materializer 必须把这类文件视为空白，才能安全写入真实档案；
    /// 而用户手改过的内容（与模板不同）永远返回 false，绝不覆盖。
    static func isUninitialized(_ filename: String) -> Bool {
        let local = localContent(for: filename).trimmingCharacters(in: .whitespacesAndNewlines)
        if local.isEmpty { return true }
        return local == defaultContent(for: filename).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func loadAllDocuments() -> [WikiDocument] {
        let signature = currentFileSignatures()
        if let cached = dictionaryCache.documents(for: signature) {
            return cached
        }
        let documents = filenames.compactMap { entry in
            let url = localURL(for: entry.filename)
            let localContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let updatedAt = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date

            let bundledContent = bundledContent(for: entry.filename)
            let content = canonicalContent(
                localContent: localContent,
                bundledContent: bundledContent,
                filename: entry.filename
            )

            return WikiDocument(
                filename: entry.filename,
                title: entry.title,
                content: content,
                updatedAt: updatedAt ?? Date()
            )
        }
        dictionaryCache.storeDocuments(documents, signature: signature)
        return documents
    }

    /// Load documents as a simple [filename: content] dictionary for AI context.
    /// 带文件签名缓存：内容未变化时直接复用上一次读取结果；
    /// updateSection / sync 写入后会主动失效，外部直接写盘则靠签名自动失效。
    static func loadDictionary() -> [String: String] {
        let signature = currentFileSignatures()
        if let cached = dictionaryCache.value(for: signature) {
            return cached
        }
        var dictionary: [String: String] = [:]
        var initialized: [String: Bool] = [:]
        for entry in filenames {
            let url = localURL(for: entry.filename)
            let localContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let bundled = bundledContent(for: entry.filename)
            dictionary[entry.filename] = canonicalContent(
                localContent: localContent,
                bundledContent: bundled,
                filename: entry.filename
            )
            initialized[entry.filename] = Self.isInitialized(
                localContent: localContent,
                filename: entry.filename
            )
        }
        dictionaryCache.store(dictionary, initialized: initialized, signature: signature)
        return dictionary
    }

    /// 只根据「本地文件内容」判断是否已初始化；与 `isUninitialized` 同口径，
    /// 但可复用 loadDictionary 读取过的 localContent，不重复读盘。
    private static func isInitialized(localContent: String, filename: String) -> Bool {
        let trimmedLocal = localContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocal.isEmpty else { return false }
        let defaultContent = defaultContentsByFilename[filename]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLocal != defaultContent
    }

    /// 仅返回「已初始化」文件的字典（空/默认模板文件被剔除）。
    /// AI 上下文专用（A5）：避免把 14 个文件的英文空模板样板发给模型、
    /// 浪费 token 并让模型误以为档案字段已填写。
    static func loadPopulatedDictionary() -> [String: String] {
        // 复用 loadDictionary 的签名缓存和初始化标记，完全不重复读盘。
        let signature = currentFileSignatures()
        let dictionary: [String: String]
        let initialized: [String: Bool]
        if let cached = dictionaryCache.value(for: signature),
           let cachedInitialized = dictionaryCache.initialized(for: signature) {
            dictionary = cached
            initialized = cachedInitialized
        } else {
            dictionary = loadDictionary()
            initialized = dictionaryCache.initialized(for: signature) ?? [:]
        }
        return dictionary.filter { initialized[$0.key] == true }
    }

    private static func canonicalContent(localContent: String, bundledContent: String, filename: String) -> String {
        let trimmedLocal = localContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLocal.isEmpty {
            return localContent
        }

        let trimmedBundled = bundledContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBundled.isEmpty {
            return bundledContent
        }

        return defaultContent(for: filename)
    }

    // MARK: - Write (Agent-driven)

    /// Agent calls this to update a specific wiki section.
    /// - Returns: `true` if the file content actually changed; `false` if the
    ///   target file is not allowed, every new paragraph was deduplicated out, or
    ///   the new content equals the existing content. Callers (e.g. MemoryLedger)
    ///   must NOT mark a write as successful when this returns `false` — otherwise
    ///   a proposal would read as "accepted" while its content never reached the wiki.
    @discardableResult
    static func updateSection(filename: String, content: String, mode: WikiUpdateMode = .append) throws -> Bool {
        guard allowedFilenames.contains(filename) else {
            logger.warning("Wiki update rejected: unknown file '\(filename)'")
            return false
        }

        let url = localURL(for: filename)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        let newContent: String
        switch mode {
        case .replace:
            newContent = content
        case .append:
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let block = existing.isEmpty
                ? content
                : "\(existing)\n\n## Updated \(timestamp)\n\(content)"
            newContent = block
        case .merge:
            let existingParagraphs = existing.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let newParagraphs = content.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // Deduplicate: check if a paragraph already exists exactly, is a substring of existing,
            // or existing is a substring of new, or they have Levenshtein similarity > 0.85.
            // M9：子串规则加长度门槛（两侧均 ≥8 字符才判定），
            // 避免「素食」这类短事实被既有长段落吞掉导致静默丢失。
            let newDeduplicated = newParagraphs.filter { newPara in
                !existingParagraphs.contains { existingPara in
                    (existingPara.count >= 8 && newPara.count >= 8
                        && (existingPara.contains(newPara) || newPara.contains(existingPara)))
                    || levenshteinSimilarity(existingPara, newPara) > 0.85
                }
            }

            guard !newDeduplicated.isEmpty else {
                logger.info("Wiki merge skipped: all paragraphs are duplicates for '\(filename)'")
                return false
            }

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let block = existingParagraphs + ["## Updated \(timestamp)"] + newDeduplicated
            newContent = block.joined(separator: "\n\n")
        }

        try newContent.write(to: url, atomically: true, encoding: .utf8)
        dictionaryCache.invalidate()
        return true
    }

    static func replacingStructuredFields(
        in markdown: String,
        title: String,
        fieldValues: [String: String],
        preferredOrder: [String]
    ) -> String {
        var lines = markdown.components(separatedBy: .newlines)
        if lines.isEmpty || lines.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            lines = ["# \(title)", ""]
        } else if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }) {
            lines.insert(contentsOf: ["# \(title)", ""], at: 0)
        }

        var replaced = Set<String>()
        let fieldSet = Set(preferredOrder)

        for index in lines.indices {
            let line = lines[index]
            let leadingWhitespace = String(line.prefix { $0 == " " || $0 == "\t" })
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { continue }

            let marker = String(trimmed.prefix(2))
            let body = String(trimmed.dropFirst(2))
            guard let match = matchedField(in: body, fields: fieldSet) else { continue }

            let value = fieldValues[match] ?? ""
            lines[index] = "\(leadingWhitespace)\(marker)\(match): \(value)"
            replaced.insert(match)
        }

        let missing = preferredOrder.filter { !replaced.contains($0) }
        guard !missing.isEmpty else {
            return normalizedMarkdown(lines)
        }

        let insertionIndex = structuredFieldInsertionIndex(in: lines)
        let inserted = missing.map { "- \($0): \(fieldValues[$0] ?? "")" }
        lines.insert(contentsOf: inserted, at: insertionIndex)
        if insertionIndex < lines.count, !lines[insertionIndex + inserted.count - 1].isEmpty {
            lines.insert("", at: insertionIndex + inserted.count)
        }

        return normalizedMarkdown(lines)
    }

    private static func matchedField(in bulletBody: String, fields: Set<String>) -> String? {
        for field in fields.sorted(by: { $0.count > $1.count }) {
            if bulletBody == field || bulletBody.hasPrefix("\(field):") || bulletBody.hasPrefix("\(field)：") {
                return field
            }
        }
        return nil
    }

    private static func structuredFieldInsertionIndex(in lines: [String]) -> Int {
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }) else {
            return 0
        }

        var index = headingIndex + 1
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            index += 1
        }
        return index
    }

    private static func normalizedMarkdown(_ lines: [String]) -> String {
        var result = lines
        while result.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            result.removeLast()
        }
        return result.joined(separator: "\n") + "\n"
    }

    /// Generate a weekly wiki review prompt for the agent
    static func weeklyReviewPrompt(dailyLogs: [DailyLogEntry], language: AppLanguage = .stored) -> String {
        let weekSummary = dailyLogs.map { log in
            let dateStr = DateFormatter.localizedString(from: log.date, dateStyle: .medium, timeStyle: .none)
            return """
            ### \(dateStr)
            Health: \(String(log.healthBrief.prefix(300)))
            Key Insights: \(log.keyInsights.joined(separator: "; "))
            """
        }.joined(separator: "\n\n")

        let currentWiki = loadDictionary().map { "### \($0.key)\n\($0.value)" }.joined(separator: "\n\n")

        if language.isChinese {
            return """
            你正在为你的用户做每周 Wiki 回顾。请仔细阅读这周的健康日志和当前 Wiki，找出用户的新模式、习惯变化、或者值得记录的稳定特征。

            ## 本周日志
            \(weekSummary)

            ## 当前 Wiki
            \(currentWiki)

            ## 任务
            分析本周日志，识别出值得更新到 Wiki 的内容。输出格式：

            [ACTION:update_wiki]
            file: habits.md
            [内容——只写新发现或变化，不要重复已有信息]
            [/ACTION]

            每个 Wiki 文件最多更新一条。如果没有值得记录的新信息，就不输出任何 ACTION。
            只在发现用户的稳定模式、偏好变化、或新的健康背景时才更新。
            """
        }

        return """
        You are reviewing the past week's health logs and current wiki for your user.
        Identify new patterns, habit changes, or stable characteristics worth recording.

        ## This Week's Logs
        \(weekSummary)

        ## Current Wiki
        \(currentWiki)

        ## Task
        Analyze the week's logs and identify wiki-worthy updates. Output format:

        [ACTION:update_wiki]
        file: habits.md
        [content — only new findings or changes, don't repeat existing info]
        [/ACTION]

        At most one update per wiki file. If nothing new is worth recording, output no ACTION at all.
        Only record stable patterns, preference changes, or new health context.
        """
    }

    // MARK: - Public URL Access (used by MemoryLedger)

    static func localURL(for filename: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Vela", isDirectory: true)
            .appendingPathComponent("user_wiki", isDirectory: true)
            .appendingPathComponent(filename)
    }

    @discardableResult
    static func deleteLocalDocuments(
        at directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Int {
        let directory = directoryURL ?? localURL(for: "profile.md").deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        try fileManager.removeItem(at: directory)
        return contents.count
    }

    static func localDocumentCount(fileManager: FileManager = .default) -> Int {
        let directory = localURL(for: "profile.md").deletingLastPathComponent()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return 0 }
        return contents.filter { $0.pathExtension.lowercased() == "md" }.count
    }

    private static func bundledContent(for filename: String) -> String {
        let name = (filename as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "user_wiki"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func defaultContent(for filename: String) -> String {
        switch filename {
        case "profile.md":
            return "# Profile\n\n- Age: \n- Activity level: \n- Primary sports: \n- Health goals: \n"
        case "goals.md":
            return "# Goals\n\n- Sleep: \n- Activity: \n- Recovery: \n- Other: \n"
        case "constraints.md":
            return "# Constraints\n\n- Injuries: \n- Equipment: \n- Time: \n- Dietary: \n"
        case "preferences.md":
            return "# Preferences\n\n- Training style: \n- Communication style: \n- Dietary preferences: \n"
        case "habits.md":
            return "# Habits\n\n- Caffeine: \n- Alcohol: \n- Evening routine: \n- Morning routine: \n"
        case "training_history.md":
            return "# Training History\n\n- Typical weekly volume: \n- Preferred training types: \n- Past injuries: \n"
        case "health_context.md":
            return "# Health Context\n\n- Known conditions: \n- Medications: \n- Recent changes: \n"
        case "baselines.md":
            return "# Personal Baselines\n\nYour physiological baselines will be computed automatically after 7+ days of data.\n"
        case "observations.md":
            return "# AI Observations\n\nPatterns observed from data but not yet user-confirmed.\n"
        case "strategies.md":
            return "# Active Strategies\n\nCurrent training/recovery strategies in use.\n"
        case "archive.md":
            return "# Archive\n\nSuperseded or expired memories.\n"
        case "diet.md":
            return "# Diet\n\n- Dietary restrictions: \n- Caffeine window: \n- Preferred meals: \n"
        case "sleep.md":
            return "# Sleep\n\n- Sleep environment: \n- Wind-down routine: \n- Targets: \n"
        case "notes.md":
            return "# Notes\n\n"
        default:
            return ""
        }
    }

    static func getAgeFromWiki() -> Int? {
        let dictionary = loadDictionary()
        guard let profileContent = dictionary["profile.md"] else { return nil }
        
        let lines = profileContent.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                let body = String(trimmed.dropFirst(2))
                let colonPrefix = "Age: "
                let spacePrefix = "Age "
                if body.hasPrefix(colonPrefix) {
                    let ageStr = body.dropFirst(colonPrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                    return Int(ageStr)
                } else if body.hasPrefix(spacePrefix) {
                    let ageStr = body.dropFirst(spacePrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                    return Int(ageStr)
                }
            }
        }
        
        // As a fallback, use the regex
        let pattern = "(?i)(?:age|年龄)\\s*[:：]\\s*(\\d+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsRange = NSRange(profileContent.startIndex..<profileContent.endIndex, in: profileContent)
            if let match = regex.firstMatch(in: profileContent, options: [], range: nsRange) {
                if let range = Range(match.range(at: 1), in: profileContent) {
                    let ageStr = profileContent[range]
                    return Int(ageStr)
                }
            }
        }
        return nil
    }

    static func getMaxHeartRateFromWiki() -> Double? {
        let dictionary = loadDictionary()
        guard let profileContent = dictionary["profile.md"] else { return nil }

        let pattern = "(?i)(?:max(?:imum)?\\s*heart\\s*rate|max\\s*hr|最大心率)\\s*[:：]\\s*(\\d+(?:\\.\\d+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: profileContent,
                range: NSRange(profileContent.startIndex..<profileContent.endIndex, in: profileContent)
              ),
              let range = Range(match.range(at: 1), in: profileContent),
              let maxHeartRate = Double(profileContent[range]),
              (100...240).contains(maxHeartRate) else {
            return nil
        }
        return maxHeartRate
    }
}

enum WikiUpdateMode: String, Hashable {
    case append
    case replace
    case merge
}

/// 档案页通用的「标签: 值」字段。
struct WikiBulletField: Hashable {
    let label: String
    let value: String
}

/// 解析 markdown 中的 "- 标签: 值" 条目。
/// 同时支持英文冒号 `:` 与中文冒号 `：`，标签不限语言——
/// agent 与 materializer 写入的中文标签必须能正常展示。
enum WikiBulletParser {
    static func parseFields(in content: String, templateLabels: [String]) -> [WikiBulletField] {
        var fields: [WikiBulletField] = []
        var seen = Set<String>()

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { continue }
            let body = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard let separatorIndex = body.firstIndex(where: { $0 == ":" || $0 == "：" }) else { continue }
            let label = String(body[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(body[body.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, seen.insert(label).inserted else { continue }
            fields.append(WikiBulletField(label: label, value: value))
        }

        // 没有任何条目时回退到空模板字段（保证空白档案仍可结构化编辑）。
        if fields.isEmpty {
            return templateLabels.map { WikiBulletField(label: $0, value: "") }
        }
        return fields
    }
}

@MainActor
public enum WikiSyncManager {
    public static func sync(modelContext: ModelContext) {
        let allDocs = WikiFileService.loadAllDocuments()
        
        let existingRecords = (try? UserWikiDocumentRepository(modelContext: modelContext).fetchAll()) ?? []
        
        let existingMap = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.filename, $0) })
        
        for doc in allDocs {
            let url = WikiFileService.localURL(for: doc.filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                // 空模板只用于展示兜底，绝不能落盘：
                // 一旦落盘，materializer 会把模板误判为"已写入"，真实档案永远无法初始化。
                let isTemplate = doc.content == WikiFileService.defaultContent(for: doc.filename)
                if !isTemplate {
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? doc.content.write(to: url, atomically: true, encoding: .utf8)
                    WikiFileService.invalidateDictionaryCache()
                }
            }
            
            if let existing = existingMap[doc.filename] {
                if existing.markdownContent != doc.content {
                    existing.markdownContent = doc.content
                    existing.title = doc.title
                    existing.updatedAt = doc.updatedAt
                }
            } else {
                let record = UserWikiDocumentRecord(
                    filename: doc.filename,
                    title: doc.title,
                    markdownContent: doc.content,
                    updatedAt: doc.updatedAt
                )
                modelContext.insert(record)
            }
        }
        
        let allowedFilenames = Set(allDocs.map(\.filename))
        for record in existingRecords {
            if !allowedFilenames.contains(record.filename) {
                modelContext.delete(record)
            }
        }

        // M6：白名单外的孤儿 .md（改名/历史版本/手放文件）从未被加载、删除或同步。
        // 不擅自删除用户文件，只记录日志便于诊断导出时发现。
        let directory = WikiFileService.localURL(for: "profile.md").deletingLastPathComponent()
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) {
            for url in contents where url.pathExtension.lowercased() == "md" {
                if !allowedFilenames.contains(url.lastPathComponent) {
                    logger.warning("Orphaned wiki file ignored (not in whitelist): \(url.lastPathComponent)")
                }
            }
        }

        modelContext.saveOrRecordFailure("modelContext.save")
    }

    /// M8：「写透」helper——写 wiki 文件后立即同步 SwiftData 记录缓存，
    /// 消除「打开页面前恰好 sync」才能自愈的潜伏漂移。
    /// 所有写文件入口（materializer / UpdateUserProfileTool / 设置页）统一走这里。
    @discardableResult
    static func writeFileThrough(
        filename: String,
        content: String,
        mode: WikiUpdateMode,
        modelContext: ModelContext
    ) throws -> Bool {
        let changed = try WikiFileService.updateSection(filename: filename, content: content, mode: mode)
        if changed {
            sync(modelContext: modelContext)
        }
        return changed
    }
}

// MARK: - 建档资料落盘

/// 建档资料此前只存 SwiftData（OnboardingState），wiki 档案页因此显示空模板。
/// 本工具把建档收集的目标/训练方式/设备/教练风格写入对应 wiki 文件——
/// 仅当本地文件「未初始化」（空或仍是空模板）时写入，用户手改内容绝不覆盖。
/// 同时把 UserDefaults 维护的生理档案（年龄/体重/身高/最大心率/性别）
/// 合并进 profile.md，打通 Coach 档案维护与健康档案页。
@MainActor
enum WikiProfileMaterializer {
    static func materializeIfNeeded(modelContext: ModelContext) {
        if let onboarding = (try? OnboardingRepository(modelContext: modelContext).fetchLatest()) ?? nil {
            materializeProfileIfLocalEmpty(onboarding, modelContext: modelContext)
            materializePreferencesIfLocalEmpty(onboarding, modelContext: modelContext)
            materializeHabitsIfLocalEmpty(onboarding, modelContext: modelContext)
            materializeTrainingHistoryIfLocalEmpty(onboarding, modelContext: modelContext)
        }
        refreshPhysiologicalProfile(modelContext: modelContext)
    }

    /// 生理档案同步：UserDefaults（手动录入 / agent 经 update_user_profile 维护）
    /// 是生理字段的事实来源。只更新 profile.md 中对应标签行，其余内容一律保留。
    /// M8：写入后同步 SwiftData 记录缓存（modelContext 提供时）。
    static func refreshPhysiologicalProfile(
        defaults: UserDefaults = .standard,
        modelContext: ModelContext? = nil
    ) {
        let filename = "profile.md"
        let content = WikiFileService.localContent(for: filename)

        var updates: [(aliases: [String], line: String)] = []
        // 联通专项批次 2：清空手填字段时删除 wiki 对应行——此前只写不删，
        // 清空后陈旧值会在 HealthKit 也缺失时经 getAgeFromWiki 复活。
        var removals: [[String]] = []
        if let age = UserProfileSettings.age(defaults: defaults) {
            updates.append((["年龄", "Age"], "- 年龄: \(age)"))
        } else {
            removals.append(["年龄", "Age"])
        }
        if let height = UserProfileSettings.heightCentimeters(defaults: defaults) {
            updates.append((["身高", "Height"], "- 身高: \(formatNumber(height)) cm"))
        } else {
            removals.append(["身高", "Height"])
        }
        if let weight = UserProfileSettings.weightKilograms(defaults: defaults) {
            updates.append((["体重", "Weight"], "- 体重: \(formatNumber(weight)) kg"))
        } else {
            removals.append(["体重", "Weight"])
        }
        if let maxHR = UserProfileSettings.maxHeartRate(defaults: defaults) {
            updates.append((["最大心率", "Max heart rate", "Max HR"], "- 最大心率: \(Int(maxHR)) bpm"))
        } else {
            removals.append(["最大心率", "Max heart rate", "Max HR"])
        }
        if let sex = UserProfileSettings.biologicalSex(defaults: defaults) {
            updates.append((["性别", "Sex"], "- 性别: \(sexLabel(sex))"))
        } else {
            removals.append(["性别", "Sex"])
        }
        guard !updates.isEmpty || !removals.isEmpty else { return }

        var updated = content
        for aliases in removals {
            updated = removeBullets(in: updated, aliases: aliases)
        }
        updated = upsertBullets(in: updated, updates: updates)
        let hasHeading = updated.components(separatedBy: .newlines)
            .contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") })
        if !hasHeading {
            updated = "# 个人档案\n\n" + updated
        }
        guard updated != content else { return }
        if let modelContext {
            _ = try? WikiSyncManager.writeFileThrough(
                filename: filename,
                content: updated,
                mode: .replace,
                modelContext: modelContext
            )
        } else {
            _ = try? WikiFileService.updateSection(filename: filename, content: updated, mode: .replace)
        }
    }

    private static func sexLabel(_ sex: String) -> String {
        switch sex {
        case "male": return "男"
        case "female": return "女"
        default: return "其他"
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    private static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    /// 联通专项批次 2：删除命中别名（中英文标签均可）的条目行。
    private static func removeBullets(in content: String, aliases: [String]) -> String {
        let aliasSet = Set(aliases.map(normalizeKey))
        return content.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return true }
                let body = String(trimmed.dropFirst(2))
                guard let separatorIndex = body.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return true }
                let key = normalizeKey(String(body[..<separatorIndex]))
                return !aliasSet.contains(key)
            }
            .joined(separator: "\n")
    }

    /// 按标签 upsert 条目：命中（中英文标签均可）则整行替换，未命中则插入到
    /// 第一个 "##" 小节之前（没有小节则追加到末尾）。
    private static func upsertBullets(
        in content: String,
        updates: [(aliases: [String], line: String)]
    ) -> String {
        var lines = content.components(separatedBy: .newlines)
        let aliasSets = updates.map { Set($0.aliases.map(normalizeKey)) }
        var replaced = Set<Int>()

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { continue }
            let body = String(trimmed.dropFirst(2))
            guard let separatorIndex = body.firstIndex(where: { $0 == ":" || $0 == "：" }) else { continue }
            let key = normalizeKey(String(body[..<separatorIndex]))
            for (updateIndex, aliases) in aliasSets.enumerated() where !replaced.contains(updateIndex) {
                if aliases.contains(key) {
                    lines[index] = updates[updateIndex].line
                    replaced.insert(updateIndex)
                    break
                }
            }
        }

        let missing = updates.indices.filter { !replaced.contains($0) }
        if !missing.isEmpty {
            if let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ") }) {
                lines.insert(contentsOf: missing.map { updates[$0].line }, at: max(0, sectionIndex - 1))
            } else {
                while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    lines.removeLast()
                }
                lines.append(contentsOf: missing.map { updates[$0].line })
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func label(_ key: String) -> String {
        switch key {
        case "performance": return "运动表现"
        case "muscle_gain": return "增肌"
        case "fat_loss": return "减脂"
        case "health": return "健康维持"
        case "strength": return "力量训练"
        case "hybrid": return "混合训练"
        case "endurance": return "耐力训练"
        case "beginner": return "初级"
        case "intermediate": return "中级"
        case "advanced": return "高级"
        case "direct": return "直截了当"
        case "balanced": return "平衡适中"
        case "explanatory": return "详细解析"
        case "gym": return "健身房"
        case "home_equipment": return "家庭器械"
        case "bodyweight": return "自重"
        default: return key
        }
    }

    private static func materializeProfileIfLocalEmpty(_ onboarding: OnboardingState, modelContext: ModelContext) {
        guard WikiFileService.isUninitialized("profile.md") else { return }
        let goal = onboarding.goalProfile
        let training = onboarding.trainingPreference
        let equipment = onboarding.equipmentProfile
        let coaching = onboarding.coachingPreference
        let lines = [
            "# 个人档案",
            "",
            "- 主要目标: \(label(goal.primaryGoal))",
            "- 经验水平: \(label(goal.experienceLevel))",
            "- 训练风格: \(label(training.trainingStyle))",
            "- 每周训练: \(training.weeklyTrainingDays) 次，每次 \(training.sessionDurationMinutes) 分钟",
            "- 设备: \(equipment.equipment.map(label).joined(separator: "、"))",
            "- 教练风格: \(label(coaching.style))",
        ]
        _ = try? WikiSyncManager.writeFileThrough(
            filename: "profile.md",
            content: lines.joined(separator: "\n"),
            mode: .replace,
            modelContext: modelContext
        )
    }

    private static func materializePreferencesIfLocalEmpty(_ onboarding: OnboardingState, modelContext: ModelContext) {
        guard WikiFileService.isUninitialized("preferences.md") else { return }
        let training = onboarding.trainingPreference
        let coaching = onboarding.coachingPreference
        let lines = [
            "# 偏好",
            "",
            "- 训练风格: \(label(training.trainingStyle))",
            "- 沟通风格: \(label(coaching.style))",
            "- 训练频次: 每周 \(training.weeklyTrainingDays) 次",
        ]
        _ = try? WikiSyncManager.writeFileThrough(
            filename: "preferences.md",
            content: lines.joined(separator: "\n"),
            mode: .replace,
            modelContext: modelContext
        )
    }

    private static func materializeHabitsIfLocalEmpty(_ onboarding: OnboardingState, modelContext: ModelContext) {
        guard WikiFileService.isUninitialized("habits.md") else { return }
        let training = onboarding.trainingPreference
        let equipment = onboarding.equipmentProfile
        let lines = [
            "# 生活习惯",
            "",
            "- 训练节奏: 每周 \(training.weeklyTrainingDays) 次，每次约 \(training.sessionDurationMinutes) 分钟",
            "- 训练设备: \(equipment.equipment.map(label).joined(separator: "、"))",
            "- 咖啡因: ",
            "- 酒精: ",
            "- 晚间作息: ",
        ]
        _ = try? WikiSyncManager.writeFileThrough(
            filename: "habits.md",
            content: lines.joined(separator: "\n"),
            mode: .replace,
            modelContext: modelContext
        )
    }

    private static func materializeTrainingHistoryIfLocalEmpty(_ onboarding: OnboardingState, modelContext: ModelContext) {
        guard WikiFileService.isUninitialized("training_history.md") else { return }
        let training = onboarding.trainingPreference
        let lines = [
            "# 训练历史",
            "",
            "- 典型每周训练量: \(training.weeklyTrainingDays) 次 × \(training.sessionDurationMinutes) 分钟",
            "- 偏好的训练类型: \(label(training.trainingStyle))",
        ]
        _ = try? WikiSyncManager.writeFileThrough(
            filename: "training_history.md",
            content: lines.joined(separator: "\n"),
            mode: .replace,
            modelContext: modelContext
        )
    }
}
