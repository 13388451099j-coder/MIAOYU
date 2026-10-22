import SwiftUI

/// 「我的」页：键盘与权限 / 功能入口 / 关于与隐私说明
struct MeView: View {

    /// 键盘完全访问状态（onAppear 刷新）
    @State private var fullAccess: Bool = false

    /// 应用版本号（读取 Info.plist）
    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            // 键盘与权限
            Section("键盘与权限") {
                NavigationLink {
                    GuideView()
                } label: {
                    Label("键盘安装引导", systemImage: "keyboard")
                }
                HStack {
                    Label(
                        "键盘完全访问",
                        systemImage: fullAccess
                            ? "checkmark.shield.fill"
                            : "exclamationmark.shield.fill"
                    )
                    .foregroundStyle(fullAccess ? Color.green : Color.orange)
                    Spacer()
                    Text(fullAccess ? "已开启" : "未开启")
                        .foregroundStyle(.secondary)
                }
            }

            // 功能入口
            Section("功能") {
                NavigationLink {
                    ModelSettingsView()
                } label: {
                    Label("模型设置", systemImage: "cpu")
                }
                NavigationLink {
                    PersonaListView()
                } label: {
                    Label("人设管理", systemImage: "theatermasks")
                }
                NavigationLink {
                    OCRView()
                } label: {
                    Label("截图识别改写", systemImage: "viewfinder")
                }
                NavigationLink {
                    LiveView()
                } label: {
                    Label("直播模式（读屏免复制）", systemImage: "dot.radiowaves.left.and.right")
                }
            }

            // 关于
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }

            // 隐私说明
            Section("隐私说明") {
                Text(
                    """
                    · 人设、短语、会话记录等全部数据仅保存在本机，不上传任何服务器。

                    · AI 改写请求会携带当前对话内容，通过 HTTPS 直达你选择的服务商（DeepSeek、智谱、通义千问、Kimi 等），不经任何第三方中转。

                    · API Key 仅保存在本机钥匙串（Keychain），除发往对应服务商的请求外不会出现在任何地方。
                    """
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我的")
        .onAppear {
            fullAccess = AppGroup.keyboardHasFullAccess
        }
    }
}

#Preview {
    NavigationStack {
        MeView()
    }
}
