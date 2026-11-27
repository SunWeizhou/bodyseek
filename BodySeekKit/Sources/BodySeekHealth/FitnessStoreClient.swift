import BodySeekCore
import BodySeekStore
import Dependencies
import DependenciesMacros
import Foundation
import os
import SwiftData

// MARK: - Lean SwiftData Schema (4 domain models)

@Model
public final class StoredWorkoutTemplate {
    @Attribute(.unique) public var id: UUID
    public var sortOrder: Int
    public var updatedAt: Date
    public var payload: Data

    public init(id: UUID, sortOrder: Int, updatedAt: Date, payload: Data) {
        self.id = id
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

@Model
public final class StoredWorkoutSession {
    @Attribute(.unique) public var id: UUID
    public var completedAt: Date
    public var payload: Data

    public init(id: UUID, completedAt: Date, payload: Data) {
        self.id = id
        self.completedAt = completedAt
        self.payload = payload
    }
}

@Model
public final class StoredAthleteMemory {
    @Attribute(.unique) public var id: UUID
    public var updatedAt: Date
    public var payload: Data

    public init(id: UUID, updatedAt: Date, payload: Data) {
        self.id = id
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

@Model
public final class StoredCoachMessage {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var payload: Data

    public init(id: UUID, timestamp: Date, payload: Data) {
        self.id = id
        self.timestamp = timestamp
        self.payload = payload
    }
}

// MARK: - Container Actor

public actor BodySeekSwiftDataBackend {
    public static let shared = BodySeekSwiftDataBackend()
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "SwiftDataStore")

    private var cachedContainer: ModelContainer?

    private func decodeRows<T: Decodable>(_ payloads: [Data], as type: T.Type, label: String) throws -> [T] {
        let decoder = JSONDecoder()
        do {
            return try payloads.map { try decoder.decode(T.self, from: $0) }
        } catch {
            Self.logger.error("Failed decoding \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private var legacyStoreURL: URL {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseDir
            .appendingPathComponent("BodySeek", isDirectory: true)
            .appendingPathComponent("bodyseek_v3.store")
    }

    private func container() throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        let schema = Schema([
            StoredWorkoutTemplate.self,
            StoredWorkoutSession.self,
            StoredAthleteMemory.self,
            StoredCoachMessage.self,
        ])
        let storeURL = legacyStoreURL
        let folder = storeURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let config = ModelConfiguration(url: storeURL)
        let mc = try ModelContainer(for: schema, configurations: [config])
        cachedContainer = mc
        return mc
    }

    /// Deletes the retained legacy SwiftData store so an explicit reset cannot be
    /// undone by a later migration import.
    public func deleteLegacyStoreIfExists() {
        cachedContainer = nil
        let base = legacyStoreURL
        let manager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: base.path + suffix)
            try? manager.removeItem(at: url)
        }
    }

    /// Reads the legacy SwiftData SQLite file ONLY if it already exists on disk (used once for GRDB migration).
    public nonisolated func exportLegacyPayloadIfStoreExists() throws -> LegacyImportPayload? {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let storeURL = baseDir
            .appendingPathComponent("BodySeek", isDirectory: true)
            .appendingPathComponent("bodyseek_v3.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return nil
        }
        let schema = Schema([
            StoredWorkoutTemplate.self,
            StoredWorkoutSession.self,
            StoredAthleteMemory.self,
            StoredCoachMessage.self,
        ])
        let config = ModelConfiguration(url: storeURL)
        let mc = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(mc)
        let decoder = JSONDecoder()

        let templateRows = try context.fetch(FetchDescriptor<StoredWorkoutTemplate>(sortBy: [SortDescriptor(\.sortOrder)]))
        let sessionRows = try context.fetch(FetchDescriptor<StoredWorkoutSession>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)]))
        let memoryRows = try context.fetch(FetchDescriptor<StoredAthleteMemory>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        let messageRows = try context.fetch(FetchDescriptor<StoredCoachMessage>(sortBy: [SortDescriptor(\.timestamp, order: .forward)]))

        return LegacyImportPayload(
            templates: try templateRows.map { try decoder.decode(WorkoutTemplate.self, from: $0.payload) },
            sessions: try sessionRows.map { try decoder.decode(LoggedWorkoutSession.self, from: $0.payload) },
            memories: try memoryRows.map { try decoder.decode(AthleteMemoryItem.self, from: $0.payload) },
            messages: try messageRows.map { try decoder.decode(CoachMessage.self, from: $0.payload) },
            checkIns: []
        )
    }

