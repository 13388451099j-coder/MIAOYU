import SwiftUI

/// 根视图：底部四 Tab（改写 / 短语 / 历史 / 我的）
///
/// Tab 的 selection 绑定到 AppState.selectedTab，
/// 供 OCR 页把识别文本送入改写页时一键切换。
struct RootTabView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {

            NavigationStack {
                ChatRewriteView()
            }
            .tabItem { Label("改写", systemImage: "wand.and.stars") }
            .tag(AppState.Tab.rewrite)

            NavigationStack {
                QuickPhraseView()
            }
            .tabItem { Label("短语", systemImage: "text.quote") }
            .tag(AppState.Tab.phrases)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            .tag(AppState.Tab.history)

            NavigationStack {
                MeView()
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle") }
            .tag(AppState.Tab.me)
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppState())
}
