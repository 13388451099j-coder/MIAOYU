// MARK: - 直播模式共享层：快照模型 + 对话解析 + App Group 存储
//
// 本文件同时编译进三个产品：主 App、键盘扩展、广播扩展（MiaoyuLive）。
// 刻意**不依赖** SharedKit / PinyinKit：广播扩展内存上限 ~50MB（jetsam 硬杀），
// 把 AiService、词库、SwiftUI 拖进去只会白白吃掉额度。所以 App Group 标识在这里自带一份，
// 与 SharedKit/AppGroup.swift 的 identifier 必须保持一致（改一处要同步另一处 + 三份 entitlements）。
//
// 数据流：广播扩展每 2 秒取一帧 → Vision 本地 OCR → LiveChatParser 按气泡横向位置分「我方/对方」
// → 快照写 App Group → 键盘与主 App 轮询读取，把「对方最新一条 + 前文」交给 AiService 出候选。

import Foundation
import CoreGraphics

/// 一行识别出来的对话。side 靠气泡的横向位置判断（右半屏 = 我方），
/// 这是启发式：微信 / QQ / iMessage 等主流 App 都满足，但长文本换行气泡、贴图、引用块会判错。
struct LiveLine: Codable, Equatable {
    enum Side: String, Codable {
        case them, me, system
    }

    var side: Side
    var text: String
}

/// 一次识别的完整快照，存 App Group UserDefaults 跨进程共享：广播扩展写，键盘与主 App 读。
///
/// 两个时间戳各司其职：
/// - `updatedAt` 是**心跳**：扩展每 2 秒落盘一次，广播活着它就新；
/// - `changedAt` 才是**画面内容最后一次变化**：主 App 用它做防抖，对方连发时不急着分析。
///
/// 只留「内容变了才落盘」一个语义会踩坑：广播刚启动、OCR 冷启动还没出活的窗口里，
/// 键盘永远显示「未在监听」，用户以为功能没生效。
struct LiveScreenSnapshot: Codable, Equatable {
    var updatedAt: Date
    var changedAt: Date
    var lines: [LiveLine]
    /// 扩展自启动以来见过的帧数（诊断用，够判断「广播活着但没有新帧」）
    var frameCount: Int
    /// 最近识别过的**全部对方消息**（新→旧，模糊去重，跨帧累积）。
    /// 键盘弹出时聊天 App 会自动滚到最底，当前帧往往只剩最新几条——用户想回更早的消息
    /// 就得靠这份累积历史。
    var recent: [String] = []

    /// 当前该回的消息：跳过尾部的系统行（时间/撤回提示），从尾往前取连续的对方气泡。
    /// 多行气泡合并成一条；最后一屏全是自己发的则返回 nil。
    var latestIncoming: String? {
        var i = lines.count - 1
        while i >= 0, lines[i].side == .system { i -= 1 }
        guard i >= 0, lines[i].side == .them else { return nil }
        var buf: [String] = []
        while i >= 0, lines[i].side == .them {
            buf.insert(lines[i].text, at: 0)
            i -= 1
        }
        let joined = buf.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// 前文（给模型的 context）：latestIncoming 之前的对话，带说话人前缀，
    /// 只取最近 14 行 / 600 字——上下文只用来定语气的，太长白花 token。
    var contextText: String? {
        var i = lines.count - 1
        while i >= 0, lines[i].side == .system { i -= 1 }
        guard i >= 0, lines[i].side == .them else { return nil }
        var buf: [String] = []
        var j = i - 1
        while j >= 0, buf.count < 14 {
            let line = lines[j]
            switch line.side {
            case .them: buf.insert("对方：" + line.text, at: 0)
            case .me: buf.insert("我：" + line.text, at: 0)
            case .system: break
            }
            j -= 1
        }
        let joined = buf.joined(separator: "\n").suffix(600)
        return joined.isEmpty ? nil : String(joined)
    }
}

// MARK: - 对话解析（纯函数，主 App 自检页可以直接喂截图验证）

enum LiveChatParser {

    /// OCR 的输出：文本 + 归一化包围盒（原点左下）。抽成值类型方便自检页直接构造。
    struct Observation {
        var text: String
        var boundingBox: CGRect
    }

