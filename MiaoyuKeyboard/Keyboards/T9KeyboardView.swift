import SwiftUI

/// T9 九宫格键盘：3x4 数字键（2abc…9wxyz）+ 分词键 + 0 空格 + 退格。
/// 数字经 `context.tapDigit(_:)` 进入 T9 映射路径（T9Mapper 契约 API），见 KeyboardContext.rebuildT9Engine。
struct T9KeyboardView: View {
    @EnvironmentObject private var context: KeyboardContext

    /// 九宫格定义：(数字, 字母组)；1 无字母映射
    private static let gridKeys: [(String, String)] = [
        ("1", ""), ("2", "abc"), ("3", "def"),
        ("4", "ghi"), ("5", "jkl"), ("6", "mno"),
        ("7", "pqrs"), ("8", "tuv"), ("9", "wxyz"),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - KeyboardTheme.edgePadding * 2
            let s = KeyboardTheme.keySpacing
            let unit = (w - 2 * s) / 3

            VStack(spacing: s) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: s) {
                        ForEach(Self.gridKeys[row * 3..<(row + 1) * 3], id: \.0) { key in
                            gridKey(key, width: unit)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }

                // 第四行：分词 / 0 空格 / 退格
                HStack(spacing: s) {
                    KeyButton(title: "分词", width: unit, isFunction: true) {
                        tapSeparator()
                    }
                    KeyButton(title: "0", subtitle: "空格", width: unit, isFunction: true) {
                        context.tapSpace() // 0 键与空格同语义：有组合上屏第一候选，无组合插空格
                    }
                    KeyButton(systemImage: "delete.left", width: unit, isFunction: true) {
                        context.tapBackspace()
                    }
                }
                .frame(maxHeight: .infinity)

                // 附加功能行：任务未列出此行；无它则符号页/回车/键盘形态切换不可达（偏差已在交付说明注明）
                utilityRow(width: w, spacing: s)
            }
            .padding(KeyboardTheme.edgePadding)
        }
    }

    /// 九宫格数字键
    private func gridKey(_ key: (String, String), width: CGFloat) -> some View {
        let (digit, letters) = key
        return KeyButton(title: digit, subtitle: letters, width: width) {
            if digit == "1" {
                // 1 无字母映射：无组合时快捷插入句号，有组合时忽略
                if context.rawInput.isEmpty {
                    context.sendToProxy(text: "。")
                }
            } else {
                context.tapDigit(Character(digit))
            }
        }
    }

    /// 分词键：引擎暂不支持组合内分隔符——无组合时插入「'」，有组合时无操作。
    private func tapSeparator() {
        if context.rawInput.isEmpty {
            context.sendToProxy(text: "'")
        }
    }

    /// 附加功能行：123 符号 / EN 英文 / 地球 / 空格 / 回车
    private func utilityRow(width w: CGFloat, spacing s: CGFloat) -> some View {
        let key123 = w * 0.12
        let cycle = w * 0.10
        let globe = context.needsInputModeSwitchKey ? w * 0.12 : 0
        let ret = w * 0.14
        let gapCount = context.needsInputModeSwitchKey ? 3 : 2
        let space = w - key123 - cycle - globe - ret - CGFloat(gapCount) * s

        return HStack(spacing: s) {
            KeyButton(title: "123", width: key123, isFunction: true) {
                context.mode = .symbol
            }
            KeyButton(title: "EN", width: cycle, isFunction: true) {
                context.mode = .english
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
