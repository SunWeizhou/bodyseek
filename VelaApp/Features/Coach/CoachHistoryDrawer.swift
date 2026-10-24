import SwiftUI
import SwiftData

// MARK: - CoachHistoryDrawer

struct CoachHistoryDrawer: View {
    @ObservedObject var vm: CoachChatVM
    let modelContext: ModelContext
    @Binding var showHistoryDrawer: Bool
    @Binding var renamingSession: CoachSessionRecord?
    @Binding var renameText: String
    @Binding var isRenamingSession: Bool
    @Binding var sessionPendingDeletion: CoachSessionRecord?
    @State private var searchText = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var filteredSessions: [CoachSessionRecord] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return vm.sessions
        }
        return vm.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.serializedMessages.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drawer Header
            HStack {
                Text("历史对话")
                    .font(VelaTheme.body().weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Button {
                    showHistoryDrawer = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .frame(width: VelaTheme.minimumHitTarget, height: VelaTheme.minimumHitTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.cardPress)
                .accessibilityLabel("关闭对话历史")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            
            // New Chat Button
            Button {
                vm.createNewSession(modelContext: modelContext)
                showHistoryDrawer = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("新建对话")
                        .font(VelaTheme.footnote().weight(.bold))
                }
                .foregroundStyle(VelaTheme.rhythmDeepOn)
                .frame(maxWidth: .infinity)
                .frame(minHeight: VelaTheme.minimumHitTarget)
                .background(Capsule().fill(VelaTheme.rhythmDeep))
            }
            .buttonStyle(.cardPress)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                TextField("搜索标题或对话内容", text: $searchText)
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                    .fill(VelaTheme.rhythmCanvasRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            Rectangle()
                .fill(VelaTheme.hairline)
                .frame(height: VelaTheme.hairlineWidth)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            
            // Sessions Scroll List
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(filteredSessions) { session in
                        HStack(spacing: 12) {
                            Button {
                                vm.selectSession(session, modelContext: modelContext)
                                showHistoryDrawer = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(vm.currentSession?.id == session.id ? VelaTheme.rhythmDeep : VelaTheme.rhythmInkSecondary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title.isEmpty ? "新对话" : session.title)
                                            .font(VelaTheme.footnote().weight(.bold))
                                            .foregroundStyle(VelaTheme.rhythmInk)
                                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Text(session.updatedAt.formatted(.dateTime.month().day().hour().minute()))
                                            .font(VelaTheme.caption2().weight(.semibold))
                                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(session.title.isEmpty ? "新对话" : session.title)
                            .accessibilityValue(vm.currentSession?.id == session.id ? "当前对话" : "")
                            
                            if vm.currentSession?.id == session.id {
                                Button {
                                    renamingSession = session
                                    renameText = session.title
                                    isRenamingSession = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12))
                                        .foregroundStyle(VelaTheme.rhythmDeep)
                                        .frame(width: VelaTheme.minimumHitTarget, height: VelaTheme.minimumHitTarget)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.cardPress)
                                .accessibilityLabel("重命名\(session.title.isEmpty ? "新对话" : session.title)")
                                
                                Button {
                                    sessionPendingDeletion = session
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(VelaTheme.rhythmInk)
                                        .frame(width: VelaTheme.minimumHitTarget, height: VelaTheme.minimumHitTarget)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.cardPress)
                                .accessibilityLabel("删除\(session.title.isEmpty ? "新对话" : session.title)")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                                .fill(vm.currentSession?.id == session.id ? VelaTheme.rhythmCanvasRaised : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                                        .stroke(
                                            vm.currentSession?.id == session.id ? VelaTheme.rhythmInk : Color.clear,
                                            lineWidth: VelaTheme.hairlineWidth
                                        )
                                )
                        )
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Drawer Footer
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(VelaTheme.rhythmDeep)
                        .frame(width: 34, height: 34)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("本机健康资料")
                        .font(VelaTheme.footnote().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text("本机优先存储")
                        .font(VelaTheme.caption2().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(VelaTheme.rhythmCanvasRaised)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VelaTheme.rhythmCanvas)
    }
}
