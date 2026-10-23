import SwiftUI
import SwiftData

@MainActor
final class CoachSessionStore: ObservableObject {
    @Published var sessions: [CoachSessionRecord] = []
    @Published var currentSession: CoachSessionRecord?
    @Published var persistenceError: String?
    /// 流式/前台重试中被守卫拦截的会话操作提示（短暂展示）。
    @Published var interactionHint: String?

    init() {}

    func loadSessions(modelContext: ModelContext, isStreaming: Bool, isAwaitingForegroundRetry: Bool, messagesHandler: ([CoachChatVM.ChatMsg]) -> Void) {
        let list = (try? CoachSessionRepository(modelContext: modelContext).fetchUnarchived()) ?? []
        self.sessions = list
        
        if list.isEmpty {
            let defaultSession = CoachSessionRecord(
                id: UUID(),
                title: "新对话",
                createdAt: Date(),
                updatedAt: Date(),
                serializedMessages: "[]"
            )
            modelContext.insert(defaultSession)
            do {
                try modelContext.save()
                self.sessions = [defaultSession]
                self.currentSession = defaultSession
                messagesHandler([])
            } catch {
                modelContext.rollback()
                persistenceError = "无法创建本地对话。请稍后重试。"
            }
        } else if self.currentSession == nil {
            self.currentSession = list.first
        }
        
        guard !isStreaming, !isAwaitingForegroundRetry else {
            interactionHint = "正在回复中，完成后即可操作会话。"
            return
        }

        if let currentSession {
            if let data = currentSession.serializedMessages.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([CoachChatVM.ChatMsg].self, from: data) {
                messagesHandler(decoded)
            } else {
                messagesHandler([])
            }
        }
    }

    func createNewSession(modelContext: ModelContext, isStreaming: Bool, isAwaitingForegroundRetry: Bool, messagesHandler: ([CoachChatVM.ChatMsg]) -> Void) {
        // 流式中新建会话会导致完成时的 persistThread 把在途问答写进新会话、
        // 或清空 UI 后回复凭空消失——与 selectSession 同一守卫，拒绝切换。
        guard !isStreaming, !isAwaitingForegroundRetry else {
            interactionHint = "正在回复中，完成后即可操作会话。"
            return
        }
        let newSession = CoachSessionRecord(
            id: UUID(),
            title: "新对话",
            createdAt: Date(),
            updatedAt: Date(),
            serializedMessages: "[]"
        )
        modelContext.insert(newSession)
        do {
            try modelContext.save()
            loadSessions(modelContext: modelContext, isStreaming: isStreaming, isAwaitingForegroundRetry: isAwaitingForegroundRetry, messagesHandler: messagesHandler)
            self.currentSession = newSession
            messagesHandler([])
        } catch {
            modelContext.rollback()
            persistenceError = "无法创建新对话。请稍后重试。"
        }
    }

    func selectSession(_ session: CoachSessionRecord, modelContext: ModelContext, isStreaming: Bool, isAwaitingForegroundRetry: Bool, messagesHandler: ([CoachChatVM.ChatMsg]) -> Void) {
        // Don't swap to another session while a reply is streaming: the messages
        // array was already loaded and the in-flight stream writes to the old
        // session's indices, so switching would orphan the completed response.
        guard !isStreaming, !isAwaitingForegroundRetry else {
            interactionHint = "正在回复中，完成后即可操作会话。"
            return
        }
        self.currentSession = session
        if let data = session.serializedMessages.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([CoachChatVM.ChatMsg].self, from: data) {
            messagesHandler(decoded)
        } else {
            messagesHandler([])
        }
        loadSessions(modelContext: modelContext, isStreaming: isStreaming, isAwaitingForegroundRetry: isAwaitingForegroundRetry, messagesHandler: messagesHandler)
    }

    func deleteSession(_ session: CoachSessionRecord, modelContext: ModelContext, isStreaming: Bool, isAwaitingForegroundRetry: Bool, messagesHandler: ([CoachChatVM.ChatMsg]) -> Void) {
        // 流式中删除当前会话：完成后 persistThread 会写进 loadSessions 自动选中的
        // 另一个会话并覆盖其历史（旧历史全部丢失）——与 selectSession 同一守卫。
        guard !isStreaming, !isAwaitingForegroundRetry else {
            interactionHint = "正在回复中，完成后即可操作会话。"
            return
        }
        modelContext.delete(session)
        do {
            try modelContext.save()
            if currentSession?.id == session.id {
                currentSession = nil
            }
            loadSessions(modelContext: modelContext, isStreaming: isStreaming, isAwaitingForegroundRetry: isAwaitingForegroundRetry, messagesHandler: messagesHandler)
        } catch {
            modelContext.rollback()
            persistenceError = "对话未删除。请稍后重试。"
        }
    }

    func renameSession(_ session: CoachSessionRecord, to newTitle: String, modelContext: ModelContext, isStreaming: Bool, isAwaitingForegroundRetry: Bool, messagesHandler: ([CoachChatVM.ChatMsg]) -> Void) {
        let previousTitle = session.title
        let previousUpdatedAt = session.updatedAt
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        session.title = trimmed.isEmpty ? "新对话" : trimmed
        session.updatedAt = Date()
        do {
            try modelContext.save()
            loadSessions(modelContext: modelContext, isStreaming: isStreaming, isAwaitingForegroundRetry: isAwaitingForegroundRetry, messagesHandler: messagesHandler)
        } catch {
            modelContext.rollback()
            session.title = previousTitle
            session.updatedAt = previousUpdatedAt
            persistenceError = "对话标题未保存。请稍后重试。"
        }
    }
}
