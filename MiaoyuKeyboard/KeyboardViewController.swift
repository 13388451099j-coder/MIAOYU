import UIKit
import SwiftUI

/// 键盘扩展主控制器：装配 SwiftUI 根视图，并把 textDocumentProxy 通道注入 KeyboardContext。
///
/// 说明：
/// - 系统键盘切换（地球键）由注入的 `advanceToNextInputMode()` 完成，不覆写 textInputMode；
/// - 高度通过 self.view 的高度约束设定（KeyboardTheme.totalHeight，约 300pt），
///   优先级 999 以避免与系统自动布局约束冲突产生警告。
final class KeyboardViewController: UIInputViewController {

    /// 键盘全局状态（持有并传入 SwiftUI 环境）
    private let context = KeyboardContext()

    override func viewDidLoad() {
        super.viewDidLoad()

        // 自定义键盘高度（优先级 999：足够生效，又不与系统必需约束硬冲突）
        view.backgroundColor = KeyboardTheme.backgroundUIColor
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: KeyboardTheme.totalHeight)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true

        // SwiftUI 根视图：UIHostingController 装入（底色用主题背景，避免容器透明露出黑底）
        let host = UIHostingController(rootView: KeyboardRootView().environmentObject(context))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = KeyboardTheme.backgroundUIColor
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        injectContext()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 完全访问权限 / proxy 可能随宿主 App 与焦点变化，出现时刷新注入
        injectContext()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 键盘占屏比例上报给广播扩展：扩展据此抬高底部裁剪，避免把键盘面板本身
        // （上面显示着上一轮的待回消息）OCR 进快照，形成「按钮文本被当成对方消息」的自反馈。
        reportPanelFraction()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 键盘收起：清零，让广播扩展恢复默认底部裁剪
        lastReportedFraction = -1
        LiveScreenStore.setKeyboardPanel(fraction: 0)
    }

    /// 上次上报的占屏比例：布局回调很频繁，值没变就别反复写 UserDefaults（跨进程同步有成本）
    private var lastReportedFraction: Double = -1

    /// 上报本键盘高度占整屏的比例（0…1）。窗口还没挂上时跳过，下次布局再报。
    /// 注意不能用 `UIApplication.shared`——键盘是扩展，该符号在扩展里编译期不可用。
    private func reportPanelFraction() {
        let screenHeight = (view.window?.windowScene?.screen ?? UIScreen.main).bounds.height
        guard screenHeight > 0, view.bounds.height > 0 else { return }
        let fraction = Double(min(1, view.bounds.height / screenHeight))
        guard abs(fraction - lastReportedFraction) > 0.005 else { return }
        lastReportedFraction = fraction
        LiveScreenStore.setKeyboardPanel(fraction: fraction)
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        // 焦点切换可能换 proxy 实例，重新注入保证闭包捕获最新代理
        injectContext()
    }

    /// 注入上屏通道：insertText / deleteBackward / documentContextBeforeInput /
    /// 切系统键盘（advanceToNextInputMode）/ 收起（dismissKeyboard）。
    private func injectContext() {
        context.install(proxy: textDocumentProxy,
                        fullAccess: hasFullAccess,
                        needsSwitchKey: needsInputModeSwitchKey,
                        switcher: { [weak self] in
                            self?.advanceToNextInputMode()
                        },
                        dismiss: { [weak self] in
                            self?.dismissKeyboard()
                        })
        // 上报完全访问状态：主 App 的「键盘完全访问」与直播模式引导都读这个值。
        // 只在值变化时写：注入在 viewDidLoad / viewDidAppear / textWillChange 都会跑，
        // 每次键都写一遍 App Group UserDefaults 是白白的跨进程同步开销。
        if lastReportedFullAccess != hasFullAccess {
            lastReportedFullAccess = hasFullAccess
            AppGroup.reportKeyboardFullAccess(hasFullAccess)
        }
    }

    /// 上次上报过的完全访问状态（nil = 还没报过）
    private var lastReportedFullAccess: Bool?
}
