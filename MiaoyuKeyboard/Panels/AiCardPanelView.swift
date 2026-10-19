import SwiftUI

/// AI 卡片面板：「润色本条」（替换输入框最后一句）与「沟通三策略」（直接追加，不动原文）。
///
/// - 输入来源：textDocumentProxy 的 documentContextBeforeInput，按换行切分取最后一个非空行，
///   截前 500 字作为 userInput；
/// - 无完全访问权限时整面板显示引导卡片（键盘扩展无法联网）；
/// - 人设只读：PersonaStore.shared.active 作为 system prompt 来源传给 AiService；
/// - 结果上屏：润色 = replaceChars(原文字数, with: 新文本)；三策略 = sendToProxy(text:) 直接插入。
struct AiCardPanelView: View {
    @EnvironmentObject private var context: KeyboardContext

    /// 面板阶段状态
    private enum Phase {
        case idle
        case loading(title: String)
        case rewriteResult(text: String, sourceCount: Int) // 润色结果 + 原文（最后一段）字数
        case strategyResults([StrategyResult])
        case failed(String)
    }

    /// AI 动作类型
    private enum AiAction {
        case rewrite      // 润色本条
        case strategies   // 沟通三策略
    }

    @State private var phase: Phase = .idle

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView(title: "AI 帮你说") {
                EmptyView()
            }
            Group {
                if context.hasFullAccess {
                    content
                } else {
                    fullAccessGuide
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(KeyboardTheme.background)
    }

    // MARK: - 无完全访问权限引导

    /// 无完全访问权限：键盘无法联网，整面板显示引导卡片
    private var fullAccessGuide: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 30))
                .foregroundStyle(KeyboardTheme.secondaryForeground)
            Text("需要完全访问权限才能联网")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KeyboardTheme.foreground)
            Text("设置 → 键盘 → 妙语 → 允许完全访问")
                .font(.system(size: 13))
                .foregroundStyle(KeyboardTheme.secondaryForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 有权限内容

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            entryArea(hint: "取输入框最后一句话，让 AI 帮你换个说法")
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                entryArea(hint: "")
            }
        case .loading(let title):
            VStack(spacing: 12) {
                ProgressView()
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
            }
            .frame(maxHeight: .infinity)
        case .rewriteResult(let text, let sourceCount):
            rewriteResultView(text: text, sourceCount: sourceCount)
        case .strategyResults(let list):
            strategyListView(list)
        }
    }

    /// 入口区：两个大按钮
    private func entryArea(hint: String) -> some View {
        VStack(spacing: 14) {
            if !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
            }
            HStack(spacing: 12) {
                entryButton("润色本条", icon: "wand.and.stars") {
                    run(.rewrite)
                }
                entryButton("沟通三策略", icon: "bubble.left.and.bubble.right.fill") {
                    run(.strategies)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func entryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KeyboardTheme.panelBackground)
            )
            .foregroundStyle(KeyboardTheme.accent)
        }
        .frame(height: 88)
        .buttonStyle(.plain)
    }

    /// 润色结果：点击卡片替换输入框里的最后一句（删除原文再插入新文本）
    private func rewriteResultView(text: String, sourceCount: Int) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Button {
                    // 替换：对 documentContextBeforeInput 尾部 deleteBackward(sourceCount) 后插入
                    context.replaceChars(sourceCount, with: text)
                    context.mode = .pinyin // 上屏后回到拼音键盘
                } label: {
                    Text(text)
                        .font(.system(size: KeyboardTheme.panelFontSize))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(KeyboardTheme.panelBackground)
                        )
                        .foregroundStyle(KeyboardTheme.foreground)
                }
                .buttonStyle(.plain)

                Text("点击卡片替换输入框里的最后一句")
                    .font(.system(size: 11))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)

                Button("重新生成") {
                    run(.rewrite)
                }
                .font(.system(size: 13))
                .buttonStyle(.borderless)
            }
            .padding(14)
        }
    }

    /// 三策略结果：点击任意一条直接追加到输入框（不改动原文）
    private func strategyListView(_ list: [StrategyResult]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("点击任意一条直接追加到输入框（不改动原文）")
                    .font(.system(size: 11))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)

                ForEach(Array(list.enumerated()), id: \.offset) { _, item in
                    Button {
                        // 三策略 = 直接插入，不动原文
                        context.sendToProxy(text: item.content)
                        context.mode = .pinyin
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(KeyboardTheme.accent)
                            Text(item.content)
                                .font(.system(size: 14))
                                .foregroundStyle(KeyboardTheme.foreground)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(KeyboardTheme.panelBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    // MARK: - 请求执行

    private func run(_ action: AiAction) {
        guard let source = Self.lastParagraph(of: context.documentContextBeforeInput()) else {
            phase = .failed("输入框里还没有文字，先打一句再试")
            return
        }
        // 键盘侧人设只读：取当前激活人设作为改写风格
        let persona = PersonaStore.shared.active
        phase = .loading(title: action == .rewrite ? "正在润色…" : "正在生成三策略…")

        Task { @MainActor in
            do {
                switch action {
                case .rewrite:
                    let text = try await AiService.shared.rewrite(userInput: source, persona: persona)
                    phase = .rewriteResult(text: text, sourceCount: source.count)
                case .strategies:
                    let list = try await AiService.shared.communicationStrategies(for: source, persona: persona)
                    phase = .strategyResults(list)
                }
            } catch {
                phase = .failed("请求失败：\(error.localizedDescription)")
            }
        }
    }

    /// 取光标前文的最后一段：按换行切分取最后一个非空行，截前 500 字。
    static func lastParagraph(of text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard let last = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).last,
              !last.isEmpty else { return nil }
        return String(last.prefix(500))
    }
}
