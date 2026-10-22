import SwiftUI
import Combine
import UIKit

/// AI 卡片面板：三种输入来源共用一套候选展示。
///
/// ① **直播（读屏）**：广播扩展持续 OCR 屏幕并把「对方最新一条 + 前文」写进 App Group，
///    本面板每 2 秒轮询一次快照，把待回消息直接列成按钮——用户不用再长按复制；
/// ② **润色本条**：取 textDocumentProxy 的 documentContextBeforeInput 最后一段，改写后替换原文；
/// ③ **沟通三策略**：同样取输入框文字，给 3 种风格回复，点击直接上屏（不动原文）。
///
/// - 无「允许完全访问」时整面板显示引导卡片（键盘扩展无权限时既不能联网也不能读共享容器）；
/// - 人设只读：PersonaStore.shared.active 作为 system prompt 来源传给 AiService；
/// - 上屏通道只有两条：`replaceChars(原文字数, with:)` 与 `sendToProxy(text:)`，
///   发送动作永远由用户自己在宿主 App 里按。
struct AiCardPanelView: View {
    @EnvironmentObject private var context: KeyboardContext

    /// 面板阶段状态
    private enum Phase {
        case idle
        case loading(title: String)
        case rewriteResult(text: String, sourceCount: Int)   // 润色结果 + 原文（最后一段）字数
        case candidates([StrategyResult], source: String)     // 候选回复 + 来源说明（对方消息预览）
        case failed(String)
    }

    /// AI 动作类型
    private enum AiAction {
        case rewrite      // 润色本条
        case strategies   // 沟通三策略
    }

    @State private var phase: Phase = .idle

    /// 本进程（键盘扩展）是否已拿到可用的 API Key。
    /// 自签安装没有 App Groups，主 App 存进它自己钥匙串的 Key 在键盘这边读不到，
    /// 所以这里必须单独判断，并给用户一条搬运配置的路径。
    /// 初值给 false、在 onAppear 里读：View 的 init 会在每次 body 重建时执行，
    /// 把钥匙串读取放在属性默认值里等于每次重建都读一遍 Keychain。
    @State private var hasKey: Bool = false

    /// 手动粘贴配置串的输入框内容
    @State private var configToken: String = ""
    /// 配置搬运的提示语（成功 / 令牌不合法 / 剪贴板为空）
    @State private var configMessage: String?

    /// 最新一次读到的直播快照（每 2 秒刷新；轮询本身很轻，快照只有几 KB）
    @State private var snapshot: LiveScreenSnapshot?