    /// 界面上没有信息量的固定文案，识别出来只会污染快照。三组：
    /// ① 聊天 App 自己的底部/状态词；② 系统与第三方 App 的常见按钮词；
    /// ③ 我们自家 App / 键盘的界面词——广播开着时屏幕上常有自家 UI（回「直播」页看结果、
    /// 键盘面板盖住下半屏），不洗掉就会混进快照，甚至被当成「对方消息」触发分析。
    /// 精确整行匹配，聊天正文撞上这些词的概率可忽略。
    private static let uiTokens: Set<String> = [
        // ① 聊天 App 底部/状态
        "发送", "输入", "按住说话", "按住 说话", "语音", "相册", "红包", "转账",
        "返回", "微信", "正在输入", "对方正在输入...", "已读", "已送达", "拍一拍",
        // ② 常见系统/工具词
        "取消", "确定", "完成", "编辑", "删除", "更多", "搜索", "分享", "设置",
        // ③ 妙语自家 UI（主 App 直播页 + 键盘面板）
        "妙语", "妙语键盘", "直播模式", "屏幕监听", "监听中", "未在监听", "识别结果",
        "读屏幕分析", "回复更早", "分析剪贴板", "识别输入框", "润色本条", "沟通三策略",
        "AI 帮你说", "重新生成", "换一批", "点击卡片上屏", "正在生成候选",
        "允许完全访问", "键盘已启用", "自检", "合成示例", "从相册选截图",
    ]

    /// 时间行：`20:31`、`昨天 21:05`、`星期二`，以及 iOS 聊天 App 的跨天分隔行
    /// `9月26日 23:00` / `10月15日15:23`——后者不洗掉会被并进「对方消息」，待回内容里混进日期。
    private static let timePattern = try! NSRegularExpression(pattern:
        #"^([0-9]{1,2}[:：][0-9]{2}|(昨天|今天)\s*[0-9]{1,2}[:：][0-9]{2}|[0-9]{1,2}月[0-9]{1,2}日(\s*[0-9]{1,2}[:：][0-9]{2})?|星期[一二三四五六日天]|昨天|今天)$"#)

    /// 观测 → 对话行。步骤：清洗 → 按 midY 聚成视觉行 → 行内按 x 拼接 → 并集框中点定左右。
    static func parse(_ observations: [Observation]) -> [LiveLine] {
        let cleaned: [Observation] = observations.compactMap { o in
            let t = o.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            if uiTokens.contains(t) { return nil }
            if timePattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil { return nil }
            return Observation(text: t, boundingBox: o.boundingBox)
        }
        guard !cleaned.isEmpty else { return [] }

        // Vision 的 y 轴向上（原点左下）：从上往下扫，midY 接近的算同一视觉行。
        // 0.55 × 行高是经验值：同一行内多框（中文一段常碎成几框）的 midY 几乎重合，
        // 相邻两行气泡的高度差远大于半个行高。
        let sorted = cleaned.sorted { a, b in
            let am = a.boundingBox.midY, bm = b.boundingBox.midY
            return am == bm ? a.boundingBox.midX < b.boundingBox.midX : am > bm
        }
        var rows: [[Observation]] = []
        for o in sorted {
            if var last = rows.last, let first = last.first {
                let tol = 0.55 * max(first.boundingBox.height, o.boundingBox.height, 0.02)
                if abs(first.boundingBox.midY - o.boundingBox.midY) < tol {
                    last.append(o)
                    rows[rows.count - 1] = last
                    continue
                }
            }
            rows.append([o])
        }

        var lines: [LiveLine] = []
        for row in rows {
            let items = row.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
            var text = ""
            for item in items {
                if let last = text.last, joinsTight(last, item.text.first ?? " ") {
                    text += item.text
                } else {
                    if !text.isEmpty { text += " " }
                    text += item.text
                }
            }
            // 并集框中点：短气泡贴边（微信里「哦」在对方手里 midX≈0.15，在我方手里 midX≈0.9），
            // 长气泡趋中。0.55 偏向我方一点，因为长消息里我方气泡整体更靠右。
            let union = items.dropFirst().reduce(items[0].boundingBox) { $0.union($1.boundingBox) }
            let side: LiveLine.Side = union.midX > 0.55 ? .me : .them
            lines.append(LiveLine(side: side, text: text))
        }
        return lines
    }

    /// 行内多框拼接：两边都是 CJK 就贴死（OCR 常把一句中文切成几框，加空格反而碍事），
    /// 否则补空格保住英文词距。
    private static func joinsTight(_ left: Character, _ right: Character) -> Bool {
        func cjk(_ c: Character) -> Bool {
            guard let s = String(c).unicodeScalars.first else { return false }
            return (0x4E00...0x9FFF).contains(s.value) || (0x3000...0x303F).contains(s.value)
                || (0xFF00...0xFFEF).contains(s.value)
        }
        return cjk(left) && cjk(right)
    }

    /// 一帧里的全部对方消息簇（新→旧）。与 latestIncoming 同规则（多行合并、系统行当边界），
    /// 但不只在帧尾找——用户滚动浏览聊天历史时每帧看到不同片段，逐帧去重累积进 `recent`，
    /// 键盘才能让用户挑「更早的消息」来回复。
    static func incomingClusters(in lines: [LiveLine]) -> [String] {
        var clusters: [String] = []
        var i = lines.count - 1
        while i >= 0 {
            guard lines[i].side == .them else { i -= 1; continue }
            var buf: [String] = []
            while i >= 0, lines[i].side == .them {
                buf.insert(lines[i].text, at: 0)
                i -= 1
            }
            let joined = buf.joined(separator: "\n")
            if !joined.isEmpty { clusters.append(joined) }
        }
        return Array(clusters.prefix(4))
    }

    /// 会话画面门控：广播扩展拿不到「当前前台 App」（iOS 不提供该 API，按 App 白名单过滤做不到），
    /// 退而求其次——只把「长得像双人聊天」的画面当会话：我方与对方两侧气泡同时在场。
    /// 真实聊天几乎总满足（有来才有回）；设置/相册/网页等单列画面几乎不会同时出现左右两种气泡。
    static func looksLikeConversation(_ lines: [LiveLine]) -> Bool {
        var them = 0, me = 0
        for line in lines {
            if line.side == .them { them += 1 }
            else if line.side == .me { me += 1 }
        }
        return them >= 1 && me >= 1
    }

    /// 会话延续判定：本帧与上一帧有共同文本行。用户在聊天里滚动浏览时（包括翻到
    /// 只剩单侧气泡的老历史），相邻两帧画面必有交集；切到别的 App 则内容完全不同、交集为空。
    /// 与 looksLikeConversation 二选一满足即视为会话——否则门控会把单侧气泡的历史区间整段漏掉。
    static func extendsConversation(_ current: [LiveLine], previous: [LiveLine]) -> Bool {
        guard !previous.isEmpty else { return false }
        let cur = Set(current.map(\.text))
        let prev = Set(previous.map(\.text))
        return !cur.isDisjoint(with: prev)
    }

    // MARK: 同一句话识别变体的归并（模糊去重）

    /// OCR 抖动归一化：去空白、小写。同一句话两帧识别常在空格/断行位置不一致
    ///（「拉一\n把」vs「拉一 把」vs「拉一把」），归一化后才能对上。
    static func normalizedForDedup(_ s: String) -> String {
        s.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
    }

    /// 两条识别结果是否指同一句话：归一化后相等，或一方包含另一方且较短方 ≥6 字
    /// （滚动中只露半条的截断变体），或归一化后编辑距离占比较小（逐字抖动：
    /// 「wizard」偶发认成「wizzard」，包含关系判不出来）。短消息（<8 字）不用距离——
    /// 「好的」和「好的呀」是真不同的消息，防止误吞。
    static func areSameMessage(_ a: String, _ b: String) -> Bool {
        let na = normalizedForDedup(a)
        let nb = normalizedForDedup(b)
        if na == nb { return true }
        let (short, long) = na.count < nb.count ? (na, nb) : (nb, na)
        if short.count >= 6 && long.contains(short) { return true }
        guard short.count >= 8, na.count <= 400, nb.count <= 400 else { return false }
        return levenshtein(na, nb) <= max(2, Int(0.15 * Double(max(na.count, nb.count))))
    }

    /// 经典 DP 编辑距离。消息都是短文本（≤ 数百字），每 2 秒至多 24 次比较，开销可忽略。
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty else { return y.count }
        guard !y.isEmpty else { return x.count }
        var prev = Array(0...y.count)
        var curr = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            curr[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                curr[j] = Swift.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[y.count]
    }
}

// MARK: - App Group 存储

/// 快照的唯一存放点。不往共享容器里塞文件——UserDefaults 跨进程同步由 cfprefsd 负责，
/// 键盘 2 秒轮询一次小 key 的开销可以忽略。
enum LiveScreenStore {
    /// v1：本工程首个版本（含 recent 跨帧累积），无需迁移旧数据。
    static let snapshotKey = "miaoyu.live.snapshot.v1"

