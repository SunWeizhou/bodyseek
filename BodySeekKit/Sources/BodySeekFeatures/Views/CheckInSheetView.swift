import SwiftUI

public struct CheckInSheetView: View {
    public let currentFeeling: Int?
    public let onSelect: (Int) -> Void
    public let onDismiss: () -> Void

    private let options: [(score: Int, title: String, note: String)] = [
        (5, "精力充沛", "精神饱满，适合高质量训练"),
        (4, "状态不错", "步调轻松，按常规推进即可"),
        (3, "整体平稳", "没有明显疲惫感，正常作息"),
        (2, "有些发沉", "建议放慢节奏或做小幅减量"),
        (1, "明显疲劳", "优先补觉与主动恢复"),
    ]

    public init(
        currentFeeling: Int?,
        onSelect: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.currentFeeling = currentFeeling
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("今天主观感觉如何？") {
                    ForEach(options, id: \.score) { item in
                        Button {
                            onSelect(item.score)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BevelTheme.ink)
                                    Text(item.note)
                                        .font(.caption)
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                }
                                Spacer()
                                if currentFeeling == item.score {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(BevelTheme.brand)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("今日体感记录")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("关闭", action: onDismiss)
                }
            }
        }
    }
}
