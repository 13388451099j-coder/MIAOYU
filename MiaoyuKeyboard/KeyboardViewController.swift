import UIKit
import SwiftUI

/// 键盘扩展主控制器：装配 SwiftUI 根视图，并把 textDocumentProxy 通道注入 KeyboardContext。
///
/// 这个文件里每一处「看起来多余」的写法都对应一次真机翻车，改动前先读注释：
/// 1. `allowsSelfSizing` —— 不设它，系统按默认高度摆宿主 inputView，我们画的 300pt
///    只是「渲染上去」而不参与 hit test，表现是按键有按压反馈却打不出字、点 AI 没反应；
/// 2. hosting view 用 frame + autoresizingMask 而不是约束 —— 键盘在切 App、旋屏、
///    切输入法时会反复改尺寸，Auto Layout 链路里任何一次没跟上，hosting view 的
///    bounds 就停在旧值，**视觉正确但触摸坐标整体偏移**；
/// 3. `viewDidLayoutSubviews` 里再同步一次 bounds —— 兜住系统不触发 autoresize 的路径。
final class KeyboardViewController: UIInputViewController {

    /// 键盘全局状态（持有并传入 SwiftUI 环境）
    private let context = KeyboardContext()

    /// SwiftUI 宿主。强引用只是为了让 `viewDidLayoutSubviews` 能拿到它；
    /// 它本身已经是 self 的 child view controller，不会因此产生循环引用。
    private var hostController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = KeyboardTheme.backgroundUIColor

        // 自定义键盘高度：必须同时满足两点才生效
        //   a) view 是 UIInputView 且 allowsSelfSizing = true（否则系统用自己的默认高度）
        //   b) 高度约束优先级 999（1000 会和系统必需约束硬冲突）
        (view as? UIInputView)?.allowsSelfSizing = true
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: KeyboardTheme.totalHeight)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true

        // SwiftUI 根视图。注意 rootView 外面套 AnyView：environmentObject 返回的是
        // ModifiedContent<...>，不套 AnyView 就没法用统一的 UIHostingController<T> 类型存字段。
        let host = UIHostingController(
            rootView: AnyView(KeyboardRootView().environmentObject(context))
        )
        host.view.backgroundColor = KeyboardTheme.backgroundUIColor
        host.view.isUserInteractionEnabled = true
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.frame = view.bounds
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        hostController = host

        injectContext()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        injectContext()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 完全访问权限 / proxy 可能随宿主 App 与焦点变化，出现时刷新注入
        injectContext()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 兜底同步：系统改宿主尺寸时不一定会触发 autoresizing（例如键盘从「候选展开」
        // 收回到默认高度的那一帧），这里显式对一次，保证 SwiftUI 的坐标系和触摸坐标系一致。
        if let hostView = hostController?.view, hostView.frame != view.bounds {
            hostView.frame = view.bounds
        }
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
        // 焦点切换可能换 proxy 实例，重新注入保证 KeyboardContext 持有的是最新那份
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
        // 只在值变化时写：注入在 viewDidLoad / viewWillAppear / viewDidAppear /
        // textWillChange 都会跑，每次都写一遍 App Group UserDefaults 是白白的跨进程同步开销。
        if lastReportedFullAccess != hasFullAccess {
            lastReportedFullAccess = hasFullAccess
            AppGroup.reportKeyboardFullAccess(hasFullAccess)
        }
    }

    /// 上次上报过的完全访问状态（nil = 还没报过）
    private var lastReportedFullAccess: Bool?
}