    /// 与 `SharedKit/AppGroup.swift` 的 identifier 同值。本文件单独编译进广播扩展
    ///（不拖 SharedKit），所以这里自带一份——改 App Group 时 entitlements / project.yml /
    /// 这两处要一起改。
    private static let appGroupID = "group.com.miaoyu.zuiti"

    /// 快照多久之内算「监听中」。扩展靠 2 秒一次的心跳维持 updatedAt，
    /// 广播一停快照自然过期，键盘/主 App 据此回到空闲，不需要显式的停止信号。
    static let freshWindow: TimeInterval = 150

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ snapshot: LiveScreenSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> LiveScreenSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(LiveScreenSnapshot.self, from: data) else { return nil }
        return snap
    }

    /// 把本帧识别到的对方消息簇并进累积历史：新的在前、模糊去重（同一句话的识别变体
    /// 只留一条、以更全的版本为准）、封顶。found 与 existing 都是新→旧序。
    /// 封顶 6 条——键盘上最多展示 3 条（主目标 + 2 个更早），留一倍冗余；
    /// 再多用户也挑不过来，还平白增大快照体积（UserDefaults 每次整块重写）。
    static func mergingRecent(existing: [String], found: [String], cap: Int = 6) -> [String] {
        var out: [String] = []
        for msg in found + existing {
            if let i = out.firstIndex(where: { LiveChatParser.areSameMessage($0, msg) }) {
                if msg.count > out[i].count { out[i] = msg }   // 识别更全的版本顶掉残缺版
            } else {
                out.append(msg)
            }
        }
        return Array(out.prefix(cap))
    }

