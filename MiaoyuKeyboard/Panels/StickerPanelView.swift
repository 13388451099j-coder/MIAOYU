import SwiftUI

/// 颜文字/表情面板：内置 45 条文本颜文字与常用 emoji 组合（纯文本，直接 insertText 上屏）。
struct StickerPanelView: View {
    @EnvironmentObject private var context: KeyboardContext

    /// 内置清单：29 条颜文字 + 16 条常用 emoji
    static let stickers: [String] = [
        // 颜文字
        "(๑•̀ㅂ•́)و✧", "(｡•ᴗ•｡)", "Σ(°△°|||)", "(¬_¬)", "(T▽T)",
        "(￣▽￣)~*", "(｡•́︿•̀｡)", "ヽ(✿ﾟ▽ﾟ)ノ", "(ง •̀_•́)ง", "٩(◕‿◕｡)۶",
        "(◍•ᴗ•◍)", "(๑´ㅂ`๑)", "(≧∇≦)ﾉ", "(´･_･`)", "(＾▽＾)",
        "(눈_눈)", "(๑¯∀¯๑)", "┗( ▔, ▔ )┛", "(ง˙ω˙)ว", "(´∀｀)♡",
        "(￢‿￢)", "(・ω・)", "ヾ(≧▽≦*)o", "(っ˘̩╭╮˘̩)っ", "ʕ•ᴥ•ʔ",
        "(∪.∪ )...zzz", "(ﾉ´ヮ`)ﾉ*: ･ﾟ", "✧(≖ ◡ ≖✿)", "ᕕ( ᐛ )ᕗ",
        // emoji（含 ok 手势等常用组合）
        "👌", "✌️", "🤝", "👍", "😂",
        "🥹", "😭", "😅", "😊", "🥺",
        "❤️", "💯", "🎉", "✨", "🤔",
    ]

    private static let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        VStack(spacing: 6) {
            PanelHeaderView(title: "颜文字") {
                EmptyView()
            }

            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(Array(Self.stickers.enumerated()), id: \.offset) { _, sticker in
                        Button {
                            context.sendToProxy(text: sticker)
                        } label: {
                            Text(sticker)
                                .font(.system(size: 16))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, minHeight: 38)
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
        .frame(maxHeight: .infinity)
        .background(KeyboardTheme.background)
    }
}
