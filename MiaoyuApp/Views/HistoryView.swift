import SwiftUI

/// 会话历史：按 updatedAt 倒序的会话列表 → 只读回看；左滑删除；一键清空（带确认）
struct HistoryView: View {

    @State private var conversations: [Conversation] = []
    @State private var showingClearConfirm = false

    var body: some View {
        Group {
            if conversations.isEmpty {
                // 空态
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 42))
                        .foregroundStyle(.tertiary)
                    Text("还没有会话记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(conversations) { conversation in
                        NavigationLink {
                            HistoryDetailView(conversation: conversation)
                        } label: {
                            row(for: conversation)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                ConversationStore.shared.delete(id: conversation.id)
                                reload()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("历史")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(conversations.isEmpty)
            }
        }
        .onAppear(perform: reload)
        .alert("清空全部历史？", isPresented: $showingClearConfirm) {
            Button("清空", role: .destructive) {
                ConversationStore.shared.clearAll()
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有会话记录将被删除，无法恢复。")
        }
    }

    // MARK: 逻辑

    private func reload() {
        conversations = ConversationStore.shared.all()   // 契约保证倒序
    }

    /// 单行：标题 + 最后一条消息预览 + 相对时间
    private func row(for conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conversation.title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            HStack {
                Text(conversation.messages.last?.content ?? "（空会话）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 会话只读回看

/// 会话只读回看：复用 ChatBubbleView 气泡组件（无收藏菜单）
struct HistoryDetailView: View {

    let conversation: Conversation

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(conversation.messages) { message in
                    ChatBubbleView(message: message)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
}
