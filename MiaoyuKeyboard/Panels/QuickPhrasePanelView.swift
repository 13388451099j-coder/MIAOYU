import SwiftUI

/// 常用短语面板：读 QuickPhraseStore（App Group 共享存储）网格展示，点击整句上屏。
/// 右上「管理」按钮仅显示提示文案——键盘扩展中 UIApplication.shared 不可用
/// （App Extension API 限制），无法 openURL 跳转主 App，短语增删改去主 App 完成。
struct QuickPhrasePanelView: View {
    @EnvironmentObject private var context: KeyboardContext

    @State private var phrases: [QuickPhrase] = []
    @State private var showManageToast = false

    private static let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]

    var body: some View {
        VStack(spacing: 6) {
            PanelHeaderView(title: "常用短语") {
                Button("管理") {
                    flashManageToast()
                }
                .font(.system(size: 12))
                .foregroundStyle(KeyboardTheme.secondaryForeground)
            }

            if phrases.isEmpty {
                Spacer()
                Text("还没有常用短语\n去主 App「妙语 → 短语」添加")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 8) {
                        ForEach(phrases) { phrase in
                            Button {
                                // 点击上屏短语正文（按钮上只显示短标题）
                                context.sendToProxy(text: phrase.content)
                            } label: {
                                Text(phrase.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius)
                                            .fill(KeyboardTheme.keyBackground)
                                    )
                                    .foregroundStyle(KeyboardTheme.foreground)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(KeyboardTheme.background)
        .overlay(alignment: .bottom) {
            if showManageToast { manageToast }
        }
        .onAppear {
            // 确保内置短语已播种（键盘与主 App 共用同一份存储；主 App 未启动过时也能看到默认短语）
            QuickPhraseStore.shared.seedDefaultsIfNeeded()
            phrases = QuickPhraseStore.shared.all()
        }
    }

    // MARK: - 管理提示 toast

    /// toast 式提示：键盘扩展无法打开主 App（UIApplication.shared 在扩展中不可用），
    /// 只提示用户去主 App 管理。
    private var manageToast: some View {
        Text("短语请在主 App「妙语」中管理")
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(KeyboardTheme.keyBackground)
            )
            .foregroundStyle(KeyboardTheme.foreground)
            .padding(.bottom, 10)
            .transition(.opacity)
    }

    private func flashManageToast() {
        withAnimation { showManageToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showManageToast = false }
        }
    }
}
