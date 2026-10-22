import SwiftUI
import UIKit

/// 键盘模式：四个主键盘 + 三个功能面板
enum KeyboardMode {
    case pinyin        // 26 键拼音
    case t9            // 九宫格 T9 拼音
    case symbol        // 符号页（两页网格）
    case english       // 英文直上屏
    case aiPanel       // AI 卡片面板（润色 / 沟通三策略）
    case phrasePanel   // 常用短语面板
    case stickerPanel  // 颜文字/表情面板
}

/// 键盘全局状态与输入协调中枢。
///
/// 职责：
/// 1. 持有拼音引擎 `PinyinEngine`（PinyinKit 契约 API），维护组合字母串与候选，
///    每次引擎操作后把最新值同步进 @Published，由 SwiftUI 驱动候选条刷新；
/// 2. 通过 KeyboardViewController 注入的闭包通道对 textDocumentProxy 执行
///    insertText / deleteBackward / 读取 documentContextBeforeInput；
/// 3. 在拼音 / T9 / 英文 / 符号 / 三个面板之间切换并维护各自的输入状态。
///
/// 契约偏差说明：
/// - 任务指定方法名 `tap(letter:)`（契约原文为 `tap(key:)`，按任务实现）；
/// - `install` 相比任务示例多一个 `needsSwitchKey` 参数（用于地球键显隐），语义一致。
final class KeyboardContext: ObservableObject {

    // MARK: - 发布状态（SwiftUI 驱动）

    /// 当前键盘模式。切到 T9/英文会清空拼音组合；切符号页/面板则保留组合，返回后可继续输入。
    @Published var mode: KeyboardMode = .pinyin {
        didSet { handleModeChange(from: oldValue) }
    }

    /// 已敲字母串（来自引擎，每次操作后同步）
    @Published private(set) var rawInput: String = ""

    /// 当前置候选（来自引擎，≤ 20 条，按 score 降序）
    @Published private(set) var candidates: [Candidate] = []

    /// 组合的音节展示（如 "ni hao"，来自引擎，用于候选条左侧）
    @Published private(set) var syllableDisplay: String = ""

    /// 英文 shift 状态（仅英文直上屏模式有意义；单次大写后自动回落）
    @Published var shift: Bool = false

    /// 完全访问权限（VC 从 self.hasFullAccess 注入刷新）
    @Published private(set) var hasFullAccess: Bool = false

    /// 是否需要显示地球键（VC 从 self.needsInputModeSwitchKey 注入刷新）
    @Published private(set) var needsInputModeSwitchKey: Bool = true

    /// 进入符号页前所在的字母键盘（符号页 ABC 键返回用）
    @Published private(set) var symbolReturnMode: KeyboardMode = .pinyin

    // MARK: - 引擎（PinyinKit 契约）

    /// 拼音引擎：字母追加 / 退格 / 候选查询 / 候选上屏消费
    private let engine = PinyinEngine()

    /// 词库是否就绪（后台解码完成）。键盘扩展里词库是异步解码的，
    /// 未就绪时候选条显示「词库加载中」而不是把用户敲的字母当成候选。
    @Published private(set) var lexiconReady: Bool = false

    init() {
        // 键盘一出现就让引擎在后台解词库：4.8MB / 12 万条，主线程解要 1 秒以上，
        // 首字母按下去会整个键盘冻住（真机就是这个症状）。预热后用户敲第一个字母时通常已就绪。
        engine.onLexiconReady = { [weak self] in
            guard let self else { return }
            self.lexiconReady = true
            self.syncFromEngine()
        }
        engine.prepare()
    }

    /// T9 当前数字串（键盘侧自行维护，映射成字母路径后喂给 engine）
    private var t9Digits: String = ""

    // MARK: - 上屏通道（由 KeyboardViewController 注入）

    private var performInsert: (String) -> Void = { _ in }
    private var performDelete: (Int) -> Void = { _ in }
    private var readDocumentBeforeInput: () -> String? = { nil }
    private var performSwitchInputMode: () -> Void = { }
    private var performDismiss: () -> Void = { }

