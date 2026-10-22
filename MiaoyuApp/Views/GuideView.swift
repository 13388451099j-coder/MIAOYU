import SwiftUI
import UIKit

/// 键盘安装三步引导 + 完全访问状态检测
///
/// 三步：添加键盘 → 允许完全访问 → App Group 数据共享说明
struct GuideView: View {

    /// 键盘完全访问状态（读取 App Group 的 kb_full_access，onAppear 刷新）
    @State private var fullAccess: Bool = false
    /// App Group 是否可用（自签免费证书不支持）
    @State private var sharedContainerOK: Bool = true

    var body: some View {
        List {
            // 当前状态卡
            Section {
                HStack(spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    KeyboardSettings.open()
                } label: {
                    Label("打开 设置 → 通用 → 键盘", systemImage: "gearshape")
                }
            }

            // 第 1 步：添加键盘
            Section {
                Label("打开 设置 → 通用 → 键盘 → 键盘", systemImage: "1.circle.fill")
                Label("点「添加新键盘」，选择「妙语键盘」", systemImage: "arrow.right.circle")
            } header: {
                Text("第 1 步 · 添加键盘")
            }

            // 第 2 步：允许完全访问
            Section {
                Label("回到「键盘」列表，点开「妙语键盘」", systemImage: "2.circle.fill")
                Label("打开「允许完全访问」开关", systemImage: "arrow.right.circle")
                Text("AI 联网改写、读取剪贴板都需要完全访问；不开启则键盘只能本地打字。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("第 2 步 · 允许完全访问")
            }

            // 第 3 步：App Group 数据共享说明
            Section {
                Label("主 App 与键盘通过 App Group 共享数据", systemImage: "3.circle.fill")
                Text(
                    """
                    人设、常用短语、模型配置等数据存放在 App Group 共享容器中：在主 App 里配置好后，键盘里立即可用，无需重复设置，也不依赖 iCloud。
                    """
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                if !sharedContainerOK {
                    Text(
                        """
                        ⚠️ 当前安装方式共享容器不可用：普通 Apple ID 的自签免费证书不支持 App Groups。这时键盘仍能打字，但完全访问状态、快捷短语、直播识别结果都不会在主 App 与键盘之间同步。换付费开发者账号签名即可恢复。
                        """
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("第 3 步 · 数据共享说明")
            }
        }
        .navigationTitle("键盘安装引导")
        .onAppear {
            fullAccess = AppGroup.keyboardHasFullAccess
            sharedContainerOK = AppGroup.isSharedContainerAvailable
        }
    }

    // MARK: 状态文案

    /// 自签免费证书没有 App Groups，主 App 读不到键盘上报的权限值，
    /// 这时不能武断地写「未开启」——用户明明打开了也会以为开关没生效。
    private var statusTitle: String {
        if !sharedContainerOK { return "键盘完全访问：无法检测" }
        return fullAccess ? "键盘完全访问：已开启" : "键盘完全访问：未开启"
    }

    private var statusDetail: String {
        if !sharedContainerOK {
            return "当前签名不含 App Groups，主 App 读不到键盘的权限状态；请在系统设置里自行确认「允许完全访问」已打开（下面第 2 步）。"
        }
        return fullAccess
            ? "妙语键盘已具备联网请求 AI 与读取剪贴板的能力。"
            : "开启后妙语键盘才能联网请求 AI 并读取剪贴板。"
    }

    private var statusIcon: String {
        if !sharedContainerOK { return "questionmark.shield.fill" }
        return fullAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
    }

    private var statusColor: Color {
        return sharedContainerOK && fullAccess ? .green : .orange
    }
}

#Preview {
    NavigationStack {
        GuideView()
    }
}
