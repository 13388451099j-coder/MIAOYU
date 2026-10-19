import SwiftUI

/// 符号键盘：两页网格（第 1 页中文常用符号 / 第 2 页数字与英文符号），
/// 分段控件切页，点击直接 insertText 上屏。
struct SymbolKeyboardView: View {
    @EnvironmentObject private var context: KeyboardContext

    /// 当前页：0 = 中文符号，1 = 数字符号
    @State private var page: Int = 0

    /// 第 1 页：中文常用标点
    private static let chineseSymbols: [String] = [
        "，", "。", "？", "！", "：", "；", "、",
        "“", "”", "‘", "’", "（", "）", "《", "》", "【", "】",
        "…", "—", "～", "·", "@", "#", "￥", "%", "……",
        "&", "*", "+", "-", "=", "/",
    ]

    /// 第 2 页：数字 0-9 与英文符号
    private static let westernSymbols: [String] = [
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
        "[", "]", "{", "}", "<", ">", "\\", "|", "^", "_", "`",
        "~", ".", ",", ";", ":", "?", "!", "(", ")",
        "-", "+", "=", "/", "'", "\"",
    ]

    private var symbols: [String] {
        page == 0 ? Self.chineseSymbols : Self.westernSymbols
    }

    private static let columns = [GridItem(.adaptive(minimum: 44), spacing: 6)]

    var body: some View {
        VStack(spacing: 6) {
            // 页切换分段控件
            Picker("符号页", selection: $page) {
                Text("中文符号").tag(0)
                Text("数字符号").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)

            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 6) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            context.sendToProxy(text: symbol) // 点击直接上屏
                        } label: {
                            Text(symbol)
                                .font(.system(size: 17))
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
            }

            bottomRow
        }
        .padding(.vertical, 6)
        .frame(maxHeight: .infinity)
        .background(KeyboardTheme.background)
    }

    /// 底部功能行：ABC 返回来源字母键盘 / 空格 / 退格 / 回车
    private var bottomRow: some View {
        GeometryReader { geo in
            let w = geo.size.width - KeyboardTheme.edgePadding * 2
            let s = KeyboardTheme.keySpacing
            let abc = w * 0.16
            let del = w * 0.14
            let ret = w * 0.14
            let space = w - abc - del - ret - 3 * s

            HStack(spacing: s) {
                KeyButton(title: "ABC", width: abc, isFunction: true) {
                    context.exitSymbolMode()
                }
                KeyButton(title: "空格", width: space, isFunction: true) {
                    context.tapSpace()
                }
                KeyButton(systemImage: "delete.left", width: del, isFunction: true) {
                    context.tapBackspace()
                }
                KeyButton(systemImage: "return", width: ret, isFunction: true, isAccent: true) {
                    context.tapReturn()
                }
            }
            .frame(height: 40)
            .padding(.horizontal, KeyboardTheme.edgePadding)
        }
        .frame(height: 46)
    }
}