    /// 由 VC 注入代理通道。
    ///
    /// - Parameters:
    ///   - proxy: VC 的 textDocumentProxy（闭包内弱引用捕获，避免延长代理生命周期）；
    ///   - fullAccess: VC.hasFullAccess（是否拥有完全访问权限）；
    ///   - needsSwitchKey: VC.needsInputModeSwitchKey（是否需要地球键）；
    ///   - switcher: 切下一个系统输入法，VC 注入 `advanceToNextInputMode()`；
    ///   - dismiss: 收起键盘，VC 注入 `dismissKeyboard()`。
    ///
    /// VC 在 viewDidLoad / viewDidAppear / textWillChange 重复调用以刷新（proxy 可能随焦点变化）。
    func install(proxy: UITextDocumentProxy,
                 fullAccess: Bool,
                 needsSwitchKey: Bool,
                 switcher: @escaping () -> Void,
                 dismiss: @escaping () -> Void) {
        performInsert = { [weak proxy] text in
            proxy?.insertText(text)
        }
        performDelete = { [weak proxy] count in
            guard let proxy = proxy else { return }
            // UITextDocumentProxy 只暴露单字符 deleteBackward()，按次数循环；上限防御
            let n = min(max(count, 0), 1000)
            for _ in 0..<n { proxy.deleteBackward() }
        }
        readDocumentBeforeInput = { [weak proxy] in
            proxy?.documentContextBeforeInput
        }
        performSwitchInputMode = switcher
        performDismiss = dismiss
        hasFullAccess = fullAccess
        needsInputModeSwitchKey = needsSwitchKey
    }

    // MARK: - 模式切换

    private func handleModeChange(from old: KeyboardMode) {
        guard old != mode else { return }
        switch mode {
        case .t9, .english:
            // T9/英文与 26 键拼音的组合语义互不兼容，切换即清空（T9 数字串一并清空）
            resetComposition()
        case .symbol:
            // 记录来源字母键盘，符号页 ABC 返回用；组合保留（打字中途插符号是常见路径）
            if old == .pinyin || old == .english { symbolReturnMode = old }
        default:
            break // 拼音与各面板：保留组合
        }
    }

    /// 从符号页返回来源字母键盘
    func exitSymbolMode() {
        mode = symbolReturnMode
    }

    // MARK: - 按键输入

    /// 字母键：拼音/T9 模式进引擎组词；英文模式按 shift 状态直接上屏。
    func tap(letter: Character) {
        switch mode {
        case .pinyin, .t9:
            engine.append(letter: letter)
            syncFromEngine()
        case .english:
            let output = shift ? String(letter).uppercased() : String(letter)
            sendToProxy(text: output)
            shift = false // 单次大写后自动回落（暂不做大写锁定）
        default:
            break
        }
    }

    /// T9 数字键：维护数字串并重建引擎字母路径（重建策略见 `rebuildT9Engine` 注释）。
    /// 无字母映射的数字（如 1）由视图层拦截，不会走到这里。
    func tapDigit(_ digit: Character) {
        guard mode == .t9, !T9Mapper.letters(for: digit).isEmpty else { return }
        t9Digits.append(digit)
        rebuildT9Engine()
    }

    /// 退格：有组合删组合（拼音删字母 / T9 删数字），无组合删除正文一个字符。
    func tapBackspace() {
        switch mode {
        case .pinyin:
            if !engine.rawInput.isEmpty {
                engine.backspace()
                syncFromEngine()
            } else {
                performDelete(1)
            }
        case .t9:
            if !t9Digits.isEmpty {
                t9Digits.removeLast()
                rebuildT9Engine()
            } else {
                performDelete(1)
            }
        default:
            performDelete(1)
        }
    }

    /// 空格：有组合时上屏第一候选（无候选则原样上屏字母串），无组合插入空格。
    func tapSpace() {
        if !engine.rawInput.isEmpty {
            if let first = engine.candidates.first {
                selectCandidate(first)
            } else {
                commitRawLetters()
            }
        } else {
            sendToProxy(text: " ")
        }
    }

