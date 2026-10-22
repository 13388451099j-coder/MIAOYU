import SwiftUI

/// 「我的」页：键盘与权限 / 功能入口 / 关于与隐私说明
struct MeView: View {

    /// 键盘完全访问状态（onAppear 刷新）
    @State private var fullAccess: Bool = false
    /// App Group 共享容器是否可用（自签免费证书不支持 App Groups）
    @State private var sharedContainerOK: Bool = true

    /// 应用版本号（读取 Info.plist）
    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// 权限状态三态：自签没有 App Group 时读不到键盘上报的值，显示「无法检测」而不是「未开启」
    private var accessText: String {
        if !sharedContainerOK { return "无法检测" }
        return fullAccess ? "已开启" : "未开启"
    }

    private var accessIcon: String {
        if !sharedContainerOK { return "questionmark.shield.fill" }
        return fullAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
    }

    private var accessColor: Color {
        return sharedContainerOK && fullAccess ? .green : .orange
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
                    Label("键盘完全访问", systemImage: accessIcon)
                        .foregroundStyle(accessColor)
                    Spacer()
                    Text(accessText)
                        .foregroundStyle(.secondary)
                }
                // App Groups 是自签免费证书的硬限制：没有它，键盘写不进主 App 读得到的地方，
                // 这一行就永远「未开启」。说清楚原因，别让用户以为是开关没点。
                if !sharedContainerOK {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("共享容器不可用（自签限制）")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("当前安装方式用普通 Apple ID 自签，免费证书不支持 App Groups：主 App 与键盘各自存各自的数据，完全访问状态、快捷短语、直播识别结果都无法互通。要用完整功能需付费开发者账号签名（或在 Xcode 里用付费 Team 直接运行）。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
            sharedContainerOK = AppGroup.isSharedContainerAvailable
        }
    }
}

#Preview {
    NavigationStack {
        MeView()
    }
}
