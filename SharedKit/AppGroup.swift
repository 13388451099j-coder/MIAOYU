// MARK: - AppGroup 共享容器入口
//
// 主 App 与键盘扩展共用的 App Group 常量与便捷访问：
// - `identifier`：App Group 标识，需与两个 target 的 entitlements 保持一致
// - `defaults`：App Group UserDefaults；suite 创建失败时回退 .standard（保证单 target 调试可跑）
// - `keyboardHasFullAccess`：键盘侧写入的"完全访问"状态快照，主 App 引导页读取展示

import Foundation

enum AppGroup {
    /// App Group 标识（主 App 与键盘扩展 entitlements 中声明同一值）
    static let identifier = "group.com.miaoyu.zuiti"

    /// App Group UserDefaults；创建失败回退 .standard
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// App Group 容器是否真的可用（entitlement 生效）。
    ///
    /// 自签免费 Apple ID **不支持 App Groups**：这种装法下系统不会给共享容器，
    /// 主 App 与键盘各写各的 UserDefaults，快捷短语 / 完全访问状态 / 直播快照全部读不到。
    /// 显式暴露这个状态，UI 才能告诉用户「为什么键盘明明开着完全访问，这里还显示未开启」。
    static var isSharedContainerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    /// 键盘是否拥有完全访问权限。
    /// 键盘侧在 `hasFullAccess` 变化时调用 `reportKeyboardFullAccess(_:)` 写入；主 App 侧读该值
    /// 用于安装引导展示，主 App 进程内并不真正持有键盘权限，读到的只是键盘上报的快照。
    static var keyboardHasFullAccess: Bool {
        defaults.bool(forKey: "kb_full_access")
    }

    /// 键盘侧上报完全访问状态（主 App「我的 → 键盘完全访问」据此显示）。
    /// 之前只有读端没有写端，主 App 这项永远显示「未开启」——直播模式依赖完全访问，一并修掉。
    static func reportKeyboardFullAccess(_ value: Bool) {
        defaults.set(value, forKey: "kb_full_access")
    }
}
