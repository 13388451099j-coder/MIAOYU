import SwiftUI

// MARK: - 通用按键组件（各键盘视图共用）

/// 通用按键：统一 KeyboardTheme 配色、圆角与按压反馈。
/// - `width` 为 nil 时弹性铺满可用宽度，否则固定宽度（由各键盘视图按行宽计算）。
/// - `isFunction` 功能键（小字号）；`isAccent` 强调键（如回车，蓝底白字）；
///   `isActive` 激活态（如英文 shift 开启，蓝色图标）。
struct KeyButton: View {
    var title: String = ""
    var systemImage: String? = nil
    var subtitle: String? = nil
    var width: CGFloat? = nil
    var isFunction: Bool = false
    var isAccent: Bool = false
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(KeyButtonStyle(isAccent: isAccent))
    }

    /// 按键内容：图标或标题 + 可选小字副标题（T9 的数字下字母组）
    private var label: some View {
        VStack(spacing: 1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: isFunction ? KeyboardTheme.functionKeyFontSize + 2 : KeyboardTheme.keyFontSize,
                                  weight: .medium))
            } else {
                Text(title)
                    .font(.system(size: isFunction ? KeyboardTheme.functionKeyFontSize : KeyboardTheme.keyFontSize,
                                  weight: isFunction ? .regular : .medium))
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(isAccent ? Color.white.opacity(0.8) : KeyboardTheme.secondaryForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: .infinity)
        .foregroundStyle(foregroundColor)
        .contentShape(RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius))
    }

    private var foregroundColor: Color {
        if isAccent { return .white }
        if isActive { return KeyboardTheme.accent }
        return KeyboardTheme.foreground
    }
}

/// 按压态：底色变按压色（强调键保持蓝底、降低不透明度）
private struct KeyButtonStyle: ButtonStyle {
    let isAccent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius, style: .continuous)
                    .fill(configuration.isPressed
                          ? KeyboardTheme.keyPressedBackground
                          : (isAccent ? KeyboardTheme.accent : KeyboardTheme.keyBackground))
            )
            .opacity(configuration.isPressed ? (isAccent ? 0.85 : 1.0) : 1.0)
    }
}

// MARK: - 26 键拼音键盘

/// 26 键拼音主键盘：三行字母（q..p / a..l / z..m+退格）+ 底部功能行。
/// 拼音模式不放 shift（shift 仅对英文直上屏有意义，见任务说明）。
struct PinyinKeyboardView: View {
    @EnvironmentObject private var context: KeyboardContext

    private static let rowTop = Array("qwertyuiop")
    private static let rowMid = Array("asdfghjkl")
    private static let rowBottom = Array("zxcvbnm")

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - KeyboardTheme.edgePadding * 2
            let s = KeyboardTheme.keySpacing
            let unitTop = (w - CGFloat(Self.rowTop.count - 1) * s) / CGFloat(Self.rowTop.count)
            let unitMid = (w - CGFloat(Self.rowMid.count - 1) * s) / CGFloat(Self.rowMid.count)
            // 第三行：7 个字母 + 退格 = 8 键
            let unitBottom = (w - CGFloat(Self.rowBottom.count) * s) / CGFloat(Self.rowBottom.count + 1)

            VStack(spacing: s) {
                letterRow(Self.rowTop, unit: unitTop)
                letterRow(Self.rowMid, unit: unitMid)

                HStack(spacing: s) {
                    ForEach(Self.rowBottom, id: \.self) { ch in
                        KeyButton(title: String(ch), width: unitBottom) {
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

    /// 字母行：每键固定等宽
    private func letterRow(_ letters: [Character], unit: CGFloat) -> some View {
        HStack(spacing: KeyboardTheme.keySpacing) {
            ForEach(letters, id: \.self) { ch in
                KeyButton(title: String(ch), width: unit) {
                    context.tap(letter: ch)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// 底部功能行：123 符号切换 / 键盘形态循环（拼音↔九键↔英文）/ 地球 / 空格 / 回车。
    /// 注：任务指定为「123、地球、空格、回车」；额外补一个键盘形态循环键，
    /// 否则九宫格与英文键盘没有入口（偏差已在交付说明中注明）。
    private func bottomRow(width w: CGFloat, spacing s: CGFloat) -> some View {
        let key123 = w * 0.10
        let cycle = w * 0.10
        let globe = context.needsInputModeSwitchKey ? w * 0.10 : 0
        let ret = w * 0.13
        let gapCount = context.needsInputModeSwitchKey ? 3 : 2
        let space = w - key123 - cycle - globe - ret - CGFloat(gapCount) * s

        return HStack(spacing: s) {
            KeyButton(title: "123", width: key123, isFunction: true) {
                context.mode = .symbol
            }
            KeyButton(title: "9键", width: cycle, isFunction: true) {
                context.mode = .t9
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
