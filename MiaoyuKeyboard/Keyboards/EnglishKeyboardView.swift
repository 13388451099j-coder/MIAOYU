import SwiftUI

/// 英文键盘：26 键布局同拼音，字母直接上屏（shift 控制大小写，单次大写后自动回落）。
/// 第三行左侧 shift、右侧退格；底部行：123 / 拼音切换 / 地球 / 空格 / 回车。
struct EnglishKeyboardView: View {
    @EnvironmentObject private var context: KeyboardContext

    private static let rowTop = Array("qwertyuiop")
    private static let rowMid = Array("asdfghjkl")
    private static let rowBottom = Array("zxcvbnm")

    /// shift 开启时按键显示大写，给出即时视觉反馈
    private func display(_ ch: Character) -> String {
        context.shift ? String(ch).uppercased() : String(ch)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - KeyboardTheme.edgePadding * 2
            let s = KeyboardTheme.keySpacing
            let unitTop = (w - 9 * s) / 10
            let unitMid = (w - 8 * s) / 9
            // 第三行：shift + 7 字母 + 退格 = 9 键
            let unitBottom = (w - 8 * s) / 9

            VStack(spacing: s) {
                HStack(spacing: s) {
                    ForEach(Self.rowTop, id: \.self) { ch in
                        KeyButton(title: display(ch), width: unitTop) {
                            context.tap(letter: ch)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: s) {
                    ForEach(Self.rowMid, id: \.self) { ch in
                        KeyButton(title: display(ch), width: unitMid) {
                            context.tap(letter: ch)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: s) {
                    // shift：仅对英文直上屏有意义，切换大小写状态
                    KeyButton(systemImage: context.shift ? "shift.fill" : "shift",
                              width: unitBottom,
                              isFunction: true,
                              isActive: context.shift) {
                        context.shift.toggle()
                    }
                    ForEach(Self.rowBottom, id: \.self) { ch in
                        KeyButton(title: display(ch), width: unitBottom) {
                            context.tap(letter: ch)
                        }
                    }
                    KeyButton(systemImage: "delete.left", width: unitBottom, isFunction: true) {
                        context.tapBackspace()
                    }
                }
                .frame(maxHeight: .infinity)

                bottomRow(width: w, spacing: s)
            }
            .padding(KeyboardTheme.edgePadding)
        }
    }

    /// 底部功能行：123 符号切换 / 拼音键盘 / 地球 / 空格 / 回车
    private func bottomRow(width w: CGFloat, spacing s: CGFloat) -> some View {
        let key123 = w * 0.10
        let pin = w * 0.11
        let globe = context.needsInputModeSwitchKey ? w * 0.10 : 0
        let ret = w * 0.13
        let gapCount = context.needsInputModeSwitchKey ? 3 : 2
        let space = w - key123 - pin - globe - ret - CGFloat(gapCount) * s

        return HStack(spacing: s) {
            KeyButton(title: "123", width: key123, isFunction: true) {
                context.mode = .symbol
            }
            KeyButton(title: "拼音", width: pin, isFunction: true) {
                context.mode = .pinyin
            }
            if context.needsInputModeSwitchKey {
                KeyButton(systemImage: "globe", width: globe, isFunction: true) {
                    context.switchToNextKeyboard()
                }
            }
            KeyButton(title: "空格", width: space, isFunction: true) {
                context.tapSpace()
            }
            KeyButton(systemImage: "return", width: ret, isFunction: true, isAccent: true) {
                context.tapReturn()
            }
        }
        .frame(maxHeight: .infinity)
    }
}