    public func loadTemplates() throws -> [WorkoutTemplate] {
        let context = ModelContext(try container())
        let desc = FetchDescriptor<StoredWorkoutTemplate>(sortBy: [SortDescriptor(\.sortOrder)])
        let rows = try context.fetch(desc)
        if rows.isEmpty {
            let defaults = ExerciseCatalog.defaultTemplates
            for (idx, item) in defaults.enumerated() {
                let data = try JSONEncoder().encode(item)
                context.insert(StoredWorkoutTemplate(id: item.id, sortOrder: idx, updatedAt: Date(), payload: data))
            }
            try context.save()
            return defaults
        }
        return try decodeRows(rows.map(\.payload), as: WorkoutTemplate.self, label: "WorkoutTemplate")
    }

    public func saveTemplate(_ template: WorkoutTemplate) throws {
        let context = ModelContext(try container())
        let data = try JSONEncoder().encode(template)
        let targetID = template.id
        let desc = FetchDescriptor<StoredWorkoutTemplate>(predicate: #Predicate { $0.id == targetID })
        if let existing = try context.fetch(desc).first {
            existing.payload = data
            existing.updatedAt = Date()
        } else {
            let count = try context.fetchCount(FetchDescriptor<StoredWorkoutTemplate>())
            context.insert(StoredWorkoutTemplate(id: template.id, sortOrder: count, updatedAt: Date(), payload: data))
        }
        try context.save()
    }

    public func loadSessions() throws -> [LoggedWorkoutSession] {
        let context = ModelContext(try container())
        let desc = FetchDescriptor<StoredWorkoutSession>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        let rows = try context.fetch(desc)
        return try decodeRows(rows.map(\.payload), as: LoggedWorkoutSession.self, label: "LoggedWorkoutSession")
    }

    public func saveSession(_ session: LoggedWorkoutSession) throws {
        let context = ModelContext(try container())
        let data = try JSONEncoder().encode(session)
        let targetID = session.id
        let desc = FetchDescriptor<StoredWorkoutSession>(predicate: #Predicate { $0.id == targetID })
        if let existing = try context.fetch(desc).first {
            existing.payload = data
            existing.completedAt = session.completedAt
        } else {
            context.insert(StoredWorkoutSession(id: session.id, completedAt: session.completedAt, payload: data))
        }
        try context.save()
    }

    public func loadMemories() throws -> [AthleteMemoryItem] {
        let context = ModelContext(try container())
        let desc = FetchDescriptor<StoredAthleteMemory>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let rows = try context.fetch(desc)
        return try decodeRows(rows.map(\.payload), as: AthleteMemoryItem.self, label: "AthleteMemoryItem")
    }

    public func saveMemory(_ item: AthleteMemoryItem) throws {
        let context = ModelContext(try container())
        let data = try JSONEncoder().encode(item)
        let targetID = item.id
        let desc = FetchDescriptor<StoredAthleteMemory>(predicate: #Predicate { $0.id == targetID })
        if let existing = try context.fetch(desc).first {
            existing.payload = data
            existing.updatedAt = item.updatedAt
        } else {
            context.insert(StoredAthleteMemory(id: item.id, updatedAt: item.updatedAt, payload: data))
        }
        try context.save()
    }

    public func deleteMemory(id: UUID) throws {
        let context = ModelContext(try container())
        let desc = FetchDescriptor<StoredAthleteMemory>(predicate: #Predicate { $0.id == id })
        for item in try context.fetch(desc) {
            context.delete(item)
        }
        try context.save()
    }

    public func loadMessages() throws -> [CoachMessage] {
        let context = ModelContext(try container())
        let desc = FetchDescriptor<StoredCoachMessage>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        let rows = try context.fetch(desc)
        return try decodeRows(rows.map(\.payload), as: CoachMessage.self, label: "CoachMessage")
    }

    public func appendMessage(_ msg: CoachMessage) throws {
        let context = ModelContext(try container())
        let data = try JSONEncoder().encode(msg)
        context.insert(StoredCoachMessage(id: msg.id, timestamp: msg.timestamp, payload: data))
        try context.save()
    }

    public func clearMessages() throws {
        let context = ModelContext(try container())
        for item in try context.fetch(FetchDescriptor<StoredCoachMessage>()) {
            context.delete(item)
        }
        try context.save()
    }

    public func resetAll() throws {
        let context = ModelContext(try container())
        for item in try context.fetch(FetchDescriptor<StoredWorkoutTemplate>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<StoredWorkoutSession>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<StoredAthleteMemory>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<StoredCoachMessage>()) { context.delete(item) }
        try context.save()
    }
}

// MARK: - TCA DependencyClient

@DependencyClient
public struct FitnessStoreClient: Sendable {
    public var loadTemplates: @Sendable () async throws -> [WorkoutTemplate] = { ExerciseCatalog.defaultTemplates }
    public var saveTemplate: @Sendable (_ template: WorkoutTemplate) async throws -> Void
    public var loadSessions: @Sendable () async throws -> [LoggedWorkoutSession] = { [] }
    public var saveSession: @Sendable (_ session: LoggedWorkoutSession) async throws -> Void
    public var loadMemories: @Sendable () async throws -> [AthleteMemoryItem] = { [] }
    public var saveMemory: @Sendable (_ item: AthleteMemoryItem) async throws -> Void
    public var deleteMemory: @Sendable (_ id: UUID) async throws -> Void
    public var loadMessages: @Sendable () async throws -> [CoachMessage] = { [] }
    public var appendMessage: @Sendable (_ message: CoachMessage) async throws -> Void
    public var clearMessages: @Sendable () async throws -> Void
    public var resetAll: @Sendable () async throws -> Void
}

extension FitnessStoreClient: DependencyKey {
    public static let liveValue: FitnessStoreClient = {
        let preview = InMemoryPreviewStore()
        @Sendable func grdbRepository() async throws -> BodySeekRepository {
            _ = try await BodySeekSharedStore.shared.ensureLegacyMigratedIfNeeded()
            return try await BodySeekSharedStore.shared.repository()
        }

        return FitnessStoreClient(
            loadTemplates: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    return await preview.templates
                }
                return try await grdbRepository().loadTemplates()
            },
            saveTemplate: { template in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    await preview.saveTemplate(template)
                    return
                }
                try await grdbRepository().saveTemplate(template)
            },
            loadSessions: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    return await preview.sessions
                }
                return try await grdbRepository().loadSessions()
            },
            saveSession: { session in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    await preview.saveSession(session)
                    return
                }
                try await grdbRepository().saveSession(session)
            },
            loadMemories: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    return await preview.memories
                }
                return try await grdbRepository().loadAthleteMemories()
            },
            saveMemory: { item in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    await preview.saveMemory(item)
                    return
                }
                try await grdbRepository().saveAthleteMemory(item)
            },
            deleteMemory: { id in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    await preview.deleteMemory(id: id)
                    return
                }
                try await grdbRepository().deleteMemory(id: id)
            },
            loadMessages: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    return await preview.messages
                }
                return try await grdbRepository().loadMessages()
            },
            appendMessage: { msg in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    await preview.appendMessage(msg)
                    return
                }
                try await grdbRepository().appendMessage(msg)
            },
            clearMessages: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    await preview.clearMessages()
                    return
                }
                try await grdbRepository().clearMessages()
            },
            resetAll: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard") {
                    await preview.reset()
                    return
                }
                try await BodySeekSharedStore.shared.resetAll()
            }
        )
    }()

    public static let previewValue: FitnessStoreClient = {
        let store = InMemoryPreviewStore()
        return FitnessStoreClient(
            loadTemplates: { await store.templates },
            saveTemplate: { await store.saveTemplate($0) },
            loadSessions: { await store.sessions },
            saveSession: { await store.saveSession($0) },
            loadMemories: { await store.memories },
            saveMemory: { await store.saveMemory($0) },
            deleteMemory: { await store.deleteMemory(id: $0) },
            loadMessages: { await store.messages },
            appendMessage: { await store.appendMessage($0) },
            clearMessages: { await store.clearMessages() },
            resetAll: { await store.reset() }
        )
    }()
}

