import SwiftUI
import UIKit

/// 键盘统一主题：浅色/暗色自适应配色 + 按键尺寸常量。
/// 全部为静态成员，供各键盘视图与 KeyboardViewController（容器底色）直接引用。
enum KeyboardTheme {

    // MARK: - 尺寸常量（整键盘总高约 300pt）

    /// 键盘整体高度（VC 侧高度约束使用）
    static let totalHeight: CGFloat = 300
    /// 顶栏高度（logo / 功能入口 / 地球 / 收起）
    static let topBarHeight: CGFloat = 30
    /// 候选条高度
    static let candidateBarHeight: CGFloat = 40
    /// 按键间距
    static let keySpacing: CGFloat = 5
    /// 键盘区水平/垂直内边距
    static let edgePadding: CGFloat = 4
    /// 按键圆角
    static let keyCornerRadius: CGFloat = 6
    /// 字母键字号
    static let keyFontSize: CGFloat = 18
    /// 功能键字号
    static let functionKeyFontSize: CGFloat = 14
    /// 候选词字号
    static let candidateFontSize: CGFloat = 17
    /// 面板正文/卡片字号
    static let panelFontSize: CGFloat = 15

    // MARK: - 动态配色（UIColor 动态提供者，浅/暗自适应）

    /// 键盘整体背景：浅色为浅灰、暗色为深灰
    static let backgroundUIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
            : UIColor(red: 0.83, green: 0.84, blue: 0.87, alpha: 1)
    }

    /// 按键底色：浅色为白色、暗色为中灰
    static let keyUIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1)
            : UIColor.white
    }

    /// 按键按下态底色
    static let keyPressedUIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
            : UIColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1)
    }

    /// 面板卡片/候选条底色（比键盘背景略浅/略深一档）
    static let panelUIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1)
            : UIColor(red: 0.89, green: 0.90, blue: 0.92, alpha: 1)
    }

    /// 主文字色
    static let textUIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
    }

    /// 次要文字色（音节展示、提示文案）
    static let secondaryTextUIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.68, alpha: 1)
            : UIColor(white: 0.42, alpha: 1)
    }

    /// 强调色：系统蓝（自带深浅自适应）
    static let accentUIColor = UIColor.systemBlue

    /// 分隔线颜色
    static let separatorUIColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.32, alpha: 1)
            : UIColor(white: 0.72, alpha: 1)
    }

    // MARK: - SwiftUI 便捷访问

    static var background: Color { Color(backgroundUIColor) }
    static var keyBackground: Color { Color(keyUIColor) }
    static var keyPressedBackground: Color { Color(keyPressedUIColor) }
    static var panelBackground: Color { Color(panelUIColor) }
    static var foreground: Color { Color(textUIColor) }
    static var secondaryForeground: Color { Color(secondaryTextUIColor) }
    static var accent: Color { Color(accentUIColor) }
    static var separator: Color { Color(separatorUIColor) }
}