    static func isFresh(_ snapshot: LiveScreenSnapshot) -> Bool {
        Date().timeIntervalSince(snapshot.updatedAt) < freshWindow
    }

    /// 「监听中且能 actionable」= 快照新鲜 + 里面有一条待回的对方消息。
    /// 键盘面板用这一个布尔决定要不要把「读屏幕分析」当主按钮。
    static var isActionable: Bool {
        guard let snap = load(), isFresh(snap), snap.latestIncoming != nil else { return false }
        return true
    }

    /// 「广播活着」= 快照新鲜（扩展每 2 秒心跳落盘）。比 isActionable 宽：
    /// 广播刚开、还没读到对方气泡时也是 true。键盘面板用它显示「监听中」提示——
    /// 否则开播后键盘和平时长得一模一样，用户会以为功能没生效。
    static var isListening: Bool {
        guard let snap = load() else { return false }
        return isFresh(snap)
    }

    // MARK: 自报状态（键盘 / 主 App 写，广播扩展读）

    /// 键盘面板高度占整屏的比例。键盘开着时它自己周期性上报（带时间戳），
    /// 广播扩展据此抬高底部裁剪——键盘面板在识别区里会被 OCR，按钮上显示的上一轮目标
    /// 还会被喂回快照形成自反馈，`recent` 全变成按钮文本的变体。
    struct PanelState: Codable {
        var fraction: Double
        var at: Date
    }

    private static let keyboardPanelKey = "miaoyu.live.keyboardPanel.v1"
    private static let appLiveVisibleKey = "miaoyu.live.appVisible.v1"

    static func setKeyboardPanel(fraction: Double) {
        guard let data = try? JSONEncoder().encode(PanelState(fraction: fraction, at: Date())) else { return }
        defaults.set(data, forKey: keyboardPanelKey)
    }

    /// 过期（键盘没在跑 / 进程死了没来得及清）返回 0 = 不抬底部裁剪。
    static func keyboardPanelFraction(maxAge: TimeInterval = 20) -> Double {
        guard let data = defaults.data(forKey: keyboardPanelKey),
              let state = try? JSONDecoder().decode(PanelState.self, from: data),
              Date().timeIntervalSince(state.at) < maxAge else { return 0 }
        return state.fraction
    }

    /// 主 App「直播」页在前台时自报（每秒续期）。页面上是我们自己的识别结果 UI，OCR 它
    /// 只会把上一轮目标喂回快照（同一个自反馈回路），扩展看到新鲜标记直接整帧跳过。
    /// 用时间戳而不是裸布尔：用户带着直播页退后台时 onDisappear 不可靠，
    /// 卡死的 true 会让扩展在用户回到聊天后仍然永远跳过。
    static func setAppLiveVisible(_ visible: Bool) {
        guard let data = try? JSONEncoder().encode(PanelState(fraction: visible ? 1 : 0, at: Date())) else { return }
        defaults.set(data, forKey: appLiveVisibleKey)
    }

    static func appLiveVisible(maxAge: TimeInterval = 5) -> Bool {
        guard let data = defaults.data(forKey: appLiveVisibleKey),
              let state = try? JSONDecoder().decode(PanelState.self, from: data),
              state.fraction > 0,
              Date().timeIntervalSince(state.at) < maxAge else { return false }
        return true
    }

    /// 扩展侧自检日志。广播扩展连 Xcode 控制台都看不着，出问题全靠这一条通道。
    /// 不做 DEBUG 门控：Release/Archive 配置下 DEBUG 条件不存在，门控会让归档编译失败；
    /// 每次只写几百字节，Release 留着正好排查真机内存问题。
    static func diag(_ line: String) {
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
        let prev = defaults.string(forKey: "miaoyu.live.diag.v1") ?? ""
        defaults.set(String((prev + "[\(stamp)] [直播] \(line)\n").suffix(6000)),
                     forKey: "miaoyu.live.diag.v1")
    }

    /// 主 App / 键盘读诊断日志（真机排查用，不参与功能逻辑）。
    static func loadDiag() -> String {
        defaults.string(forKey: "miaoyu.live.diag.v1") ?? ""
    }
}
