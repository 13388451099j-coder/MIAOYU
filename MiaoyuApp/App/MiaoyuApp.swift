import SwiftUI

/// 全局共享的应用状态（跨 Tab 传递数据）
///
/// 主要用途：截图识别页（OCRView）把待改写文本递给改写页（ChatRewriteView），
/// 并联动 RootTabView 切换到「改写」Tab。
final class AppState: ObservableObject {

    /// 底部 Tab 枚举
    enum Tab: Int {
        case rewrite = 0   // 改写
        case phrases = 1   // 短语
        case history = 2   // 历史
        case me = 3        // 我的
    }

    /// 当前选中的 Tab（供 OCR 页一键切回改写页）
    @Published var selectedTab: Tab = .rewrite

    /// 待送入改写输入框的文本（OCR 识别结果等）
    /// 改写页 onAppear 消费后立即清空
    @Published var pendingRewriteText: String = ""
}

/// 妙语 App 入口
@main
struct MiaoyuApp: App {

    /// 全局状态：注入环境，供 RootTabView / ChatRewriteView / OCRView 共用
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
        }
    }
}