    /// 直播快照轮询。2 秒与广播扩展的 OCR 节流周期一致，再快也只是读到同一份。
    private let liveTicker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView(title: "AI 帮你说") {
                EmptyView()
            }
            Group {
                if !context.hasFullAccess {
                    fullAccessGuide
                } else if !hasKey {
                    configPanel
                } else {
                    content
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(KeyboardTheme.background)
        .onAppear {
            hasKey = LlmProviderStore.shared.hasUsableKey()
            snapshot = LiveScreenStore.load()
        }
        .onReceive(liveTicker) { _ in
            guard context.hasFullAccess else { return }
            snapshot = LiveScreenStore.load()
        }
    }

    // MARK: - 无完全访问权限引导

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
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 未配置 API Key：键盘侧自行搬运配置

    /// 自签安装时 App Groups 不可用，主 App 的 Key 过不来。
    /// 这里给两条路：直接从剪贴板导入，或手动粘贴那条配置串。
    private var configPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 12))
                    Text("键盘还没拿到 API Key")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(KeyboardTheme.foreground)

                Text("① 妙语 App › 我的 › 模型设置 › 选服务商 › 点「复制配置串」\n② 回到这里导入，只写进键盘自己的钥匙串")
                    .font(.system(size: 11))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    importFromPasteboard()
                } label: {
                    Text("从剪贴板导入配置")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(KeyboardTheme.panelBackground)
                        )
                        .foregroundStyle(KeyboardTheme.accent)
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    TextField("或粘贴配置串", text: $configToken)
                        .font(.system(size: 11))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(KeyboardTheme.panelBackground)
                        )
                    Button("保存") {
                        applyConfig(configToken)
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.borderless)
                }

                if let configMessage {
                    Text(configMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(KeyboardTheme.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    /// 读剪贴板并导入。iOS 16 起读剪贴板会弹系统「允许粘贴」，用户在弹窗点允许即可。
    private func importFromPasteboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            configMessage = "剪贴板是空的：先在主 App 点「复制配置串」"
            return
        }
        applyConfig(text)
    }

    /// 落地配置：解析失败（不是妙语令牌）/ 写入失败（钥匙串被拒）/ 成功，三态各自提示
    private func applyConfig(_ token: String) {
        switch ConfigPortable.apply(token: token) {
        case .some(true):
            hasKey = LlmProviderStore.shared.hasUsableKey()
            configToken = ""
            configMessage = "导入成功"
            phase = .idle
        case .some(false):
            configMessage = "配置已读到，但写不进钥匙串（签名限制），请用付费开发者账号签名"
        case .none:
            configMessage = "这段文本不是妙语配置串，检查是否复制完整"
        }
    }

    // MARK: - 有权限内容

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            ScrollView {
                VStack(spacing: 12) {
                    liveSection
                    entryArea
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                Button("返回") { phase = .idle }
                    .font(.system(size: 13))
                    .buttonStyle(.borderless)
            }
            .frame(maxHeight: .infinity)
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
        case .candidates(let list, let source):
            candidateListView(list, source: source)
        }
    }

    // MARK: - 直播（读屏）区

    /// 监听态三态提示 + 待回消息按钮。目标列表 = 当前帧尾部的对方消息（没有则退回累积历史最近一条）
    /// + 至多两条更早的：键盘一弹聊天就滚到底，当前帧常只剩自己发的，目标不能因此消失乱跳。
    @ViewBuilder
    private var liveSection: some View {
        liveSectionContent(
            listening: snapshot.map { LiveScreenStore.isFresh($0) } ?? false,
            targets: liveTargets
        )
    }

    private func liveSectionContent(listening: Bool, targets: [String]) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: listening ? "dot.radiowaves.left.and.right" : "circle.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(listening ? Color.green : KeyboardTheme.secondaryForeground)
                Text(listening ? "直播监听中 · 免复制" : "未在直播监听")
                    .font(.system(size: 11))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
                Spacer(minLength: 0)
                // 键盘扩展拉不起宿主 App（iOS 硬限制：扩展不能 openURL），所以这里只给指路文字，
                // 不做成按钮——不想放一个点不动的控件骗人。
                Text("App›我的›直播模式")
                    .font(.system(size: 10))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
            }

            if targets.isEmpty {
                Text(listening
                     ? "还没读到对方的新消息：回聊天界面停一两秒再回来"
                     : "去妙语 App「我的 → 直播模式」开启屏幕直播，就不用再长按复制")
                    .font(.system(size: 11))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(targets.enumerated()), id: \.offset) { index, message in
                    liveTargetButton(message: message, isPrimary: index == 0)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardTheme.panelBackground)
        )
    }

    /// 待回消息按钮：预览截 34 字 + 折行——太短用户分不清回的是哪一条。
    private func liveTargetButton(message: String, isPrimary: Bool) -> some View {
        let flattened = message.replacingOccurrences(of: "\n", with: " ")
        let preview = String(flattened.prefix(34)) + (flattened.count > 34 ? "…" : "")
        return Button {
            runLive(message: message)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isPrimary
                      ? "dot.radiowaves.left.and.right" : "clock.arrow.circlepath")
                    .font(.system(size: 11))
                Text(isPrimary ? "读屏幕分析：「\(preview)」" : "回复更早：「\(preview)」")
                    .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isPrimary ? KeyboardTheme.accent : KeyboardTheme.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(KeyboardTheme.background.opacity(isPrimary ? 1 : 0.6))
            )
        }
        .buttonStyle(.plain)
    }

    /// 目标列表：主目标（当前帧尾部；空帧时退回累积历史最近一条）+ 至多两条更早的。
    private var liveTargets: [String] {
        guard let snapshot, LiveScreenStore.isFresh(snapshot) else { return [] }
        guard let primary = snapshot.latestIncoming ?? snapshot.recent.first else { return [] }
        var list = [primary]
        for older in snapshot.recent.dropFirst()
        where !LiveChatParser.areSameMessage(older, primary) && list.count < 3 {
            list.append(older)
        }
        return list
    }

    // MARK: - 输入框来源的两个入口

    private var entryArea: some View {
        VStack(spacing: 8) {
            Text("针对输入框里已打的那句话")
                .font(.system(size: 11))
                .foregroundStyle(KeyboardTheme.secondaryForeground)

            HStack(spacing: 10) {
                entryButton("润色本条", icon: "wand.and.stars") {
                    run(.rewrite)
                }
                entryButton("沟通三策略", icon: "bubble.left.and.bubble.right.fill") {
                    run(.strategies)
                }
            }
        }
    }

    private func entryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KeyboardTheme.panelBackground)
            )
            .foregroundStyle(KeyboardTheme.accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 结果展示

    /// 润色结果：点击卡片替换输入框里的最后一句（删除原文再插入新文本）
    private func rewriteResultView(text: String, sourceCount: Int) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Button {
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

                Button("重新生成") { run(.rewrite) }
                    .font(.system(size: 13))
                    .buttonStyle(.borderless)
            }
            .padding(12)
        }
    }

    /// 候选列表（直播 / 三策略共用）：点击任意一条直接上屏，不动输入框原有内容。
    private func candidateListView(_ list: [StrategyResult], source: String) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(source)
                    .font(.system(size: 11))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(list.enumerated()), id: \.offset) { _, item in
                    Button {
                        // 只插入，不动原文；发送仍由用户在宿主 App 里按
                        context.sendToProxy(text: item.content)
                        context.mode = .pinyin
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
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

                Button("返回") { phase = .idle }
                    .font(.system(size: 12))
                    .buttonStyle(.borderless)
            }
            .padding(12)
        }
    }

    // MARK: - 请求执行

    /// 直播来源：message = 待回的那条，context = 前文（只影响语气）。
    private func runLive(message: String) {
        let contextText = snapshot?.contextText
        let persona = PersonaStore.shared.active
        let flattened = message.replacingOccurrences(of: "\n", with: " ")
        phase = .loading(title: "正在生成候选…")

        Task { @MainActor in
            do {
                let list = try await AiService.shared.replyCandidates(
                    message: message, context: contextText, persona: persona)
                phase = .candidates(list, source: "针对：「\(String(flattened.prefix(40)))」")
            } catch {
                phase = .failed("请求失败：\(error.localizedDescription)")
            }
        }
    }

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
                    let list = try await AiService.shared.communicationStrategies(
                        for: source, persona: persona)
                    phase = .candidates(list, source: "针对输入框：「\(String(source.prefix(40)))」")
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
