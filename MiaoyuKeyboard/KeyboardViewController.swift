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
    }
}
