// MARK: - 跳到系统设置（键盘页优先）
//
// iOS 没有任何公开 API 能让 App 直接打开「键盘」设置页，也没有 API 能查询/开启
// 键盘的「完全访问」——那是用户在系统设置里手动点的开关。常见的做法是用私有的
// App-Prefs scheme 直达键盘列表，失败再退回本 App 的设置页。
//
// ⚠️ 上架 App Store 前必须去掉 App-Prefs 分支（私有 scheme，审核会拒），
//    只保留 openSettingsURLString。当前是自签安装阶段，方便用户少点两层。
//
// 只编译进主 App（键盘扩展里 UIApplication.shared 不可用）。

import UIKit

enum KeyboardSettings {

    /// 打开系统设置：先试键盘列表，失败退回本 App 设置页。
    static func open() {
        let deepLinks = [
            "App-Prefs:root=General&path=Keyboard/KEYBOARDS",
            "App-Prefs:root=General&path=Keyboard",
        ]
        for raw in deepLinks {
            guard let url = URL(string: raw) else { continue }
            UIApplication.shared.open(url, options: [:]) { opened in
                if !opened { openAppSettings() }
            }
            return
        }
        openAppSettings()
    }

    /// 本 App 的系统设置页（公开 API，任何情况都可用）
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