private actor InMemoryPreviewStore {
    var templates: [WorkoutTemplate] = ExerciseCatalog.defaultTemplates
    var sessions: [LoggedWorkoutSession] = PreviewSeedFactory.makeSampleLoggedWorkouts()
    var memories: [AthleteMemoryItem] = [
        AthleteMemoryItem(category: .preference, content: "习惯早上训练，周末偏好长距离慢跑"),
    ]
    var messages: [CoachMessage] = []

    func saveTemplate(_ t: WorkoutTemplate) {
        if let idx = templates.firstIndex(where: { $0.id == t.id }) {
            templates[idx] = t
        } else {
            templates.append(t)
        }
    }

    func saveSession(_ s: LoggedWorkoutSession) {
        sessions.insert(s, at: 0)
    }

    func saveMemory(_ m: AthleteMemoryItem) {
        if let idx = memories.firstIndex(where: { $0.id == m.id }) {
            memories[idx] = m
        } else {
            memories.insert(m, at: 0)
        }
    }

    func deleteMemory(id: UUID) {
        memories.removeAll { $0.id == id }
    }

    func appendMessage(_ msg: CoachMessage) {
        messages.append(msg)
    }

    func clearMessages() {
        messages.removeAll()
    }

    func reset() {
        templates = ExerciseCatalog.defaultTemplates
        sessions = []
        memories = []
        messages = []
    }
}

public extension DependencyValues {
    var fitnessStoreClient: FitnessStoreClient {
        get { self[FitnessStoreClient.self] }
        set { self[FitnessStoreClient.self] = newValue }
    }
}
