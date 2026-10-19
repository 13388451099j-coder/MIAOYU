import SwiftUI
import UIKit

// MARK: - 气泡组件（改写页与历史回看共用）

/// 单条消息气泡
/// - user 气泡：右对齐、灰底
/// - assistant 气泡：左对齐、蓝底白字
/// - 长按弹出菜单：复制 / 收藏切换
struct ChatBubbleView: View {

    let message: ChatMessage

    /// 收藏切换回调；nil 表示只读模式（历史回看），菜单里不显示收藏项
    var onToggleFavorite: (() -> Void)? = nil

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isUser { Spacer(minLength: 48) }

            HStack(alignment: .top, spacing: 6) {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(isUser ? Color.primary : Color.white)
                    .textSelection(.enabled)
                if message.isFavorite {
                    // 已收藏星标
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(isUser ? Color.yellow : Color.yellow)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isUser ? Color(uiColor: .systemGray5) : Color.blue)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contextMenu {
                // 复制正文
                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                // 收藏 / 取消收藏（只读模式不提供）
                if let onToggleFavorite {
                    Button {
                        onToggleFavorite()
                    } label: {
                        Label(
                            message.isFavorite ? "取消收藏" : "收藏",
                            systemImage: message.isFavorite ? "star.slash" : "star"
                        )
                    }
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - 改写主界面

/// 改写主界面：顶部人设胶囊选择 + 对话气泡流 + 底部输入区
///
/// 功能：
/// - 发送原话 → 按当前人设调 AiService.rewrite 改写
/// - 「再来一版」：重发最后一条 user 消息，替换最后一条 assistant 消息
/// - 「沟通三策略」：对最后输入内容生成三种风格回复，点选填回输入框
/// - 每次 AI 回复后自动保存会话到 ConversationStore
struct ChatRewriteView: View {

    @EnvironmentObject private var appState: AppState

    // MARK: 状态

    /// 当前会话（nil 表示尚未产生任何 AI 回复，还未落盘）
    @State private var conversation: Conversation?
    /// 当前气泡流消息
    @State private var messages: [ChatMessage] = []
    /// 输入框文本
    @State private var inputText: String = ""
    /// AI 请求进行中
    @State private var isThinking = false
    /// 错误提示（非 nil 弹 alert）
    @State private var errorMessage: String?
    /// 人设列表
    @State private var personas: [Persona] = []
    /// 当前激活人设 id（胶囊高亮用）
    @State private var activePersonaId: String = ""
    /// 沟通三策略结果
    @State private var strategies: [StrategyResult] = []
    @State private var showingStrategies = false
    @State private var isLoadingStrategies = false

    // MARK: 计算属性

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 输入框为空或请求中时，发送按钮禁用
    private var canSend: Bool { !trimmedInput.isEmpty && !isThinking }

    /// 存在 user 消息且不在请求中，才允许「再来一版」
    private var canRegenerate: Bool {
        !isThinking && messages.contains(where: { $0.role == .user })
    }

    /// 三策略的输入源：优先输入框，其次最后一条 user 消息，再次最后一条消息
    private var strategySourceText: String {
        if !trimmedInput.isEmpty { return trimmedInput }
        if let lastUser = messages.last(where: { $0.role == .user }) {
            return lastUser.content
        }
        return messages.last?.content ?? ""
    }

    private var canStrategize: Bool {
        !strategySourceText.isEmpty && !isThinking && !isLoadingStrategies
    }

    // MARK: 视图

    var body: some View {
        VStack(spacing: 0) {
            personaBar
            Divider()
            messageList
            Divider()
            inputBar
        }
        .navigationTitle("改写")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: handleAppear)
        .alert(
            "出错了",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingStrategies) {
            strategySheet
        }
    }

    /// 顶部人设横向胶囊选择
    private var personaBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(personas) { persona in
                    let isActive = persona.id == activePersonaId
                    Button {
                        // 切换激活人设
                        PersonaStore.shared.setActive(id: persona.id)
                        activePersonaId = persona.id
                    } label: {
                        Text(persona.name)
                            .font(.subheadline.weight(isActive ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    isActive ? Color.blue : Color(uiColor: .secondarySystemFill)
                                )
                            )
                            .foregroundStyle(isActive ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    /// 中部气泡流
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if messages.isEmpty && !isThinking {
                        emptyHint
                    }
                    ForEach(messages) { message in
                        ChatBubbleView(message: message) {
                            toggleFavorite(message)
                        }
                        .id(message.id)
                    }
                    if isThinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("妙语正在想…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .id("thinkingIndicator")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isThinking) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    /// 空态提示
    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("把想说的话丢进来，妙语帮你换个说法")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
        .padding(.horizontal)
    }

    /// 底部输入区：工具条（再来一版 / 沟通三策略）+ 输入框与发送
    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button {
                    regenerate()
                } label: {
                    Label("再来一版", systemImage: "arrow.clockwise")
                }
                .disabled(!canRegenerate)

                Spacer()

                if isLoadingStrategies {
                    ProgressView()
                }
                Button {
                    loadStrategies()
                } label: {
                    Label("沟通三策略", systemImage: "square.split.3x1")
                }
                .disabled(!canStrategize)
            }
            .font(.subheadline)
            .padding(.horizontal)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("输入你的原话…", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(.white)
                        .padding(11)
                        .background(
                            Circle().fill(canSend ? Color.blue : Color.gray)
                        )
                }
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }

    /// 沟通三策略结果弹层：三张卡片，点选把内容填回输入框
    private var strategySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(strategies.enumerated()), id: \.offset) { _, result in
                        Button {
                            inputText = result.content
                            showingStrategies = false
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(result.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(result.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("沟通三策略")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingStrategies = false }
                }
            }
        }
    }

    // MARK: 逻辑

    /// 进入页面：刷新人设、消费 OCR 送来的待改写文本
    private func handleAppear() {
        personas = PersonaStore.shared.all()
        activePersonaId = PersonaStore.shared.active.id
        if !appState.pendingRewriteText.isEmpty {
            inputText = appState.pendingRewriteText
            appState.pendingRewriteText = ""
        }
    }

    /// 滚动到底部
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            } else if isThinking {
                proxy.scrollTo("thinkingIndicator", anchor: .bottom)
            }
        }
    }

    /// 发送：append user 消息并请求改写
    private func send() {
        let text = trimmedInput
        guard !text.isEmpty, !isThinking else { return }

        let userMessage = ChatMessage(
            id: UUID(), role: .user, content: text,
            createdAt: Date(), isFavorite: false
        )
        // history = 本次 user 消息之前的上下文
        let history = messages
        messages.append(userMessage)
        inputText = ""
        requestRewrite(userInput: text, history: history)
    }

    /// 「再来一版」：重发最后一条 user 消息，替换末尾 assistant 消息
    private func regenerate() {
        guard !isThinking,
              let lastUserIndex = messages.lastIndex(where: { $0.role == .user })
        else { return }

        // 若末尾是 assistant 消息，先移除（实现"替换最后一条"）
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           lastIndex > lastUserIndex {
            messages.remove(at: lastIndex)
        }

        let userMessage = messages[lastUserIndex]
        let history = Array(messages[..<lastUserIndex])
        requestRewrite(userInput: userMessage.content, history: history)
    }

    /// 调 AiService.rewrite；成功后 append assistant 消息并保存会话
    private func requestRewrite(userInput: String, history: [ChatMessage]) {
        isThinking = true
        let persona = PersonaStore.shared.active
        Task { @MainActor in
            do {
                let reply = try await AiService.shared.rewrite(
                    userInput: userInput, persona: persona, history: history
                )
                let assistantMessage = ChatMessage(
                    id: UUID(), role: .assistant, content: reply,
                    createdAt: Date(), isFavorite: false
                )
                messages.append(assistantMessage)
                persist()
            } catch {
                errorMessage = error.localizedDescription
            }
            isThinking = false
        }
    }

    /// 调沟通三策略，成功后弹出三选一
    private func loadStrategies() {
        let source = strategySourceText
        guard !source.isEmpty, !isThinking, !isLoadingStrategies else { return }
        isLoadingStrategies = true
        let persona = PersonaStore.shared.active
        Task { @MainActor in
            do {
                strategies = try await AiService.shared.communicationStrategies(
                    for: source, persona: persona
                )
                showingStrategies = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingStrategies = false
        }
    }

    /// 切换收藏并保存
    private func toggleFavorite(_ message: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index].isFavorite.toggle()
        persist()
    }

    /// 当前会话落盘（每次 AI 回复后调用）
    private func persist() {
        let now = Date()
        if var existing = conversation {
            existing.messages = messages
            existing.updatedAt = now
            existing.personaId = PersonaStore.shared.active.id
            conversation = existing
            ConversationStore.shared.save(existing)
        } else {
            // 会话标题取第一条 user 消息前 20 字
            let titleSource = messages.first(where: { $0.role == .user })?.content ?? "新会话"
            let newConversation = Conversation(
                id: UUID(),
                title: String(titleSource.prefix(20)),
                personaId: PersonaStore.shared.active.id,
                messages: messages,
                createdAt: now,
                updatedAt: now
            )
            conversation = newConversation
            ConversationStore.shared.save(newConversation)
        }
    }
}

#Preview {
    NavigationStack {
        ChatRewriteView()
    }
    .environmentObject(AppState())
}
