import SwiftUI

/// 键盘根视图：顶栏（logo / 功能入口 / 地球 / 收起）+ 内容区（候选条或面板）+ 主键盘区，
/// 按 context.mode 切换四个子键盘视图与三个面板。
struct KeyboardRootView: View {
    @EnvironmentObject private var context: KeyboardContext

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()
            Rectangle()
                .fill(KeyboardTheme.separator)
                .frame(height: 0.5)

            if context.mode.isPanel {
                // 面板模式：AI / 短语 / 颜文字 占据整个内容区
                panelArea
            } else {
                // 键盘模式：拼音与 T9 顶部带候选条（英文/符号直上屏，不需要候选条）
                if context.mode == .pinyin || context.mode == .t9 {
                    CandidateBarView()
                    Rectangle()
                        .fill(KeyboardTheme.separator)
                        .frame(height: 0.5)
                }
                keyboardArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KeyboardTheme.background) // 容器底色，避免透明
    }

    // MARK: - 主键盘区

    @ViewBuilder
    private var keyboardArea: some View {
        switch context.mode {
        case .pinyin:  PinyinKeyboardView()
        case .t9:      T9KeyboardView()
        case .symbol:  SymbolKeyboardView()
        case .english: EnglishKeyboardView()
        default:       EmptyView()
        }
    }

    // MARK: - 面板区

    @ViewBuilder
    private var panelArea: some View {
        switch context.mode {
        case .aiPanel:      AiCardPanelView()
        case .phrasePanel:  QuickPhrasePanelView()
        case .stickerPanel: StickerPanelView()
        default:            EmptyView()
        }
    }
}

/// KeyboardMode 面板判定（供根视图分流）
extension KeyboardMode {
    var isPanel: Bool {
        switch self {
        case .aiPanel, .phrasePanel, .stickerPanel:
            return true
        default:
            return false
        }
    }
}

/// 顶栏：妙语 logo + 功能入口（AI / 短语 / 颜文字）+ 地球键（切系统键盘）+ 收起键。
private struct TopBarView: View {
    @EnvironmentObject private var context: KeyboardContext

    var body: some View {
        HStack(spacing: 12) {
            Text("妙语")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KeyboardTheme.accent)

            Spacer(minLength: 8)

            barButton("✨AI", active: context.mode == .aiPanel) { togglePanel(.aiPanel) }
            barButton("短语", active: context.mode == .phrasePanel) { togglePanel(.phrasePanel) }
            barButton("颜文字", active: context.mode == .stickerPanel) { togglePanel(.stickerPanel) }

            if context.needsInputModeSwitchKey {
                Button {
                    context.switchToNextKeyboard() // 地球键：切下一个系统输入法
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 15))
                        .foregroundStyle(KeyboardTheme.secondaryForeground)
                }
            }

            Button {
                context.dismissKeyboard() // 收起键盘
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 15))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: KeyboardTheme.topBarHeight)
        .contentShape(Rectangle())
    }

    /// 再次点击当前面板按钮则返回拼音键盘
    private func togglePanel(_ panel: KeyboardMode) {
        context.mode = (context.mode == panel) ? .pinyin : panel
    }

    private func barButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? KeyboardTheme.accent : KeyboardTheme.secondaryForeground)
        }
    }
}

/// 面板统一头：左侧「返回键盘」，中间标题，右侧自定义槽位（如短语面板的「管理」）。
struct PanelHeaderView<Trailing: View>: View {
    @EnvironmentObject private var context: KeyboardContext

    private let title: String
    private let trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                context.mode = .pinyin
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("键盘")
                        .font(.system(size: 12))
                }
                .foregroundStyle(KeyboardTheme.secondaryForeground)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KeyboardTheme.foreground)

            Spacer()

            trailing()
        }
        .padding(.horizontal, 10)
        .frame(height: KeyboardTheme.topBarHeight)
    }
}
