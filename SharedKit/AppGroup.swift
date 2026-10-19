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

    /// 键盘是否拥有完全访问权限。
    /// 键盘侧在 `hasFullAccess` 变化时写入 "kb_full_access"；主 App 侧读该值用于安装引导展示，
    /// 主 App 进程内并不真正持有键盘权限，读到的只是键盘上报的快照。
    static var keyboardHasFullAccess: Bool {
        defaults.bool(forKey: "kb_full_access")
    }
}