    /// 回车：有组合时等同空格（先上屏组合避免悬空），无组合插入换行。
    func tapReturn() {
        if !engine.rawInput.isEmpty {
            tapSpace()
        } else {
            sendToProxy(text: "\n")
        }
    }

    /// 选中候选：契约 `engine.commit` 返回上屏文本（多字词可能只消费部分音节），
    /// 上屏后再同步引擎剩余组合。
    func selectCandidate(_ candidate: Candidate) {
        let text = engine.commit(candidate)
        sendToProxy(text: text)
        syncFromEngine()
    }

    /// 候选为空时的兜底：把已敲字母串原样上屏（候选条兜底按钮）。
    func commitRawLetters() {
        guard !engine.rawInput.isEmpty else { return }
        sendToProxy(text: engine.rawInput)
        engine.reset()
        syncFromEngine()
    }

    /// 清空组合：引擎字母 + T9 数字串 + shift 状态。
    func resetComposition() {
        engine.reset()
        t9Digits = ""
        shift = false
        syncFromEngine()
    }

    // MARK: - T9 路径重建

    /// T9 简化策略（任务说明许可的键盘侧方案，避免跨模块耦合）：
    /// 1. `T9Mapper.expand(digits)` 把数字串展开为「合法音节序列」字母串集合（契约内剪枝）；
    /// 2. 逐条试探：engine.reset() + 逐字母 append，读首候选 score，取分数最高的路径；
    /// 3. 最终把 engine 重建在该最优路径上，保证候选展示与 commit 的音节消费完全一致；
    /// 4. expand 为空（输入中途可能被剪枝光）时回退：每个数字取映射首字母的确定路径，
    ///    保证 rawInput 有显示、可退格。
    /// 同一时刻只跟踪一条字母路径；多分支候选并陈展示留给后续版本。
    private func rebuildT9Engine() {
        guard !t9Digits.isEmpty else {
            engine.reset()
            syncFromEngine()
            return
        }
        let expansions = T9Mapper.expand(digits: t9Digits)
        var bestPath = ""
        if expansions.isEmpty {
            // 回退：数字 → 映射首字母（确定性路径）
            bestPath = t9Digits.compactMap { T9Mapper.letters(for: $0).first }.map(String.init).joined()
        } else {
            var bestScore = -1.0
            for path in expansions.sorted().prefix(64) { // 防御上限，避免极端组合的试探开销
                engine.reset()
                for ch in path { engine.append(letter: ch) }
                if let top = engine.candidates.first, top.score > bestScore {
                    bestScore = top.score
                    bestPath = path
                }
            }
        }
        engine.reset()
        for ch in bestPath { engine.append(letter: ch) }
        syncFromEngine()
    }

    // MARK: - 上屏 / 系统键盘

    /// 直接上屏文本：符号、英文、短语、颜文字、AI 结果共用的唯一通道（契约方法名）。
    func sendToProxy(text: String) {
        performInsert(text)
    }

    /// 删除光标前 count 个字符再插入 text（AI「润色本条」替换尾部段落用）。
    func replaceChars(_ count: Int, with text: String) {
        performDelete(count)
        performInsert(text)
    }

    /// 光标前文档内容（AI 面板取最近一条消息用）。
    func documentContextBeforeInput() -> String? {
        readDocumentBeforeInput()
    }

    /// 地球键：切到下一个系统输入法（VC 注入 advanceToNextInputMode）。
    func switchToNextKeyboard() {
        performSwitchInputMode()
    }

    /// 收起键盘（VC 注入 dismissKeyboard）。
    func dismissKeyboard() {
        performDismiss()
    }

    // MARK: - 内部同步

    /// 每次引擎操作后，把最新值同步进 @Published（SwiftUI 状态驱动候选条）。
    private func syncFromEngine() {
        rawInput = engine.rawInput
        candidates = engine.candidates
        syllableDisplay = engine.syllableDisplay
    }
}
